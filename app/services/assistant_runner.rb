# lib/assistant_runner.rb
require "http"

class AssistantRunner
  BASE_URL = "https://api.openai.com/v1".freeze
  HEADERS  = {
    "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}",
    "Content-Type"  => "application/json",
    "OpenAI-Beta"   => "assistants=v2"
  }.freeze

  attr_reader :risk_assistant, :thread_id

  # ------------------------------------------------------------
  # new(risk_assistant)
  # • Usa thread existente o lo crea y guarda en BD
  # • Inyecta mensajes developer una única vez
  # ------------------------------------------------------------
  def initialize(risk_assistant)
    @risk_assistant = risk_assistant
    @thread_id      = risk_assistant.thread_id.presence || create_thread
    inject_developer_messages unless risk_assistant.initialised?
  end

  # ------------------------------------------------------------
  # Enviar mensaje del usuario (+adjunto opcional)
  # ------------------------------------------------------------
  def submit_user_message(content:, file_id: nil)
    payload = { role: "user", content: content }
    if file_id
      payload[:attachments] = [
        { file_id: file_id, tools: [{ type: "file_search" }] }
      ]
    end

    HTTP.headers(HEADERS)
        .post("#{BASE_URL}/threads/#{thread_id}/messages", json: payload)
  end

  # ------------------------------------------------------------
  # Lanza la run y espera (timeout en segundos)
  # Devuelve **el texto** del último mensaje del assistant
  # ------------------------------------------------------------
  def run_and_wait(timeout: 40)
    run_id = start_run
    timeout.times do
      sleep 1
      break if %w[completed failed expired].include?(run_status(run_id))
    end
    extract_text(last_message)
  end

  # ==================================================================
  private
  # ==================================================================

  # ---------- crear thread ----------
  def create_thread
    resp = HTTP.headers(HEADERS).post("#{BASE_URL}/threads", json: {})
    id   = JSON.parse(resp.body)["id"]
    risk_assistant.update!(thread_id: id)
    id
  end

  # ---------- inyectar mensajes developer (solo 1ª vez) ------------
  def inject_developer_messages
    # 1. lista completa de campos (para uso interno)
    post_dev(
      "Lista de campos para uso interno, NO mostrar al usuario:\n" \
      "```json\n#{RiskFieldSet.all.to_json}\n```"
    )

    # 2. instrucciones permanentes para cada fichero
    post_dev <<~DEV
      **Instrucciones para cada archivo adjunto**

      1. Usa la herramienta `file_search` para analizar su texto, encabezados y tablas.
      2. Identifica todos los campos de la lista que aparezcan.
      3. Devuelve **en una única respuesta** los valores hallados con el formato:
           ✅ Perfecto, el campo ##Campo## es &&Valor&&.
      4. Marca internamente esos campos como completados; no los solicites de nuevo.
      5. Continúa preguntando solo por el siguiente campo pendiente.
    DEV

    risk_assistant.update!(initialised: true)
  end

  def post_dev(content)
    HTTP.headers(HEADERS)
        .post("#{BASE_URL}/threads/#{thread_id}/messages",
              json: { role: "developer", content: content })
  end

  # ---------- arrancar run ----------
  def start_run
    resp = HTTP.headers(HEADERS)
               .post("#{BASE_URL}/threads/#{thread_id}/runs",
                     json: { assistant_id: ENV.fetch("OPENAI_ASSISTANT_ID") })
    JSON.parse(resp.body)["id"]
  end

  # ---------- estado de la run ----------
  def run_status(run_id)
    resp = HTTP.headers(HEADERS)
               .get("#{BASE_URL}/threads/#{thread_id}/runs/#{run_id}")
    JSON.parse(resp.body)["status"]
  end

  # ---------- último mensaje ----------
  def last_message
    resp = HTTP.headers(HEADERS)
               .get("#{BASE_URL}/threads/#{thread_id}/messages")
    JSON.parse(resp.body)["data"].first # ya está ordenado desc
  end

  # ---------- extraer texto plano de un mensaje ----------
  def extract_text(msg_hash)
    return "" unless msg_hash
    msg_hash["content"]
      .select { |c| c["type"] == "text" }
      .map    { |c| c.dig("text", "value") }
      .join("\n")
      .strip
  end
end


