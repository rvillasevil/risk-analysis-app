class FieldCatalogueBuilder
  class InvalidPayload < StandardError; end

  def self.call(field_catalogue:, payload:)
    new(field_catalogue:, payload:).call
  end

  def initialize(field_catalogue:, payload:)
    @field_catalogue = field_catalogue
    @payload = payload
  end

  def call
    data = normalize_payload!

    ActiveRecord::Base.transaction do
      field_catalogue.sections.destroy_all
      field_catalogue.update!(generated_catalogue: data[:raw])

      data[:sections].each_with_index do |section, idx|
        section_record = field_catalogue.sections.create!(
          identifier: section[:id],
          title: section[:title],
          position: section[:position] || idx
        )

        section[:fields].each_with_index do |field_attrs, field_idx|
          section_record.fields.create!(
            identifier: field_attrs[:id],
            label: field_attrs[:label],
            prompt: field_attrs[:prompt],
            field_type: field_attrs[:type],
            options: field_attrs[:options],
            example: field_attrs[:example],
            why: field_attrs[:why],
            context: field_attrs[:context],
            validation: field_attrs[:validation],
            assistant_instructions: field_attrs[:assistant_instructions],
            normative_tips: field_attrs[:normative_tips],
            parent_identifier: field_attrs[:parent],
            array_of_objects: field_attrs[:array_of_objects],
            item_label_template: field_attrs[:item_label_template],
            array_count_source_field_id: field_attrs[:array_count_source_field_id],
            row_index_path: field_attrs[:row_index_path],
            position: field_attrs[:position] || field_idx
          )
        end
      end

      field_catalogue.ready!
    end

    field_catalogue
  rescue JSON::ParserError, InvalidPayload => e
    field_catalogue.failed!(e.message)
    raise InvalidPayload, e.message
  end

  private

  attr_reader :field_catalogue, :payload

  def normalize_payload!
    doc = parse_payload(payload)
    sections = extract_sections(doc)

    {
      raw: doc,
      sections: sections
    }
  end

  def parse_payload(value)
    case value
    when String
      cleaned = strip_code_fences(value)
      JSON.parse(cleaned)
    when Hash
      value
    when ActionController::Parameters
      value.to_unsafe_h
    else
      raise InvalidPayload, 'Formato de catálogo no reconocido'
    end
  end

  def strip_code_fences(text)
    trimmed = text.strip
    return trimmed unless trimmed.start_with?('```')

    lines = trimmed.lines
    lines.shift
    lines.pop while lines.last&.strip == '```'
    lines.join.strip
  end

  def extract_sections(doc)
    sections = doc['sections'] || doc[:sections]
    raise InvalidPayload, 'El catálogo debe contener una clave "sections"' unless sections.is_a?(Array)

    sections.map.with_index do |section, idx|
      id = section['id'] || section[:id] || section['identifier'] || section[:identifier]
      raise InvalidPayload, 'Cada sección debe tener un identificador' if id.blank?

        fields = flatten_fields(section['fields'] || section[:fields] || [])

      {
        id: id.to_s,
        title: section['title'] || section[:title] || id.to_s.humanize,
        fields: fields,
        position: section['position'] || section[:position] || idx
      }
    end
  end

    def flatten_fields(nodes, parent = nil, prefix = nil)
      Array(nodes).flat_map.with_index do |node, idx|
        node = node.deep_stringify_keys
        node_id = node['id'] || node['identifier']
        raise InvalidPayload, 'Cada campo debe tener id' if node_id.blank?

        full_id = [prefix, node_id].compact.join('.')
        type = node['type'].to_s.presence || 'string'

        case type
        when 'subsection'
          flatten_fields(node['fields'] || [], parent, prefix)
        when 'array_of_objects'
          array_field = build_field_hash(node, parent, full_id, type, false, idx)
          child_nodes = node.dig('item_schema', 'fields') || []
          children = flatten_fields(child_nodes, full_id, full_id)
          [array_field] + children
        else
          [build_field_hash(node, parent, full_id, type, parent.present?, idx)]
        end
      end
  end

  def build_field_hash(node, parent_id, full_id, type, inside_array, position)
    options = normalize_options(node['options'])
    validation = node['validation'] || node['validations'] || {}
    row_index_path = node['row_index_path'] || []

    {
      id: full_id,
      label: node['label'] || node['prompt'] || full_id.to_s.humanize,
      prompt: node['prompt'],
      type: type,
      options: options,
      example: node['example'],
      why: node['why'],
      context: node['context'] || node['tooltip'],
      validation: validation,
      assistant_instructions: node['assistant_instructions'],
      normative_tips: node['normative_tips'],
      parent: parent_id,
      array_of_objects: inside_array,
      item_label_template: node['item_label_template'],
      array_count_source_field_id: node['array_count_source_field_id'],
      row_index_path: row_index_path,
      position: node['position'] || position
    }
  end

  def normalize_options(options)
    return [] unless options.is_a?(Array)

    options.map do |opt|
      case opt
      when Hash
        opt['label'] || opt[:label] || opt['value'] || opt[:value]
      else
        opt
      end
    end.compact
  end
end