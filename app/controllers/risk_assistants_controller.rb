  class RiskAssistantsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_risk_assistant, only: [:show, :generate_report, :report, :resume, :update_message, :create_message]
  
    def index
      @risk_assistants = current_user.risk_assistants
    end
  
    def show
      @risk_assistant = current_user.risk_assistants.find(params[:id])
      @messages = @risk_assistant.messages
      @company_name = @messages.where("key LIKE ?", "%Nombre de la empresa%").last
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
    
    def report
      @risk_assistant = current_user.risk_assistants.find(params[:id])
      @messages = @risk_assistant.messages
      @message = @risk_assistant.messages.last
      @report_markdown = fetch_response_from_openai(@message)
      # Ahora @report_markdown está disponible en la vista
    end

    def generate_report
      @message         = @risk_assistant.messages.last
      @report_markdown = fetch_response_from_openai(@message)

      # Renderiza la misma vista show, con @report_markdown disponible
      render :report
    end
  
    def resume
      @risk_assistant = current_user.risk_assistants.find(params[:id])
      @messages = @risk_assistant.messages
    end

    # GET /risk_assistants/:id/resume
    def resume
      # Columnas del modelo Message
      @columns = Message.column_names
      # Solo los mensajes de este RiskAssistant
      @records = @risk_assistant.messages.order(:created_at)
    end

    # PATCH /risk_assistants/:id/update_message
    def update_message
      # Encuentra el mensaje concreto
      message = @risk_assistant.messages.find(params[:message_id])
      if request.delete?
        message.destroy
        redirect_to tabla_datos_risk_assistant_path(@risk_assistant), notice: "Mensaje ##{message.id} eliminado."
        return
      end
      # Actualiza solo los campos permitidos
      if message.update(message_params)
        redirect_to tabla_datos_risk_assistant_path(@risk_assistant),
                    notice: "Mensaje ##{message.id} actualizado."
      else
        flash.now[:alert] = "No se pudo actualizar el mensaje ##{message.id}."
        # recarga datos para re-render
        @columns = Message.column_names
        @records = @risk_assistant.messages.order(:created_at)
        render :tabla_datos
      end
    end

    # POST /risk_assistants/:id/create_message
    def create_message
      msg = @risk_assistant.messages.create(
        role:  params[:role]  || 'user',
        key:   params[:key],
        value: params[:value]
      )
      if msg.persisted?
        redirect_to resume_risk_assistant_path(@risk_assistant), notice: "Mensaje ##{msg.id} añadido."
      else
        flash.now[:alert] = "No se pudo crear el mensaje: #{msg.errors.full_messages.join(', ')}"
        @records = @risk_assistant.messages.order(:created_at)
        render :resume
      end
    end


    private
  
    def risk_assistant_params
      params.require(:risk_assistant).permit(:name, :thread_id)
    end

    def format_previous_messages(messages)
      messages.map do |message|
        "[#{message[:role].capitalize}]: #{message[:content]}"
      end.join("\n")
    end

    def collect_messages_for_context(risk_assistant)
      risk_assistant.messages.order(:created_at).pluck(:role, :content).map do |role, content|
        { role: role, content: content }
      end
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

      puts "🔍 Content: #{response["content"].inspect}"

      print response
    end

    def set_risk_assistant
      @risk_assistant = RiskAssistant.find(params[:id])
    end

    # Permite editar todos los campos de Message excepto id, conversation_id, created_at, updated_at
    def message_params
      params.require(:message).permit(Message.column_names - %w[id risk_assistant_id created_at updated_at])
    end

    def fetch_response_from_openai(message)
      previous_messages = collect_messages_for_context(@risk_assistant)
      prompt_messages   = format_previous_messages(previous_messages)

      context = <<~CTX
        Eres un asistente que recibe la información proporcionada en una conversación para la obtención de datos para conformar un informe descriptivo de riesgos para el sector asegurador.
        Con toda la información recabada en esta conversación que puede estar completa o incompleta: #{prompt_messages}, por favor redacta únicamente:
        1. Haz un **resumen ejecutivo**.
        2. Extrae las **métricas clave** (campos del formulario) y organizalos en:
          A. Datos identificativos
          B. Edificios construcción
          C. Actividad y proceso
          D. Instalaciones Auxiliares
            D.1 Mantenimiento
          E. Riesgo de incendio
            E.1 Protección contra incendios
            E.2 Prevención de incendios
          F. Riesgo de Robo
          G. Riesgo de interrupción de negocio / Pérdida de beneficio
        3. Identifica **lagunas de información** si las hubiera.
        4. Ofrece **conclusiones y recomendaciones**.
        Devuélvelo como un informe estructurado en Markdown.
      CTX

      prompt = message.content

      response = HTTP.post(
        "https://api.openai.com/v1/chat/completions",
        headers: {
          "Authorization" => "Bearer #{ENV['OPENAI_API_KEY']}",
          "Content-Type"  => "application/json"
        },
        json: {
          model:       "gpt-4o-mini",
          messages: [
            { role: "developer", content: context },
            { role: "user",      content: prompt  }
          ],
          max_tokens:  5000,
          temperature: 0.8
        }
      )

      response.parse.dig("choices", 0, "message", "content")&.strip ||
        "No se recibió una respuesta válida."
    end

  end