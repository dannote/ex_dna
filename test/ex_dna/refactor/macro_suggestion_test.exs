defmodule ExDNA.Refactor.MacroSuggestionTest do
  use ExUnit.Case, async: true

  alias ExDNA.Detection.Clone
  alias ExDNA.Refactor.MacroSuggestion
  alias ExDNA.Refactor.Suggestion

  describe "macro_candidate?/1" do
    test "returns false for fewer than 3 fragments" do
      clone = clone_with_struct_fragments(2)
      refute MacroSuggestion.macro_candidate?(clone)
    end

    test "returns true for 3+ module-level struct literals" do
      clone = clone_with_struct_fragments(3)
      assert MacroSuggestion.macro_candidate?(clone)
    end

    test "returns true for DSL calls like field" do
      ast =
        quote do
          field(:name, :string)
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 5,
        fragments: for(f <- ~w(a.ex b.ex c.ex), do: %{file: f, line: 1, ast: ast, mass: 5})
      }

      assert MacroSuggestion.macro_candidate?(clone)
    end

    test "returns true for pipe_through DSL calls" do
      ast =
        quote do
          pipe_through([:browser])
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 5,
        fragments: for(f <- ~w(a.ex b.ex c.ex), do: %{file: f, line: 1, ast: ast, mass: 5})
      }

      assert MacroSuggestion.macro_candidate?(clone)
    end

    test "returns false when fragments are inside def" do
      ast =
        quote do
          def build do
            %Step{id: :contact}
          end
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: for(f <- ~w(a.ex b.ex c.ex), do: %{file: f, line: 1, ast: ast, mass: 10})
      }

      refute MacroSuggestion.macro_candidate?(clone)
    end

    test "returns false for plain function calls without DSL or struct content" do
      ast =
        quote do
          Enum.map(list, &to_string/1)
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 5,
        fragments: for(f <- ~w(a.ex b.ex c.ex), do: %{file: f, line: 1, ast: ast, mass: 5})
      }

      refute MacroSuggestion.macro_candidate?(clone)
    end
  end

  describe "integration with Suggestion.suggest/1" do
    test "produces :extract_macro kind for qualifying clones" do
      clone = clone_with_struct_fragments(4)
      suggestion = Suggestion.suggest(clone)

      assert %Suggestion{kind: :extract_macro} = suggestion
      assert suggestion.occurrence_count == 4
      assert suggestion.name =~ "step"
    end

    test "produces :extract_function kind for non-qualifying clones" do
      ast =
        quote do
          Enum.map(list, fn x -> x * 2 end)
        end

      clone = %Clone{
        type: :type_i,
        hash: "x",
        mass: 10,
        fragments: [
          %{file: "a.ex", line: 1, ast: ast, mass: 10},
          %{file: "b.ex", line: 2, ast: ast, mass: 10}
        ]
      }

      suggestion = Suggestion.suggest(clone)
      assert %Suggestion{kind: :extract_function} = suggestion
    end
  end

  defp clone_with_struct_fragments(count) do
    ast =
      quote do
        %Step{id: :contact, type: :form}
      end

    files = Enum.map(1..count, &"module_#{&1}.ex")

    %Clone{
      type: :type_i,
      hash: "x",
      mass: 8,
      fragments: Enum.map(files, fn f -> %{file: f, line: 1, ast: ast, mass: 8} end)
    }
  end
end
