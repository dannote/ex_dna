defmodule ExDNA.CacheTest do
  use ExUnit.Case, async: true

  alias ExDNA.Cache

  @moduletag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    cache_path = Path.join(tmp_dir, "test_cache")
    {:ok, cache_path: cache_path}
  end

  describe "write/2 and read/1" do
    test "round-trips entries through disk", %{cache_path: path} do
      entries = %{
        "lib/foo.ex" => %{mtime: 1_700_000_000, fragments: [%{hash: "abc", mass: 10}]},
        "lib/bar.ex" => %{mtime: 1_700_000_001, fragments: []}
      }

      assert :ok = Cache.write(entries, path)
      assert Cache.read(path) == entries
    end

    test "returns empty map when file does not exist", %{cache_path: path} do
      assert Cache.read(path) == %{}
    end

    test "returns empty map when file is corrupt", %{cache_path: path} do
      File.write!(path, "not a valid term")
      assert Cache.read(path) == %{}
    end

    test "returns empty map when cache version mismatches", %{cache_path: path} do
      binary = :erlang.term_to_binary({999, %{"a.ex" => %{mtime: 0, fragments: []}}})
      File.write!(path, binary)
      assert Cache.read(path) == %{}
    end
  end

  describe "stale_files/2" do
    test "marks missing files as stale" do
      cached = %{"lib/known.ex" => %{mtime: 1_700_000_000, fragments: []}}
      assert Cache.stale_files(["lib/new.ex"], cached) == ["lib/new.ex"]
    end

    test "marks files with changed mtime as stale", %{tmp_dir: dir} do
      file = Path.join(dir, "changed.ex")
      File.write!(file, "defmodule A, do: nil")
      mtime = Cache.file_mtime(file)

      cached = %{file => %{mtime: mtime - 1, fragments: []}}
      assert Cache.stale_files([file], cached) == [file]
    end

    test "keeps files with matching mtime", %{tmp_dir: dir} do
      file = Path.join(dir, "fresh.ex")
      File.write!(file, "defmodule B, do: nil")
      mtime = Cache.file_mtime(file)

      cached = %{file => %{mtime: mtime, fragments: []}}
      assert Cache.stale_files([file], cached) == []
    end
  end

  describe "merge/3" do
    test "overwrites cached entries with fresh ones" do
      cached = %{"a.ex" => %{mtime: 1, fragments: [%{hash: "old"}]}}
      fresh = %{"a.ex" => %{mtime: 2, fragments: [%{hash: "new"}]}}

      merged = Cache.merge(cached, fresh, ["a.ex"])
      assert merged["a.ex"].fragments == [%{hash: "new"}]
    end

    test "drops entries for files no longer in the file list" do
      cached = %{
        "a.ex" => %{mtime: 1, fragments: []},
        "deleted.ex" => %{mtime: 1, fragments: []}
      }

      merged = Cache.merge(cached, %{}, ["a.ex"])
      assert Map.keys(merged) == ["a.ex"]
    end

    test "preserves unchanged cached entries" do
      cached = %{"a.ex" => %{mtime: 1, fragments: [%{hash: "kept"}]}}
      merged = Cache.merge(cached, %{}, ["a.ex"])
      assert merged == cached
    end
  end

  describe "build_entry/2" do
    test "captures current mtime", %{tmp_dir: dir} do
      file = Path.join(dir, "entry.ex")
      File.write!(file, "defmodule E, do: nil")

      entry = Cache.build_entry(file, [%{hash: "h1"}])
      assert entry.mtime == Cache.file_mtime(file)
      assert entry.fragments == [%{hash: "h1"}]
    end
  end

  describe "file_mtime/1" do
    test "returns posix timestamp for existing file", %{tmp_dir: dir} do
      file = Path.join(dir, "exists.ex")
      File.write!(file, "ok")
      assert is_integer(Cache.file_mtime(file))
      assert Cache.file_mtime(file) > 0
    end

    test "returns 0 for missing file" do
      assert Cache.file_mtime("/nonexistent/path.ex") == 0
    end
  end
end
