defmodule ExDNA.Config do
  @moduledoc false

  @defaults %{
    paths: ["lib/"],
    min_mass: 30,
    min_similarity: 1.0,
    ignore: [],
    reporters: [ExDNA.Reporter.Console],
    literal_mode: :keep
  }

  defstruct Map.keys(@defaults)

  @type literal_mode :: :keep | :abstract
  @type t :: %__MODULE__{
          paths: [String.t()],
          min_mass: pos_integer(),
          min_similarity: float(),
          ignore: [String.t()],
          reporters: [module()],
          literal_mode: literal_mode()
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    attrs =
      @defaults
      |> Map.merge(Map.new(opts))

    struct!(__MODULE__, attrs)
  end

  @spec default(atom()) :: term()
  def default(key), do: Map.fetch!(@defaults, key)
end
