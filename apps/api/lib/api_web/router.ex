defmodule ApiWeb.Router do
  use ApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :auth do
    plug ApiWeb.GuardianPipeline
  end

  scope "/", ApiWeb do
    pipe_through :api

    get "/health", HealthController, :ping

    post "/signup", UserController, :create

    post "/login", UserController, :login
  end

  scope "/mart", ApiWeb do
    pipe_through [:api, :auth]

    post "/publishers", UserController, :create_publisher

    resources "/charts", ChartController, only: [:create] do
      post "/version", ChartController, :version
      get "/token", ChartController, :token
    end

    resources "/installations", InstallationController, only: [:create] do
      get "/token", InstallationController, :token
    end
  end

  scope "/", ApiWeb do
    get "/:publisher/:repo/index.yaml", ChartMuseumController, :index
    get "/:publisher/:repo/charts/:chart", ChartMuseumController, :get

    scope "/api" do
      post "/:publisher/:repo/charts", ChartMuseumController, :create_chart
      post "/:publisher/:repo/prov", ChartMuseumController, :create_prov
      delete "/:publisher/:repo/charts/:name/:version", ChartMuseumController, :delete

      get "/:publisher/:repo/charts", ChartMuseumController, :list
      get "/:publisher/:repo/charts/:chart", ChartMuseumController, :list_versions
      get "/:publisher/:repo/charts/:chart/:version", ChartMuseumController, :get_version
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", ApiWeb do
  #   pipe_through :api
  # end
end
