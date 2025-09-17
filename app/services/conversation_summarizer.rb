class ConversationSummarizer
  OPENAI_URL = "https://api.openai.com/v1/chat/completions".freeze
  MODEL = "gpt-4o-mini"
  HEADERS = {
    "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
    "Content-Type"  => "application/json"
  }.freeze

  def self.summarize(risk_assistant)
    confirmations = risk_assistant.messages
                                 .where.not(key: nil)
                                 .order(:created_at)
                                 .map { |m| "#{RiskFieldSet.label_for(m.key, owner: risk_assistant.catalogue_owner)}: #{m.value}" }
    return "" if confirmations.empty?

    prompt = <<~PROMPT
      Resume los siguientes datos confirmados de manera concisa:
      #{confirmations.join("\n")}
    PROMPT

    body = {
      model: MODEL,
      messages: [ { role: "user", content: prompt } ],
      temperature: 0.7
    }

    response = HTTP.headers(HEADERS).post(OPENAI_URL, json: body)
    response.parse.dig("choices", 0, "message", "content").to_s.strip
  rescue => e
    Rails.logger.error "ConversationSummarizer error: #{e.class} – #{e.message}"
    ""
  end
end