defmodule ExDNA.AST.FingerprintTest do
  use ExUnit.Case, async: true

  alias ExDNA.AST.Fingerprint

  describe "fragments/4" do
    test "excludes module attributes by default with excluded_macros: [:@]" do
      ast =
        quote do
          defmodule Foo do
            @moduledoc "Some docs"
            @type t :: %{name: String.t()}

            def process(data) do
              data
              |> Enum.map(fn x -> x * 2 end)
              |> Enum.filter(fn x -> x > 10 end)
            end
          end
        end

      frags = Fingerprint.fragments(ast, "test.ex", 3, excluded_macros: [:@])

      attr_frags =
        Enum.filter(frags, fn f -> match?({:@, _, _}, f.ast) end)

      assert attr_frags == []

      has_process =
        Enum.any?(frags, fn f ->
          Macro.to_string(f.ast) |> String.contains?("process")
        end)

      assert has_process
    end

    test "excludes specified macros" do
      ast =
        quote do
          defmodule MySchema do
            use Ecto.Schema

            schema "users" do
              field(:name, :string)
              field(:email, :string)
            end

            def changeset(user, attrs) do
              user
              |> Ecto.Changeset.cast(attrs, [:name, :email])
              |> Ecto.Changeset.validate_required([:name])
            end
          end
        end

      frags_without = Fingerprint.fragments(ast, "test.ex", 3, excluded_macros: [])

      frags_with =
        Fingerprint.fragments(ast, "test.ex", 3, excluded_macros: [:schema, :field])

      schema_frags_without =
        Enum.filter(frags_without, fn f ->
          Macro.to_string(f.ast) |> String.contains?("schema")
        end)

      schema_frags_with =
        Enum.filter(frags_with, fn f ->
          match?({:schema, _, _}, f.ast) or match?({:field, _, _}, f.ast)
        end)

      assert length(schema_frags_without) > length(schema_frags_with)
    end

    test "excluded macros don't prevent child fragments from non-excluded code" do
      ast =
        quote do
          defmodule Foo do
            @moduledoc "docs"

            def process(data) do
              data
              |> Enum.map(fn x -> x * 2 end)
            end
          end
        end

      frags = Fingerprint.fragments(ast, "test.ex", 3, excluded_macros: [:@])

      has_process =
        Enum.any?(frags, fn f ->
          Macro.to_string(f.ast) |> String.contains?("process")
        end)

      assert has_process
    end
  end

  describe "mass/1" do
    test "counts leaf as 1" do
      assert Fingerprint.mass(42) == 1
      assert Fingerprint.mass(:ok) == 1
    end

    test "counts call nodes" do
      # foo(1, 2) → {:foo, [], [1, 2]} = 1 call + 2 args = 3
      ast = quote do: foo(1, 2)
      assert Fingerprint.mass(ast) == 3
    end

    test "counts nested structures" do
      # foo(bar(1), 2) → 1 (foo) + 1 (bar) + 1 (1) + 1 (2) = 4
      ast = quote do: foo(bar(1), 2)
      assert Fingerprint.mass(ast) == 4
    end
  end
end
