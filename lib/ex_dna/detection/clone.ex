defmodule ExDNA.Detection.Clone do
  @moduledoc """
  Represents a detected code clone — a group of structurally identical fragments.
  """

  @type fragment_location :: %{
          file: String.t(),
          line: pos_integer(),
          ast: Macro.t(),
          mass: pos_integer()
        }

  @type clone_type :: :type_i | :type_ii

  @type t :: %__MODULE__{
          type: clone_type(),
          hash: binary(),
          mass: pos_integer(),
          fragments: [fragment_location()],
          source_snippets: [String.t()],
          suggestion: map() | nil
        }

  defstruct [:type, :hash, :mass, :suggestion, fragments: [], source_snippets: []]

  @doc """
  Build a clone from a group of matching fragments.
  """
  @spec from_fragments([map()], clone_type()) :: t()
  def from_fragments(frags, type) do
    mass = frags |> List.first() |> Map.get(:mass, 0)

    locations =
      Enum.map(frags, fn f ->
        %{file: f.file, line: f.line, ast: f.ast, mass: f.mass}
      end)

    snippets =
      Enum.map(frags, fn f ->
        f.ast |> Macro.to_string()
      end)

    %__MODULE__{
      type: type,
      hash: List.first(frags).hash,
      mass: mass,
      fragments: locations,
      source_snippets: snippets
    }
  end
end
