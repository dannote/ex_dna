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

      assert clones != []

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

      assert clones != []
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

      assert clones != []
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

    test "excludes specified macros from detection", %{dir: dir} do
      write_fixture(dir, "schema_a.ex", """
      defmodule SchemaA do
        use Ecto.Schema

        schema "users" do
          field :name, :string
          field :email, :string
          field :age, :integer
        end
      end
      """)

      write_fixture(dir, "schema_b.ex", """
      defmodule SchemaB do
        use Ecto.Schema

        schema "admins" do
          field :name, :string
          field :email, :string
          field :age, :integer
        end
      end
      """)

      config_without =
        Config.new(paths: [dir], min_mass: 3, reporters: [], excluded_macros: [])

      clones_without = Detector.run(config_without)

      schema_clones =
        Enum.filter(clones_without, fn c ->
          Enum.any?(c.source_snippets, &String.contains?(&1, "field"))
        end)

      config_with =
        Config.new(paths: [dir], min_mass: 3, reporters: [], excluded_macros: [:schema, :field])

      clones_with = Detector.run(config_with)

      field_clones_with =
        Enum.filter(clones_with, fn c ->
          Enum.any?(c.fragments, fn f -> match?({:field, _, _}, f.ast) end)
        end)

      assert schema_clones != []
      assert field_clones_with == []
    end

    test "handles parse errors gracefully", %{dir: dir} do
      write_fixture(dir, "broken.ex", """
      defmodule Broken do
        def foo(
      end
      """)

      write_fixture(dir, "good.ex", """
      defmodule Good do
        def process(data), do: data
      end
      """)

      config = Config.new(paths: [dir], min_mass: 5, reporters: [])
      clones = Detector.run(config)

      assert is_list(clones)
    end

    test "skips @no_clone annotated defs from detection", %{dir: dir} do
      write_fixture(dir, "clone_a.ex", """
      defmodule CloneA do
        def process(data) do
          data
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 10 end)
          |> Enum.sort()
          |> Enum.take(5)
        end
      end
      """)

      write_fixture(dir, "clone_b.ex", """
      defmodule CloneB do
        @no_clone true
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

      # The annotated def in CloneB should not produce fragments,
      # so no clone pair at the `def process` level should be found.
      process_clones =
        Enum.filter(clones, fn c ->
          Enum.any?(c.fragments, fn f ->
            case f.ast do
              {:def, _, [{:process, _, _} | _]} -> true
              _ -> false
            end
          end)
        end)

      assert process_clones == []
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
      assert type_iii != []
    end

    test "detects duplicated multi-clause functions across files", %{dir: dir} do
      write_fixture(dir, "cache.ex", """
      defmodule Cache do
        defp format_bytes(bytes) when bytes < 1024, do: "\#{bytes} B"
        defp format_bytes(bytes) when bytes < 1_048_576, do: "\#{Float.round(bytes / 1024, 1)} KB"
        defp format_bytes(bytes), do: "\#{Float.round(bytes / 1_048_576, 1)} MB"
      end
      """)

      write_fixture(dir, "size.ex", """
      defmodule Size do
        defp format_bytes(bytes) when bytes < 1024, do: "\#{bytes} B"
        defp format_bytes(bytes) when bytes < 1_048_576, do: "\#{Float.round(bytes / 1024, 1)} KB"
        defp format_bytes(bytes), do: "\#{Float.round(bytes / 1_048_576, 1)} MB"
      end
      """)

      config = Config.new(paths: [dir], min_mass: 30, reporters: [])
      clones = Detector.run(config)

      format_clones =
        Enum.filter(clones, fn c ->
          Enum.any?(c.source_snippets, &String.contains?(&1, "format_bytes"))
        end)

      assert length(format_clones) == 1
      clone = hd(format_clones)
      assert clone.mass >= 30
      assert length(clone.fragments) == 2

      files = Enum.map(clone.fragments, & &1.file) |> Enum.sort()
      assert Enum.any?(files, &String.ends_with?(&1, "cache.ex"))
      assert Enum.any?(files, &String.ends_with?(&1, "size.ex"))

      snippet = hd(clone.source_snippets)
      refute String.contains?(snippet, "__ex_dna_grouped_def__")
      assert String.contains?(snippet, "format_bytes")
    end

    test "detects multi-clause duplicates with renamed variables", %{dir: dir} do
      write_fixture(dir, "a.ex", """
      defmodule A do
        defp convert(val) when val < 100, do: val
        defp convert(val) when val < 10000, do: val / 100
        defp convert(val), do: val / 10000
      end
      """)

      write_fixture(dir, "b.ex", """
      defmodule B do
        defp convert(amount) when amount < 100, do: amount
        defp convert(amount) when amount < 10000, do: amount / 100
        defp convert(amount), do: amount / 10000
      end
      """)

      config = Config.new(paths: [dir], min_mass: 5, reporters: [])
      clones = Detector.run(config)

      convert_clones =
        Enum.filter(clones, fn c ->
          Enum.any?(c.source_snippets, &String.contains?(&1, "convert"))
        end)

      grouped_clone =
        Enum.find(convert_clones, fn c -> c.mass > 20 end)

      assert grouped_clone != nil
      assert length(grouped_clone.fragments) == 2
    end

    test "does not group non-consecutive clauses as a single clone", %{dir: dir} do
      write_fixture(dir, "split_a.ex", """
      defmodule SplitA do
        defp foo(:a), do: 1
        defp bar(x), do: x * 2
        defp foo(:b), do: 2
      end
      """)

      write_fixture(dir, "split_b.ex", """
      defmodule SplitB do
        defp foo(:a), do: 1
        defp bar(x), do: x * 2
        defp foo(:b), do: 2
      end
      """)

      config = Config.new(paths: [dir], min_mass: 5, reporters: [])
      clones = Detector.run(config)

      grouped_clones =
        Enum.filter(clones, fn c ->
          Enum.any?(c.fragments, fn f ->
            match?({:__ex_dna_grouped_def__, _, _}, f.ast)
          end)
        end)

      assert grouped_clones == []
    end
  end
end
