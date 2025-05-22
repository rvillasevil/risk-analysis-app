# app/services/assistant_runner.rb
# frozen_string_literal: true

require "http"
require "json"

class AssistantRunner
  BASE_URL = "https://api.openai.com/v1"
  HEADERS  = {
    "Authorization" => "Bearer #{ENV.fetch('OPENAI_API_KEY')}",
    "Content-Type"  => "application/json",
    "OpenAI-Beta"   => "assistants=v2"
  }.freeze

  attr_reader :risk_assistant, :thread_id

  # ------------------------------------------------------------
  # new(risk_assistant)
  #   • Usa el thread existente o lo crea y lo guarda en BD.
  #   • Prepara la lista de campos (memoizada)
  # ------------------------------------------------------------
  def initialize(risk_assistant)
    @risk_assistant = risk_assistant
    @thread_id      = risk_assistant.thread_id.presence || create_thread
    @fields_json    = build_fields_json         # sólo se calcula 1 vez
  end

  # ------------------------------------------------------------
  # Enviar turno del usuario (más adjunto opcional)
  # ------------------------------------------------------------
  def submit_user_message(content:, file_id: nil)
    payload = { role: "user", content: content }
    if file_id.present?
      payload[:attachments] = [
        { file_id: file_id, tools: [{ type: "file_search" }] }
      ]
    end
    post("#{BASE_URL}/threads/#{thread_id}/messages", payload)
  end

  # ------------------------------------------------------------
  # Lanza la run y devuelve **texto** del último mensaje del assistant
  # ------------------------------------------------------------
  def run_and_wait(timeout: 40)
    run_id = start_run_with_instructions

    timeout.times do
      sleep 1
      break if %w[completed failed expired].include?(run_status(run_id))
    end

    extract_text(last_message)
  end

  # =================================================================
  private
  # =================================================================

  # ---------- Crear thread y guardarlo en BD ---------- #
  def create_thread
    resp = post("#{BASE_URL}/threads", {})
    id   = resp["id"]
    risk_assistant.update!(thread_id: id)
    id
  end

  # ---------- Construye lista de campos (json compacto) ---------- #
  def build_fields_json
    Rails.logger.info "AssistantRunner: generando lista de campos…"
    RiskFieldSet.flat_fields.map { |f| { id: f[:id], label: f[:label] } }.to_json
  end

  # ---------- Arranca la run con instrucciones adicionales ---------- #
  def start_run_with_instructions
    extra_instructions = <<~SYS
      Lista de campos (para uso interno):

      ```json
      #{@fields_json}
      ```

      Instrucciones:
      1. Cuando reconozcas un campo responde exactamente:
           ✅ Perfecto, el campo ##Campo## es &&Valor&&.
      2. No pidas dos campos a la vez.
      3. Respeta las condiciones `visible_if` del YAML.
      4. Valida el tipo de dato y, si no encaja, pide aclaración.
    SYS

    resp = post("#{BASE_URL}/threads/#{thread_id}/runs",
                assistant_id:        ENV.fetch("OPENAI_ASSISTANT_ID"),
                additional_instructions: extra_instructions)
    resp["id"]
  end

  # ---------- Estado de la run ---------- #
  def run_status(run_id)
    get("#{BASE_URL}/threads/#{thread_id}/runs/#{run_id}")["status"]
  end

  # ---------- Último mensaje del thread ---------- #
  def last_message
    get("#{BASE_URL}/threads/#{thread_id}/messages")["data"].first
  end

  # ---------- Extrae texto del mensaje ---------- #
  def extract_text(msg_hash)
    return "" unless msg_hash

    msg_hash["content"]
      .select { |c| c["type"] == "text" }
      .map    { |c| c.dig("text", "value") }
      .join("\n")
      .strip
  end

  # ----------------------------------------------------------------
  # Helpers HTTP (devuelven hash ya parseado)
  # ----------------------------------------------------------------
  def post(url, body_hash)
    JSON.parse HTTP.headers(HEADERS).post(url, json: body_hash).body.to_s
  end

  def get(url)
    JSON.parse HTTP.headers(HEADERS).get(url).body.to_s
  end
end


