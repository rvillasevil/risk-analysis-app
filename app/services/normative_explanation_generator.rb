class NormativeExplanationGenerator
  OPENAI_URL = "https://api.openai.com/v1/chat/completions".freeze
  MODEL = "gpt-4o-mini"
  HEADERS = {
    "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
    "Content-Type" => "application/json"
  }.freeze

  def self.generate(field_id)
    tips = RiskFieldSet.normative_tips_for(field_id)
    return "" if tips.blank?

    label = RiskFieldSet.label_for(field_id)
    prompt = <<~PROMPT
      Eres un asistente experto en normativa. Explica brevemente la normativa relacionada con el siguiente campo de un formulario de análisis de riesgos.
      Campo: #{label}
      Normativa: #{tips}
      Responde en un párrafo conciso sobre su relevancia.
    PROMPT

    body = {
      model: MODEL,
      messages: [ { role: "user", content: prompt } ],
      temperature: 0.2
    }

    HTTP.headers(HEADERS).post(OPENAI_URL, json: body).parse.dig("choices", 0, "message", "content").to_s.strip
  rescue => e
    Rails.logger.error "NormativeExplanationGenerator error: #{e.class} – #{e.message}"
    ""
  end
end