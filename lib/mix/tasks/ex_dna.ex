defmodule Mix.Tasks.ExDna do
  @shortdoc "Detect code duplication in your Elixir project"
  @moduledoc """
  Scans your project for duplicated code blocks using AST analysis.

      $ mix ex_dna
      $ mix ex_dna lib/my_app/accounts
      $ mix ex_dna --min-mass 20 --literal-mode abstract

  ## Command-line options

    * `--min-mass` — minimum AST node count (default: 30)
    * `--min-similarity` — similarity threshold 0.0–1.0 (default: 1.0)
    * `--literal-mode` — `keep` (Type-I only) or `abstract` (also Type-II). Default: `keep`
    * `--ignore` — glob pattern to exclude (repeatable)
    * `--format` — output format: `console` (default) or `json`

  Exits with code 1 if clones are found.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, paths, _} =
      OptionParser.parse(argv,
        strict: [
          min_mass: :integer,
          min_similarity: :float,
          literal_mode: :string,
          ignore: :keep,
          format: :string
        ],
        aliases: [m: :min_mass, s: :min_similarity, i: :ignore, f: :format]
      )

    reporters =
      case Keyword.get(opts, :format, "console") do
        "json" -> [ExDNA.Reporter.JSON]
        _ -> [ExDNA.Reporter.Console]
      end

    literal_mode =
      case Keyword.get(opts, :literal_mode, "keep") do
        "abstract" -> :abstract
        _ -> :keep
      end

    ignore =
      opts
      |> Keyword.get_values(:ignore)

    config_opts =
      [
        paths: if(paths != [], do: paths, else: ["lib/"]),
        reporters: reporters,
        literal_mode: literal_mode,
        ignore: ignore
      ]
      |> maybe_put(:min_mass, Keyword.get(opts, :min_mass))
      |> maybe_put(:min_similarity, Keyword.get(opts, :min_similarity))

    start = System.monotonic_time(:millisecond)
    report = ExDNA.analyze(config_opts)
    elapsed = System.monotonic_time(:millisecond) - start

    IO.puts(["  Detection time:    #{elapsed}ms\n"])

    if report.stats.total_clones > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
