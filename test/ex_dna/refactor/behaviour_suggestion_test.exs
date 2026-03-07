defmodule ExDNA.Refactor.BehaviourSuggestionTest do
  use ExUnit.Case, async: true

  alias ExDNA.Detection.Clone
  alias ExDNA.Refactor.BehaviourSuggestion

  defp def_ast(name, arity) do
    args =
      case arity do
        0 -> nil
        n -> Enum.map(1..n, fn i -> {:"arg#{i}", [line: 1], nil} end)
      end

    {:def, [line: 1], [{name, [line: 1], args}, [do: {:ok, [], nil}]]}
  end

  defp defp_ast(name, arity) do
    args =
      case arity do
        0 -> nil
        n -> Enum.map(1..n, fn i -> {:"arg#{i}", [line: 1], nil} end)
      end

    {:defp, [line: 1], [{name, [line: 1], args}, [do: {:ok, [], nil}]]}
  end

  describe "suggest/1" do
    test "suggests behaviour for identical defs in different modules" do
      ast = def_ast(:validate, 1)

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 15,
        fragments: [
          %{file: "lib/bank_complaint.ex", line: 10, ast: ast, mass: 15},
          %{file: "lib/mfo_complaint.ex", line: 10, ast: ast, mass: 15}
        ]
      }

      suggestion = BehaviourSuggestion.suggest(clone)

      assert %BehaviourSuggestion{} = suggestion
      assert suggestion.callback_name == :validate
      assert suggestion.callback_arity == 1
      assert "BankComplaint" in suggestion.modules
      assert "MfoComplaint" in suggestion.modules
    end

    test "suggests behaviour for zero-arity defs" do
      ast = def_ast(:defaults, 0)

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "lib/http_client.ex", line: 5, ast: ast, mass: 10},
          %{file: "lib/grpc_client.ex", line: 5, ast: ast, mass: 10}
        ]
      }

      suggestion = BehaviourSuggestion.suggest(clone)
      assert suggestion.callback_name == :defaults
      assert suggestion.callback_arity == 0
    end

    test "returns nil when fragments are not defs" do
      ast =
        quote do
          Enum.map(list, fn x -> x * 2 end)
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "lib/a.ex", line: 1, ast: ast, mass: 10},
          %{file: "lib/b.ex", line: 1, ast: ast, mass: 10}
        ]
      }

      assert BehaviourSuggestion.suggest(clone) == nil
    end

    test "returns nil when defs have different names" do
      ast_a = def_ast(:validate, 1)
      ast_b = def_ast(:verify, 1)

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "lib/a.ex", line: 1, ast: ast_a, mass: 10},
          %{file: "lib/b.ex", line: 1, ast: ast_b, mass: 10}
        ]
      }

      assert BehaviourSuggestion.suggest(clone) == nil
    end

    test "returns nil when all fragments come from the same file" do
      ast = def_ast(:validate, 1)

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "lib/complaint.ex", line: 10, ast: ast, mass: 10},
          %{file: "lib/complaint.ex", line: 30, ast: ast, mass: 10}
        ]
      }

      assert BehaviourSuggestion.suggest(clone) == nil
    end

    test "returns nil for fewer than 2 fragments" do
      ast = def_ast(:validate, 1)

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [%{file: "lib/a.ex", line: 1, ast: ast, mass: 10}]
      }

      assert BehaviourSuggestion.suggest(clone) == nil
    end

    test "works with defp as well as def" do
      ast = defp_ast(:transform, 1)

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 8,
        fragments: [
          %{file: "lib/parser_a.ex", line: 5, ast: ast, mass: 8},
          %{file: "lib/parser_b.ex", line: 5, ast: ast, mass: 8}
        ]
      }

      suggestion = BehaviourSuggestion.suggest(clone)
      assert suggestion.callback_name == :transform
      assert suggestion.callback_arity == 1
    end
  end

  describe "analyze/1" do
    test "attaches behaviour_suggestion to qualifying clones" do
      ast = def_ast(:validate, 1)

      clones = [
        %Clone{
          type: :type_i,
          hash: "x",
          mass: 10,
          fragments: [
            %{file: "lib/bank_complaint.ex", line: 10, ast: ast, mass: 10},
            %{file: "lib/mfo_complaint.ex", line: 10, ast: ast, mass: 10}
          ]
        }
      ]

      [clone] = BehaviourSuggestion.analyze(clones)
      assert %BehaviourSuggestion{} = clone.behaviour_suggestion
      assert clone.behaviour_suggestion.callback_name == :validate
    end

    test "leaves behaviour_suggestion nil for non-qualifying clones" do
      ast =
        quote do
          Enum.map(list, fn x -> x * 2 end)
        end

      clones = [
        %Clone{
          type: :type_i,
          hash: "x",
          mass: 10,
          fragments: [
            %{file: "lib/a.ex", line: 1, ast: ast, mass: 10},
            %{file: "lib/b.ex", line: 1, ast: ast, mass: 10}
          ]
        }
      ]

      [clone] = BehaviourSuggestion.analyze(clones)
      assert clone.behaviour_suggestion == nil
    end
  end
end
