Rails.application.routes.draw do
  devise_for :users
  resources :risk_assistants, only: %i[index show new create destroy report] do
    resources :messages, only: :create
    member do 
      get :report
      get   :tabla_datos
      patch :update_message
      post :create_message
    end
  end

  get  'risk_assistants/:id/report', to: "risk_assistants#report", as: 'risk_assistant_report'
  get  'risk_assistants/:id/resume', to: "risk_assistants#resume", as: 'risk_assistant_resume'

  root 'static_pages#home'
end