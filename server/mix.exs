defmodule AiBrain.MixProject do
  use Mix.Project

  def project do
    [
      app: :ai_brain,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {AIBrain.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.6"},
      {:jason, "~> 1.4"},
      {:websock, "~> 0.5"},
      {:websock_adapter, "~> 0.5"},
      {:req, "~> 0.5"},
      {:req_llm, "~> 1.12"},
      {:html_entities, "~> 0.5"},
      {:gen_smtp, "~> 1.0"},
      {:mox, "~> 1.1", only: :test},
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, "~> 0.17"},

      # New dependencies for unified platform
      {:gen_stage, "~> 1.0"},
      {:uuid, "~> 1.1"},
      {:telemetry, "~> 1.3"},
      {:sweet_xml, "~> 0.7"},
      {:file_system, "~> 1.0", only: :dev}
    ]
  end
end
