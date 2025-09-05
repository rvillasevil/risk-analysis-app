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
      6. **Al preguntar**, usa `RiskFieldSet.question_for(id)` y 'assistant_instructions' para formular la pregunta.
        - Incluye “Opciones disponibles” si `options` está definido.
        - Incluye “Ejemplo: …” si `example` está definido.
        - Incluye normative_tips si está definido.
      7. Si la respuesta es ambigua, reitera el ejemplo u opciones.
      8. Si la respuesta no guarda relación con el campo preguntado, repite la misma pregunta indicando que la respuesta no es válida.
        - Ejemplos de respuestas no válidas: "no lo sé", "ninguna", "¿qué es esto?", "otro tema".
      9. Si el usuario responde "no aplica", "siguiente pregunta", o desconoce el dato, valida el campo como "desconocido"."
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

  # ⇒ dentro de la clase AssistantRunner
  def ask_next!
    answered = risk_assistant.messages.where.not(key: nil).pluck(:key)
    field    = RiskFieldSet.next_field_hash(answered)   # helper de RiskFieldSet

    unless field
      summary = ConversationSummarizer.summarize(risk_assistant)
      if summary.present?
        risk_assistant.messages.create!(
          sender:    "assistant",
          role:      "assistant",
          content:   summary,
          thread_id: thread_id
        )
      end
      return
    end                               # ya no quedan

    if field
      field_id = field[:id].to_s
      question = RiskFieldSet.question_for(field_id.to_sym, include_tips: true)
      instr    = field[:assistant_instructions].to_s.strip
      tips = RiskFieldSet.normative_tips_for(field_id)
    # guarda la PREGUNTA para que el guardia pueda validarla

      risk_assistant.messages.create!(
        sender:      "assistant_guard",
        role:        "assistant",
        field_asked: field_id,
        key:         nil,
        content:     question,
        thread_id:   thread_id
      )

      confirmations = risk_assistant.messages
                                    .where.not(key: nil)
                                    .order(:created_at)
                                    .map { |m| "✅ #{RiskFieldSet.label_for(m.key)}: #{m.value}" }

      history_block = confirmations.any? ? "### Historial de respuestas confirmadas:\n#{confirmations.join("\n")}\n\n" : ""

      extra = +""
      extra << history_block
      extra << "### Instrucciones de campo:\n#{instr}\n\n" if instr.present?
      extra << "### Tip normativo:\n#{tips}\n\n" if tips.present?
      extra << "### Pregunta:\n#{question}\n\n"
      extra << "⚠️ Tras confirmar, responde SOLO \"OK\" y espera la siguiente instrucción."
      extra << "\nAntes de formular la siguiente pregunta, revisa este historial y señala cualquier contradicción detectada."

      
      expanded = ParagraphGenerator.generate(question: question,
                                             instructions: instr,
                                             normative_tips: tips,
                                             confirmations: confirmations,
                                             field_id: field_id)  
      risk_assistant.messages.create!(
        sender:    "paragraph_generator",
        role:      "assistant",
        content:   expanded,
        field_asked: field_id,
        thread_id: thread_id
      )
    end
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
        assistant_instructions: f[:assistant_instructions],
        normative_tips: f[:normative_tips]
      }
    }.to_json
  end

    # ------------------------------------------------------------
    # Encuentra el siguiente campo que NO tenga valor en BD
    # ------------------------------------------------------------
  def next_pending_field
    answered = @risk_assistant.messages.where.not(key: nil).pluck(:key).to_set
    root_fields = RiskFieldSet.flat_fields.select { |f| f[:parent].nil? }

    root_fields.each do |field|
      if field[:type] == :array_of_objects
        pending = next_from_array(field[:id], [], answered)
        return pending if pending
      else
        return field[:id].to_sym unless answered.include?(field[:id])
      end
    end
    nil
  end

  def next_from_array(array_id, prefix_parts, answered)
    info = RiskFieldSet.by_id[array_id.to_sym]
      return nil unless info

    count_field = info[:array_count_source_field_id]

    if count_field
      count_key = (prefix_parts + [count_field]).reject(&:blank?).join('.')
      count_msg = @risk_assistant.messages.where(key: count_key).order(:created_at).last
      return count_key.to_sym unless count_msg
      count = count_msg.value.to_i
    else
      prefix = (prefix_parts + [array_id]).reject(&:blank?).join('.')
      idx_re  = /^#{Regexp.escape(prefix)}\.(\d+)\./
      existing = answered.map { |k| k[idx_re, 1] }.compact.map(&:to_i)
      count = [existing.max.to_i + 1, 1].max
    end

    (0...count).each do |idx|
      item_prefix = prefix_parts + [array_id, idx]
      RiskFieldSet.children_of_array(array_id).each do |child|
        if child[:type] == :array_of_objects
          pending = next_from_array(child[:id], item_prefix, answered)
          return pending if pending
        else
          suffix = child[:id].sub(/^#{Regexp.escape(array_id)}\./, '')
          key = (item_prefix + [suffix]).join('.')
          return key.to_sym unless answered.include?(key)
        end
      end
    end

    if count_field.nil? && info[:allow_add_remove_rows]
      idx = count
      item_prefix = prefix_parts + [array_id, idx]
      child = RiskFieldSet.children_of_array(array_id).first
      if child
        suffix = child[:id].sub(/^#{Regexp.escape(array_id)}\./, '')
        return (item_prefix + [suffix]).join('.').to_sym
      end
    end
    nil
  end    

  # ------------------------------------------------------------
  # Lanza la run con instrucciones + la PREGUNTA exacta
  # ------------------------------------------------------------
  def start_run_with_instructions
    
    field    = next_pending_field
    return unless field
    question = RiskFieldSet.question_for(field, include_tips: true)   # ← YA incluye opciones

    # ↓ Recupera las instrucciones privadas que el JSON trae para ese campo

    # 3) Recuperamos las instrucciones privadas para este campo (sin índice si lo hubiera)
    #    Ej.: si field == :"constr_edificios_detalles_array.0.edif_nombre_uso",
    #    querem<os buscar en JSON por :"constr_edificios_detalles_array.edif_nombre_uso"
    base_key = field.to_s.include?(".") ?
                 field.to_s.sub(/\.\d+\.(.+)$/, '.\1').to_sym :
                 field.to_sym
    info  = RiskFieldSet.by_id[base_key]
    instr = info ? info[:assistant_instructions].to_s.strip : ""
    tips = RiskFieldSet.normative_tips_for(field)
    # El asistente generará la pregunta exacta como parte de la respuesta,
    # por lo que aquí no la publicamos para evitar duplicidades en el chat.         

    # Acceso seguro al label del siguiente campo pendiente
    npf = next_pending_field
    label = ""
    if npf
      byid = RiskFieldSet.by_id[npf.to_sym]
      label = byid[:label].to_s.strip if byid
    end

    confirmations = risk_assistant.messages
                                  .where.not(key: nil)
                                  .order(:created_at)
                                  .map { |m| "✅ #{RiskFieldSet.label_for(m.key)}: #{m.value}" }

    history_block = confirmations.any? ? "Historial de respuestas confirmadas:\n#{confirmations.join("\n")}\n\n" : ""


    extra = <<~SYS
      #{history_block}
      Lista interna de campos (no mostrar al usuario):
      ```json
      #{@fields_json}
      ```
      Instrucciones para el assistant:
      1. Reconoce SOLO los campos anteriores.
      2. No pidas más de un campo a la vez.
      

      3. Genera la siguiente consulta desarrollando como máximo en cuatro párrafos. Usa Instrucciones para formular la pregunta e incluye los tipos normativos en el desarrollo:
         #{question}
         (Incluye las opciones si existen para ese campo.)

      4. Añade a la pregunta las siguientes indicaciones al usuario:
         #{instr.presence ? instr : "ninguna"}

      4.1 Añade justo después de la pregunta, una explicación de la pregunta.

      5. Incluye siempre en un párrafo independiente el desarrollo de la normativa relacionada con la pregunta del punto 3:
          Normativa: #{tips.presence ? tips : "ninguna"}

      6. Antes de validar un valor:
         – Si el campo es *select*, comprueba que la respuesta esté en
           las opciones. Si no, muestra de nuevo la lista.
         – Aplica también las reglas de `context`, `validation`, etc.

      7. Tras ✅ confirmar, no hagas otra pregunta hasta que la app te
         envíe la siguiente instrucción.
      8. Usa la plantilla indicada en assistant_instructions si existe.
      9. Si se adjunta un archivo, busca la información relacionada con cada uno de los campos y valida cada uno de ellos.
      10. Revisa el historial y señala cualquier contradicción antes de formular la siguiente pregunta.

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




