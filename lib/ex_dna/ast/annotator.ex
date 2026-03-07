defmodule ExDNA.AST.Annotator do
  @moduledoc """
  Pre-processes the AST to handle annotations like `@no_clone true`.

  When `@no_clone true` immediately precedes a `def`/`defp` in a module body,
  both the annotation and the definition are stripped from the AST so the
  fingerprinter never sees them.
  """

  @doc """
  Remove any `def`/`defp` definitions that are preceded by `@no_clone true`.

  The corresponding `@no_clone true` attribute nodes are also removed.
  """
  @spec strip_no_clone(Macro.t()) :: Macro.t()
  def strip_no_clone(ast) do
    Macro.prewalk(ast, fn
      {:defmodule, meta, [alias_node, [do: {:__block__, block_meta, body}]]}
      when is_list(body) ->
        {:defmodule, meta, [alias_node, [do: {:__block__, block_meta, strip_body(body)}]]}

      other ->
        other
    end)
  end

  defp strip_body(nodes), do: do_strip(nodes, [])

  defp do_strip([], acc), do: Enum.reverse(acc)

  defp do_strip([{:@, _, [{:no_clone, _, [true]}]}, next | rest], acc) do
    if def_node?(next) do
      do_strip(rest, acc)
    else
      do_strip([next | rest], [{:@, [], [{:no_clone, [], [true]}]} | acc])
    end
  end

  defp do_strip([node | rest], acc), do: do_strip(rest, [node | acc])

  defp def_node?({form, _, _}) when form in [:def, :defp], do: true
  defp def_node?(_), do: false
end
