class AnswerValidator
  OPENAI_URL = "https://api.openai.com/v1/chat/completions".freeze
  MODEL      = "gpt-4o-mini"
  HEADERS    = {
    "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
    "Content-Type"  => "application/json"
  }.freeze

  def self.validate(question:, answer:, context:)
    prompt = <<~PROMPT
      Eres un validador que decide si la respuesta de un usuario resuelve la pregunta solicitada.

      ### Contexto confirmado
      #{context}

      ### Pregunta
      #{question}

      ### Respuesta del usuario
      #{answer}

      Devuelve solo una de las siguientes opciones:
      - "VALID" si la respuesta satisface completamente la pregunta.
      - "INCOMPLETE: <motivo>" si falta información relevante.
      - "INVALID: <motivo>" si la respuesta no corresponde o es errónea.
    PROMPT

    body = {
      model:       MODEL,
      temperature: 0.3,
      max_tokens:  1000,
      messages:    [ { role: "user", content: prompt } ]
    }

    resp_txt = HTTP
                 .headers(HEADERS)
                 .post(OPENAI_URL, json: body)
                 .parse.dig("choices", 0, "message", "content").to_s.strip

    case resp_txt
    when /^VALID\b/i
      { status: :valid }
    when /^INCOMPLETE:\s*(.+)/i
      { status: :incomplete, message: $1.strip }
    when /^INVALID:\s*(.+)/i
      { status: :invalid, message: $1.strip }
    else
      { status: :valid }
    end
  rescue => e
    Rails.logger.error "AnswerValidator error: #{e.message}"
    { status: :valid }
  end
end