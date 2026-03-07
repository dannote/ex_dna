defmodule Mix.Tasks.ExDna do
  @shortdoc "Detect code duplication in your Elixir project"
  @moduledoc """
  Scans your project for duplicated code blocks using AST analysis.

      $ mix ex_dna
      $ mix ex_dna lib/my_app/accounts
      $ mix ex_dna --min-mass 20 --literal-mode abstract
      $ mix ex_dna --min-similarity 0.85

  ## Command-line options

    * `--min-mass` — minimum AST node count (default: 30)
    * `--min-similarity` — similarity threshold 0.0–1.0 (default: 1.0).
      Values below 1.0 enable Type-III near-miss detection.
    * `--literal-mode` — `keep` (Type-I only) or `abstract` (also Type-II). Default: `keep`
    * `--normalize-pipes` — treat `x |> f()` the same as `f(x)`. Default: false
    * `--exclude-macro` — macro name to skip during analysis (repeatable).
      `@` is excluded by default. Common: `schema`, `pipe_through`, `plug`
    * `--ignore` — glob pattern to exclude (repeatable)
    * `--format` — output format: `console` (default), `json`, or `html`

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
          normalize_pipes: :boolean,
          exclude_macro: :keep,
          ignore: :keep,
          format: :string
        ],
        aliases: [m: :min_mass, s: :min_similarity, i: :ignore, f: :format]
      )

    config_opts = build_config(opts, paths)

    start = System.monotonic_time(:millisecond)
    report = ExDNA.analyze(config_opts)
    elapsed = System.monotonic_time(:millisecond) - start

    unless Keyword.get(opts, :format) == "json" do
      IO.puts(["  Detection time:     #{elapsed}ms\n"])
    end

    if report.stats.total_clones > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  defp build_config(opts, paths) do
    reporters =
      case Keyword.get(opts, :format, "console") do
        "json" -> [ExDNA.Reporter.JSON]
        "html" -> [ExDNA.Reporter.HTML]
        _ -> [ExDNA.Reporter.Console]
      end

    literal_mode =
      case Keyword.get(opts, :literal_mode, "keep") do
        "abstract" -> :abstract
        _ -> :keep
      end

    excluded_macros =
      case Keyword.get_values(opts, :exclude_macro) do
        [] -> nil
        macros -> Enum.map(macros, &String.to_atom/1)
      end

    [
      paths: if(paths != [], do: paths, else: ["lib/"]),
      reporters: reporters,
      literal_mode: literal_mode,
      normalize_pipes: Keyword.get(opts, :normalize_pipes, false),
      ignore: Keyword.get_values(opts, :ignore)
    ]
    |> maybe_put(:min_mass, Keyword.get(opts, :min_mass))
    |> maybe_put(:min_similarity, Keyword.get(opts, :min_similarity))
    |> maybe_put(:excluded_macros, excluded_macros)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
