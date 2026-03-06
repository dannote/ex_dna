defmodule ExDNA.Detection.FilterTest do
  use ExUnit.Case, async: true

  alias ExDNA.Detection.{Clone, Filter}

  describe "prune_nested/1" do
    test "keeps non-overlapping clones" do
      clone1 = %Clone{
        type: :type_i,
        hash: "a",
        mass: 50,
        fragments: [
          %{file: "a.ex", line: 1, ast: nil, mass: 50},
          %{file: "b.ex", line: 1, ast: nil, mass: 50}
        ]
      }

      clone2 = %Clone{
        type: :type_i,
        hash: "b",
        mass: 30,
        fragments: [
          %{file: "c.ex", line: 10, ast: nil, mass: 30},
          %{file: "d.ex", line: 10, ast: nil, mass: 30}
        ]
      }

      result = Filter.prune_nested([clone1, clone2])
      assert length(result) == 2
    end

    test "removes smaller clone when location overlaps with larger" do
      clone_large = %Clone{
        type: :type_i,
        hash: "big",
        mass: 100,
        fragments: [
          %{file: "a.ex", line: 5, ast: nil, mass: 100},
          %{file: "b.ex", line: 5, ast: nil, mass: 100}
        ]
      }

      clone_small = %Clone{
        type: :type_i,
        hash: "small",
        mass: 20,
        fragments: [
          %{file: "a.ex", line: 5, ast: nil, mass: 20},
          %{file: "b.ex", line: 5, ast: nil, mass: 20}
        ]
      }

      result = Filter.prune_nested([clone_large, clone_small])
      assert length(result) == 1
      assert hd(result).hash == "big"
    end
  end
end
