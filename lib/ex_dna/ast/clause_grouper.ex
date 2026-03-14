defmodule ExDNA.AST.ClauseGrouper do
  @moduledoc """
  Groups consecutive function clauses with the same name/arity into synthetic
  compound nodes so the fingerprinter can detect duplicated multi-clause functions.

  In Elixir's AST, multi-clause definitions like:

      defp foo(x) when x > 0, do: x
      defp foo(x), do: -x

  are represented as separate `defp` nodes in the module body. The fingerprinter
  walks each independently, so a 3-clause function with mass 15 per clause
  (total ~50) may fall below `min_mass` per clause and never be detected.

  This module rewrites the module body to wrap consecutive same-name/arity clauses
  in a synthetic `@ex_dna_grouped_def` block that the fingerprinter treats as
  a single subtree.
  """

  @def_forms [:def, :defp, :defmacro, :defmacrop]

  @doc """
  Walk the AST and group consecutive function clauses inside module bodies.
  """
  @spec group(Macro.t()) :: Macro.t()
  def group(ast) do
    Macro.prewalk(ast, fn
      {:defmodule, meta, [alias_node, [do: {:__block__, block_meta, body}]]}
      when is_list(body) ->
        {:defmodule, meta, [alias_node, [do: {:__block__, block_meta, group_body(body)}]]}

      other ->
        other
    end)
  end

  defp group_body(nodes) do
    nodes
    |> chunk_by_clause()
    |> Enum.flat_map(fn
      [single] -> [single]
      group -> [wrap_group(group)]
    end)
  end

  defp chunk_by_clause(nodes), do: do_chunk(nodes, [])

  defp do_chunk([], acc), do: Enum.reverse(acc)

  defp do_chunk([node | rest], acc) do
    case def_identity(node) do
      nil ->
        do_chunk(rest, [[node] | acc])

      identity ->
        {same, remaining} = collect_same(rest, identity, [node])
        do_chunk(remaining, [Enum.reverse(same) | acc])
    end
  end

  defp collect_same([node | rest], identity, collected) do
    if def_identity(node) == identity do
      collect_same(rest, identity, [node | collected])
    else
      {collected, [node | rest]}
    end
  end

  defp collect_same([], _identity, collected), do: {collected, []}

  defp def_identity({form, _meta, [{:when, _, [call | _]}, _body]}) when form in @def_forms do
    {form, name_arity(call)}
  end

  defp def_identity({form, _meta, [call, _body]}) when form in @def_forms do
    {form, name_arity(call)}
  end

  defp def_identity(_), do: nil

  defp name_arity({name, _meta, args}) when is_atom(name) and is_list(args), do: {name, length(args)}
  defp name_arity({name, _meta, nil}) when is_atom(name), do: {name, 0}
  defp name_arity(_), do: nil

  defp wrap_group(clauses) do
    line = first_line(clauses)
    {:__ex_dna_grouped_def__, [line: line], clauses}
  end

  defp first_line([{_form, meta, _} | _]), do: Keyword.get(meta, :line, 0)
  defp first_line(_), do: 0
end
