defmodule ExDNA.AST.NormalizerTest do
  use ExUnit.Case, async: true

  alias ExDNA.AST.Normalizer

  describe "strip_metadata/1" do
    test "removes line and column info" do
      ast = Code.string_to_quoted!("foo(1, 2)", line: 1, columns: true)
      stripped = Normalizer.strip_metadata(ast)

      assert {:foo, [], [1, 2]} = stripped
    end

    test "preserves structural shape" do
      ast = quote do: Enum.map(list, fn x -> x * 2 end)
      stripped = Normalizer.strip_metadata(ast)

      {form, [], args} = stripped
      assert is_tuple(form)
      assert length(args) == 2
    end
  end

  describe "normalize_variables/1" do
    test "renames variables to positional placeholders" do
      ast1 = quote do: foo + bar
      ast2 = quote do: x + y

      norm1 = ast1 |> Normalizer.strip_metadata() |> Normalizer.normalize_variables()
      norm2 = ast2 |> Normalizer.strip_metadata() |> Normalizer.normalize_variables()

      assert norm1 == norm2
    end

    test "preserves binding order" do
      ast1 = quote do: a + b + a
      norm = ast1 |> Normalizer.strip_metadata() |> Normalizer.normalize_variables()

      {_, [], [{_, [], [{first_use, [], _}, {second_use, [], _}]}, {reuse, [], _}]} = norm
      assert first_use == :"$0"
      assert second_use == :"$1"
      assert reuse == :"$0"
    end

    test "does not rename function calls" do
      ast = quote do: String.upcase(x)
      norm = ast |> Normalizer.strip_metadata() |> Normalizer.normalize_variables()

      {{:., [], [{:__aliases__, [], [:String]}, :upcase]}, [], [{:"$0", [], _}]} = norm
    end
  end

  describe "normalize/2 with literal_mode: :keep" do
    test "identical code produces identical normalized AST" do
      code = "fn(a, b) -> a + b end"
      ast = Code.string_to_quoted!(code)

      n1 = Normalizer.normalize(ast)
      n2 = Normalizer.normalize(ast)

      assert n1 == n2
    end

    test "renamed variables produce identical normalized AST" do
      ast1 = Code.string_to_quoted!("fn(a, b) -> a + b end")
      ast2 = Code.string_to_quoted!("fn(x, y) -> x + y end")

      assert Normalizer.normalize(ast1) == Normalizer.normalize(ast2)
    end
  end

  describe "normalize/2 with literal_mode: :abstract" do
    test "different literal values produce identical normalized AST" do
      ast1 = Code.string_to_quoted!("x + 42")
      ast2 = Code.string_to_quoted!("y + 99")

      norm1 = Normalizer.normalize(ast1, literal_mode: :abstract)
      norm2 = Normalizer.normalize(ast2, literal_mode: :abstract)

      assert norm1 == norm2
    end

    test "different string literals produce identical normalized AST" do
      ast1 = Code.string_to_quoted!(~s[IO.puts("hello")])
      ast2 = Code.string_to_quoted!(~s[IO.puts("world")])

      norm1 = Normalizer.normalize(ast1, literal_mode: :abstract)
      norm2 = Normalizer.normalize(ast2, literal_mode: :abstract)

      assert norm1 == norm2
    end

    test "preserves true/false/nil" do
      ast = Code.string_to_quoted!("true && false || nil")
      norm = Normalizer.normalize(ast, literal_mode: :abstract)
      stringified = Macro.to_string(norm)

      assert stringified =~ "true"
      assert stringified =~ "false"
      assert stringified =~ "nil"
    end
  end
end
