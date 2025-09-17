class FieldSection < ApplicationRecord
  belongs_to :catalogue, class_name: 'FieldCatalogue', foreign_key: :field_catalogue_id, inverse_of: :sections

  has_many :fields, class_name: 'FieldDefinition', dependent: :destroy, inverse_of: :section

  validates :identifier, presence: true
  validates :title, presence: true
end