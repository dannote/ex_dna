defmodule ExDNA.AST.Fingerprint do
  @moduledoc """
  Computes structural fingerprints (hashes) for AST subtrees.

  Every subtree whose *mass* (node count) meets the threshold is hashed.
  Two normalized ASTs with the same hash are structurally identical clones.
  """

  alias ExDNA.AST.Normalizer

  @type hash :: binary()
  @type fragment :: %{
          hash: hash(),
          mass: pos_integer(),
          ast: Macro.t(),
          file: String.t(),
          line: pos_integer()
        }

  @doc """
  Walk an AST and return all subtree fragments that meet `min_mass`.

  Each fragment contains the normalized hash, mass, original AST (for display),
  source file, and starting line number.
  """
  @spec fragments(Macro.t(), String.t(), pos_integer(), keyword()) :: [fragment()]
  def fragments(ast, file, min_mass, opts \\ []) do
    norm_opts = Keyword.take(opts, [:literal_mode, :normalize_pipes])
    {_ast, frags} = walk(ast, file, min_mass, norm_opts, [])
    frags
  end

  defp walk({_form, meta, args} = node, file, min_mass, norm_opts, acc) when is_list(args) do
    acc =
      Enum.reduce(args, acc, fn child, a ->
        elem(walk(child, file, min_mass, norm_opts, a), 1)
      end)

    mass = mass(node)

    if mass >= min_mass do
      normalized = Normalizer.normalize(node, norm_opts)
      hash = compute_hash(normalized)
      line = Keyword.get(meta, :line, 0)

      frag = %{
        hash: hash,
        mass: mass,
        ast: node,
        file: file,
        line: line
      }

      {node, [frag | acc]}
    else
      {node, acc}
    end
  end

  defp walk({left, right}, file, min_mass, norm_opts, acc) do
    {_, acc} = walk(left, file, min_mass, norm_opts, acc)
    {_, acc} = walk(right, file, min_mass, norm_opts, acc)
    {{left, right}, acc}
  end

  defp walk(list, file, min_mass, norm_opts, acc) when is_list(list) do
    acc =
      Enum.reduce(list, acc, fn item, a ->
        elem(walk(item, file, min_mass, norm_opts, a), 1)
      end)

    {list, acc}
  end

  defp walk(leaf, _file, _min_mass, _norm_opts, acc), do: {leaf, acc}

  @doc """
  Count the number of AST nodes in a tree (its "mass").
  """
  @spec mass(Macro.t()) :: non_neg_integer()
  def mass({_form, _meta, args}) when is_list(args) do
    1 + Enum.sum(Enum.map(args, &mass/1))
  end

  def mass({left, right}), do: 1 + mass(left) + mass(right)

  def mass(list) when is_list(list) do
    Enum.sum(Enum.map(list, &mass/1))
  end

  def mass(_leaf), do: 1

  @doc """
  Compute a deterministic hash for a normalized AST.
  """
  @spec compute_hash(Macro.t()) :: hash()
  def compute_hash(normalized_ast) do
    normalized_ast
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:blake2b, &1))
  end
end
