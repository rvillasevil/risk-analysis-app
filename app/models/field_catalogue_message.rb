class FieldCatalogueMessage < ApplicationRecord
  ROLES = %w[user assistant system developer].freeze

  belongs_to :field_catalogue, inverse_of: :messages

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :content, presence: true
end