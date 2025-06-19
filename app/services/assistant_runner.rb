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
      1. Cuando reconozcas un campo, responde EXACTAMENTE:
          ✅ El campo ##id_del_campo## es &&Valor&&.
      2. **Antes** de dar por bueno un valor, **analiza** si la respuesta cumple el formato y la información mínima que se está solicitando en la pregunta.
        - Para direcciones, comprueba al menos calle, número, CP y población.
        - Para fechas/años, comprueba 4 dígitos válidos.
        - Para porcentajes, comprueba “%” y valor entre 0–100.    
      3. Si falta algún dato, **no completes el campo** y pregunta de forma específica por el dato faltante, ej:
        – “Habría que indicar también el código postal, ¿me lo puedes dar?”            
      4. No pidas dos campos a la vez.
      5. Valida tipos; si no encaja, pide aclaración.
      6. **Al preguntar**, usa `RiskFieldSet.question_for(id)`:
        - Incluye “Opciones disponibles” si `options` está definido.
        - Incluye “Ejemplo: …” si `example` está definido.
        - Incluye “Importancia: …” si `why` está definido.
      7. Si la respuesta es ambigua, reitera el ejemplo u opciones.
      8. Se adjuntarán documentos, para cada uno de ellos, analiza todo el documento y localiza el contenido de campos de la lista de campos:  ```json#{@fields_json} ``` dentro del documento, de la mayor parte de campos posibles. La respuesta debe contener cada uno de los campos encontrado con su valor, con el siguiente formato de salida: ✅ Perfecto, el campo ##Campo## es &&Valor&&. Importante los ## y && para capturar el valor. Y pregunta por el siguiente campo.      
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

  # ⇒ dentro de la clase AssistantRunner
  def ask_next!
    answered = risk_assistant.messages.where.not(key: nil).pluck(:key)
    field    = RiskFieldSet.next_field_hash(answered)   # helper de RiskFieldSet
    return unless field                                 # ya no quedan

    field_id = field[:id].to_s
    question = RiskFieldSet.question_for(field_id.to_sym)
    instr    = field[:assistant_instructions].to_s.strip

    # guarda la PREGUNTA para que el guardia pueda validarla
    risk_assistant.messages.create!(
      sender:      "assistant",
      role:        "assistant",
      field_asked: field_id,
      key:         nil,
      content:     question,
      thread_id:   thread_id
    )

    extra = +""
    extra << "### Instrucciones de campo:\n#{instr}\n\n" if instr.present?
    extra << "### Pregunta EXACTA:\n#{question}\n\n"
    extra << "⚠️ Tras confirmar, responde SOLO \"OK\" y espera la siguiente instrucción."

    post("#{BASE_URL}/threads/#{thread_id}/runs",
        assistant_id:            ENV['OPENAI_ASSISTANT_ID'],
        additional_instructions: extra,
        temperature:             0)
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
    # Enviamos TODO lo que el modelo necesita:
    RiskFieldSet.flat_fields.map { |f|
      {
        id:          f[:id],
        label:       f[:label],
        type:        f[:type],
        options:     f[:options],
        context:     f[:context],
        validation:  f[:validation],
        assistant_instructions: f[:assistant_instructions]
      }
    }.to_json
  end

    # ------------------------------------------------------------
    # Encuentra el siguiente campo que NO tenga valor en BD
    # ------------------------------------------------------------
    def next_pending_field
      # 1) Determinar si ya respondieron "constr_num_edificios"
      count_msg = @risk_assistant.messages
                    .where(key: "constr_num_edificios")
                    .order(:created_at).last
      if count_msg
        total_buildings = count_msg.value.to_i
        array_id = "constr_edificios_detalles_array"

        # Inicializar estado para este array si no existe
        @array_state ||= {}
        @array_state[array_id] ||= { idx: 0, count: total_buildings }

        state = @array_state[array_id]
        # Si aún quedan edificios por procesar
        if state[:idx] < state[:count]
          # Obtener lista de subcampos hijos (sin índice) para este array
          children = RiskFieldSet.children_of_array(array_id)
          # Para cada subcampo, construimos clave completa
          children.each do |child|
            child_base = child[:id].split(".").last  # ej. "edif_nombre_uso"
            full_key = "#{array_id}.#{state[:idx]}.#{child_base}"
            # Si no existe mensaje con ese key, devolvemos este campo pendiente
            return full_key.to_sym unless @risk_assistant.messages.exists?(key: full_key)
          end

          # Si llegamos acá, significa que ya respondimos todos los hijos
          # del edificio actual, así que pasamos al siguiente
          state[:idx] += 1
          # Volvemos a invocar recursivamente para avanzar
          return next_pending_field
        end
      end

      # 2) Si no hay array en proceso (o ya acabó), caemos al flujo normal:
      done_keys = @risk_assistant.messages.where.not(key: nil).pluck(:key).map(&:to_sym)
      all_ids   = RiskFieldSet.flat_fields.map { |f| f[:id].to_sym }
      (all_ids - done_keys).first
    end

  # ------------------------------------------------------------
  # Lanza la run con instrucciones + la PREGUNTA exacta
  # ------------------------------------------------------------
  def start_run_with_instructions
    
    field    = next_pending_field
    return unless field
    question = RiskFieldSet.question_for(field)   # ← YA incluye opciones

    # ↓ Recupera las instrucciones privadas que el JSON trae para ese campo
    instr = RiskFieldSet.by_id[
              # Si field incluye índice, quitamos “.0.edif_nombre_uso” para buscar las instrucciones
              field.to_s.include?(".") ?
                field.to_s.sub(/\.\d+\.(.+)$/, '.\1').to_sym :
                field 
          ][:assistant_instructions].to_s.strip

    # 3) Recuperamos las instrucciones privadas para este campo (sin índice si lo hubiera)
    #    Ej.: si field == :"constr_edificios_detalles_array.0.edif_nombre_uso",
    #    queremos buscar en JSON por :"constr_edificios_detalles_array.edif_nombre_uso"
    base_key =
      if field.to_s.include?(".")
        # quitamos el “.0.” o “.1.” dejando “array_id.child_id”
        field.to_s.sub(/\.\d+\.(.+)$/, '.\1').to_sym
      else
        field
      end

    # Guardar SOLO la pregunta que ve el usuario:
    @risk_assistant.messages.create!(
      sender:      "assistant",
      role:        "assistant",
      content:     question,
      field_asked: field.to_s,
      thread_id:   thread_id
    )          

    field_asked = field.to_s.strip

    # Acceso seguro al label del siguiente campo pendiente
    npf = next_pending_field
    label = ""
    if npf
      byid = RiskFieldSet.by_id[npf.to_sym]
      label = byid[:label].to_s.strip if byid
    end

    extra = <<~SYS
      Lista interna de campos (no mostrar al usuario):
      ```json
      #{@fields_json}
      ```
      Instrucciones para el assistant:
      1. Reconoce SOLO los campos anteriores.
      2. No pidas más de un campo a la vez.
      
      3. Usa SIEMPRE **la siguiente pregunta EXACTA**:
        #{question} e incluye siempre las opciones si existen para ese campo:
        # 👉  Instrucciones específicas del campo que estás preguntando:
        #{instr.presence ? instr : "ninguna"}        
      4. Antes de validar un valor:
        – Si el campo es *select*, comprueba q<ue la respuesta esté en
          las opciones. Si no, muestra de nuevo la lista.
        – Aplica también las reglas de `context`, `validation`, etc.
      5. Tras ✅ confirmar, no hagas otra pregunta hasta que la app te
        envíe la siguiente instrucción.
      6. Usa la plantilla indicada en assistant_instructions si existe
      7. Si se adjunta un archivo, busca la información relacionada con cada uno de los campos, y valida cada uno de ellos.
    SYS
 
    resp = post(
      "#{BASE_URL}/threads/#{thread_id}/runs",
      assistant_id:           ENV.fetch("OPENAI_ASSISTANT_ID"),
      additional_instructions: extra,
      temperature: 0
    )
    Rails.logger.debug "↳ Instrucciones de campo: #{instr.truncate(120)}" if instr.present?
    resp["id"]
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




