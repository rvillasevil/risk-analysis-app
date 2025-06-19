# app/services/document_field_extractor.rb
require "json"
require "http"

class DocumentFieldExtractor
  OPENAI_URL    = "https://api.openai.com/v1/chat/completions".freeze
  OPENAI_MODEL  = "gpt-4o-mini"
  OPENAI_HEADERS = {
    "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
    "Content-Type"  => "application/json"
  }.freeze

  # Dado un texto extraído de uno o varios ficheros, devuelve un hash { campo_id => valor } 
  # para todos los campos del JSON que aparezcan en dicho texto.
  def self.call(extracted_text)
    return {} if extracted_text.blank?

    # 1) Construir el array reducido de campos: solo id y label
    fields_info = RiskFieldSet.flat_fields.map do |f|
      { "id" => f[:id].to_s, "label" => f[:label].to_s }
    end

    # 2) Armar el prompt para que el LLM extraiga todos los campos del texto.
    prompt = <<~PROMPT
      Tienes una lista de campos (id + label) en formato JSON:
      #{fields_info.to_json}

      A continuación tienes un texto extraído de uno o varios documentos:
      -----------------------------------------------------------------
      #{extracted_text}
      -----------------------------------------------------------------

      Tu tarea es:  
      – Buscar la información relativa a los campos.  
      – Para cada campo que encuentres información relativa, devolverás una línea EXACTA con:
          ##<campo_id>## &&<valor extraído>&&
        donde `<campo_id>` es el id del campo tal como aparece en el JSON,  
        y `<valor extraído>` son los fragmentos de texto asociado a ese campo.  
      – Solo debes incluir los campos que de verdad estén presentes en el texto.  
      – Cada línea debe seguir exactamente este patrón:  
          ##campo_id## &&valor&&  
      – Si no encuentras ningún campo en el texto, respondes exactamente (sin nada más):  
          Ningún dato encontrado

      Ejemplo de salida (solo si se detecta “nombre_empresa”: “ACME S.A.” y “direccion”: “Calle Falsa 123”):  
      ##nombre_empresa## &&ACME S.A.&&  
      ##direccion## &&Calle Falsa 123&&

      => Ahora hazlo sobre el texto real:
      #{extracted_text}
    PROMPT

    # 3) Llamar a OpenAI
    body = {
      model: OPENAI_MODEL,
      temperature: 0.7,
      max_tokens: 512,
      messages: [
        { role: "user", content: prompt }
      ]
    }

    response = HTTP
                 .headers(OPENAI_HEADERS)
                 .post(OPENAI_URL, json: body)
    content = response.parse.dig("choices", 0, "message", "content") || ""
    raw = content.to_s.strip

    return {} if raw.blank? || raw.match?(/ningún dato encontrado/i)

    # 4) Parsear líneas con el patrón ##campo_id## &&valor&&
    pairs = raw.scan(/##(.*?)##\s*&&\s*(.*?)\s*&&/m)
    # Convertimos a hash: { "campo_id" => "valor", … }
    pairs.to_h
  rescue => e
    Rails.logger.error "DocumentFieldExtractor error: #{e.message}"
    {}
  end
end
