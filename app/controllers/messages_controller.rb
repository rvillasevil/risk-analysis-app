class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_risk_assistant

  require "fileutils"
  require "semantic_guard" # ← 1) carga el guardia
  require "risk_field_set"          

  # ------------------------------------------------------------------
  # POST /risk_assistants/:risk_assistant_id/messages
  # ------------------------------------------------------------------

  def create
    # 1) Validación rápida: no aceptar contenido vacío (texto o fichero)
    if params.dig(:message, :content).blank? && params[:file].blank?
      flash[:error] = "El mensaje no puede estar vacío (o adjunte un archivo)."
      return redirect_to risk_assistant_path(@risk_assistant)
    end

    # 2) Guardamos el mensaje del usuario (texto)
    @message = @risk_assistant.messages.create!(
      message_params.merge(
        sender:    "user",
        role:      "user",
        thread_id: @risk_assistant.thread_id
      )
    )

    current_thread = @risk_assistant.thread_id

    # 3) Si el usuario sube un archivo, extraer el texto y buscar campos automáticamente
    if params[:file].present?
      if image_file?(params[:file])
        params[:file].rewind
        @risk_assistant.uploaded_files.attach(params[:file])

        @risk_assistant.messages.create!(
          sender:    "assistant",
          role:      "assistant",
          content:   "Imagen subida correctamente.",
          thread_id: current_thread
        )

          answered = @risk_assistant.messages.where.not(key: nil).pluck(:key)
          next_field = RiskFieldSet.next_field_hash(answered)
          if next_field
            display_text = RiskFieldSet.question_for(next_field[:id], include_tips: true)
          @risk_assistant.messages.create!(
            sender:      "assistant",
            role:        "assistant",
            content:     display_text,
            field_asked: next_field[:id],
            thread_id:   current_thread
          )
        end
        return redirect_to risk_assistant_path(@risk_assistant)
      end

      # A partir de aquí, el fichero queda disponible localmente para descargarlo.
      # Luego extraer texto, subir a OpenA<I, etc. (tal como ya tenías).
      extracted_text = TextExtractor.call(params[:file])
      params[:file].rewind
      @risk_assistant.uploaded_files.attach(params[:file])    

      # 3.2) Guardamos en histórico (opcional) un mensaje tipo “system” con el texto crudo
      unless extracted_text.blank?
        @risk_assistant.messages.create!(
          sender:    "assistant",
          role:      "developer",
          content:   "[EXTRAÍDO]\n#{extracted_text}",
          thread_id: current_thread
        )
      end

      # 3.3) Llamar a DocumentFieldExtractor para obtener { campo_id => valor } 
      doc_pairs = DocumentFieldExtractor.call(extracted_text)

      # 3.4) Si encontramos algún campo dentro del documento, confirmamos todos
      if doc_pairs.any?
        # Construir un bloque de texto que consolide todas las confirmaciones
        summary_lines = []
        doc_pairs.each do |campo_id, valor|
          label = RiskFieldSet.label_for(campo_id)
          Message.save_unique!(
            risk_assistant: @risk_assistant,
            key:           campo_id,
            value:         valor,
            content:       "✅ Perfecto, #{label} es &&#{valor}&&.",
            sender:        "assistant",
            role:          "developer",
            field_asked:   label,
            thread_id:     current_thread
          )
          summary_lines << "✅ #{label}: #{valor}"
        end

        # 3.5) Enviar un único mensaje al usuario que contenga TODAS las confirmaciones
        todos_confirmaciones = summary_lines.join("\n")
        @risk_assistant.messages.create!(
          sender:    "assistant",
          role:      "assistant",
          content:   "He extraído y confirmado automáticamente los siguientes campos del documento:\n\n#{todos_confirmaciones}",
          field_asked: "",           # ya no hay “pregunta abierta” relacionada
          thread_id: current_thread
        )
        # A partir de ahora, esos campo_id quedan marcados como respondidos en la BD,
        # de modo que el flujo **no** volverá a preguntarlos individualmente.

        # 3.6) Una vez procesado el contenido del fichero, podemos redirigir para
        #      que el usuario vea esas confirmaciones antes de continuar.
        return redirect_to risk_assistant_path(@risk_assistant)
      end
      # Si doc_pairs está vacío, no había ningún campo reconocible en el documento:

      # 3.3) Si llegamos aquí, había PDF, extrajimos texto, ¡pero no hallamos campos!
      #       Entonces le avisamos al usuario y pedimos que escriba manualmente el siguiente campo.
      next_field_id = RiskFieldSet.next_field_hash(
                        @risk_assistant.messages.where.not(key: nil).pluck(:key)
                      )&.dig(:id)
      next_label = next_field_id ? RiskFieldSet.label_for(next_field_id) : "campo pendiente"

      @risk_assistant.messages.create!(
        sender:    "assistant",
        role:      "assistant",
        content:   "He extraído el texto del documento, pero no encontré datos para los campos solicitados.\n" \
                   "Por favor, indícame directamente el campo “#{next_label}”.",
        field_asked: next_label,
        thread_id: current_thread
      )

      return redirect_to risk_assistant_path(@risk_assistant)      
    end

    # 4) Solo llamar a SemanticGuard si NO hay archivo adjunto (o si el usuario escribió texto)
    unless params[:file].present?

      # 4) SEMANTIC GUARD: solo comprueba incompatibilidades de contenido/categoría
      last_q = @risk_assistant.messages
                              .where(sender:    "assistant",
                                      role:      "assistant",
                                      thread_id: current_thread)
                              .where.not(field_asked: nil)
                              .where(key: nil)
                              .order(:created_at)
                              .last

      if last_q
        # 4.1) Construir contexto con pares confirmados “campo: valor”
        confirmed_context = @risk_assistant.messages
                                            .where(thread_id: current_thread)
                                            .where.not(key: nil)
                                            .order(:created_at)
                                            .map { |m| "#{RiskFieldSet.label_for(m.key)}: #{m.value}" }
                                            .join("\n")

        # 4.2) Llamar a SemanticGuard para detectar contradicciones
        err = SemanticGuard.validate(
                question:       last_q.content,
                answer:         @message.content,
                context:        confirmed_context,
                risk_assistant: @risk_assistant,
                thread_id:      current_thread
              )

        if err
          # Si hay contradicción de contenido, avisamos y detenemos el flujo
          @risk_assistant.messages.create!(
            sender:      "assistant",
            role:        "assistant",
            content:     "⚠️ #{err} Por favor, revisa el campo ##{last_q.field_asked}##.",
            field_asked: last_q.field_asked,
            thread_id:   current_thread
          )
        end
      end
    end

    # 5) Si no hubo contradicción, seguimos con el flujo habitual:

    # 5.1) Preparamos el runner (crea thread si aún no existe)
    runner = AssistantRunner.new(@risk_assistant)

    # 5.2) Subir el archivo (nuevamente) para que el LLM principal lo analice, si se desea
    file_id = nil
    if params[:file].present?
      file_id = uploader_to_openai(params[:file])
      attach_to_thread(runner.thread_id, file_id) if file_id.present?
    end

    # 5.3) Enviamos el turno del usuario (texto + file_id si hay)
    runner.submit_user_message(content: @message.content, file_id: file_id)

    # 5.4) Ejecutar la run principal y esperamos su respuesta
    assistant_text = runner.run_and_wait

    last_q = @risk_assistant.messages
            .where(sender:    "assistant",
                  role:      "assistant",
                  thread_id: runner.thread_id)
            .where.not(field_asked: nil)
            .where(key: nil)
            .order(:created_at)
            .last


     # Opcional: guardar la respuesta completa del asistente para auditoría

         # 6.C) Publicar la nueva pregunta “limpia” para el cliente
    answered_keys   = @risk_assistant.messages.where.not(key: nil).pluck(:key)
    next_field_hash = RiskFieldSet.next_field_hash(answered_keys)

    next_id    = next_field_hash[:id]
    next_label = next_field_hash[:label]
    display_text = RiskFieldSet.question_for(next_id, include_tips: true)    

    @risk_assistant.messages.create!(
      sender:    "assistant2",
      role:      "assistant",
      content:   assistant_text,
      field_asked: next_label,
      thread_id: runner.thread_id
    )

    # 6) Procesar la respuesta del asistente (igual que antes)
    pairs = assistant_text.scan(/##(?<field_id>[^#()]+?)(?:\s*\((?<item_label>[^)]+)\))?##.*?&&\s*(?<value>.*?)\s*&&/m)
    flags = assistant_text.scan(/⚠️\s*(.*?)\s*⚠️/m).flatten  

    # 6.A) Guardar confirmaciones crudas
    # 6.A) Guardar confirmaciones crudas con validación
    confirmations = []

    if pairs.any?
      pairs.each do |field_id, item_label, value|
        clean_id = field_id.to_s.strip
        
        if last_q && clean_id !~ /\.\d+\./
          expected = last_q.field_asked.to_s
          clean_id = expected if expected.gsub(/\.\d+/, '') == clean_id
        end

        Message.save_unique!(
          risk_assistant: @risk_assistant,
          key:           clean_id,
          value:         value,
          item_label:    item_label,
          content:       "✅ Perfecto, #{RiskFieldSet.label_for(clean_id)} es &&#{value}&&.",
          sender:        "assistant_confirmation",
          role:          "developer",
          field_asked:   nil,
          thread_id:     runner.thread_id
        )


        confirmations << "✅ #{RiskFieldSet.label_for(clean_id)}: #{value}"        
      end
    end
  

    # 6.B) Guardar flags
    flags.each do |msg|
      @risk_assistant.messages.create!(
        sender:    "assistant",
        role:      "developer",
        content:   "⚠️ #{msg} ⚠️",
        thread_id: runner.thread_id
      )
    end

    # 6.C) Publicar la nueva pregunta “limpia” para el cliente
    answered_keys   = @risk_assistant.messages.where.not(key: nil).pluck(:key)
    next_field_hash = RiskFieldSet.next_field_hash(answered_keys)
    if next_field_hash
      next_id = next_field_hash[:id].to_s
      tips  = RiskFieldSet.normative_tips_for(next_id)
      instr = next_field_hash[:assistant_instructions].to_s

      if pairs.empty?
        sanitized = assistant_text.gsub(/(?:\u2705[^#]*?)?##[^#]+##.*?&&.*?&&\s*[.,]?/m, "").strip

        expanded = ParagraphGenerator.generate(question: sanitized,
                                        instructions: instr,
                                        normative_tips: tips,
                                        confirmations: [])
        @risk_assistant.messages.create!(
          sender: "assistant",
          role: "assistant",
          content: expanded,
          field_asked: next_id,
          thread_id: runner.thread_id
        )
      else
        question_text = RiskFieldSet.question_for(next_id.to_sym, include_tips: true)
        
        expanded = ParagraphGenerator.generate(question: question_text,
                                               instructions: instr,
                                               normative_tips: tips,
                                               confirmations: confirmations)

        @risk_assistant.messages.create!(
          sender: "assistant",
          role: "assistant",
          content: expanded,
          field_asked: next_id,
          thread_id: runner.thread_id
        )

        combined = "Confirmación:\n#{confirmations.join("\n")}\n\n" \
                   "Siguiente pregunta: #{question_text}\n\n" \
                   "**Normative tips**: #{tips}"        

        @risk_assistant.messages.create!(
          sender: "assistant",
          role: "assistant",
          content: combined,
          field_asked: next_id,
          thread_id: runner.thread_id
        )
      end 
    end
    redirect_to @risk_assistant

  rescue => e
    Rails.logger.error "💥 Error en MessagesController#create: #{e.class} – #{e.message}"
    flash[:error] = "Se produjo un error
     al procesar tu mensaje."
    redirect_to risk_assistant_path(@risk_assistant)
  end


  private

  def message_params
    params.require(:message).permit(:content, :thread_id, :section, :field_asked)
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

  def image_file?(file)
    file.content_type.to_s.start_with?("image/")
  end


  def fetch_response_from_openai(messages)

    previous_messages = collect_messages_for_context(@risk_assistant)
    prompt_messages = format_previous_messages(previous_messages)

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

    Rails.logger.debug("🔍 Content: #{response["content"].inspect}")
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

