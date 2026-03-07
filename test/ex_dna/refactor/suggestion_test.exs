defmodule ExDNA.Refactor.SuggestionTest do
  use ExUnit.Case, async: true

  alias ExDNA.Detection.Clone
  alias ExDNA.Refactor.Suggestion

  describe "suggest/1" do
    test "returns nil for clones with fewer than 2 fragments" do
      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [%{file: "a.ex", line: 1, ast: quote(do: 1 + 2), mass: 10}]
      }

      assert Suggestion.suggest(clone) == nil
    end

    test "generates suggestion for exact clone" do
      ast =
        quote do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 0 end)
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 20,
        fragments: [
          %{file: "a.ex", line: 5, ast: ast, mass: 20},
          %{file: "b.ex", line: 10, ast: ast, mass: 20}
        ]
      }

      suggestion = Suggestion.suggest(clone)

      assert %Suggestion{kind: :extract_function} = suggestion
      assert suggestion.params == []
      assert suggestion.body =~ "Enum.map"
      assert length(suggestion.call_sites) == 2
    end

    test "generates parameterized suggestion for clones with differences" do
      ast_a =
        quote do
          Enum.map(list, fn x -> x * 2 end)
        end

      ast_b =
        quote do
          Enum.map(items, fn y -> y * 3 end)
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 15,
        fragments: [
          %{file: "a.ex", line: 5, ast: ast_a, mass: 15},
          %{file: "b.ex", line: 10, ast: ast_b, mass: 15}
        ]
      }

      suggestion = Suggestion.suggest(clone)

      assert %Suggestion{kind: :extract_function} = suggestion
      assert length(suggestion.params) > 0
      assert suggestion.body =~ "Enum.map"
    end

    test "call sites show original values for holes" do
      ast_a = quote do: String.duplicate("hello", 3)
      ast_b = quote do: String.duplicate("world", 5)

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast_a, mass: 10},
          %{file: "b.ex", line: 1, ast: ast_b, mass: 10}
        ]
      }

      suggestion = Suggestion.suggest(clone)

      assert suggestion
      [site_a, site_b] = suggestion.call_sites
      assert site_a.call =~ "hello"
      assert site_b.call =~ "world"
    end

    test "names extracted function based on original def" do
      ast =
        quote do
          def process(data) do
            data |> Enum.map(fn x -> x * 2 end) |> Enum.sort()
          end
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 20,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 20},
          %{file: "b.ex", line: 1, ast: ast, mass: 20}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert suggestion.name == "shared_process"
    end
  end
end
