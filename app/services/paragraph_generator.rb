class ParagraphGenerator
  OPENAI_URL = "https://api.openai.com/v1/chat/completions".freeze
  MODEL = "gpt-4o-mini"
  HEADERS = {
    "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
    "Content-Type"  => "application/json"
  }.freeze

  def self.generate(question:, instructions:, normative_tips:, confirmations: [], field_id: nil)
    confirm_block = confirmations.any? ? "Confirmaciones previas:\n#{confirmations.join("\n")}\n\n" : ""

    prompt = <<~PROMPT
      #{confirm_block}
      Eres un asistente para la toma de datos de riesgos de forma conversacional.
      Genera la siguiente consulta en un máximo de cuatro párrafos. Usa las instrucciones para formular la pregunta e incluye los tipos normativos en el desarrollo:
      Confirmación del campo anterior:
      Pregunta: #{question}
      Instrucciones: #{instructions}
      Tipos normativos: #{normative_tips}
      Especifica de forma clara las preguntas.
      PROMPT

    body = {
      model: MODEL,
      messages: [ { role: "user", content: prompt } ],
      temperature: 0.7
    }

    response = HTTP.headers(HEADERS).post(OPENAI_URL, json: body)
    main_text = response.parse.dig("choices", 0, "message", "content").to_s.strip

    explanation = field_id ? NormativeExplanationGenerator.generate(field_id) : ""
    [main_text, (explanation.present? ? "Ex. Normativa: #{explanation}" : nil)].compact.join("\n\n")
  rescue => e
    Rails.logger.error "ParagraphGenerator error: #{e.class} – #{e.message}"
    ""
  end
end