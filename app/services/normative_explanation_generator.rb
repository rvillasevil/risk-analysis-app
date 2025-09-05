class NormativeExplanationGenerator
  OPENAI_URL = "https://api.openai.com/v1/chat/completions".freeze
  MODEL = "gpt-4o-mini"
  HEADERS = {
    "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
    "Content-Type" => "application/json"
  }.freeze

  def self.generate(field_id, question: nil)
    tips = RiskFieldSet.normative_tips_for(field_id)
    return "" if tips.blank?

    label         = RiskFieldSet.label_for(field_id)
    question_text = question.presence || RiskFieldSet.question_for(field_id.to_sym, include_tips: false)
    prompt = <<~PROMPT
      Eres un asistente experto en normativa.
      A partir de la siguiente pregunta de un formulario de análisis de riesgos, proporciona un resumen breve y único de la normativa relacionada.
      Pregunta: #{question_text}
      Campo: #{label}
      Normativa: #{tips}
      Responde en un único párrafo conciso sobre su relevancia.
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