class OnboardingAssistantRunner
  BASE_URL = defined?(AssistantRunner::BASE_URL) ? AssistantRunner::BASE_URL : 'https://api.openai.com/v1'
  HEADERS  = if defined?(AssistantRunner::HEADERS)
               AssistantRunner::HEADERS
             else
               {
                 'Authorization' => "Bearer #{ENV.fetch('OPENAI_API_KEY', nil)}",
                 'Content-Type' => 'application/json',
                 'OpenAI-Beta' => 'assistants=v2'
               }
             end

  attr_reader :field_catalogue, :thread_id

  def initialize(field_catalogue)
    @field_catalogue = field_catalogue
    @thread_id = field_catalogue.thread_id.presence || create_thread
    field_catalogue.ensure_thread!(@thread_id)
    inject_instructions_once
  end

  def start_conversation!
    run_and_capture(additional_instructions: <<~PROMPT)
      Saluda brevemente y plantea la primera pregunta necesaria para entender qué información quiere recopilar el owner. Haz una sola pregunta y espera respuesta.
    PROMPT
  end

  def send_owner_message(content)
    record_message('user', content)
    post_message(role: 'user', content: content)
    run_and_capture
  end

  def request_catalogue_json
    prompt = <<~PROMPT
      Gracias. Ahora genera un JSON siguiendo exactamente este formato:
      {
        "sections": [
          {
            "id": "identificador_en_snake_case",
            "title": "Título",
            "fields": [
              {
                "id": "campo_id",
                "label": "Etiqueta visible",
                "prompt": "Pregunta que se hará al cliente",
                "type": "string|number|select|boolean|array_of_objects",
                "options": ["opcion1", "opcion2"],
                "assistant_instructions": "Instrucciones privadas",
                "normative_tips": "Tip normativo si existe"
              }
            ]
          }
        ]
      }
      Incluye los campos discutidos. Si hay tablas, utiliza "type": "array_of_objects" e incluye un objeto "item_schema" con las columnas.
      Devuelve únicamente el JSON sin comentarios adicionales ni marcas de Markdown.
    PROMPT

    post_message(role: 'user', content: prompt)
    run_and_capture
  end

  private

  def inject_instructions_once
    return if field_catalogue.instructions_injected_at.present?

    instructions = <<~SYS
      Actúas como un consultor que ayuda a un corredor de seguros a definir el catálogo de campos que su asistente de riesgos preguntará a los clientes.
      Mantén una conversación paso a paso, formulando una sola pregunta cada vez.
      Profundiza en secciones, tipos de campos, opciones y validaciones necesarias.
      No generes el catálogo JSON hasta que el usuario lo solicite explícitamente.
      Registra mentalmente las decisiones para poder volcarlas a JSON al final.
    SYS

    post_message(role: 'developer', content: instructions)
    field_catalogue.update!(instructions_injected_at: Time.current)
  end

  def post_message(role:, content:)
    HTTP.headers(HEADERS)
        .post("#{BASE_URL}/threads/#{thread_id}/messages", json: { role: role, content: content })
  end

  def run_and_capture(additional_instructions: nil)
    run_id = start_run(additional_instructions: additional_instructions)
    return '' unless run_id

    status = wait_for_completion(run_id)
    return '' unless status == 'completed'

    messages = messages_for_run(run_id)
    assistant_messages = messages.select { |msg| msg['role'] == 'assistant' }
    texts = assistant_messages.map { |msg| extract_text(msg) }.reject(&:blank?)

    texts.each { |text| record_message('assistant', text) }

    texts.last.to_s
  end

  def start_run(additional_instructions: nil)
    payload = {
      assistant_id: ENV.fetch('OPENAI_ONBOARDING_ASSISTANT_ID'),
      temperature: 0
    }
    payload[:additional_instructions] = additional_instructions if additional_instructions.present?

    response = HTTP.headers(HEADERS)
                  .post("#{BASE_URL}/threads/#{thread_id}/runs", json: payload)
                  .body
                  .to_s
    JSON.parse(response)['id']
  rescue KeyError
    raise 'Falta la variable de entorno OPENAI_ONBOARDING_ASSISTANT_ID'
  end

  def wait_for_completion(run_id)
    60.times do
      sleep 1
      resp = HTTP.headers(HEADERS)
                 .get("#{BASE_URL}/threads/#{thread_id}/runs/#{run_id}")
                 .body
                 .to_s
      status = JSON.parse(resp)['status']
      return status if %w[completed failed cancelled expired].include?(status)
    end

    'expired'
  end

  def messages_for_run(run_id)
    resp = HTTP.headers(HEADERS)
               .get("#{BASE_URL}/threads/#{thread_id}/messages?run_id=#{run_id}")
               .body
               .to_s
    JSON.parse(resp)['data'] || []
  end

  def extract_text(message)
    Array(message['content']).select { |c| c['type'] == 'text' }
                             .map { |c| c.dig('text', 'value') }
                             .join("\n")
                             .strip
  end

  def record_message(role, content)
    field_catalogue.messages.create!(role: role, content: content)
  end

  def create_thread
    resp = HTTP.headers(HEADERS)
               .post("#{BASE_URL}/threads", json: {})
               .body
               .to_s
    JSON.parse(resp)['id']
  end
end