defmodule ExDNA.Refactor.BehaviourSuggestion do
  @moduledoc """
  Detects clone groups where the same function is implemented identically
  across multiple modules, suggesting a behaviour extraction.

  A behaviour is suggested when 2+ clones have fragments from different
  modules, and each fragment is a `def` with the same function name and arity.
  """

  alias ExDNA.Detection.Clone

  @type t :: %__MODULE__{
          callback_name: atom(),
          callback_arity: non_neg_integer(),
          modules: [String.t()]
        }

  defstruct [:callback_name, :callback_arity, modules: []]

  @doc """
  Analyze a list of clones and attach behaviour suggestions where appropriate.

  Returns the clone list with `behaviour_suggestion` populated on qualifying clones.
  """
  @spec analyze([Clone.t()]) :: [Clone.t()]
  def analyze(clones) do
    Enum.map(clones, fn clone ->
      case suggest(clone) do
        nil -> clone
        suggestion -> %{clone | behaviour_suggestion: suggestion}
      end
    end)
  end

  @doc """
  Generate a behaviour suggestion for a single clone, or nil.
  """
  @spec suggest(Clone.t()) :: t() | nil
  def suggest(%Clone{fragments: frags}) when length(frags) < 2, do: nil

  def suggest(%Clone{fragments: frags}) do
    with true <- all_defs?(frags),
         {name, arity} <- shared_name_arity(frags),
         modules when length(modules) >= 2 <- distinct_modules(frags) do
      %__MODULE__{
        callback_name: name,
        callback_arity: arity,
        modules: modules
      }
    else
      _ -> nil
    end
  end

  defp all_defs?(frags) do
    Enum.all?(frags, fn frag ->
      match?({kind, _, _} when kind in [:def, :defp], frag.ast)
    end)
  end

  defp shared_name_arity(frags) do
    name_arities =
      frags
      |> Enum.map(&extract_name_arity/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case name_arities do
      [{name, arity}] -> {name, arity}
      _ -> nil
    end
  end

  defp extract_name_arity(%{ast: {kind, _, [{name, _, args} | _]}})
       when kind in [:def, :defp] and is_atom(name) do
    arity = if is_list(args), do: length(args), else: 0
    {name, arity}
  end

  defp extract_name_arity(_), do: nil

  defp distinct_modules(frags) do
    frags
    |> Enum.map(fn frag -> module_from_path(frag.file) end)
    |> Enum.uniq()
  end

  defp module_from_path(path) do
    path
    |> Path.basename(".ex")
    |> Macro.camelize()
  end
end
