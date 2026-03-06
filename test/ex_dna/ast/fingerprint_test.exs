defmodule ExDNA.AST.FingerprintTest do
  use ExUnit.Case, async: true

  alias ExDNA.AST.Fingerprint

  describe "mass/1" do
    test "counts leaf nodes" do
      assert Fingerprint.mass(42) == 1
      assert Fingerprint.mass(:ok) == 1
    end

    test "counts call nodes" do
      ast = quote do: foo(1, 2)
      assert Fingerprint.mass(ast) >= 3
    end

    test "counts nested structures" do
      ast = quote do: Enum.map([1, 2, 3], fn x -> x * 2 end)
      assert Fingerprint.mass(ast) > 5
    end
  end

  describe "compute_hash/1" do
    test "identical ASTs produce identical hashes" do
      ast1 = quote do: foo(1, 2)
      ast2 = quote do: foo(1, 2)

      assert Fingerprint.compute_hash(ast1) == Fingerprint.compute_hash(ast2)
    end

    test "different ASTs produce different hashes" do
      ast1 = quote do: foo(1, 2)
      ast2 = quote do: bar(3, 4)

      refute Fingerprint.compute_hash(ast1) == Fingerprint.compute_hash(ast2)
    end
  end

  describe "fragments/4" do
    test "extracts fragments meeting min_mass" do
      ast =
        quote do
          def foo(a, b) do
            a + b + a * b
          end
        end

      frags = Fingerprint.fragments(ast, "test.ex", 3)
      assert length(frags) > 0
      assert Enum.all?(frags, fn f -> f.mass >= 3 end)
    end

    test "skips small fragments" do
      ast = quote do: 1 + 2
      frags = Fingerprint.fragments(ast, "test.ex", 100)
      assert frags == []
    end

    test "records file and line" do
      ast =
        Code.string_to_quoted!("""
        def foo(x) do
          x + 1 + x * 2 + x
        end
        """)

      frags = Fingerprint.fragments(ast, "myfile.ex", 3)

      assert Enum.all?(frags, fn f -> f.file == "myfile.ex" end)
    end
  end
end
