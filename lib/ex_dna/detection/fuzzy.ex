defmodule ExDNA.Detection.Fuzzy do
  @moduledoc """
  Type-III (near-miss) clone detection using structural similarity.

  Compares fragment pairs that didn't match exactly but are close in mass.
  Uses `ExDNA.AST.EditDistance` to compute similarity and groups pairs
  above the configured threshold.

  Performance strategy:
  - Only compare fragments within ±30% mass of each other
  - Skip fragments already covered by exact (Type-I/II) clones
  - Process in descending mass order so we find the largest clones first
  """

  alias ExDNA.AST.{EditDistance, Normalizer}
  alias ExDNA.Detection.Clone

  @mass_tolerance 0.3

  @doc """
  Find Type-III clones from a list of fragments at the given similarity threshold.

  Returns clone structs for every pair above the threshold that isn't
  already an exact match.
  """
  @spec detect([map()], float(), MapSet.t()) :: [Clone.t()]
  def detect(fragments, min_similarity, exact_hashes) do
    fragments
    |> Enum.reject(fn f -> MapSet.member?(exact_hashes, f.hash) end)
    |> Enum.sort_by(& &1.mass, :desc)
    |> find_similar_pairs(min_similarity)
    |> deduplicate_pairs()
    |> Enum.map(&pair_to_clone/1)
  end

  defp find_similar_pairs(fragments, min_similarity) do
    indexed = Enum.with_index(fragments)

    for {frag_a, i} <- indexed,
        {frag_b, j} <- indexed,
        j > i,
        mass_compatible?(frag_a, frag_b),
        not same_location?(frag_a, frag_b),
        sim = compute_similarity(frag_a, frag_b),
        sim >= min_similarity do
      {frag_a, frag_b, sim}
    end
  end

  defp mass_compatible?(a, b) do
    ratio = min(a.mass, b.mass) / max(a.mass, b.mass)
    ratio >= 1.0 - @mass_tolerance
  end

  defp same_location?(a, b) do
    a.file == b.file and a.line == b.line
  end

  defp compute_similarity(frag_a, frag_b) do
    norm_a = Normalizer.normalize(frag_a.ast)
    norm_b = Normalizer.normalize(frag_b.ast)
    EditDistance.similarity(norm_a, norm_b)
  end

  defp deduplicate_pairs(pairs) do
    pairs
    |> Enum.sort_by(fn {_, _, sim} -> sim end, :desc)
    |> Enum.reduce({[], MapSet.new()}, fn {a, b, sim}, {acc, seen} ->
      key_a = {a.file, a.line}
      key_b = {b.file, b.line}

      if MapSet.member?(seen, key_a) or MapSet.member?(seen, key_b) do
        {acc, seen}
      else
        seen = seen |> MapSet.put(key_a) |> MapSet.put(key_b)
        {[{a, b, sim} | acc], seen}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp pair_to_clone({frag_a, frag_b, similarity}) do
    mass = max(frag_a.mass, frag_b.mass)

    %Clone{
      type: :type_iii,
      hash: nil,
      mass: mass,
      fragments: [
        %{file: frag_a.file, line: frag_a.line, ast: frag_a.ast, mass: frag_a.mass},
        %{file: frag_b.file, line: frag_b.line, ast: frag_b.ast, mass: frag_b.mass}
      ],
      source_snippets: [
        Macro.to_string(frag_a.ast),
        Macro.to_string(frag_b.ast)
      ],
      suggestion: nil,
      similarity: similarity
    }
  end
end
