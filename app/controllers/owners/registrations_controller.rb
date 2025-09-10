class Owners::RegistrationsController < Devise::RegistrationsController
  private

  def sign_up_params
    super.merge(role: :owner)
  end
end