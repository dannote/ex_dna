defmodule ExDNA.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/dannote/ex_dna"

  def project do
    [
      app: :ex_dna,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "ExDNA",
      description: "Code duplication detector powered by Elixir AST analysis",
      source_url: @source_url,
      docs: docs(),
      package: package(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "ExDNA",
      extras: ["README.md"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp aliases do
    []
  end
end
