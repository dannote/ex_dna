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

  alias ExDNA.{Cache, Config}
  alias ExDNA.Detection.{Filter, Pipeline}

  @impl true
  def run(_argv) do
    config = Config.new([])
    cache_path = Cache.default_path()
    cached = Cache.read(cache_path)

    files = Pipeline.collect_files(config)
    stale = Cache.stale_files(files, cached)

    fresh_entries =
      stale
      |> Task.async_stream(
        fn file -> {file, Pipeline.parse_and_fingerprint(file, config)} end,
        max_concurrency: System.schedulers_online(),
        ordered: false
      )
      |> Map.new(fn {:ok, {file, frags}} -> {file, Cache.build_entry(file, frags)} end)

    merged = Cache.merge(cached, fresh_entries, files)
    Cache.write(merged, cache_path)

    fragments = Enum.flat_map(merged, fn {_file, entry} -> entry.fragments end)

    clones =
      fragments
      |> Pipeline.find_clones(:type_i)
      |> Filter.prune_nested()
      |> Enum.map(&Pipeline.attach_suggestion/1)
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
end
