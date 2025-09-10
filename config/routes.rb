Rails.application.routes.draw do
  devise_for :users
  resources :users, only: [] do
    resources :clients, only: %i[index new create destroy]
  end  
  resources :clients, only: :show  
  resources :risk_assistants, only: %i[index show new create destroy report] do
    resources :messages, only: :create
    member do 
      get :report
      get   :tabla_datos
      patch :update_message
      post :create_message
      get :summary
      delete 'files/:file_id', to: 'risk_assistants#destroy_file', as: :file
    end
  end

  resources :policy_analyses, only: [:index, :new, :create, :show, :destroy] do
    post :create_analysis, on: :member
    post :ask, on: :member   # << añadimos esta línea    
  end

  get 'clients/dashboard', to: 'clients#dashboard', as: :client_dashboard  

  get  'risk_assistants/:id/report', to: "risk_assistants#report", as: 'risk_assistant_report'
  get  'risk_assistants/:id/resume', to: "risk_assistants#resume", as: 'risk_assistant_resume'

  root 'static_pages#home'
end