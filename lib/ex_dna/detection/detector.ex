defmodule ExDNA.Detection.Detector do
  @moduledoc """
  Orchestrates the clone detection pipeline.

  1. Collect files matching the configured paths/globs.
  2. Parse each file into an AST.
  3. Extract fingerprinted fragments from every AST.
  4. Group fragments by hash — groups of 2+ are clones.
  5. Filter out nested/overlapping clones.
  """

  alias ExDNA.AST.{Annotator, Fingerprint}
  alias ExDNA.Config
  alias ExDNA.Detection.{Clone, Filter, Fuzzy}
  alias ExDNA.Refactor.{BehaviourSuggestion, Suggestion}

  @doc """
  Run detection for the given config. Returns a list of `Clone` structs.
  """
  @spec run(Config.t()) :: [Clone.t()]
  def run(%Config{} = config) do
    files = collect_files(config)

    fragments =
      files
      |> Task.async_stream(
        fn file -> parse_and_fingerprint(file, config) end,
        max_concurrency: System.schedulers_online(),
        ordered: false
      )
      |> Enum.flat_map(fn {:ok, frags} -> frags end)

    type_i_clones = find_clones(fragments, :type_i)

    type_ii_clones =
      if config.min_similarity < 1.0 or config.literal_mode == :abstract do
        abstract_config = %{config | literal_mode: :abstract}

        fragments_ii =
          files
          |> Task.async_stream(
            fn file -> parse_and_fingerprint(file, abstract_config) end,
            max_concurrency: System.schedulers_online(),
            ordered: false
          )
          |> Enum.flat_map(fn {:ok, frags} -> frags end)

        find_clones(fragments_ii, :type_ii)
        |> reject_already_found(type_i_clones)
      else
        []
      end

    exact_clones =
      (type_i_clones ++ type_ii_clones)
      |> Filter.prune_nested()

    type_iii_clones = find_fuzzy_clones(fragments, exact_clones, config)

    (exact_clones ++ type_iii_clones)
    |> Enum.map(&attach_suggestion/1)
    |> BehaviourSuggestion.analyze()
    |> Enum.sort_by(& &1.mass, :desc)
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
      File.dir?(path) ->
        Path.wildcard(Path.join(path, "**/*.{ex,exs}"))

      String.contains?(path, "*") ->
        Path.wildcard(path)

      File.regular?(path) ->
        [path]

      true ->
        []
    end
  end

  defp ignored?(file, patterns) do
    Enum.any?(patterns, fn pattern ->
      file
      |> Path.relative_to_cwd()
      |> matches_glob?(pattern)
    end)
  end

  defp matches_glob?(path, pattern) do
    regex =
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")
      |> then(&Regex.compile!("^#{&1}$"))

    Regex.match?(regex, path)
  end

  defp parse_and_fingerprint(file, config) do
    case File.read(file) do
      {:ok, source} ->
        task =
          Task.async(fn ->
            Code.string_to_quoted(source, line: 1, columns: true, file: file)
          end)

        case Task.yield(task, config.parse_timeout) || Task.shutdown(task) do
          {:ok, {:ok, ast}} ->
            ast = Annotator.strip_no_clone(ast)

            Fingerprint.fragments(ast, file, config.min_mass,
              literal_mode: config.literal_mode,
              normalize_pipes: config.normalize_pipes,
              excluded_macros: config.excluded_macros
            )

          _ ->
            []
        end

      {:error, _} ->
        []
    end
  end

  defp find_fuzzy_clones(_fragments, _exact_clones, %Config{min_similarity: s}) when s >= 1.0,
    do: []

  defp find_fuzzy_clones(fragments, exact_clones, config) do
    exact_locations =
      exact_clones
      |> Enum.flat_map(fn c -> Enum.map(c.fragments, &{&1.file, &1.line}) end)
      |> MapSet.new()

    exact_hashes = MapSet.new(exact_clones, & &1.hash)

    Fuzzy.detect(fragments, config.min_similarity, exact_hashes)
    |> Enum.reject(fn clone ->
      Enum.any?(clone.fragments, fn f -> MapSet.member?(exact_locations, {f.file, f.line}) end)
    end)
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

  defp reject_already_found(type_ii, type_i) do
    type_i_hashes = MapSet.new(type_i, & &1.hash)
    Enum.reject(type_ii, fn clone -> MapSet.member?(type_i_hashes, clone.hash) end)
  end
end
