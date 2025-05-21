# lib/assistant_runner.rb
require "http"             # gem 'http' en tu Gemfile

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
  #   • Usa el thread existente o lo crea y lo guarda en BD.
  # ------------------------------------------------------------
  def initialize(risk_assistant)
    @risk_assistant = risk_assistant
    @thread_id      = risk_assistant.thread_id.presence || create_thread
  end

  # ------------------------------------------------------------
  # Enviar el mensaje del usuario
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
  # Lanza la run y espera hasta 30 s (o lo que indiques)
  # Devuelve el ÚLTIMO mensaje del assistant.
  # ------------------------------------------------------------
  def run_and_wait(timeout: 30)
    run_id = start_run

    timeout.times do
      sleep 1
      status = run_status(run_id)
      break if %w[completed failed expired].include?(status)
    end

    last_message
  end

  private

  # ---------- crear thread ----------
  def create_thread
    resp = HTTP.headers(HEADERS).post("#{BASE_URL}/threads", json: {})
    id   = JSON.parse(resp.body)["id"]
    risk_assistant.update!(thread_id: id)
    id
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
    JSON.parse(resp.body)["data"].first
  end
end
