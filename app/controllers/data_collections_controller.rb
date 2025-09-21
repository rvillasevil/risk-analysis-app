class DataCollectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_owner!
  before_action :set_field_catalogue, only: %i[show send_message finalize]  

  def index
    @catalogues = FieldCatalogue.for_owner(Current.owner)
  end

  def show
    @messages = @field_catalogue.messages.order(:created_at)

    respond_to do |format|
      format.html
      format.json { render json: @field_catalogue.to_sections_hash }
    end    
  end

  def create
    catalogue = nil
    catalogue = Current.owner.field_catalogues.create!
    runner = OnboardingAssistantRunner.new(catalogue)
    runner.start_conversation!

    redirect_to data_collection_path(catalogue), notice: 'Conversación de onboarding iniciada.'
  rescue StandardError => e
    catalogue&.failed!(e.message)
    redirect_to data_collections_path, alert: "No se pudo iniciar la conversación: #{e.message}"
  end

  def send_message
    content = message_params[:content].to_s.strip

    if content.blank?
      redirect_to data_collection_path(@field_catalogue), alert: 'El mensaje no puede estar vacío.'
      return
    end

    runner = OnboardingAssistantRunner.new(@field_catalogue)
    runner.send_owner_message(content)

    redirect_to data_collection_path(@field_catalogue)
  rescue StandardError => e
    @field_catalogue.failed!(e.message)
    redirect_to data_collection_path(@field_catalogue), alert: "No se pudo enviar el mensaje: #{e.message}"
  end

  def finalize
    runner = OnboardingAssistantRunner.new(@field_catalogue)
    payload = runner.request_catalogue_json
    FieldCatalogueBuilder.call(field_catalogue: @field_catalogue, payload: payload)

    redirect_to data_collection_path(@field_catalogue), notice: 'Catálogo generado y almacenado correctamente.'
  rescue FieldCatalogueBuilder::InvalidPayload => e
    redirect_to data_collection_path(@field_catalogue), alert: "El catálogo generado no es válido: #{e.message}"
  rescue StandardError => e
    @field_catalogue.failed!(e.message)
    redirect_to data_collection_path(@field_catalogue), alert: "No se pudo generar el catálogo: #{e.message}"
  end

  private

  def require_owner!
    redirect_to root_path, alert: 'Acceso restringido.' unless current_user&.owner?
  end

  def set_field_catalogue
    @field_catalogue = Current.owner.field_catalogues.find(params[:id])
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
