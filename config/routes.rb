Rails.application.routes.draw do
  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }

  root "resources#index"
  get "privacy", to: "pages#privacy", as: :privacy
  get "terms", to: "pages#terms", as: :terms
  resources :resources, only: [ :index, :show ], param: :slug do
    resource :bookmark, only: [ :create, :destroy ]
    resource :hidden_resource, only: [ :create, :destroy ]
  end

  namespace :my do
    root "dashboard#index"
  end

  namespace :admin do
    root "dashboard#index"
    resources :resources, only: [ :index, :new, :create ]
    get "taxonomy", to: "taxonomy#index", as: :taxonomy
    resources :tags, only: :create do
      post :merge, on: :member
    end
    resources :resource_revisions, only: [ :show, :edit, :update ] do
      post :approve_and_publish, on: :member
    end
  end

  namespace :internal do
    resource :scheduler_tick, only: :create
  end

  get "sitemap", to: "seo#sitemap", defaults: { format: :xml }, as: :sitemap
  get "robots.txt", to: "seo#robots", as: :robots

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
