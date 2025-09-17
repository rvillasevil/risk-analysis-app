# lib/risk_field_set.rb
# frozen_string_literal: true

require "yaml"
require "json"
require "pathname"
require "set"


class RiskFieldSet
  CONFIG_DIR = Rails.root.join("config", "risk_assistant")
  YAML_PATH  = CONFIG_DIR.join("fields.yml")
  # JSON schema describing all fields in Gemini format
  FIRST_JSON = CONFIG_DIR.join("fields_gemini.json")
  JSON_PATH  = Pathname.new(FIRST_JSON)

  Field = Struct.new(
    :id, :label, :prompt, :type, :options, :example,
    :why, :context, :section, :validation, :assistant_instructions,
    :normative_tips,  
    :parent, :array_of_objects, :item_label_template,
    :array_count_source_field_id, :row_index_path,
    keyword_init: true
  ) unless const_defined?(:Field)

  Catalog = Struct.new(
    :sections, :flat_fields, :by_id, :label_to_id, :id_to_label,
    keyword_init: true
  ) unless const_defined?(:Catalog)  

  class << self
    # Devuelve el hash de secciones con sus campos ya procesados
    def all(owner: nil)
      catalog_for(owner: owner).sections
    end

    # Array plano de TODOS los campos (sin subsecciones)
    def flat_fields(owner: nil)
      catalog_for(owner: owner).flat_fields
    end

    # Índice rápido id_sym -> campo
    def by_id(owner: nil)
      catalog_for(owner: owner).by_id
    end

    # Índice label.downcase -> id_sym
    def label_to_id(owner: nil)
      catalog_for(owner: owner).label_to_id
    end

    # Label legible dado un id
    def label_for(id_sym, owner: nil)
      record = catalog_for(owner: owner).id_to_label[id_sym.to_sym]
      (record || {})[:label] || id_sym.to_s.humanize
    end

    # Construye el prompt enriquecido, incluyendo siempre las opciones
    def question_for(id_sym, include_tips: true, owner: nil)
      owner = resolve_owner(owner)
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
          array_f   = by_id(owner: owner)[array_key]
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
      f = by_id(owner: owner)[base_id.to_sym] or return "¿?"

      prefix = labels.join(' · ')
      question = f[:prompt].to_s.strip
      question = "#{prefix}: #{question}" unless prefix.empty?

      base_parts = [question]
      if f[:options]&.any?
        base_parts << "Opciones disponibles: #{f[:options].join(', ')}."
      end

      tips = []
      tips << "Contexto: #{f[:assistant_instructions]}." if f[:assistant_instructions].present?
      tips << f[:normative_tips].to_s.strip if include_tips && f[:normative_tips].present?

      [base_parts.join(' '), tips.join("\n")].reject(&:blank?).join("\n")
    end

    # Devuelve solo los tips normativos para un campo
    def normative_tips_for(id_sym)
      id_str    = id_sym.to_s
      segments  = id_str.split('.')
      base_segs = []

      i = 0
      while i < segments.length
        seg = segments[i]
        nxt = segments[i + 1]

        if nxt&.match?(/\A\d+\z/)
          base_segs << seg
          i += 2
        else
          base_segs << seg
          i += 1
        end
      end

      base_id = base_segs.join('.')
      f = by_id(owner: owner)[base_id.to_sym]   
      f && f[:normative_tips].to_s.strip.presence.to_s
    end


    # --------------------------------------------------------------------------
    # Devuelve la lista de hashes (structs) de todos los subcampos (hijos)
    # de un array con id = array_id. Esto equivale a buscar en flat_fields
    # aquellos f[:parent] == array_id.
    # --------------------------------------------------------------------------
    def children_of_array(array_id, owner: nil)
      flat_fields(owner: owner).select { |f| f[:parent] == array_id }
    end

    # Recorre un array de objetos y encuentra el siguiente campo pendiente.
    # array_id    – id del campo array (sin índices)
    # index_path  – índices de los arrays padres para construir el prefijo
    # answered    – Set con los ids de campos ya respondidos
    def next_from_array(array_id, index_path, answered, owner: nil)
      owner      = resolve_owner(owner)
      array_id   = array_id.to_s
      array_f    = by_id(owner: owner)[array_id.to_sym] || {}
      children   = children_of_array(array_id, owner: owner)

      segments = array_id.split('.')
      prefix_parts = []
      segments.each_with_index do |seg, idx|
        prefix_parts << seg
        prefix_parts << index_path[idx] if index_path[idx]
      end
      prefix = prefix_parts.join('.')
      prefix = prefix.empty? ? '' : prefix + '.'

      row_indices = answered
                      .select { |k| k.start_with?(prefix) }
                      .map { |k| k[prefix.length..].split('.').first.to_i }
                      .uniq
                      .sort
      row_indices = [0] if row_indices.empty?

      row_indices.each do |row_idx|
        children.each do |child|
          child_suffix = child[:id].to_s.split('.')[segments.length..].join('.')
          field_id = "#{prefix}#{row_idx}.#{child_suffix}"

          if child[:type] == :array_of_objects
            pending = next_from_array(child[:id], index_path + [row_idx], answered, owner: owner)
            return pending if pending
          else
            return field_id.to_sym unless answered.include?(field_id)
          end
        end
      end

      if array_f[:allow_add_remove_rows]
        next_idx    = row_indices.max.to_i + 1
        first_child = children.first
        if first_child
          suffix = first_child[:id].to_s.split('.')[segments.length..].join('.')
          return "#{prefix}#{next_idx}.#{suffix}".to_sym
        end
      end

      nil
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
    def reset_cache!(owner: nil)
      resolved = resolve_owner(owner)

      if owner.nil?
        @catalog_cache = {}
      elsif resolved
        catalog_cache.delete(resolved.id)
      else
        catalog_cache.delete(nil)
      end
    end

    # Recarga la definición de campos desde el fichero de configuración
    def reload!(owner: nil)
      reset_cache!(owner: owner)
      all(owner: owner)
    end

    public :reset_cache!, :reload!

    # ------- helpers para obtener el siguiente campo pendiente ---------
    # answers: Hash con pares { 'field_id' => 'valor' }
    def next_field_hash(answers = {}, owner: nil)
      owner    = resolve_owner(owner)
      answered = answers.keys.map(&:to_s).to_set
      root_fields = flat_fields(owner: owner).select { |f| f[:parent].nil? }

      root_fields.each do |field|
        if field[:type] == :array_of_objects
          pending = next_from_array(field[:id], [], answered, owner: owner)
          return field_hash_for(pending, owner: owner) if pending
        else
          return field if !answered.include?(field[:id].to_s)
        end
      end
      nil
    end

    def next_field_id(answers = {}, owner: nil)
      h = next_field_hash(answers, owner: owner)
      h && h[:id]
    end

    def field_hash_for(id, owner: nil)
      by_id(owner: owner)[id.to_sym]
    end    

    public :next_field_hash, :next_field_id   

    private :field_hash_for

    private

    def catalog_for(owner: nil)
      owner = resolve_owner(owner)
      key   = owner&.id
      catalog_cache[key] ||= build_catalog(owner)
    end

    def catalog_cache
      @catalog_cache ||= {}
    end

    def resolve_owner(owner)
      return owner if owner
      return Current.owner if defined?(Current) && Current.respond_to?(:owner)

      nil
    end

    def build_catalog(owner)
      sections =
        if owner && (set = ::UserFieldSet.active_for_owner(owner))
          sections_from_user_field_set(set)
        else
          load_sections_from_files
        end

      build_catalog_from_sections(sections)
    end

    def build_catalog_from_sections(sections)
      normalized_sections = symbolize_sections(sections)
      flat = normalized_sections.values.flat_map { |sec| sec[:fields] }
      byid = flat.index_by { |f| f[:id].to_sym }
      labels = flat
                 .index_by { |f| f[:label].to_s.strip.downcase }
                 .transform_values { |f| f[:id].to_sym }

      Catalog.new(
        sections: normalized_sections,
        flat_fields: flat,
        by_id: byid,
        label_to_id: labels,
        id_to_label: byid
      )
    end

    def symbolize_sections(sections)
      sections.each_with_object({}) do |(key, value), acc|
        fields = Array(value[:fields]).map { |field| symbolize_field(field) }
        acc[key.to_sym] = {
          title: value[:title],
          fields: fields
        }
      end
    end

    def symbolize_field(field)
      hash = field.deep_symbolize_keys
      hash[:options] = Array.wrap(hash[:options])
      hash
    end

    def sections_from_user_field_set(set)
      set
        .sections
        .includes(:field_definitions)
        .order(:position, :id)
        .each_with_object({}) do |section, acc|
          acc[section.key.to_sym] = {
            title: section.title,
            fields: section.field_definitions.ordered.map(&:to_risk_field_hash)
          }
        end
    end    

    # Decide parsear JSON o YAML según presencia de JSON_PATH
    def load_sections_from_files
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
        normative_tips: node["normative_tips"],        
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



