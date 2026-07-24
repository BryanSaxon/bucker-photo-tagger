Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resources :photos do
    member do
      # SKU search results for the processing panel (Turbo-driven live filter).
      get :sku_search
    end
  end

  # SKU catalog library + manual sync trigger.
  resources :skus, only: %i[index show] do
    member do
      # Pull this SKU's image bytes from NewStart and attach them.
      post :fetch_image
    end
  end
  resources :sku_syncs, only: :create

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
