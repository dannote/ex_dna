defmodule ExDNA.Cache do
  @moduledoc """
  Persistent cache for fingerprinted AST fragments.

  Stores `%{file_path => %{mtime: integer(), fragments: [fragment]}}` to disk
  using `:erlang.term_to_binary/1`. On subsequent runs, only files whose mtime
  has changed need to be re-parsed and fingerprinted.
  """

  @cache_version 1

  @type entry :: %{mtime: integer(), fragments: [map()]}
  @type entries :: %{String.t() => entry()}

  @doc """
  Default cache file path (relative to the project root).
  """
  @spec default_path :: String.t()
  def default_path, do: ".ex_dna_cache"

  @doc """
  Read cached entries from disk. Returns an empty map if the file is missing,
  corrupt, or was written by an incompatible cache version.
  """
  @spec read(String.t()) :: entries()
  def read(path \\ default_path()) do
    with {:ok, binary} <- File.read(path),
         {:ok, {@cache_version, entries}} <- safe_binary_to_term(binary) do
      entries
    else
      _ -> %{}
    end
  end

  @doc """
  Write entries to the cache file.
  """
  @spec write(entries(), String.t()) :: :ok | {:error, term()}
  def write(entries, path \\ default_path()) do
    binary = :erlang.term_to_binary({@cache_version, entries})
    File.write(path, binary)
  end

  @doc """
  Return the subset of `files` whose mtime differs from the cached value
  (or that aren't in the cache at all).
  """
  @spec stale_files([String.t()], entries()) :: [String.t()]
  def stale_files(files, cached_entries) do
    Enum.filter(files, fn file ->
      case Map.fetch(cached_entries, file) do
        {:ok, %{mtime: cached_mtime}} -> file_mtime(file) != cached_mtime
        :error -> true
      end
    end)
  end

  @doc """
  Merge fresh fragments into the cache, dropping entries for files
  that no longer exist on disk.
  """
  @spec merge(entries(), %{String.t() => [map()]}, [String.t()]) :: entries()
  def merge(cached, fresh_by_file, all_files) do
    valid_set = MapSet.new(all_files)

    merged =
      Map.merge(cached, fresh_by_file, fn _file, _old, new -> new end)

    Map.filter(merged, fn {file, _} -> MapSet.member?(valid_set, file) end)
  end

  @doc """
  Build a cache entry for a single file with its current mtime.
  """
  @spec build_entry(String.t(), [map()]) :: entry()
  def build_entry(file, fragments) do
    %{mtime: file_mtime(file), fragments: fragments}
  end

  @doc """
  Get the modification time of a file as a POSIX timestamp.
  """
  @spec file_mtime(String.t()) :: integer()
  def file_mtime(file) do
    case File.stat(file, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime
      {:error, _} -> 0
    end
  end

  defp safe_binary_to_term(binary) do
    {:ok, :erlang.binary_to_term(binary)}
  rescue
    ArgumentError -> :error
  end
end
