defmodule ExDNA.Report do
  @moduledoc """
  Analysis results: detected clones and summary statistics.
  """

  alias ExDNA.Config
  alias ExDNA.Detection.Clone

  @type stats :: %{
          files_analyzed: non_neg_integer(),
          total_clones: non_neg_integer(),
          total_duplicated_lines: non_neg_integer(),
          type_i_count: non_neg_integer(),
          type_ii_count: non_neg_integer(),
          type_iii_count: non_neg_integer(),
          detection_time_ms: non_neg_integer()
        }

  @type t :: %__MODULE__{
          clones: [Clone.t()],
          stats: stats(),
          config: Config.t()
        }

  defstruct [:config, clones: [], stats: %{}]

  @spec new([Clone.t()], Config.t()) :: t()
  def new(clones, config) do
    stats = compute_stats(clones, config)

    report = %__MODULE__{
      clones: clones,
      stats: stats,
      config: config
    }

    Enum.each(config.reporters, fn reporter ->
      reporter.report(report)
    end)

    report
  end

  defp compute_stats(clones, config) do
    files =
      config.paths
      |> Enum.flat_map(fn p ->
        if File.dir?(p), do: Path.wildcard(Path.join(p, "**/*.{ex,exs}")), else: [p]
      end)
      |> Enum.uniq()

    duplicated_lines =
      clones
      |> Enum.flat_map(& &1.source_snippets)
      |> Enum.map(fn snippet -> snippet |> String.split("\n") |> length() end)
      |> Enum.sum()

    %{
      files_analyzed: length(files),
      total_clones: length(clones),
      total_duplicated_lines: duplicated_lines,
      type_i_count: Enum.count(clones, &(&1.type == :type_i)),
      type_ii_count: Enum.count(clones, &(&1.type == :type_ii)),
      type_iii_count: Enum.count(clones, &(&1.type == :type_iii)),
      detection_time_ms: 0
    }
  end
end
