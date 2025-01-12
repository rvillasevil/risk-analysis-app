class Identificacion < ApplicationRecord
  belongs_to :risk_assistant
  validates :nombre, :direccion, :codigo_postal, :localidad, :provincia, presence: true
end
