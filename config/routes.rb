Rails.application.routes.draw do
  devise_for :users
  resources :risk_assistants, only: %i[index show new create destroy] do
    resources :messages, only: :create
  end
  root 'static_pages#home'
end