# lib/risk_field_set.rb
# frozen_string_literal: true

require "yaml"
require "json"
require "pathname"


class RiskFieldSet
  CONFIG_DIR = Rails.root.join("config", "risk_assistant")
  YAML_PATH  = CONFIG_DIR.join("fields.yml")
  FIRST_JSON = Dir.glob(CONFIG_DIR.join("*.json"), File::FNM_CASEFOLD).first
  JSON_PATH  = FIRST_JSON && Pathname.new(FIRST_JSON)

  Field = Struct.new(
    :id, :label, :prompt, :type, :options, :example,
    :why, :context, :section, :validation, :assistant_instructions,
    :parent, :array_of_objects, :item_label_template,
    :array_count_source_field_id, :row_index_path,
    keyword_init: true
  )

  class << self
    # Devuelve el hash de secciones con sus campos ya procesados
    def all
      @sections ||= load_data!
    end

    # Array plano de TODOS los campos (sin subsecciones)
    def flat_fields
      @flat ||= all.values.flat_map { |sec| sec[:fields] }
    end

    # Índice rápido id_sym -> campo
    def by_id
      @by_id ||= flat_fields.index_by { |f| f[:id].to_sym }
    end

    # Índice label.downcase -> id_sym
    def label_to_id
      @label_to_id ||= flat_fields
                         .index_by { |f| f[:label].strip.downcase }
                         .transform_values { |f| f[:id].to_sym }
    end

    # Label legible dado un id
    def label_for(id_sym)
      @id_to_label ||= flat_fields.index_by { |f| f[:id].to_sym }
      (@id_to_label[id_sym.to_sym] || {})[:label] || id_sym.to_s.humanize
    end

    # Construye el prompt enriquecido, incluyendo siempre las opciones
    def question_for(id_sym)
      id_str    = id_sym.to_s
      segments  = id_str.split('.')
      base_segs = []             # id sin índices numéricos
      labels    = []             # etiquetas de cada índice detectado

      i = 0
      while i < segments.length
        seg = segments[i]
        nxt = segments[i + 1]

        if nxt&.match?(/\A\d+\z/)
          # id del array con índice
          array_key = (base_segs + [seg]).join('.').to_sym
          array_f   = by_id[array_key]
          idx       = nxt.to_i

          if array_f && array_f[:item_label_template]
            tmpl = array_f[:item_label_template].dup
            label = tmpl.gsub(/\{\{\s*index\s*\+\s*1\s*\}\}/, (idx + 1).to_s)
          elsif array_f
            label = "#{array_f[:label]} #{idx + 1}"
          else
            label = "Item #{idx + 1}"
          end

          labels << label
          base_segs << seg
          i += 2
        else
          base_segs << seg
          i += 1
        end
      end

      base_id = base_segs.join('.')
      f = by_id[base_id.to_sym] or return "¿?"

      prefix = labels.join(' · ')
      question = f[:prompt].to_s.strip
      question = "#{prefix}: #{question}" unless prefix.empty?

      parts = [question]
      if f[:options]&.any?
        parts << "Opciones disponibles: #{f[:options].join(', ')}."
      end
      parts << "Contexto: #{f[:context]}." if f[:context].present?
      parts << "Ejemplo: #{f[:example]}."    if f[:example].present?
      parts << "Importancia: #{f[:why]}."    if f[:why].present?
      parts.join(' ')
    end

    # --------------------------------------------------------------------------
    # Devuelve la lista de hashes (structs) de todos los subcampos (hijos)
    # de un array con id = array_id. Esto equivale a buscar en flat_fields
    # aquellos f[:parent] == array_id.
    # --------------------------------------------------------------------------
    def children_of_array(array_id)
      flat_fields.select { |f| f[:parent] == array_id }
    end    

    def validate_answer(field, value)
      v = field[:validation] || {}

      return "Este campo es obligatorio" if v[:required] && value.blank?
      return "El valor mínimo es #{v[:min]}" if v[:min] && value.to_f < v[:min]
      return "El valor máximo es #{v[:max]}" if v[:max] && value.to_f > v[:max]

      if field[:type] == :select && field[:options].any?
        return "Elige una de las opciones: #{field[:options].join(', ')}" unless field[:options].include?(value)
      end

      if field[:type] == :boolean
        return "Responde Sí o No" unless %w[Sí No true false].include?(value)
      end

      nil
    end

    # Limpia todos los caches — útil tras actualizar el fichero
    def reset_cache!
      @sections    =
      @flat        =
      @by_id       =
      @label_to_id =
      @id_to_label = nil
    end
    public :reset_cache!

        # ------- NUEVO: helpers para el siguiente campo -----------------
    def next_field_hash(answered_keys = [])
      answered = answered_keys.map(&:to_s)
      flat_fields.find { |f| !answered.include?(f[:id].to_s) }
    end

    def next_field_id(answered_keys = [])
      h = next_field_hash(answered_keys)
      h && h[:id]
    end    

    public :next_field_hash, :next_field_id   # ← AÑADE ESTA LÍNEA

    private

    # Decide parsear JSON o YAML según presencia de JSON_PATH
    def load_data!
      if JSON_PATH && File.exist?(JSON_PATH)
        Rails.logger.info "RiskFieldSet: cargando #{JSON_PATH.basename}"
        parse_json(JSON_PATH)
      else
        Rails.logger.info "RiskFieldSet: cargando #{YAML_PATH.basename}"
        parse_yaml(YAML_PATH)
      end
    end

    # --- YAML clásico ---
    def parse_yaml(path)
      raw = YAML.safe_load(
        File.read(path),
        aliases: true,
        symbolize_names: true
      )
      symbolize_deep!(raw)
    rescue Psych::Exception => e
      raise "YAML mal formado en #{path}: #{e.message}"
    end

    # --- JSON formato Gemini ---
    # Espera raíz { "sections": [ { id, title, fields: [...] }, ... ] }
    def parse_json(path)
      doc = JSON.parse(File.read(path))
      sections = {}
      unless doc["sections"].is_a?(Array)
        raise "El JSON raíz debe contener key 'sections' con un Array"
      end

      doc["sections"].each do |sec|
        sec_id = sec["id"] || sec["title"].parameterize.underscore
        sections[sec_id.to_sym] = {
          title:  sec["title"] || sec_id.to_s.humanize,
          fields: walk_fields_rec(sec["fields"] || [], sec_id.to_sym)
        }
      end

      sections
    rescue JSON::ParserError => e
      raise "JSON mal formado en #{path}: #{e.message}"
    end

    # lib/risk_field_set.rb
    # ------------------------------------------------------------------
    # Recorre recursivamente las secciones.  Para los nodos
    # type:"array_of_objects" añade:
    #   • el propio campo-array  (p. ej. constr_edificios_detalles_array)
    #   • un campo por cada columna (p. ej. constr_edificios_detalles.edif_superficie)
    # ------------------------------------------------------------------
    def walk_fields_rec(nodes, section, parent_array_id = nil, id_prefix = nil)
      nodes.flat_map do |node|
        full_id = [id_prefix, node["id"]].compact.join(".")

        case node["type"]
        when "subsection"
          subsection = Field.new(
            id:          full_id,
            label:       node["title"].to_s,
            prompt:      node["title"].to_s,
            type:        :subsection,
            options:     [],
            example:     nil,
            why:         nil,
            context:     nil,
            section:     section,
            validation:  {},
            parent:      parent_array_id,
            array_of_objects: false,
            assistant_instructions: nil,
            item_label_template: nil,
            array_count_source_field_id: nil,
            row_index_path: nil
          ).to_h

          [subsection] +
            walk_fields_rec(node["fields"] || [], section, parent_array_id, id_prefix)

        when "array_of_objects"
          array_id   = node["id"]
          array_field = json_to_field(node, section,
                                     id_override: full_id,
                                     parent: parent_array_id)

          cols = walk_fields_rec(
                   node.dig("item_schema", "fields") || [],
                   section,
                   full_id,
                   full_id
                 )

          [array_field] + cols

        else
          [json_to_field(node, section,
                         id_override: full_id,
                         parent: parent_array_id,
                         in_array: parent_array_id.present?)]
        end
      end
    end


    # ------------------------------------------------------------------
    # Convierte un nodo JSON a nuestro Hash interno
    # ------------------------------------------------------------------
    def json_to_field(node, section,
                      id_override: nil,
                      parent: nil,
                      in_array: false)

      opts =
        if node["options"].is_a?(Array)
          node["options"].map { |o| o["label"].to_s }
        elsif node["type"] == "boolean"
          %w[Sí No]                          # por defecto para boolean
        else
          []
        end

      Field.new(
        id:          id_override || node["id"],
        label:       node["label"].to_s,
        prompt:      node["label"].to_s,
        type:        node["type"]&.to_sym || :string,
        options:     opts,
        example:     node["example"],
        why:         node["why"],
        context:     node["context"] || node["tooltip"],
        section:     section,
        validation:  node["validation"] || {},
        # ---- metadatos extra ----
        parent:      parent,            # id del array padre
        array_of_objects: in_array,     # true si es columna de tabla
        assistant_instructions: node["assistant_instructions"],
        item_label_template: node["item_label_template"],
        array_count_source_field_id: node["array_count_source_field_id"],
        row_index_path: node["row_index_path"]
      ).to_h
    end

    # Convierte Hashes/Arrays con claves String a símbolos
    def symbolize_deep!(obj)
      case obj
      when Hash
        obj.keys.each { |k| obj[k.to_sym] = obj.delete(k) }
        obj.values.each { |v| symbolize_deep!(v) }
      when Array
        obj.each { |v| symbolize_deep!(v) }
      end
      obj
    end
   
  end
end



