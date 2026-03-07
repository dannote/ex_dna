defmodule ExDNA.Detection.Grouper do
  @moduledoc """
  Groups clones by the directories they span so reporters can produce
  higher-level summaries.
  """

  alias ExDNA.Detection.Clone

  @type grouped_clone :: %{clone: Clone.t(), index: pos_integer()}

  @type group :: %{
          key: tuple(),
          directories: [String.t()],
          clones: [grouped_clone()],
          total_mass: non_neg_integer()
        }

  @type ordered_item :: {:group, group()} | {:clone, grouped_clone()}

  @type result :: %{
          groups: [group()],
          ungrouped: [grouped_clone()],
          ordered: [ordered_item()]
        }

  @doc """
  Group clones by the set of parent directories involved in each clone.

  Only directory sets shared by 2 or more clones form a group. Clones
  with unique directory sets stay ungrouped.
  """
  @spec group([Clone.t()]) :: result()
  def group(clones) do
    entries =
      clones
      |> Enum.with_index(1)
      |> Enum.map(fn {clone, index} ->
        dirs = directories_for(clone)
        %{key: List.to_tuple(dirs), directories: dirs, clone: clone, index: index}
      end)

    group_map = build_group_map(entries)
    group_keys = Map.keys(group_map) |> MapSet.new()

    {ordered_rev, _printed} =
      Enum.reduce(entries, {[], MapSet.new()}, fn entry, {acc, printed} ->
        cond do
          MapSet.member?(group_keys, entry.key) and not MapSet.member?(printed, entry.key) ->
            group = Map.fetch!(group_map, entry.key)
            {[{:group, group} | acc], MapSet.put(printed, entry.key)}

          MapSet.member?(group_keys, entry.key) ->
            {acc, printed}

          true ->
            {[{:clone, %{clone: entry.clone, index: entry.index}} | acc], printed}
        end
      end)

    ordered = Enum.reverse(ordered_rev)

    groups =
      ordered
      |> Enum.filter(&match?({:group, _}, &1))
      |> Enum.map(fn {:group, group} -> group end)

    ungrouped =
      entries
      |> Enum.reject(fn entry -> MapSet.member?(group_keys, entry.key) end)
      |> Enum.map(fn entry -> %{clone: entry.clone, index: entry.index} end)

    %{groups: groups, ungrouped: ungrouped, ordered: ordered}
  end

  defp build_group_map(entries) do
    entries
    |> Enum.group_by(& &1.key)
    |> Enum.reduce(%{}, fn {key, members}, acc ->
      if length(members) >= 2 do
        group = %{
          key: key,
          directories: hd(members).directories,
          clones: Enum.map(members, &%{clone: &1.clone, index: &1.index}),
          total_mass: Enum.reduce(members, 0, fn entry, sum -> sum + entry.clone.mass end)
        }

        Map.put(acc, key, group)
      else
        acc
      end
    end)
  end

  defp directories_for(%Clone{fragments: fragments}) do
    fragments
    |> Enum.map(fn frag ->
      frag.file
      |> Path.expand()
      |> Path.dirname()
      |> Path.relative_to_cwd()
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
