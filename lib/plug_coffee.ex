defmodule PlugCoffee do
  use Application

  def start(_type, _args) do
    PlugCoffee.Supervisor.start_link()
  end
end
