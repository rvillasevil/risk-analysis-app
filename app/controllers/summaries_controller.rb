class SummariesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_data_collection

  def index
    @summaries = @data_collection
                   .messages
                   .where(sender: 'assistant_summary')
                   .order(created_at: :desc)
  end

  private

  def set_data_collection
    @data_collection = risk_assistants_scope.find(params[:risk_assistant_id])
  end
end