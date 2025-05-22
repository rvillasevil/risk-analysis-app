# lib/risk_field_set.rb
require "yaml"

class RiskFieldSet
  CONFIG_PATH = Rails.root.join("config", "risk_assistant", "fields.yml")

  class << self
    # ------------------------------------------------------------
    # Carga y simboliza TODO el YAML
    # ------------------------------------------------------------
    def all
      Rails.env.development? ? load_yaml! : (@cache ||= load_yaml!)
    end

    # Array plano con TODOS los campos
    def flat_fields
      @flat ||= all.values.flat_map { |sec| sec[:fields] }
    end

    # ---------- CORREGIDO ----------
    # { "nombre de la empresa" => :nombre, ... }
    def label_to_id
      @label_to_id ||= flat_fields
                        .index_by { |f| f[:label].strip.downcase }
                        .transform_values { |f| f[:id].to_sym }
    end

    # :nombre  ->  "Nombre de la empresa"
    def label_for(id_sym)
      @id_to_label ||= flat_fields.index_by { |f| f[:id].to_sym }
      (@id_to_label[id_sym] || {})[:label] || id_sym.to_s.humanize
    end
    # --------------------------------

    # hash O(1) por id
    def by_id
      @by_id ||= flat_fields.index_by { |f| f[:id].to_sym }
    end

    # Follow-up
    def follow_ups(field_id, answer_bool)
      field  = by_id[field_id.to_sym] or return []
      branch = answer_bool ? :if_yes : :if_no
      Array(field.dig(:follow_ups, branch))
    end

    # ------------------------------------------------------------
    private
    # ------------------------------------------------------------
    def load_yaml!
      yaml = YAML.safe_load(
               File.read(CONFIG_PATH),
               aliases: true,
               symbolize_names: true
             )
      symbolize_deep!(yaml)
    rescue Errno::ENOENT
      raise "No se encontró #{CONFIG_PATH}"
    rescue Psych::Exception => e
      raise "YAML mal formado en #{CONFIG_PATH}: #{e.message}"
    end

    def symbolize_deep!(obj)
      case obj
      when Hash
        obj.transform_keys!(&:to_sym)
        obj.each { |_, v| symbolize_deep!(v) }
      when Array
        obj.each { |v| symbolize_deep!(v) }
      end
      obj
    end
  end
end

