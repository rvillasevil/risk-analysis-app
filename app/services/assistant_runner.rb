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
    inject_instructions_once if !risk_assistant.initialised?
    @fields_json    = build_fields_json
  end

  def inject_instructions_once
    dev = <<~SYS
      **LISTA DE CAMPOS (interno)**

      ```json
      #{@fields_json}
      ```

      **Instrucciones al Assistant:**
      1. Cuando reconozcas un campo, responde EXACTO:
          ✅ Perfecto, el campo ##id_del_campo## es &&Valor&&.
      2. **Antes** de dar por bueno un valor, **analiza** si la respuesta cumple el formato y la información mínima:
        - Para direcciones, comprueba al menos calle, número, CP y población.
        - Para fechas/años, comprueba 4 dígitos válidos.
        - Para porcentajes, comprueba “%” y valor entre 0–100.    
      3. Si falta algún dato, **no completes el campo** y pregunta de forma específica:
        – “Habría que indicar también el código postal, ¿me lo puedes dar?”            
      4. No pidas dos campos a la vez.
      5. Respeta las reglas `visible_if` del YAML.
      6. Valida tipos; si no encaja, pide aclaración.
      7. **Al preguntar**, usa `RiskFieldSet.question_for(id)`:
        - Incluye “Opciones disponibles” si `options` está definido.
        - Incluye “Ejemplo: …” si `example` está definido.
        - Incluye “Importancia: …” si `why` está definido.
      8. Si la respuesta es ambigua, reitera el ejemplo u opciones.
      9. Si un campo depende de otro (visible_if, follow_ups),
        - ignora preguntas no relevantes.
      10. Se adjuntarán documentos, para cada uno de ellos, analiza todo el documento y localiza el contenido de campos de la lista de campos:  ```json#{@fields_json} ``` dentro del documento, de la mayor parte de campos posibles. La respuesta debe contener cada uno de los campos encontrado con su valor, con el siguiente formato de salida: ✅ Perfecto, el campo ##Campo## es &&Valor&&. Importante los ## y && para capturar el valor. Y pregunta por el siguiente campo.      
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
    run_id = start_run_with_instructions

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
    Rails.logger.info "AssistantRunner: generando lista de campos…"
    RiskFieldSet.flat_fields.map { |f| { id: f[:id], label: f[:label] } }.to_json
  end

  # ------------------------------------------------------------
  # Encuentra el siguiente campo que NO tenga valor en BD
  # ------------------------------------------------------------
  def next_pending_field
    done = risk_assistant.messages.where.not(key: nil).pluck(:key).map(&:to_sym)
    all_ids = RiskFieldSet.flat_fields.map { |f| f[:id].to_sym }
    (all_ids - done).first
  end

  # ------------------------------------------------------------
  # Lanza la run con instrucciones + la PREGUNTA exacta
  # ------------------------------------------------------------
  def start_run_with_instructions
    field    = next_pending_field
    question = RiskFieldSet.question_for(field)

    extra = <<~SYS
      Lista interna de campos (no mostrar al usuario):
      ```json
      #{@fields_json}
      ```

      Instrucciones:
      1. Reconoce SOLO los campos de la lista de arriba.
      2. No pidas más de un campo a la vez.
      3. Mantén las dependencias (`visible_if` / `follow_ups`).
      4. **Ahora**, formula la siguiente pregunta EXACTAMENTE así:
         #{question}
      5. Valida la respuesta según el `context` y confirma usando el
         formato ✅ Perfecto, el campo ##Campo## es &&Valor&&.
      6. Si la respuesta no está entre las opciones, díselo y repítela.
      7. No hagas preguntas nuevas hasta confirmar el campo actual.
    SYS

    # ——— LOG completo del prompt ———
    Rails.logger.debug "-----------------------------"
    Rails.logger.debug "PROMPT COMPLETO A OPENAI:"
    Rails.logger.debug extra
    Rails.logger.debug "-----------------------------"
    # ——————————————————————————   

    post(
      "#{BASE_URL}/threads/#{thread_id}/runs",
      assistant_id:            ENV.fetch("OPENAI_ASSISTANT_ID"),
      additional_instructions: extra,
      temperature:             0,
      top_p:                   0
    )["id"]
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




