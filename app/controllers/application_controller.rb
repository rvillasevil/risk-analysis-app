class ApplicationController < ActionController::Base
  before_action :set_current_owner
  before_action :configure_permitted_parameters, if: :devise_controller?

  private

  def risk_assistants_scope
    owner_or_self.risk_assistants
  end
  helper_method :risk_assistants_scope

  def owner_or_self
    current_user.owner || current_user
  end
  helper_method :owner_or_self

  def require_authorized_user!
    redirect_to root_path, alert: 'Acceso no autorizado' unless current_user&.owner? || current_user&.client?
  end
  alias_method :require_client!, :require_authorized_user!

  protected

  def after_sign_in_path_for(resource)
    resource.owner? ? owner_dashboard_path : client_dashboard_path
  end  

  def configure_permitted_parameters
    allowed = [:name, :role, :company_name, :owner_id, :logo]
    devise_parameter_sanitizer.permit(:account_update, keys: %i[name role owner_id company_name logo])
    devise_parameter_sanitizer.permit(:sign_up,        keys: %i[name role owner_id company_name logo])
  end

  def set_current_owner
    Current.owner = current_user&.owner || current_user
    Current.field_catalogue = FieldCatalogue.active_for(Current.owner)
  end  
end
