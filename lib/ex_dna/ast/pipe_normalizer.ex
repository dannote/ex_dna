defmodule ExDNA.AST.PipeNormalizer do
  @moduledoc """
  Normalizes pipe operators to nested function calls.

  `x |> foo() |> bar(1)` becomes `bar(foo(x), 1)`.

  This ensures that stylistic choices between pipe chains and nested calls
  don't prevent clone detection.
  """

  @doc """
  Convert all pipe expressions in an AST to nested function calls.
  """
  @spec normalize(Macro.t()) :: Macro.t()
  def normalize(ast) do
    Macro.prewalk(ast, &flatten_pipe/1)
  end

  defp flatten_pipe({:|>, _meta, [left, right]}) do
    inject_first_arg(right, left)
  end

  defp flatten_pipe(other), do: other

  defp inject_first_arg({call, meta, args}, first_arg) when is_list(args) do
    {call, meta, [first_arg | args]}
  end

  defp inject_first_arg({call, meta, nil}, first_arg) do
    {call, meta, [first_arg]}
  end

  defp inject_first_arg(other, first_arg) do
    {other, [], [first_arg]}
  end
end
