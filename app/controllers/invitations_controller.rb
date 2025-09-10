class InvitationsController < ApplicationController
  def accept
    invitation = Invitation.find_by!(token: params[:token])
    redirect_to new_user_registration_path(invitation_token: invitation.token)
  end
end