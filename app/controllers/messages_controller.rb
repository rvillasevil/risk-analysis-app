class MessagesController < ApplicationController
  before_action :authenticate_user!

  def create
    @risk_assistant = current_user.risk_assistants.find(params[:risk_assistant_id])

    if params[:message].blank? || params[:message][:content].blank?
      flash[:error] = "El mensaje no puede estar vacío."
      redirect_to risk_assistant_path(@risk_assistant) and return
    end

    @message = @risk_assistant.messages.new(message_params.merge(sender: 'user', role: 'user'))

    if @message.save
      if @risk_assistant.thread_id == nil
        #runs thread
        base_url = "https://api.openai.com/v1"
        headers = {
          "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}",
          "Content-Type" => "application/json",
          "OpenAI-Beta" => "assistants=v2"
        }
        thread_id = @risk_assistant.thread_id

        # Añadir mensaje del usuario
        HTTP.post("#{base_url}/threads/#{thread_id}/messages", headers: headers, body: {
          role: "user",
          content: @message
        }.to_json)

        # Lanzar Assistant
        run_id = HTTP.post("#{base_url}/threads/#{thread_id}/runs", headers: headers, body: {
          assistant_id: ENV['OPENAI_ASSISTANT_ID']
        }.to_json).parse["id"]

        # Obtener respuesta
        response_content = HTTP.get("#{base_url}/threads/#{thread_id}/messages", headers: headers).parse["data"].first["content"].first["text"]["value"]

        key_match = response_content.match(/##(.*?)##/)
        if key_match != nil
          key_match = key_match[1]
        end
        value_match = response_content.match(/&&(.*?)&&/)
        if value_match != nil
          value_match = value_match[1]
        end
        @risk_assistant.messages.create(content: response_content, sender: 'assistant2', role: 'assistant', key:key_match, value:value_match, thread_id: @risk_assistant.thread_id)
      else
        response_content = fetch_response_from_openai(@message)
        key_match = response_content.match(/##(.*?)##/)
        if key_match != nil
          key_match = key_match[1]
        end
        value_match = response_content.match(/&&(.*?)&&/)
        if value_match != nil
          value_match = value_match[1]
        end

        @risk_assistant.messages.create(content: response_content, sender: 'assistant', role: 'assistant', key:key_match, value:value_match, thread_id: nil)
      end
    else
      flash[:error] = "No se pudo guardar el mensaje: #{@message.errors.full_messages.join(', ')}"
    end

    redirect_to @risk_assistant
    print response_content
  end

  private

  def message_params
    params.require(:message).permit(:content, :thread_id)
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
      "Actúa como un sistema de recopilación de datos para construir una tabla de riesgos industriales.
        Haz una pregunta por cada campo, una a una, para que el usuario las conteste. Después de cada respuesta, confirma lo recibido y comprueba si la respuesta es correcta (ejemplo: pregunta por sector y la respuesta es algo no reconocible como sector, pregunta de nuevo) y haz la siguiente pregunta hasta completar todos los campos, incluyendo la respuesta resumen anterior:
          - El campo que estás completando, marcado así: ##campo##, con la primera letra en mayúsculas
          - El valor extraído resumido en caso de ser necesario, marcado así: &&valor&&

          Ejemplo:
          - Usuario: Acme Corp
          - Respuesta: Perfecto, el nombre de la empresa es ##name##&&Acme Corp&&.

      Si la respuesta no es válida para el tipo de dato esperado, solicita que se reformule.

      Cuando todos los campos estén completos, muestra una tabla resumen final.

      IDENTIFICACIÓN DE LA EMPRESA:

      Nombre de la empresa (texto)

      Sector (texto)

      Número de empleados (número entero)

      Ingresos anuales (miles de €) (número con decimales)

      Ubicación (texto)

      Actividad principal (texto)

      CARACTERÍSTICAS DE LAS INSTALACIONES:

      Año de construcción del edificio principal (año)

      Número total de edificios en el complejo (número entero)

      Materiales constructivos de cubierta (texto)

      Materiales constructivos de cerramientos (texto)

      Materiales constructivos de tabiquería interior (texto)

      Materiales del forjado y estructura principal (texto)

      Estado de mantenimiento general del edificio (texto)

      SISTEMAS DE PROTECCIÓN CONTRA INCENDIOS (PCI):

      Sistemas PCI existentes (texto)

      Existencia de rociadores automáticos (sí/no)

      Existencia de sistemas de detección de incendios (sí/no, tipo)

      Existencia de sistemas de extracción de humos (sí/no)

      Existencia de depósitos de agua contra incendios (sí/no)

      Sistemas de alarma sonora o luminosa existentes (texto)

      INSTALACIONES TÉCNICAS:

      Tipo de sistema eléctrico principal (texto)

      Tipos de protecciones eléctricas existentes (texto)

      Tipo de sistema de climatización (texto)

      Existencia de plantas de producción de frío o calor (sí/no)

      Instalaciones auxiliares relevantes (texto)

      ALMACENAMIENTO Y ACTIVIDADES ESPECIALES:

      Tipo de almacenamiento (altura, productos almacenados) (texto)

      Existencia de almacenamiento de productos peligrosos (sí/no, especificar)

      Existencia de actividades especiales con riesgo (sí/no, especificar)

      Medidas de prevención aplicadas a las actividades especiales (texto)

      MEDIDAS ORGANIZATIVAS DE SEGURIDAD:

      Existencia de plan de emergencia documentado (sí/no)

      Realización de simulacros de evacuación (sí/no, frecuencia)

      Formación en prevención de riesgos a empleados (sí/no, frecuencia)

      Mantenimiento preventivo de sistemas críticos (sí/no)

      HISTORIAL DE SINIESTROS:

      Existencia de siniestros en los últimos 5 años (sí/no, descripción)

      Reclamaciones a seguros relacionadas (sí/no)

      CUMPLIMIENTO NORMATIVO Y CERTIFICACIONES:

      Existencia de certificaciones de seguridad (ISO, APQ, ATEX, etc.) (sí/no, especificar)

      Cumplimiento de legislación local de prevención de riesgos (sí/no)

      Realización de auditorías de seguridad internas o externas (sí/no, frecuencia)

      SERVICIOS DE EMERGENCIA Y RESPUESTA:

      Distancia al parque de bomberos más cercano (km)

      Adecuación de accesos para bomberos y servicios de emergencia (sí/no)

      VALORACIÓN DE VULNERABILIDAD Y EXPOSICIÓN:

      Estimación del daño máximo posible (en miles de €)

      Existencia de dependencias externas críticas (sí/no, especificar)

      CONFIRMACIONES Y VALIDACIONES:

      Confirmar cada dato usando el formato:
      Perfecto, el valor de ##Campo## es &&Valor&&.

      Si el dato no encaja, pedir reformulación.

      Si un dato no aplica, permitir la respuesta No aplica o N/A.

      FINAL:

      Mostrar una tabla resumen con todos los datos recopilados.
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

