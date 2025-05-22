class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_risk_assistant

  require "fileutils"

  # ------------------------------------------------------------------
  # POST /risk_assistants/:risk_assistant_id/messages
  # ------------------------------------------------------------------
  def create
    # 1) Validación rápida del texto
    if params.dig(:message, :content).blank?
      flash[:error] = "El mensaje no puede estar vacío."
      return redirect_to risk_assistant_path(@risk_assistant)
    end

    # 2) Persistimos el mensaje del usuario
    @message = @risk_assistant.messages.create!(
      message_params.merge(sender: "user", role: "user",
                           thread_id: @risk_assistant.thread_id)
    )

    # 3) Preparamos el runner (crea thread si aún no existe)
    runner = AssistantRunner.new(@risk_assistant)

    # 4) Subida opcional de archivo
    file_id = nil
    if params[:file].present?
      # a) subir el fichero
      file_id = uploader_to_openai(params[:file])

      # b) si se subió bien, lo asociamos al thread
      attach_to_thread(runner.thread_id, file_id) if file_id.present?
    end

    # 5) Enviamos el turno del usuario (incluye adjunto si hay)
    runner.submit_user_message(content: @message.content, file_id: file_id)

    # 6) Ejecutamos la run y esperamos
    assistant_text = runner.run_and_wait

    # --------------------------------------------------------------------
    # NUEVO  ➜  extraer N-pares  ##campo##   &&valor&&
    # --------------------------------------------------------------------
    pairs  = assistant_text.scan(/##(.*?)##.*?&&\s*(.*?)\s*&&/m)   # => [[campo1,val1],[campo2,val2],...]
    flags  = assistant_text.scan(/⚠️\s*(.*?)\s*⚠️/m)               # => [[flag1],[flag2],...]

    # 1. guarda (opcional) el mensaje completo para histórico
    @risk_assistant.messages.create!(
      content: assistant_text, sender: "assistant", role: "assistant",
      thread_id: runner.thread_id
    )

    # 2. un mensaje por cada campo/valor
    pairs.each do |key, value|
      @risk_assistant.messages.create!(
        content: "✅ Perfecto, el campo ##{key}## es &&#{value}&&.",
        sender:  "assistant", role: "assistant",
        key: key, value: value, thread_id: runner.thread_id
      )
    end

    # 3. un mensaje por cada flag crítico encontrado
    if flag.present?
      flags.flatten.each do |txt|
        @risk_assistant.messages.create!(
          content: txt,
          sender:  "red_flag", role: "assistant",
          key: nil, value: nil, thread_id: runner.thread_id
        )
      end
    end


    if flag.present?
      @risk_assistant.messages.create!(
        content: flag, sender: "red_flag", role: "assistant",
        key: key, value: value, thread_id: runner.thread_id
      )
    end

    redirect_to @risk_assistant

  rescue => e
    Rails.logger.error "💥 Error en MessagesController#create: #{e.class} – #{e.message}"
    flash[:error] = "Se produjo un error al procesar tu mensaje."
    redirect_to risk_assistant_path(@risk_assistant)
  end

  private

  def message_params
    params.require(:message).permit(:content, :thread_id, :section)
  end

  def set_risk_assistant
    @risk_assistant = current_user.risk_assistants.find(params[:risk_assistant_id])
  end

  # ---------- subida de fichero + asociación al thread ----------
  def uploader_to_openai(file)
    tmp = Tempfile.new(
            [File.basename(file.original_filename, '.*'),
            File.extname(file.original_filename)],
            binmode: true                                  # ← Windows friendly
          )

    tmp.write file.read
    tmp.flush                                            # asegura disco
    tmp.rewind
    tmp.close                                            # <-- CERRAR ANTES de enviar

    Rails.logger.debug { "Uploader: subiendo #{tmp.path}" }

    resp = HTTP
          .headers(
            "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}",
            "OpenAI-Beta"   => "assistants=v2"
          )
          .post(
            "#{AssistantRunner::BASE_URL}/files",
            form: {
              file: HTTP::FormData::File.new(tmp.path),  # ya está cerrado
              purpose: "assistants"
            }
          )

    body    = JSON.parse(resp.body.to_s)
    file_id = body["id"]
    Rails.logger.debug { "Uploader: file_id #{file_id}" }

    file_id
  ensure
    # Siempre intentar borrar (solo posible si está cerrado)
    if tmp && !tmp.closed?      # si hubo excepción antes del close
      tmp.close
    end
    tmp&.unlink                # en Windows hay que cerrar *antes* de unlink
    Rails.logger.debug { "Uploader: eliminado #{tmp.path}" }
  end
  
  def attach_to_thread(thread_id, file_id)
    HTTP.headers(AssistantRunner::HEADERS)
        .post("https://api.openai.com/v1/threads/#{thread_id}/files",
              json: { file_id: file_id })
  end

  def format_previous_messages(messages)
    messages.map do |message|
      "[#{message[:role].capitalize}]: #{message[:content]}"
    end.join("\n")
  end

  def collect_messages_for_context(risk_assistant)
    risk_assistant.messages.order(:created_at).pluck(:role, :content).map do |role, content|
      { role: role, content: content }
    end
  end

  def fetch_response_from_openai(messages)

    previous_messages = collect_messages_for_context(@risk_assistant)
    prompt_messages = format_previous_messages(previous_messages)

    print prompt_messages

    # Construir el context
    context = 
      "
        Con toda la información recabada en esta conversación, por favor:
        1. Haz un **resumen ejecutivo de cada aparatado desde un punto de vista de un informe descriptivo de ingeniería de riesgos**.
        2. Extrae las **métricas clave** (campos del formulario).
        3. Identifica **lagunas de información** si las hubiera.
        4. Ofrece **conclusiones y recomendaciones**.
        Devuélvelo como un informe estructurado en Markdown.
      PROMPT
      Preguntas realizadas por ti y las respuestas del usuario: #{prompt_messages}"

    # Construir el prompt completo
    prompt = @message.content

    #enviar la solicitud a openai
    response = HTTP.post(
      "https://api.openai.com/v1/chat/completions",
      headers: {
        "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}",
        "Content-Type" => "application/json"
      },
      body: {
        model: "gpt-4o-mini",
        messages: [
          { role: "developer", content: context },
          { role: "user", content: prompt }
        ],
        max_tokens: 600,
        temperature: 0.7
      }.to_json
    )

    puts "🔍 Content: #{response["content"].inspect}"
    response.parse["choices"]&.first&.dig("message", "content")&.strip || "No se recibió una respuesta válida."
  end

  def parse_response(response_content)
    # Verificar si la respuesta contiene un formato esperado
    if response_content.include?(':')
      response_content.split("\n").map do |line|
        key_value = line.split(': ').map(&:strip)
        next if key_value.size != 2
        [key_value[0].to_sym, key_value[1]]
      end.compact.to_h
    else
      Rails.logger.warn("Respuesta genérica o no estructurada: #{response_content}")
      {}
    end

    #Guardar en la base de datos las respuesta de chatgpt

  rescue StandardError => e
    Rails.logger.error("Error al procesar la respuesta: #{e.message}")
    {}
  end

end

