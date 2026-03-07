defmodule ExDNA.Compiler do
  @moduledoc """
  A `Mix.Task.Compiler` that runs clone detection incrementally.

  On first run every source file is parsed, fingerprinted, and cached.
  On subsequent compilations only files that changed (by mtime) are
  re-analyzed; the rest is loaded from the cache.

  ## Setup

  Add `:ex_dna` to the compilers list in your `mix.exs`:

      def project do
        [compilers: Mix.compilers() ++ [:ex_dna]]
      end

  The cache is stored in `.ex_dna_cache` and should be added to `.gitignore`.
  """

  use Mix.Task.Compiler

  alias ExDNA.AST.{Annotator, Fingerprint}
  alias ExDNA.{Cache, Config}
  alias ExDNA.Detection.{Clone, Filter}
  alias ExDNA.Refactor.Suggestion

  @impl true
  def run(_argv) do
    config = Config.new([])
    cache_path = Cache.default_path()
    cached = Cache.read(cache_path)

    files = collect_files(config)
    stale = Cache.stale_files(files, cached)

    fresh_entries =
      stale
      |> Task.async_stream(
        fn file -> {file, parse_and_fingerprint(file, config)} end,
        max_concurrency: System.schedulers_online(),
        ordered: false
      )
      |> Map.new(fn {:ok, {file, frags}} -> {file, Cache.build_entry(file, frags)} end)

    merged = Cache.merge(cached, fresh_entries, files)
    Cache.write(merged, cache_path)

    fragments = Enum.flat_map(merged, fn {_file, entry} -> entry.fragments end)

    clones =
      fragments
      |> find_clones(:type_i)
      |> Filter.prune_nested()
      |> Enum.map(&attach_suggestion/1)
      |> Enum.sort_by(& &1.mass, :desc)

    diagnostics =
      Enum.flat_map(clones, fn clone ->
        Enum.map(clone.fragments, fn frag ->
          %Mix.Task.Compiler.Diagnostic{
            file: frag.file,
            position: frag.line,
            message: "Code clone detected (#{clone.type}, mass: #{clone.mass})",
            severity: :warning,
            compiler_name: "ExDNA"
          }
        end)
      end)

    {:ok, diagnostics}
  end

  defp collect_files(%Config{paths: paths, ignore: ignore_patterns}) do
    paths
    |> Enum.flat_map(&expand_path/1)
    |> Enum.reject(fn file -> ignored?(file, ignore_patterns) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp expand_path(path) do
    cond do
      File.dir?(path) -> Path.wildcard(Path.join(path, "**/*.{ex,exs}"))
      String.contains?(path, "*") -> Path.wildcard(path)
      File.regular?(path) -> [path]
      true -> []
    end
  end

  defp ignored?(file, patterns) do
    rel = Path.relative_to_cwd(file)

    Enum.any?(patterns, fn pattern ->
      regex =
        pattern
        |> Regex.escape()
        |> String.replace("\\*\\*", ".*")
        |> String.replace("\\*", "[^/]*")
        |> then(&Regex.compile!("^#{&1}$"))

      Regex.match?(regex, rel)
    end)
  end

  defp parse_and_fingerprint(file, config) do
    case File.read(file) do
      {:ok, source} ->
        case Code.string_to_quoted(source, line: 1, columns: true, file: file) do
          {:ok, ast} ->
            ast = Annotator.strip_no_clone(ast)

            Fingerprint.fragments(ast, file, config.min_mass,
              literal_mode: config.literal_mode,
              normalize_pipes: config.normalize_pipes,
              excluded_macros: config.excluded_macros
            )

          {:error, _} ->
            []
        end

      {:error, _} ->
        []
    end
  end

  defp find_clones(fragments, type) do
    fragments
    |> Enum.group_by(& &1.hash)
    |> Enum.filter(fn {_hash, group} -> length(group) >= 2 end)
    |> Enum.map(fn {_hash, group} -> Clone.from_fragments(group, type) end)
  end

  defp attach_suggestion(clone) do
    case Suggestion.suggest(clone) do
      nil -> clone
      suggestion -> %{clone | suggestion: suggestion}
    end
  end
end
