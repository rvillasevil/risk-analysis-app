# frozen_string_literal: true
require "http"
require "json"

class AssistantRunner
  BASE_URL = "https://api.openai.com/v1".freeze
  HEADERS  = {
    "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
    "Content-Type"  => "application/json",
    "OpenAI-Beta"   => "assistants=v2"
  }.freeze

  attr_reader :risk_assistant, :thread_id

  def initialize(risk_assistant)
    @risk_assistant = risk_assistant
    @thread_id      = risk_assistant.thread_id.presence || create_thread
    @fields_json    = build_fields_json
    inject_instructions_once if !risk_assistant.initialised?

  end

  def inject_instructions_once
    dev = <<~SYS
      **LISTA DE CAMPOS (interno)**

      ```json
      #{@fields_json}
      ```

      **Instrucciones para el assistant:**
      1. Tu rol es recopilar los datos de todos los campos anteriores hasta completarlos al 100 %.
      2. Cuando un campo quede claro, confírmalo EXACTAMENTE con: ✅ El campo ##id## es &&Valor&&.
      3. Si la respuesta es incompleta o incoherente, no confirmes el campo; solicita el dato faltante o pide aclaración.
         – Si el usuario desconoce el dato o responde "no aplica", marca el campo como "desconocido".
         – Si se adjuntan archivos, analiza su contenido y extrae los valores de los campos que aparezcan, confimando todos ellos segun el punto 2.
      4. Estas instrucciones y la lista de campos se envían una sola vez al crear el hilo.  
      5. Si el usuario responde "no lo sé", "desconozco", "no aplica", "siguiente pregunta" u otra frase equivalente, valida el campo como "desconocido"."      
    SYS

    HTTP.headers(HEADERS)
        .post("#{BASE_URL}/threads/#{thread_id}/messages",
              json: { role: "developer", content: dev })

    risk_assistant.update!(initialised: true)
  end  

  def submit_user_message(content:, file_id: nil)
    payload = { role: "user", content: content }
    if file_id.present?
      payload[:attachments] = [{ file_id: file_id, tools: [{ type: "file_search" }] }]
    end
    Rails.logger.debug "→ Enviando mensaje de usuario: #{content.inspect}"
    Rails.logger.debug "→ Payload adjunto (si lo hay): #{payload.to_json}"    
    post("#{BASE_URL}/threads/#{thread_id}/messages", payload)
  end

  # Inicia la run y devuelve el TEXTO del último mensaje
  def run_and_wait(timeout: 40)
    run_id = post(
      "#{BASE_URL}/threads/#{thread_id}/runs",
      assistant_id: ENV.fetch("OPENAI_ASSISTANT_ID"),
      temperature: 0
    )["id"]

    timeout.times do
      sleep 1
      break if %w[completed failed expired].include?(run_status(run_id))
    end

    extract_text(last_message)
  end

  private

  def create_thread
    resp = post("#{BASE_URL}/threads", {})
    id   = resp["id"]
    risk_assistant.update!(thread_id: id)
    id
  end

  def build_fields_json
    Rails.logger.info "AssistantRunner: cargando campos desde JSON…"
    file = Rails.root.join("config", "risk_assistant", "fields_gemini.json")
    File.read(file)
  end  

   def run_status(run_id)
    get("#{BASE_URL}/threads/#{thread_id}/runs/#{run_id}")["status"]
  end

  def last_message
    get("#{BASE_URL}/threads/#{thread_id}/messages")["data"].first
  end

  def extract_text(msg)
    return "" unless msg
    msg["content"]
      .select { |c| c["type"] == "text" }
      .map    { |c| c.dig("text", "value") }
      .join("\n")
      .strip
  end

  def post(url, body)
    Rails.logger.debug "→ HTTP POST to #{url} with body:\n#{JSON.pretty_generate(body)}"
    resp = HTTP.headers(HEADERS).post(url, json: body).body.to_s
    Rails.logger.debug "← Response: #{resp.truncate(200).gsub("\n"," ")}"
    JSON.parse(resp)
  end

  def get(url)
    JSON.parse HTTP.headers(HEADERS).get(url).body.to_s
  end
end




