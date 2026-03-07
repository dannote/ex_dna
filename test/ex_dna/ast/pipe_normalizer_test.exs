defmodule ExDNA.AST.PipeNormalizerTest do
  use ExUnit.Case, async: true

  alias ExDNA.AST.PipeNormalizer

  describe "normalize/1" do
    test "converts simple pipe to nested call" do
      piped = quote do: x |> foo()
      nested = quote do: foo(x)

      assert strip(PipeNormalizer.normalize(piped)) == strip(nested)
    end

    test "converts multi-step pipe to deeply nested calls" do
      piped = quote do: x |> foo() |> bar(1)
      nested = quote do: bar(foo(x), 1)

      assert strip(PipeNormalizer.normalize(piped)) == strip(nested)
    end

    test "converts pipe with remote calls" do
      piped = quote do: list |> Enum.map(fn x -> x * 2 end) |> Enum.filter(fn x -> x > 0 end)

      normalized = PipeNormalizer.normalize(piped)
      str = normalized |> strip() |> Macro.to_string()

      assert str =~ "Enum.filter(Enum.map("
    end

    test "leaves non-pipe code untouched" do
      ast = quote do: foo(bar(x), 1)
      assert PipeNormalizer.normalize(ast) == ast
    end

    test "handles pipe inside def" do
      ast =
        quote do
          def process(data) do
            data |> transform() |> format()
          end
        end

      normalized = PipeNormalizer.normalize(ast)
      str = normalized |> strip() |> Macro.to_string()

      assert str =~ "format(transform("
    end
  end

  defp strip(ast) do
    Macro.prewalk(ast, fn
      {form, _meta, args} when is_list(args) -> {form, [], args}
      {form, _meta, atom} when is_atom(atom) -> {form, [], atom}
      other -> other
    end)
  end
end
