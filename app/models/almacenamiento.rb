class Almacenamiento < ApplicationRecord
  belongs_to :risk_assistant
  validates :materias_primas, :tipo_almacenamiento, presence: true
end