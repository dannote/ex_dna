defmodule ExDNA.Refactor.Suggestion do
  @moduledoc """
  Generates refactoring suggestions from detected clones.

  Uses anti-unification to find the common structure between clone fragments,
  then proposes an extracted function whose parameters are the "holes" —
  the positions where the fragments diverge.
  """

  alias ExDNA.AST.AntiUnifier
  alias ExDNA.AST.Normalizer
  alias ExDNA.Detection.Clone

  @type t :: %__MODULE__{
          kind: :extract_function,
          name: String.t(),
          params: [atom()],
          body: String.t(),
          call_sites: [%{file: String.t(), line: pos_integer(), call: String.t()}]
        }

  defstruct [:kind, :name, :body, params: [], call_sites: []]

  @doc """
  Generate a refactoring suggestion for a clone group.

  Takes the first two fragments, anti-unifies them, and builds a function
  extraction suggestion. When there are zero holes the suggestion is a
  simple extract; when there are holes they become function parameters.
  """
  @spec suggest(Clone.t()) :: t() | nil
  def suggest(%Clone{fragments: frags}) when length(frags) < 2, do: nil

  def suggest(%Clone{fragments: frags} = clone) do
    [frag_a, frag_b | _] = frags

    ast_a = Normalizer.strip_metadata(frag_a.ast)
    ast_b = Normalizer.strip_metadata(frag_b.ast)

    {pattern, holes} = AntiUnifier.anti_unify(ast_a, ast_b)

    func_name = generate_name(clone)
    params = Enum.map(holes, & &1.var)

    body =
      if params == [] do
        pattern |> humanize_ast() |> Macro.to_string()
      else
        pattern |> rename_holes(holes) |> humanize_ast() |> Macro.to_string()
      end

    param_names = Enum.map(holes, fn hole -> hole.var |> rename_hole() end)

    call_sites =
      frags
      |> Enum.with_index()
      |> Enum.map(fn {frag, idx} ->
        args =
          holes
          |> Enum.map(fn hole ->
            value = Enum.at(hole.values, min(idx, 1))
            value |> humanize_ast() |> Macro.to_string()
          end)
          |> Enum.join(", ")

        call =
          if args == "" do
            "#{func_name}()"
          else
            "#{func_name}(#{args})"
          end

        %{file: frag.file, line: frag.line, call: call}
      end)

    %__MODULE__{
      kind: :extract_function,
      name: func_name,
      params: param_names,
      body: body,
      call_sites: call_sites
    }
  end

  defp generate_name(%Clone{fragments: [frag | _]}) do
    case frag.ast do
      {:def, _, [{name, _, _} | _]} -> "shared_#{name}"
      {:defp, _, [{name, _, _} | _]} -> "shared_#{name}"
      _ -> "extracted_function"
    end
  end

  defp rename_holes(ast, holes) do
    Enum.reduce(holes, ast, fn hole, acc ->
      renamed = rename_hole(hole.var)

      Macro.prewalk(acc, fn
        {var, meta, nil} when var == hole.var -> {renamed, meta, nil}
        other -> other
      end)
    end)
  end

  defp rename_hole(var) do
    var
    |> Atom.to_string()
    |> String.replace("hole", "arg")
    |> String.to_atom()
  end

  defp humanize_ast(ast) do
    Macro.prewalk(ast, fn
      {name, meta, ctx} when is_atom(name) and is_atom(ctx) ->
        clean_name =
          name
          |> Atom.to_string()
          |> String.replace(~r/^\$\d+$/, fn match ->
            index = String.trim_leading(match, "$")
            "var_#{index}"
          end)
          |> String.to_atom()

        {clean_name, meta, ctx}

      other ->
        other
    end)
  end
end
