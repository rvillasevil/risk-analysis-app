class ApplicationController < ActionController::Base
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    # Para editar el perfil
    devise_parameter_sanitizer.permit(:account_update, keys: [:name])
    # Para el registro inicial (si quieres)
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
  end    
end
