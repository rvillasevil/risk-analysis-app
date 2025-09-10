class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user, except: :show
  before_action :set_client, only: %i[destroy show]

  def index
    @clients = @user.clients
  end

  def show; end

  def new
    @client = User.new
  end

  def create
    @client = User.new(client_params)
    @client.owner_id = current_user.id
    @client.role = :client
    if @client.save
      redirect_to user_clients_path(@user), notice: 'Client was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @client.destroy
    redirect_to user_clients_path(@user), notice: 'Client was archived.'
  end

  def dashboard; end  

  private

  def set_user
    @user = current_user
  end

  def set_client
    @client = (@user || current_user).clients.find(params[:id])
  end

  def client_params
    params.require(:client).permit(:email, :name, :password, :password_confirmation)
  end
end