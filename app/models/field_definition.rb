class FieldDefinition < ApplicationRecord
  belongs_to :section, class_name: 'FieldSection', foreign_key: :field_section_id, inverse_of: :fields

  validates :identifier, presence: true
  validates :label, presence: true
  validates :field_type, presence: true

  scope :ordered, -> { order(:position) }

  def to_risk_field_hash
    {
      id: identifier,
      label: label,
      prompt: prompt.presence || label,
      type: field_type.to_s.downcase.to_sym,
      options: options || [],
      example: example,
      why: why,
      context: context,
      section: section.identifier.to_sym,
      validation: (validation || {}).deep_symbolize_keys,
      assistant_instructions: assistant_instructions,
      normative_tips: normative_tips,
      parent: parent_identifier&.to_sym,
      array_of_objects: array_of_objects,
      item_label_template: item_label_template,
      array_count_source_field_id: array_count_source_field_id,
      row_index_path: Array(row_index_path)
    }
  end
end