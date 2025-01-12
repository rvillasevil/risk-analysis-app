class RiskAssistant < ApplicationRecord
  belongs_to :user
  has_many :messages, dependent: :destroy

  validates :name, presence: true

  has_one :identificacion, class_name: 'Identificacion', dependent: :destroy
  has_one :ubicacion_configuracion, dependent: :destroy
  has_one :edificios_construccion, dependent: :destroy
  has_one :actividad_procesos, dependent: :destroy
  has_one :almacenamiento, dependent: :destroy
  has_one :instalaciones_auxiliares, dependent: :destroy
  has_one :riesgos_especificos, dependent: :destroy
  has_one :siniestralidad, dependent: :destroy
  has_one :recomendaciones, dependent: :destroy

  accepts_nested_attributes_for :identificacion, :ubicacion_configuracion, :edificios_construccion,
                                :actividad_procesos, :almacenamiento, :instalaciones_auxiliares,
                                :riesgos_especificos, :siniestralidad, :recomendaciones

  has_many :messages, dependent: :destroy

  def first_question
    identificacion.nil? ? '¿Cuál es el nombre y la dirección del lugar de riesgo?' : nil
  end

  def save_response_to_section(section, content)
    case section
    when 'identificacion'
      identificacion ||= build_identificacion
      identificacion.assign_attributes(content)
      identificacion.save
    when 'ubicacion_configuracion'
      ubicacion_configuracion ||= build_ubicacion_configuracion
      ubicacion_configuracion.assign_attributes(content)
      ubicacion_configuracion.save
    # Agregar más secciones aquí
    else
      Rails.logger.warn("Sección desconocida o no implementada: #{section}")
    end
  end


  def next_section
    return 'identificacion' if identificacion.nil?
    return 'ubicacion_configuracion' if ubicacion_configuracion.nil?
    # Agregar más secciones según el orden lógico
    nil
  end

  def next_field_in_section(section)
    case section
    when 'identificacion'
      return :nombre if identificacion.nil? || identificacion.nombre.blank?
      return :direccion if identificacion.direccion.blank?
      return :codigo_postal if identificacion.codigo_postal.blank?
      return :localidad if identificacion.localidad.blank?
      return :provincia if identificacion.provincia.blank?
    when 'ubicacion_configuracion'
      return :ubicacion if ubicacion_configuracion.nil? || ubicacion_configuracion.ubicacion.blank?
      return :configuracion if ubicacion_configuracion.configuracion.blank?
    # Agregar más secciones y campos aquí
    end
    nil
  end

end
