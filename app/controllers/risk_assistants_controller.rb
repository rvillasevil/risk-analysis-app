  class RiskAssistantsController < ApplicationController
    before_action :authenticate_user!
  
    def index
      @risk_assistants = current_user.risk_assistants
    end
  
    def show
      @risk_assistant = current_user.risk_assistants.find(params[:id])
      @messages = @risk_assistant.messages
      @company_name = @messages.where("key LIKE ?", "%Nombre de la empresa%").last
      @company_sector = @messages.where("key LIKE ?", "%Sector%").last
      @company_employes = @messages.where("key LIKE ?",  "%Número de empleados%").last
      @company_revenue = @messages.where("key LIKE ?",  "%Ingresos anuales%").last
      @company_location = @messages.where("key LIKE ?",  "%Ubicación%").last
      @company_activity = @messages.where("key LIKE ?",  "%Actividad%").last
      @company_roof = @messages.where("key LIKE ?",  "%Materiales constructivos de cubierta%").last
      @company_walls = @messages.where("key LIKE ?",  "%Materiales constructivos de cerramientos%").last
      @company_interior_walls = @messages.where("key LIKE ?",  "%Materiales constructivos de tabiquería interior%").last
    end
  
    def new
      @risk_assistant = current_user.risk_assistants.new
    end
  
    def create
      @risk_assistant = current_user.risk_assistants.new(risk_assistant_params)
  
      if @risk_assistant.save
        redirect_to risk_assistant_path(@risk_assistant), notice: 'RiskAssistant creado con éxito.'
        create_openai_thread(@risk_assistant)
      else
        flash[:error] = "No se pudo crear el RiskAssistant: #{@risk_assistant.errors.full_messages.join(', ')}"
        render :new, status: :unprocessable_entity
      end
    end
  
    def destroy
      @risk_assistant = current_user.risk_assistants.find(params[:id])
  
      if @risk_assistant.destroy
        flash[:notice] = "RiskAssistant eliminado con éxito."
      else
        flash[:error] = "No se pudo eliminar el RiskAssistant."
      end
  
      redirect_to risk_assistants_path
    end  
  
    private
  
    def risk_assistant_params
      params.require(:risk_assistant).permit(:name, :thread_id)
    end

    def create_openai_thread(risk_assistant)

      base_url = "https://api.openai.com/v1"
      headers = {
        "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}",
        "Content-Type" => "application/json",
        "OpenAI-Beta" => "assistants=v2"
      }

      response = HTTP.post("#{base_url}/threads", headers: headers, body: {}.to_json)
      thread_id = response.parse["id"]
      @risk_assistant.update!(thread_id: thread_id)

      print response
    end

  end