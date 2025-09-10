class OwnersController < ApplicationController
  before_action :authenticate_owner!

  def dashboard; end
end