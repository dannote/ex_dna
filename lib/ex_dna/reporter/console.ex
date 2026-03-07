defmodule ExDNA.Reporter.Console do
  @moduledoc """
  Pretty-prints clone detection results to the terminal.

  Inspired by Credo's output style — scannable by humans and parseable by LLMs.
  """

  alias ExDNA.Detection.Grouper
  alias ExDNA.Report

  @behaviour ExDNA.Reporter

  @max_snippet_lines 8

  @impl true
  def report(%Report{clones: [], stats: stats}) do
    IO.puts([
      "\n",
      IO.ANSI.green(),
      "  ✓ No code duplication detected",
      IO.ANSI.reset(),
      IO.ANSI.faint(),
      " (#{stats.files_analyzed} files)\n",
      IO.ANSI.reset()
    ])
  end

  def report(%Report{clones: clones, stats: stats}) do
    IO.puts(["\n", IO.ANSI.yellow(), "  ExDNA", IO.ANSI.reset(), " — code duplication report\n"])

    clones
    |> Grouper.group()
    |> Map.fetch!(:ordered)
    |> Enum.each(fn
      {:group, group} ->
        print_group_header(group)
        Enum.each(group.clones, &print_clone({&1.clone, &1.index}))

      {:clone, entry} ->
        print_clone({entry.clone, entry.index})
    end)

    print_summary(stats)
  end

  defp print_group_header(group) do
    dirs = Enum.join(group.directories, " ↔ ")
    count = length(group.clones)
    mass = group.total_mass

    IO.puts([
      "┃\n",
      "┃ ",
      IO.ANSI.yellow(),
      "── #{dirs}",
      IO.ANSI.reset(),
      IO.ANSI.faint(),
      " (#{count} clones, #{mass} nodes)",
      IO.ANSI.reset()
    ])
  end

  defp print_clone({clone, index}) do
    badge = type_badge(clone.type)
    sim = format_similarity(clone.similarity)

    IO.puts([
      "┃\n",
      "┃ ",
      badge,
      " ##{index}",
      IO.ANSI.faint(),
      "  #{clone.mass} nodes#{sim}",
      IO.ANSI.reset()
    ])

    Enum.each(clone.fragments, fn frag ->
      location =
        if frag.line > 0,
          do: "#{relative_path(frag.file)}:#{frag.line}",
          else: relative_path(frag.file)

      IO.puts(["┃   ", IO.ANSI.cyan(), location, IO.ANSI.reset()])
    end)

    snippet = List.first(clone.source_snippets) || ""
    lines = String.split(snippet, "\n")
    show = Enum.take(lines, @max_snippet_lines)

    IO.puts("┃")

    Enum.each(show, fn line ->
      IO.puts(["┃     ", IO.ANSI.faint(), line, IO.ANSI.reset()])
    end)

    if length(lines) > @max_snippet_lines do
      IO.puts([
        "┃     ",
        IO.ANSI.faint(),
        "… (+#{length(lines) - @max_snippet_lines} lines)",
        IO.ANSI.reset()
      ])
    end

    print_suggestion(clone.suggestion)
    print_behaviour_suggestion(clone.behaviour_suggestion)
    IO.puts("┃")
  end

  defp print_suggestion(nil), do: :ok

  defp print_suggestion(%{kind: :extract_macro} = suggestion) do
    params = if suggestion.params == [], do: "", else: Enum.join(suggestion.params, ", ")

    IO.puts([
      "┃\n",
      "┃   ",
      IO.ANSI.green(),
      "→ Consider: ",
      IO.ANSI.reset(),
      IO.ANSI.green(),
      "defmacro #{suggestion.name}(#{params})",
      IO.ANSI.reset(),
      IO.ANSI.faint(),
      " — #{suggestion.occurrence_count} occurrences across modules",
      IO.ANSI.reset()
    ])
  end

  defp print_suggestion(%{kind: :extract_function} = suggestion) do
    params = Enum.join(suggestion.params, ", ")

    IO.puts([
      "┃\n",
      "┃   ",
      IO.ANSI.green(),
      "→ Extract: ",
      IO.ANSI.reset(),
      IO.ANSI.green(),
      "defp #{suggestion.name}(#{params})",
      IO.ANSI.reset()
    ])

    Enum.each(suggestion.call_sites, fn site ->
      IO.puts([
        "┃     ",
        IO.ANSI.faint(),
        relative_path(site.file),
        ":#{site.line} → #{site.call}",
        IO.ANSI.reset()
      ])
    end)
  end

  defp print_behaviour_suggestion(nil), do: :ok

  defp print_behaviour_suggestion(%{callback_name: name, callback_arity: arity, modules: modules}) do
    args = List.duplicate("term()", arity) |> Enum.join(", ")
    module_list = Enum.join(modules, ", ")

    IO.puts([
      "┃\n",
      "┃   ",
      IO.ANSI.blue(),
      "→ Consider: ",
      IO.ANSI.reset(),
      IO.ANSI.blue(),
      "@callback #{name}(#{args})",
      IO.ANSI.reset(),
      IO.ANSI.faint(),
      " — implemented identically in #{module_list}",
      IO.ANSI.reset()
    ])
  end

  defp print_summary(stats) do
    type_iii = Map.get(stats, :type_iii_count, 0)

    parts =
      [
        if(stats.type_i_count > 0, do: "#{stats.type_i_count} exact"),
        if(stats.type_ii_count > 0, do: "#{stats.type_ii_count} renamed"),
        if(type_iii > 0, do: "#{type_iii} near-miss")
      ]
      |> Enum.reject(&is_nil/1)

    breakdown = if parts != [], do: " (#{Enum.join(parts, ", ")})", else: ""

    IO.puts([
      "\n",
      IO.ANSI.yellow(),
      String.duplicate("─", 64),
      IO.ANSI.reset(),
      "\n",
      "  Files analyzed:     #{stats.files_analyzed}\n",
      "  Clones found:       ",
      clone_color(stats.total_clones),
      "#{stats.total_clones}",
      IO.ANSI.reset(),
      breakdown,
      "\n",
      "  Duplicated lines:   ~#{stats.total_duplicated_lines}\n"
    ])
  end

  defp type_badge(:type_i), do: [IO.ANSI.red(), "[I]", IO.ANSI.reset(), " "]
  defp type_badge(:type_ii), do: [IO.ANSI.yellow(), "[II]", IO.ANSI.reset()]
  defp type_badge(:type_iii), do: [IO.ANSI.magenta(), "[≈]", IO.ANSI.reset(), " "]

  defp format_similarity(nil), do: ""
  defp format_similarity(sim), do: "  #{Float.round(sim * 100, 1)}%"

  defp clone_color(0), do: IO.ANSI.green()
  defp clone_color(_), do: IO.ANSI.red()

  defp relative_path(path) do
    case File.cwd() do
      {:ok, cwd} -> Path.relative_to(path, cwd)
      _ -> path
    end
  end
end
