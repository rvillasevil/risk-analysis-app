class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  before_action :require_client!  
  before_action :set_client, only: :destroy

  def index
    @clients = @user.clients.active
  end

  def new
    @client = @user.clients.build
  end

  def create
    @client = @user.clients.build(client_params)
    if @client.save
      redirect_to user_clients_path(@user), notice: 'Client was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @client.update(inactive: true)
    redirect_to user_clients_path(@user), notice: 'Client was archived.'
  end

  def dashboard; end  

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def set_client
    @client = @user.clients.find(params[:id])
  end

  def client_params
    params.require(:client).permit(:name)
  end
end