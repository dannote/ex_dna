defmodule ExDNA.Reporter.JSON do
  @moduledoc """
  Outputs clone detection results as a JSON string to stdout.
  """

  @behaviour ExDNA.Reporter

  @impl true
  def report(%ExDNA.Report{clones: clones, stats: stats}) do
    data = %{
      stats: stats,
      clones:
        Enum.map(clones, fn clone ->
          %{
            type: clone.type,
            mass: clone.mass,
            fragments:
              Enum.map(clone.fragments, fn f ->
                %{file: f.file, line: f.line, mass: f.mass}
              end),
            snippets: clone.source_snippets
          }
        end)
    }

    data
    |> inspect(pretty: true, limit: :infinity, printable_limit: :infinity)
    |> IO.puts()
  end
end
