defmodule ExDNA do
  @moduledoc """
  Code duplication detector powered by Elixir AST analysis.

  ExDNA finds duplicated code blocks by normalizing the AST (stripping variable
  names, metadata, and literals), fingerprinting subtrees, and grouping
  collisions. Unlike token-based detectors, it understands Elixir's structure:
  pipes, pattern matching, guards, and module boundaries.

  ## Quick start

      ExDNA.analyze("lib/")
      #=> %ExDNA.Report{clones: [...], stats: %{...}}

  ## Clone types

  - **Type I** — exact copies (modulo whitespace/comments)
  - **Type II** — renamed variables and/or changed literals

  ## Configuration

  Pass options to `analyze/1` or configure in `.ex_dna.exs`:

      %{
        min_mass: 30,
        min_similarity: 1.0,
        paths: ["lib/"],
        ignore: ["lib/my_app_web/templates/**"]
      }
  """

  alias ExDNA.{Config, Detection, Report}

  @type path_or_paths :: String.t() | [String.t()]

  @doc """
  Analyze files for code duplication.

  Accepts a path string, a list of paths, or a keyword list of options.

  ## Options

    * `:paths` — list of file/directory paths to scan (default: `["lib/"]`)
    * `:min_mass` — minimum AST node count for a fragment to be considered (default: `#{Config.default(:min_mass)}`)
    * `:min_similarity` — similarity threshold 0.0–1.0 (default: `#{Config.default(:min_similarity)}`)
    * `:ignore` — list of glob patterns to exclude
    * `:reporters` — list of reporter modules (default: `[ExDNA.Reporter.Console]`)

  ## Examples

      ExDNA.analyze("lib/")
      ExDNA.analyze(paths: ["lib/", "test/"], min_mass: 20)
  """
  @spec analyze(path_or_paths() | keyword()) :: Report.t()
  def analyze(path_or_opts \\ [])

  def analyze(path) when is_binary(path), do: analyze(paths: [path])

  def analyze(opts) when is_list(opts) do
    config = Config.new(opts)

    config
    |> Detection.Detector.run()
    |> Report.new(config)
  end
end
