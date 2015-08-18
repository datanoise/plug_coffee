# PlugCoffee

This plug compiles and serves coffeescript files.

```elixir
Plug.Adapters.Cowboy.http PlugCoffee.Plug, [root: "public/coffee", urls: ["/js"], cache_compile_dir: "/tmp"]
```

## Installation

  1. Add plug_coffee to your list of dependencies in mix.exs:

        def deps do
          [{:plug_coffee, "~> 0.0.1"}]
        end

  2. Ensure plug_coffee is started before your application:

        def application do
          [applications: [:plug_coffee]]
        end
