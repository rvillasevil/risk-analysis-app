class Owners::RegistrationsController < Devise::RegistrationsController
  private

  def sign_up_params
    super.merge(role: :owner)
  end
  protected

  def after_sign_up_path_for(resource)
    after_sign_in_path_for(resource)
  end
end