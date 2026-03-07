defmodule ExDNA.Detection.Filter do
  @moduledoc """
  Prunes overlapping and nested clones.

  When a large subtree is a clone, all its sub-subtrees will also match.
  We keep only the largest non-overlapping clone per file location.
  """

  alias ExDNA.Detection.Clone

  @doc """
  Remove clones whose fragment locations are all contained within a larger clone's fragments.
  """
  @spec prune_nested([Clone.t()]) :: [Clone.t()]
  def prune_nested(clones) do
    sorted = Enum.sort_by(clones, & &1.mass, :desc)
    prune_nested(sorted, [])
  end

  defp prune_nested([], acc), do: Enum.reverse(acc)

  defp prune_nested([clone | rest], accepted) do
    if subsumed_by_any?(clone, accepted) do
      prune_nested(rest, accepted)
    else
      prune_nested(rest, [clone | accepted])
    end
  end

  defp subsumed_by_any?(clone, accepted) do
    Enum.any?(accepted, fn larger -> subsumes?(larger, clone) end)
  end

  defp subsumes?(larger, smaller) do
    larger.mass > smaller.mass and
      Enum.all?(smaller.fragments, fn small_frag ->
        Enum.any?(larger.fragments, fn large_frag ->
          large_frag.file == small_frag.file and
            location_overlap?(large_frag, small_frag)
        end)
      end)
  end

  defp location_overlap?(larger_frag, smaller_frag) do
    large_span = line_span(larger_frag.ast)
    small_span = line_span(smaller_frag.ast)
    large_start = larger_frag.line
    small_start = smaller_frag.line

    if large_start == 0 or small_start == 0 do
      true
    else
      small_start >= large_start and
        small_start + small_span <= large_start + large_span
    end
  end

  defp line_span(ast) do
    {min_line, max_line} = line_range(ast, {nil, nil})

    case {min_line, max_line} do
      {nil, _} -> 0
      {_, nil} -> 0
      {min, max} -> max - min + 1
    end
  end

  defp line_range({_form, meta, args}, {min, max}) when is_list(args) do
    line = Keyword.get(meta, :line)
    {min, max} = update_range(line, min, max)
    Enum.reduce(args, {min, max}, &line_range/2)
  end

  defp line_range({_form, meta, ctx}, {min, max}) when is_atom(ctx) do
    line = Keyword.get(meta, :line)
    update_range(line, min, max)
  end

  defp line_range({left, right}, acc) do
    acc = line_range(left, acc)
    line_range(right, acc)
  end

  defp line_range(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &line_range/2)
  end

  defp line_range(_leaf, acc), do: acc

  defp update_range(nil, min, max), do: {min, max}
  defp update_range(line, nil, nil), do: {line, line}
  defp update_range(line, min, max), do: {min(line, min), max(line, max)}
end
