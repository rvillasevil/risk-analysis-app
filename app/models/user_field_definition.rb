class UserFieldDefinition < ApplicationRecord
  belongs_to :user_field_section

  delegate :user_field_set, :user, to: :user_field_section

  validates :field_key, presence: true
  validates :label, presence: true
  validates :field_type, presence: true

  before_validation :ensure_prompt
  before_validation :normalize_field_type

  after_commit :reset_risk_field_set_cache

  scope :ordered, -> { order(:position, :id) }

  def to_risk_field_hash
    {
      id: field_key,
      label: label.to_s,
      prompt: (prompt.presence || label.to_s),
      type: normalized_field_type,
      options: normalized_options,
      example: example,
      why: why,
      context: context,
      section: user_field_section.key.to_sym,
      validation: normalized_validation,
      normative_tips: normative_tips,
      parent: parent_field_key,
      array_of_objects: array_of_objects,
      assistant_instructions: assistant_instructions,
      item_label_template: item_label_template,
      array_count_source_field_id: array_count_source_field_key,
      row_index_path: normalized_row_index_path
    }.compact
  end

  private

  def ensure_prompt
    self.prompt = prompt.presence || label
  end

  def normalize_field_type
    self.field_type = field_type.to_s.presence || "string"
  end

  def normalized_field_type
    field_type.to_s.presence&.to_sym || :string
  end

  def normalized_options
    Array.wrap(options).map(&:to_s)
  end

  def normalized_validation
    (validation || {}).deep_symbolize_keys
  end

  def normalized_row_index_path
    value = row_index_path.presence
    return value if value.nil? || value.is_a?(Array)

    Array.wrap(value)
  end

  def reset_risk_field_set_cache
    RiskFieldSet.reset_cache!(owner: user)
  end
end