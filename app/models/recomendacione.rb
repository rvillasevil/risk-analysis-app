class Recomendacione < ApplicationRecord
  belongs_to :risk_assistant
  validates :accion, :estado, :prioridad, presence: true
end
