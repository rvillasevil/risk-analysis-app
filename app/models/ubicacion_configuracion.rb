class UbicacionConfiguracion < ApplicationRecord
  belongs_to :risk_assistant
  validates :ubicacion, :configuracion, presence: true
end
