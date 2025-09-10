class Users::RegistrationsController < Devise::RegistrationsController
  def create
    invitation = Invitation.find_by(token: params[:invitation_token])

    if invitation
      params[:user] ||= {}
      params[:user][:owner_id] = invitation.owner_id
      params[:user][:role] = 'client'
    end

    super do |resource|
      invitation.update!(accepted_at: Time.current) if resource.persisted? && invitation
    end
  end
end