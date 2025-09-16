class DocumentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_data_collection

  def index
    @documents = @data_collection
                    .uploaded_files_attachments
                    .includes(:blob)
                    .order(created_at: :desc)
  end

  private

  def set_data_collection
    @data_collection = risk_assistants_scope.find(params[:risk_assistant_id])
  end
end