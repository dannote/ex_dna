defmodule ExDNA.CredoTest do
  use Credo.Test.Case

  alias ExDNA.Credo, as: Check

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  @duplicate_a """
  defmodule A do
    def process(data) do
      data
      |> Enum.map(fn x -> x * 2 end)
      |> Enum.filter(fn x -> x > 10 end)
      |> Enum.sort()
      |> Enum.take(5)
    end
  end
  """

  @duplicate_b """
  defmodule B do
    def process(data) do
      data
      |> Enum.map(fn x -> x * 2 end)
      |> Enum.filter(fn x -> x > 10 end)
      |> Enum.sort()
      |> Enum.take(5)
    end
  end
  """

  @unique_a """
  defmodule UniqueA do
    def foo(x), do: x + 1
  end
  """

  @unique_b """
  defmodule UniqueB do
    def bar(x, y), do: x * y - 3
  end
  """

  test "reports issues for duplicate code across files" do
    issues =
      [
        to_source_file(@duplicate_a, "a.ex"),
        to_source_file(@duplicate_b, "b.ex")
      ]
      |> run_check(Check, min_mass: 5)

    assert length(issues) >= 2

    issue_a = Enum.find(issues, &(&1.filename == "a.ex"))
    issue_b = Enum.find(issues, &(&1.filename == "b.ex"))

    assert issue_a.category == :design
    assert issue_a.message =~ "Duplicate code"
    assert issue_a.message =~ "b.ex"
    assert issue_b.message =~ "a.ex"
  end

  test "reports no issues for unique code" do
    issues =
      [
        to_source_file(@unique_a, "unique_a.ex"),
        to_source_file(@unique_b, "unique_b.ex")
      ]
      |> run_check(Check, min_mass: 10)

    assert issues == []
  end

  test "detects renamed-variable clones with literal_mode: :abstract" do
    renamed_a = """
    defmodule C do
      def transform(items) do
        items
        |> Enum.map(fn item -> item * 2 end)
        |> Enum.filter(fn item -> item > 10 end)
        |> Enum.sort()
        |> Enum.take(5)
      end
    end
    """

    renamed_b = """
    defmodule D do
      def transform(values) do
        values
        |> Enum.map(fn value -> value * 2 end)
        |> Enum.filter(fn value -> value > 10 end)
        |> Enum.sort()
        |> Enum.take(5)
      end
    end
    """

    issues =
      [
        to_source_file(renamed_a, "c.ex"),
        to_source_file(renamed_b, "d.ex")
      ]
      |> run_check(Check, min_mass: 5, literal_mode: :abstract)

    assert length(issues) >= 2
  end

  test "respects excluded_macros" do
    schema_a = """
    defmodule SchemaA do
      use Ecto.Schema

      schema "users" do
        field :name, :string
        field :email, :string
        timestamps()
      end
    end
    """

    schema_b = """
    defmodule SchemaB do
      use Ecto.Schema

      schema "posts" do
        field :title, :string
        field :body, :string
        timestamps()
      end
    end
    """

    issues =
      [
        to_source_file(schema_a, "schema_a.ex"),
        to_source_file(schema_b, "schema_b.ex")
      ]
      |> run_check(Check, min_mass: 5, excluded_macros: [:@, :schema])

    schema_issues = Enum.filter(issues, &(&1.message =~ "schema"))
    assert schema_issues == []
  end

  test "message includes type label" do
    issues =
      [
        to_source_file(@duplicate_a, "a.ex"),
        to_source_file(@duplicate_b, "b.ex")
      ]
      |> run_check(Check, min_mass: 5)

    assert Enum.all?(issues, &(&1.message =~ "exact" or &1.message =~ "renamed"))
  end

  test "does not emit self-match issues when all fragments resolve to the same location" do
    duplicate = """
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
    """

    issues =
      [to_source_file(duplicate, "same_file.ex")]
      |> run_check(Check, min_mass: 5)

    refute Enum.any?(issues, fn issue ->
             issue.line_no == 0 and String.contains?(issue.message, "also in .")
           end)
  end

  test "does not emit line 0 issues for reduced reports from issue #1" do
    reduced = """
    defmodule Example.A do
      defp organization_tone(:government), do: "purple"
      defp organization_tone(:business), do: "blue"
      defp organization_tone(:individual), do: "green"
      defp organization_tone(:non_profit), do: "orange"
      defp organization_tone(:event), do: "pink"
      defp organization_tone(:chamber), do: "indigo"
    end

    defmodule Example.B do
      defp encode_csv_row(fields) do
        fields
        |> Enum.map_join(",", &escape_csv_field/1)
      end

      defp escape_csv_field(value), do: to_string(value)
    end
    """

    issues =
      [to_source_file(reduced, "issue_1_reduced.ex")]
      |> run_check(Check, min_mass: 30, literal_mode: :abstract)

    refute Enum.any?(issues, &(&1.line_no == 0))
    refute Enum.any?(issues, &(String.contains?(&1.message, "also in .")))
  end
end
