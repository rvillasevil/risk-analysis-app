class DataCollectionsController < ApplicationController
  before_action :authenticate_user!

  def index
    @data_collections = risk_assistants_scope.order(created_at: :desc)
  end

  def show; end

  def new; end  
end
