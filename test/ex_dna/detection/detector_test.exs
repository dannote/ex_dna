defmodule ExDNA.Detection.DetectorTest do
  use ExUnit.Case, async: true

  alias ExDNA.Config
  alias ExDNA.Detection.Detector

  setup do
    dir = Path.join(System.tmp_dir!(), "ex_dna_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp write_fixture(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end

  describe "run/1" do
    test "detects exact duplicates across files", %{dir: dir} do
      write_fixture(dir, "a.ex", """
      defmodule A do
        def process(data) do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.sort()
          |> Enum.take(5)
        end
      end
      """)

      write_fixture(dir, "b.ex", """
      defmodule B do
        def process(data) do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.sort()
          |> Enum.take(5)
        end
      end
      """)

      config = Config.new(paths: [dir], min_mass: 5, reporters: [])
      clones = Detector.run(config)

      assert length(clones) > 0

      clone = List.first(clones)
      files = Enum.map(clone.fragments, & &1.file) |> Enum.sort()
      assert length(files) == 2
    end

    test "detects duplicates with renamed variables", %{dir: dir} do
      write_fixture(dir, "c.ex", """
      defmodule C do
        def transform(items) do
          items
          |> Enum.map(fn item -> item * 2 end)
          |> Enum.filter(fn item -> item > 10 end)
          |> Enum.sort()
          |> Enum.take(5)
        end
      end
      """)

      write_fixture(dir, "d.ex", """
      defmodule D do
        def transform(values) do
          values
          |> Enum.map(fn value -> value * 2 end)
          |> Enum.filter(fn value -> value > 10 end)
          |> Enum.sort()
          |> Enum.take(5)
        end
      end
      """)

      config = Config.new(paths: [dir], min_mass: 5, reporters: [])
      clones = Detector.run(config)

      assert length(clones) > 0
    end

    test "returns empty list for unique code", %{dir: dir} do
      write_fixture(dir, "unique_a.ex", """
      defmodule UniqueA do
        def foo(x), do: x + 1
      end
      """)

      write_fixture(dir, "unique_b.ex", """
      defmodule UniqueB do
        def bar(x, y), do: x * y - 3
      end
      """)

      config = Config.new(paths: [dir], min_mass: 10, reporters: [])
      clones = Detector.run(config)

      assert clones == []
    end

    test "respects ignore patterns", %{dir: dir} do
      write_fixture(dir, "keep.ex", """
      defmodule Keep do
        def process(data) do
          data |> Enum.map(fn x -> x * 2 end) |> Enum.filter(fn x -> x > 10 end) |> Enum.sort()
        end
      end
      """)

      write_fixture(dir, "skip.ex", """
      defmodule Skip do
        def process(data) do
          data |> Enum.map(fn x -> x * 2 end) |> Enum.filter(fn x -> x > 10 end) |> Enum.sort()
        end
      end
      """)

      config =
        Config.new(
          paths: [dir],
          min_mass: 5,
          ignore: [Path.join(dir, "skip.ex")],
          reporters: []
        )

      clones = Detector.run(config)
      assert clones == []
    end

    test "detects duplicates within the same file", %{dir: dir} do
      write_fixture(dir, "same_file.ex", """
      defmodule SameFile do
        def foo(data) do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.sort()
          |> Enum.take(5)
        end

        def bar(data) do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.sort()
          |> Enum.take(5)
        end
      end
      """)

      config = Config.new(paths: [dir], min_mass: 5, reporters: [])
      clones = Detector.run(config)

      assert length(clones) > 0
    end

    test "detects pipe vs nested call when normalize_pipes is enabled", %{dir: dir} do
      write_fixture(dir, "piped.ex", """
      defmodule Piped do
        def process(data) do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.sort()
          |> Enum.take(5)
        end
      end
      """)

      write_fixture(dir, "nested.ex", """
      defmodule Nested do
        def process(data) do
          Enum.take(Enum.sort(Enum.filter(Enum.map(data, fn x -> x * 2 end), fn x -> x > 10 end)), 5)
        end
      end
      """)

      config_without =
        Config.new(paths: [dir], min_mass: 5, reporters: [], normalize_pipes: false)

      clones_without = Detector.run(config_without)
      pipe_body_clones = Enum.filter(clones_without, fn c -> c.mass >= 15 end)

      config_with = Config.new(paths: [dir], min_mass: 5, reporters: [], normalize_pipes: true)
      clones_with = Detector.run(config_with)
      pipe_body_clones_with = Enum.filter(clones_with, fn c -> c.mass >= 15 end)

      assert length(pipe_body_clones_with) > length(pipe_body_clones)
    end

    test "detects near-miss clones with min_similarity < 1.0", %{dir: dir} do
      write_fixture(dir, "near_a.ex", """
      defmodule NearA do
        def process(data) do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.sort()
        end
      end
      """)

      write_fixture(dir, "near_b.ex", """
      defmodule NearB do
        def process(data) do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.take(5)
        end
      end
      """)

      config_exact = Config.new(paths: [dir], min_mass: 5, reporters: [])
      exact_clones = Detector.run(config_exact)

      config_fuzzy = Config.new(paths: [dir], min_mass: 5, min_similarity: 0.7, reporters: [])
      fuzzy_clones = Detector.run(config_fuzzy)

      type_iii = Enum.filter(fuzzy_clones, &(&1.type == :type_iii))
      exact_only = Enum.filter(exact_clones, &(&1.type == :type_i))

      assert length(fuzzy_clones) >= length(exact_only)
      assert length(type_iii) > 0
    end
  end
end
