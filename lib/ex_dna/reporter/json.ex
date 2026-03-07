defmodule ExDNA.Reporter.JSON do
  @moduledoc """
  Outputs clone detection results as JSON to stdout.

  Designed for CI pipelines and LLM consumption.
  """

  @behaviour ExDNA.Reporter

  @impl true
  def report(%ExDNA.Report{clones: clones, stats: stats}) do
    data = %{
      stats: stats,
      clones: Enum.map(clones, &serialize_clone/1)
    }

    data
    |> Jason.encode!(pretty: true)
    |> IO.puts()
  end

  defp serialize_clone(clone) do
    base = %{
      type: clone.type,
      mass: clone.mass,
      fragments:
        Enum.map(clone.fragments, fn f ->
          %{file: f.file, line: f.line, mass: f.mass}
        end),
      snippets: clone.source_snippets
    }

    base
    |> maybe_put(:similarity, clone.similarity)
    |> maybe_put(:suggestion, serialize_suggestion(clone.suggestion))
  end

  defp serialize_suggestion(nil), do: nil

  defp serialize_suggestion(%{kind: kind} = s) do
    %{
      kind: kind,
      name: s.name,
      params: s.params,
      body: s.body,
      call_sites:
        Enum.map(s.call_sites, fn site ->
          %{file: site.file, line: site.line, call: site.call}
        end)
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
