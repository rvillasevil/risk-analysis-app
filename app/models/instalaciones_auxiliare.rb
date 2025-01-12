class InstalacionesAuxiliare < ApplicationRecord
  belongs_to :risk_assistant
  validates :estado_sistema_electrico, presence: true
end
