class ClientInvitationMailer < ApplicationMailer
  def invite
    @invitation = params[:invitation]
    mail(to: @invitation.email, subject: 'Client Invitation')
    end
end