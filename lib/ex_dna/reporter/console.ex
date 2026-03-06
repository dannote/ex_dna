defmodule ExDNA.Reporter.Console do
  @moduledoc """
  Pretty-prints clone detection results to the terminal.
  """

  alias ExDNA.Report

  @behaviour ExDNA.Reporter

  @impl true
  def report(%Report{clones: [], stats: stats}) do
    IO.puts([
      "\n",
      IO.ANSI.green(),
      "✓ No code duplication detected",
      IO.ANSI.reset(),
      " (#{stats.files_analyzed} files analyzed)\n"
    ])
  end

  def report(%Report{clones: clones, stats: stats}) do
    IO.puts(["\n", IO.ANSI.yellow(), "ExDNA — Code Duplication Report", IO.ANSI.reset(), "\n"])

    clones
    |> Enum.with_index(1)
    |> Enum.each(&print_clone/1)

    print_summary(stats)
  end

  defp print_clone({clone, index}) do
    type_label = format_type(clone.type)
    mass_label = "#{clone.mass} nodes"

    IO.puts([
      IO.ANSI.cyan(),
      "Clone ##{index}",
      IO.ANSI.reset(),
      " [#{type_label}, #{mass_label}]\n"
    ])

    clone.fragments
    |> Enum.zip(clone.source_snippets)
    |> Enum.each(fn {frag, snippet} ->
      IO.puts([
        "  ",
        IO.ANSI.faint(),
        relative_path(frag.file),
        ":#{frag.line}",
        IO.ANSI.reset()
      ])

      snippet
      |> String.split("\n")
      |> Enum.take(10)
      |> Enum.each(fn line ->
        IO.puts(["    ", IO.ANSI.faint(), line, IO.ANSI.reset()])
      end)

      if length(String.split(snippet, "\n")) > 10 do
        IO.puts(["    ", IO.ANSI.faint(), "...", IO.ANSI.reset()])
      end

      IO.puts("")
    end)
  end

  defp print_summary(stats) do
    IO.puts([
      IO.ANSI.yellow(),
      "─── Summary ",
      String.duplicate("─", 50),
      IO.ANSI.reset(),
      "\n",
      "  Files analyzed:    #{stats.files_analyzed}\n",
      "  Clones found:      #{stats.total_clones}",
      type_breakdown(stats),
      "\n",
      "  Duplicated lines:  ~#{stats.total_duplicated_lines}\n"
    ])
  end

  defp type_breakdown(%{type_i_count: i, type_ii_count: ii}) do
    parts =
      [
        if(i > 0, do: "#{i} exact"),
        if(ii > 0, do: "#{ii} renamed")
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> ""
      _ -> " (#{Enum.join(parts, ", ")})"
    end
  end

  defp format_type(:type_i), do: "exact"
  defp format_type(:type_ii), do: "renamed"

  defp relative_path(path) do
    case File.cwd() do
      {:ok, cwd} -> Path.relative_to(path, cwd)
      _ -> path
    end
  end
end
