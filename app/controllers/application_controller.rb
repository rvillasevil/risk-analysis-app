class ApplicationController < ActionController::Base
  before_action { Current.owner = current_user.owner || current_user }  
  before_action :configure_permitted_parameters, if: :devise_controller?

  private

  def owner_or_self
    current_user.owner || current_user
  end
  helper_method :owner_or_self

  def require_authorized_user!
    redirect_to root_path, alert: 'Acceso no autorizado' unless current_user&.owner? || current_user&.client?
  end
  alias_method :require_client!, :require_authorized_user!

  protected

  def configure_permitted_parameters
    allowed = [:name, :role, :company_name, :owner_id, :logo]
    devise_parameter_sanitizer.permit(:account_update, keys: %i[name role owner_id company_name logo])
    devise_parameter_sanitizer.permit(:sign_up,        keys: %i[name role owner_id company_name logo])
  end
end
