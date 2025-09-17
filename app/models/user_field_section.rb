class UserFieldSection < ApplicationRecord
  belongs_to :user_field_set

  has_many :field_definitions,
           -> { order(:position, :id) },
           class_name: "UserFieldDefinition",
           dependent: :destroy,
           inverse_of: :user_field_section

  delegate :user, to: :user_field_set

  validates :key, presence: true
  validates :title, presence: true

  after_commit :reset_risk_field_set_cache

  private

  def reset_risk_field_set_cache
    RiskFieldSet.reset_cache!(owner: user)
  end
end