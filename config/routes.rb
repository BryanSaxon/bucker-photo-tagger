Rails.application.routes.draw do
  # Preview outgoing mail in development at /mail.
  mount LetterOpenerWeb::Engine, at: "/mail" if Rails.env.development?

  resource :session
  resources :passwords, param: :token

  resources :photos do
    member do
      # SKU search results for the processing panel (Turbo-driven live filter).
      get :sku_search
    end
  end

  # SKU catalog library + manual sync trigger.
  resources :skus, only: %i[index show]
  resources :sku_syncs, only: :create

  # Admin-only user management (invite / role / remove).
  resources :users, only: %i[index create update destroy] do
    member do
      post :resend_invite
      post :deactivate
      post :reactivate
    end
  end

  root "photos#index"


  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
