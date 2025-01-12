  class RiskAssistantsController < ApplicationController
    before_action :authenticate_user!
  
    def index
      @risk_assistants = current_user.risk_assistants
    end
  
    def show
      @risk_assistant = current_user.risk_assistants.find(params[:id])
      @messages = @risk_assistant.messages
      @first_question = @risk_assistant.first_question
    end
  
    def new
      @risk_assistant = current_user.risk_assistants.new
    end
  
    def create
      @risk_assistant = current_user.risk_assistants.new(risk_assistant_params)
  
      if @risk_assistant.save
        redirect_to risk_assistant_path(@risk_assistant), notice: 'RiskAssistant creado con éxito.'
      else
        flash[:error] = "No se pudo crear el RiskAssistant: #{@risk_assistant.errors.full_messages.join(', ')}"
        render :new, status: :unprocessable_entity
      end
    end
  
    def destroy
      @risk_assistant = current_user.risk_assistants.find(params[:id])
      @risk_assistant.destroy
      redirect_to risk_assistants_path, notice: 'RiskAssistant eliminado con éxito.'
    end

    def next_section
      return 'identificacion' if identificacion.nil?
      return 'ubicacion_configuracion' if ubicacion_configuracion.nil?
      return 'edificios_construccion' if edificios_construccion.nil?
      return 'actividad_procesos' if actividad_procesos.nil?
      return 'almacenamiento' if almacenamiento.nil?
      return 'instalaciones_auxiliares' if instalaciones_auxiliares.nil?
      return 'riesgos_especificos' if riesgos_especificos.nil?
      return 'siniestralidad' if siniestralidad.nil?
      return 'recomendaciones' if recomendaciones.nil?
      nil
    end
    
  
    private
  
    def risk_assistant_params
      params.require(:risk_assistant).permit(:name)
    end
  end