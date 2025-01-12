class MessagesController < ApplicationController
  before_action :authenticate_user!

  def create
    @risk_assistant = current_user.risk_assistants.find(params[:risk_assistant_id])

    if params[:message].blank? || params[:message][:content].blank?
      flash[:error] = "El mensaje no puede estar vacío."
      redirect_to risk_assistant_path(@risk_assistant) and return
    end

    @message = @risk_assistant.messages.create(message_params.merge(sender: 'user', role: 'user'))

    if @message.save
      # Identificar la sección actual y el siguiente campo vacío
      current_section = @risk_assistant.next_section
      next_field = @risk_assistant.next_field_in_section(current_section)

      if current_section && next_field
        # Generar pregunta para el siguiente campo vacío
        response_content = fetch_response_from_openai(next_field.to_s.humanize, current_section)

        # Guardar respuesta en la sección correspondiente
        parsed_response = { next_field => @message.content }
        @risk_assistant.save_response_to_section(current_section, parsed_response)

        # Crear mensaje del asistente con la pregunta generada
        @risk_assistant.messages.create(content: response_content, sender: 'assistant', role: 'assistant')
      else
        flash[:notice] = "Formulario completado o sección no identificada."
      end
    else
      flash[:error] = "No se pudo guardar el mensaje: #{@message.errors.full_messages.join(', ')}"
    end

    redirect_to @risk_assistant
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end

  def fetch_response_from_openai(field, section)

    #Definir contexto especifico segun la seccion
    context = case field
            when :nombre
              "¿Cuál es el nombre del lugar de riesgo?"
            when :direccion
              "¿Cuál es la dirección del lugar de riesgo?"
            when :codigo_postal
              "¿Cuál es el código postal del lugar de riesgo?"
            when :localidad
              "¿En qué localidad se encuentra el lugar de riesgo?"
            when :provincia
              "¿En qué provincia se encuentra el lugar de riesgo?"
            when :ubicacion
              "¿Cuál es la ubicación (núcleo urbano, polígono industrial, etc.)?"
            when :configuracion
              "¿Cómo describirías la configuración del lugar (colindante, aislado, etc.)?"
            else
              "Proporciona información para completar el formulario."
            end       

    # Construir el prompt completo
    prompt = "#{context}\nUsuario: #{prompt}\nAsistente:"
    prompt = "¿Cuál es el valor del campo #{field} en la sección #{section.humanize}?"

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
          { role: "system", content: context },
          { role: "user", content: prompt }
        ],
        max_tokens: 200,
        temperature: 0.7
      }.to_json
    )

    response.parse["choices"]&.first&.dig("message", "content")&.strip || "No se recibió una respuesta válida."
  end

  def parse_response(response_content)
    # Dividir la respuesta en líneas
    lines = response_content.split("\n").map(&:strip).reject(&:empty?)

    # Extraer pares clave-valor
    parsed_data = lines.map do |line|
      key_value = line.split(': ').map(&:strip)
      next if key_value.size != 2
      [key_value[0].to_sym, key_value[1]]
    end.compact.to_h

    parsed_data
  rescue StandardError => e
    Rails.logger.error("Error al procesar la respuesta: #{e.message}")
    {}
  end

end

