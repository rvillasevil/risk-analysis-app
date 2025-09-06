require "risk_field_set"

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

  has_many_attached :uploaded_files

  accepts_nested_attributes_for :identificacion, :ubicacion_configuracion, :edificios_construccion,
                                :actividad_proceso, :almacenamiento, :instalaciones_auxiliare,
                                :riesgos_especifico, :siniestralidad, :recomendacione

  alias_attribute :initialised?, :initialised   # permite usar “?” al final

  # Devuelve un hash con el estado de cada campo del cuestionario.
  # El estado puede ser:
  #   - "sin_preguntar": no hay mensajes relacionados con el campo.
  #   - "en_proceso":   se ha preguntado pero no se ha confirmado un valor.
  #   - "confirmado":   existe un mensaje con clave (key) para el campo.
  # Se tienen en cuenta los identificadores definidos en RiskFieldSet.
  def campos
    field_ids = RiskFieldSet.by_id.keys.map(&:to_s)
    confirmed = messages.where.not(key: nil).pluck(:key)
    asked     = messages.where(sender: %w[assistant assistant_guard])
                         .where.not(field_asked: nil)
                         .pluck(:field_asked)

    field_ids.index_with do |fid|
      if confirmed.any? { |k| k == fid || k.start_with?("#{fid}.") }
        "confirmado"
      elsif asked.any? { |k| k == fid || k.start_with?("#{fid}.") }
        "en_proceso"
      else
        "sin_preguntar"
      end
    end
  end
end
