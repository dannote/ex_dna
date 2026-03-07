defmodule ExDNA.AST.EditDistanceTest do
  use ExUnit.Case, async: true

  alias ExDNA.AST.{EditDistance, Fingerprint, Normalizer}

  describe "similarity/2" do
    test "identical ASTs have similarity 1.0" do
      ast = quote do: Enum.map(list, fn x -> x * 2 end)
      assert EditDistance.similarity(ast, ast) == 1.0
    end

    test "completely different ASTs have low similarity" do
      ast_a = quote do: foo(1, 2, 3)
      ast_b = quote do: String.upcase("hello")

      sim = EditDistance.similarity(ast_a, ast_b)
      assert sim < 0.5
    end

    test "similar ASTs have high similarity" do
      ast_a =
        quote do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.sort()
        end

      ast_b =
        quote do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.take(5)
        end

      sim = EditDistance.similarity(ast_a, ast_b)
      assert sim > 0.7
      assert sim < 1.0
    end

    test "ASTs differing only in variable names are dissimilar without normalization" do
      ast_a = quote do: foo(a, b, c)
      ast_b = quote do: foo(x, y, z)

      sim = EditDistance.similarity(ast_a, ast_b)
      # Without normalization, variable names are different atoms → low similarity.
      # The fuzzy detector normalizes first, which makes them identical.
      assert sim < 0.5
    end

    test "normalized ASTs with renamed variables are identical" do
      ast_a = quote do: foo(a, b, c)
      ast_b = quote do: foo(x, y, z)

      norm_a = Normalizer.normalize(ast_a)
      norm_b = Normalizer.normalize(ast_b)

      assert EditDistance.similarity(norm_a, norm_b) == 1.0
    end

    test "ASTs differing only in one literal have high similarity" do
      ast_a =
        quote do
          def handle(:start, state) do
            {:ok, state + 1}
          end
        end

      ast_b =
        quote do
          def handle(:stop, state) do
            {:ok, state + 1}
          end
        end

      sim = EditDistance.similarity(ast_a, ast_b)
      assert sim > 0.8
    end
  end

  describe "matching_nodes/2" do
    test "counts all nodes for identical trees" do
      ast = quote do: foo(1, 2)
      mass = Fingerprint.mass(ast)

      assert EditDistance.matching_nodes(ast, ast) == mass
    end

    test "returns 0 for leaf mismatch" do
      assert EditDistance.matching_nodes(1, 2) == 0
    end

    test "returns 1 for leaf match" do
      assert EditDistance.matching_nodes(:ok, :ok) == 1
    end
  end
end
