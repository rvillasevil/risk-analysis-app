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
    unless current_user.can_add_client?
      redirect_to user_clients_path(@user), alert: 'Client limit reached.'
      return
    end

    invitation = ClientInvitation.create(
      email: client_params[:email],
      owner: current_user,
      token: SecureRandom.hex(10)
    )

    ClientInvitationMailer.with(invitation: invitation).invite.deliver_now
    redirect_to user_clients_path(@user), notice: 'Invitation sent.'    
  end

  def destroy
    @client.destroy
    @client.update(inactive: true) unless @client.destroyed?
    redirect_to user_clients_path(@user), notice: 'Client was revoked.'
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
    params.require(:client).permit(:email)
  end
end