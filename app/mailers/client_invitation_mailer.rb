class ClientInvitationMailer < ApplicationMailer
  def invite
    @invitation = params[:invitation]
    mail(to: @invitation.email, subject: 'Client Invitation', body: "Signup link: /signup?token=#{@invitation.token}")
  end
end