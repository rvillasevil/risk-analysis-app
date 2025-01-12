class ActividadProceso < ApplicationRecord
  belongs_to :risk_assistant
  validates :actividad_principal, :anio_inicio, presence: true
end
