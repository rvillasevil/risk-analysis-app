# lib/risk_field_set.rb
# frozen_string_literal: true
#
#  ▸ Carga la definición de campos desde:
#      – config/risk_assistant/fields.yml      (YAML clásico)
#      – config/risk_assistant/*.json          (nuevo formato Gemini)
#  ▸ Expone la MISMA API que usaba el resto de la app:
#      RiskFieldSet.flat_fields
#      RiskFieldSet.by_id
#      RiskFieldSet.label_for(:id)
#      RiskFieldSet.question_for(:id)
#
require "yaml"
require "json"

class RiskFieldSet
  CONFIG_DIR  = Rails.root.join("config", "risk_assistant")
  YAML_PATH   = CONFIG_DIR.join("fields.yml")
  # → 1) averiguamos si existe algún JSON en la carpeta
  FIRST_JSON = Dir[CONFIG_DIR.join("*.json")].first

  # → 2) lo convertimos en Pathname (o nil si no hay ninguno)
  JSON_PATH  = FIRST_JSON && Pathname.new(FIRST_JSON)

  # ----------------------  CACHES  ----------------------
  @sections     = nil   # Hash seccion → {title:, fields:[]}
  @flat         = nil   # Array de campos
  @by_id        = nil   # Hash id_sym → campo
  @label_to_id  = nil   # Hash label.downcase → id_sym
  @id_to_label  = nil   # Hash id_sym → label

  # ------------------------------------------------------------
  # Dominio del CAMPO (estructura in-memory)
  # ------------------------------------------------------------
  Field = Struct.new(
    :id,       :label,  :prompt,  :type, :options, :example,
    :why,      :context,:section, :position, :validations,
    keyword_init: true
  )

  class << self
    # -------------- 1. Carga única (secciones + campos) ----------
    def all
      @sections ||= load_data!
    end

    # -------------- 2. Array plano ------------------------------
    def flat_fields
      @flat ||= all.values.flat_map { |s| s[:fields] }
    end

    # -------------- 3. Índices rápidos --------------------------
    def by_id
      @by_id ||= flat_fields.index_by { |f| f[:id].to_sym }
    end

    def label_to_id
      @label_to_id ||= flat_fields
                         .index_by { |f| f[:label].strip.downcase }
                         .transform_values { |f| f[:id].to_sym }
    end

    def label_for(id_sym)
      @id_to_label ||= flat_fields.index_by { |f| f[:id].to_sym }
      (@id_to_label[id_sym.to_sym] || {})[:label] || id_sym.to_s.humanize
    end

    # -------------- 4. Prompt enriquecido -----------------------
    def question_for(id_sym)
      f = by_id[id_sym.to_sym] or return "¿?"
      parts = [f[:prompt].to_s.strip]

      parts << "Opciones disponibles: #{f[:options].join(', ')}." \
        if f[:options]&.any?
      parts << "Ejemplo: #{f[:example]}."  if f[:example].present?
      parts << "Importancia: #{f[:why]}."  if f[:why].present?
      parts << "Contexto: #{f[:context]}." if f[:context].present?

      parts.join(" ")
    end

    # -------------- 5. Forzar recarga ---------------------------
    def reset_cache!
      instance_variables.each { |iv| remove_instance_variable(iv) }
    end
    public :reset_cache!

    # ============================================================
    #                     PRIVATE HELPERS
    # ============================================================
    private

    # Detecta si hay JSON → lo usa, si no lee YAML
    def load_data!
      if JSON_PATH && File.exist?(JSON_PATH)
        Rails.logger.info "RiskFieldSet: cargando #{JSON_PATH.basename}"
        parse_json(JSON_PATH)
      else
        Rails.logger.info "RiskFieldSet: cargando #{YAML_PATH.basename}"
        parse_yaml(YAML_PATH)
      end
    end

    # ---------- YAML -------------
    def parse_yaml(path)
      raw = YAML.safe_load(File.read(path),
                           aliases: true,
                           symbolize_names: true)
      symbolize_deep!(raw)
    rescue Psych::Exception => e
      raise "YAML mal formado en #{path}: #{e.message}"
    end

    # ---------- JSON (formato Gemini) -------------
    #
    #  Espera un ARRAY de objetos:
    #  [
    #    {
    #      "id":        "direccion_riesgo",
    #      "label":     "Dirección de riesgo",
    #      "prompt":    "...",
    #      "type":      "select",
    #      "options":   ["A","B"],
    #      "example":   "...",
    #      "why":       "...",
    #      "context":   "...",
    #      "section":   "identificacion"
    #    },
    #    ...
    #  ]
    #
    def parse_json(path)
      arr = JSON.parse(File.read(path))
      raise "El JSON raíz debe ser un Array" unless arr.is_a?(Array)

      # 1) Agrupar por sección (nil ⇒ :general)
      grouped = arr.group_by { |n| n["section"].presence || "general" }

      # 2) Transformar a la misma estructura que devolvía el YAML
      sections = {}
      grouped.each do |sec_name, nodes|
        sections[sec_name.to_sym] = {
          title:  sec_name.titleize,
          fields: nodes.map.with_index(1) { |node, idx| json_to_field(node, sec_name, idx) }
        }
      end
      sections
    rescue JSON::ParserError => e
      raise "JSON mal formado en #{path}: #{e.message}"
    end

    def json_to_field(node, sec_name, idx)
      Field.new(
        id:          node["id"],
        label:       node["label"]   || node["prompt"],
        prompt:      node["prompt"]  || node["label"],
        type:        node["type"]&.to_sym || :string,
        options:     node["options"],
        example:     node["example"],
        why:         node["why"],
        context:     node["context"],
        section:     sec_name,
        position:    idx,
        validations: Array(node["validations"])
      ).to_h
    end

    # ---------- util ---------- #
    def symbolize_deep!(obj)
      case obj
      when Hash
        obj.transform_keys!(&:to_sym)
        obj.each_value { |v| symbolize_deep!(v) }
      when Array
        obj.each { |v| symbolize_deep!(v) }
      end
      obj
    end
  end
end


