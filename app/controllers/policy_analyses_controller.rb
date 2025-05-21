# app/controllers/policy_analyses_controller.rb
class PolicyAnalysesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_policy_analysis, only: [:show, :create_analysis, :destroy, :ask]

  def index
    @policy_analyses = current_user.policy_analyses
  end

  def new
    @policy_analysis = current_user.policy_analyses.new
  end

  def create
    @policy_analysis = current_user.policy_analyses.new
    if @policy_analysis.save
      attach_documents
      PolicyAnalysisJob.perform_later(@policy_analysis.id)
      redirect_to @policy_analysis, notice: 'Pólizas en cola de análisis. Recibirás los resultados pronto.'
    else
      flash.now[:error] = @policy_analysis.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @extractions = @policy_analysis.extractions
  end

  def create_analysis
    PolicyAnalysisJob.perform_later(@policy_analysis.id)
    redirect_to @policy_analysis, notice: 'Re-analizando pólizas.'
  end

  def destroy
    @policy_analysis.destroy
    redirect_to policy_analyses_path, notice: 'Análisis eliminado con éxito.'
  end

  # POST /policy_analyses/:id/ask
  def ask
    pregunta = params.require(:question)
    contexto = @policy_analysis.extractions.to_s

    system_prompt = <<~SYS
      Eres un asistente experto en seguros. Tienes este texto extraído de una póliza,
      con marcadores de página "== Página X ==" insertados. Cuando respondas:
      - Contesta sólo a la pregunta.
      - Cita siempre la página en formato [página X].
      - No inventes nada.

      Contexto:
      #{contexto}
    SYS

    ai_answer = call_openai(system_prompt, "Pregunta: #{pregunta}")

    # Guardamos la respuesta en flash y redirigimos a show
    flash[:policy_answer] = ai_answer
    redirect_to policy_analysis_path(@policy_analysis)
  end

  private

  def set_policy_analysis
    @policy_analysis = current_user.policy_analyses.find(params[:id])
  end

  def attach_documents
    Array(params[:policy_analysis][:documents]).each do |doc|
      @policy_analysis.documents.attach(doc)
    end
  end

  def call_openai(system, user)
    uri = URI(PolicyAnalyzer::OPENAI_URL)
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{ENV.fetch('OPENAI_API_KEY')}"
    req["Content-Type"]  = "application/json"
    req.body = {
      model:    PolicyAnalyzer::MODEL,
      messages: [
        { role: "system", content: system },
        { role: "user",   content: user   }
      ],
      temperature: 0.0,
      max_tokens:  1000
    }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    JSON.parse(res.body).dig("choices",0,"message","content").to_s.strip
  rescue
    "Lo siento, no he podido procesar tu pregunta."
  end
end



