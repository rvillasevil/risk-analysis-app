class EdificiosConstruccion < ApplicationRecord
  belongs_to :risk_assistant
  validates :superficie_construida, :anio_construccion, presence: true
end
