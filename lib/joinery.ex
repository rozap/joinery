defmodule Joinery do
  use Application
  require Logger

  @port 4000

  def start(_type, _args) do
    Logger.info("Starting our app!")
    import Supervisor.Spec

    child_specs = [
      # Plug can adapt our Router plug to a child specification that
      # we can then give to a supervisor. A child specification is something
      # that says how we start something, and how we restart it when it crashes
      Plug.Adapters.Cowboy.child_spec(:http, Joinery.Router, [], [port: @port])
    ]

    Logger.info("Starting on port #{@port}")

    # start_link starts our supervisor with our child_specs
    Supervisor.start_link(
      child_specs,
      # We give it a name, so when you start observer you can identify it easily
      strategy: :one_for_one, name: Joinery.Supervisor
    )
  end
end