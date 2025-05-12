class RiskAssistant < ApplicationRecord
  belongs_to :user
  has_many :messages, dependent: :destroy

  has_one :report

  validates :name, presence: true

  has_one :identificacion, class_name: 'Identificacion', dependent: :destroy
  has_one :ubicacion_configuracion, dependent: :destroy
  has_one :edificios_construccion, dependent: :destroy
  has_one :actividad_proceso, dependent: :destroy
  has_one :almacenamiento, dependent: :destroy
  has_one :instalaciones_auxiliare, dependent: :destroy
  has_one :riesgos_especifico, dependent: :destroy
  has_one :siniestralidad, dependent: :destroy
  has_one :recomendacione, dependent: :destroy

  accepts_nested_attributes_for :identificacion, :ubicacion_configuracion, :edificios_construccion,
                                :actividad_proceso, :almacenamiento, :instalaciones_auxiliare,
                                :riesgos_especifico, :siniestralidad, :recomendacione


end
