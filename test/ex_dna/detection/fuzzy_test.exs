defmodule ExDNA.Detection.FuzzyTest do
  use ExUnit.Case, async: true

  alias ExDNA.AST.{Fingerprint, Normalizer}
  alias ExDNA.Detection.Fuzzy

  defp make_fragment(code, file, line) do
    ast = Code.string_to_quoted!(code)
    normalized = Normalizer.normalize(ast)
    hash = Fingerprint.compute_hash(normalized)
    mass = Fingerprint.mass(ast)

    %{hash: hash, mass: mass, ast: ast, file: file, line: line}
  end

  describe "detect/3" do
    test "finds near-miss clones above threshold" do
      frag_a =
        make_fragment(
          """
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.sort()
          """,
          "a.ex",
          1
        )

      frag_b =
        make_fragment(
          """
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.take(5)
          """,
          "b.ex",
          1
        )

      clones = Fuzzy.detect([frag_a, frag_b], 0.7, MapSet.new())

      assert length(clones) > 0
      [clone] = clones
      assert clone.type == :type_iii
      assert clone.similarity >= 0.7
    end

    test "skips exact matches already found" do
      code = """
      data
      |> Enum.map(fn x -> x * 2 end)
      |> Enum.filter(fn x -> x > 10 end)
      """

      frag_a = make_fragment(code, "a.ex", 1)
      frag_b = make_fragment(code, "b.ex", 1)

      exact_hashes = MapSet.new([frag_a.hash])
      clones = Fuzzy.detect([frag_a, frag_b], 0.7, exact_hashes)

      assert clones == []
    end

    test "ignores pairs below threshold" do
      frag_a = make_fragment("foo(1, 2, 3)", "a.ex", 1)

      frag_b =
        make_fragment(
          "bar(String.upcase(x), Enum.count(y), Map.get(z, :key))",
          "b.ex",
          1
        )

      clones = Fuzzy.detect([frag_a, frag_b], 0.9, MapSet.new())

      assert clones == []
    end

    test "ignores fragments at the same location" do
      code_a = """
      data |> Enum.map(fn x -> x * 2 end) |> Enum.sort()
      """

      code_b = """
      data |> Enum.map(fn x -> x * 3 end) |> Enum.sort()
      """

      frag_a = make_fragment(code_a, "same.ex", 5)
      frag_b = make_fragment(code_b, "same.ex", 5)

      clones = Fuzzy.detect([frag_a, frag_b], 0.7, MapSet.new())
      assert clones == []
    end
  end
end
