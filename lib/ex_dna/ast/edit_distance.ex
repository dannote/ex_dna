defmodule ExDNA.AST.EditDistance do
  @moduledoc """
  Computes structural similarity between two ASTs using a simplified
  tree edit distance.

  Instead of a full Zhang-Shasha algorithm (O(n²m²)), we use a top-down
  recursive approach that is O(n·m) in practice for typical Elixir ASTs.
  It computes the number of matching nodes and derives a similarity score.

  The similarity is `2 * matching_nodes / (size_a + size_b)`, yielding
  a value between 0.0 (completely different) and 1.0 (identical).
  """

  alias ExDNA.AST.Fingerprint

  @doc """
  Compute similarity between two ASTs, returning a float 0.0–1.0.
  """
  @spec similarity(Macro.t(), Macro.t()) :: float()
  def similarity(ast_a, ast_b) do
    mass_a = Fingerprint.mass(ast_a)
    mass_b = Fingerprint.mass(ast_b)

    if mass_a == 0 and mass_b == 0 do
      1.0
    else
      matched = matching_nodes(ast_a, ast_b)
      2 * matched / (mass_a + mass_b)
    end
  end

  @doc """
  Count the number of structurally matching nodes between two ASTs.
  """
  @spec matching_nodes(Macro.t(), Macro.t()) :: non_neg_integer()
  def matching_nodes(same, same), do: Fingerprint.mass(same)

  def matching_nodes({form_a, _meta_a, args_a}, {form_b, _meta_b, args_b})
      when is_list(args_a) and is_list(args_b) do
    form_match = if forms_equal?(form_a, form_b), do: 1, else: 0
    args_match = matching_children(args_a, args_b)
    form_match + args_match
  end

  def matching_nodes({form_a, _meta_a, ctx_a}, {form_b, _meta_b, ctx_b})
      when is_atom(ctx_a) and is_atom(ctx_b) do
    if forms_equal?(form_a, form_b) and ctx_a == ctx_b, do: 1, else: 0
  end

  def matching_nodes({la, ra}, {lb, rb}) do
    1 + matching_nodes(la, lb) + matching_nodes(ra, rb)
  end

  def matching_nodes(list_a, list_b) when is_list(list_a) and is_list(list_b) do
    matching_children(list_a, list_b)
  end

  def matching_nodes(a, b) do
    if a == b, do: 1, else: 0
  end

  defp matching_children(list_a, list_b) do
    min_len = min(length(list_a), length(list_b))

    list_a
    |> Enum.take(min_len)
    |> Enum.zip(Enum.take(list_b, min_len))
    |> Enum.map(fn {a, b} -> matching_nodes(a, b) end)
    |> Enum.sum()
  end

  defp forms_equal?(a, b) when is_atom(a) and is_atom(b), do: a == b

  defp forms_equal?({:., _, parts_a}, {:., _, parts_b}) do
    length(parts_a) == length(parts_b) and
      Enum.zip(parts_a, parts_b)
      |> Enum.all?(fn {a, b} -> forms_equal?(a, b) end)
  end

  defp forms_equal?({:__aliases__, _, mods_a}, {:__aliases__, _, mods_b}), do: mods_a == mods_b
  defp forms_equal?(a, b), do: a == b
end
