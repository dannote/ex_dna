if Code.ensure_loaded?(Credo.Check) do
  defmodule ExDNA.Credo do
    @moduledoc """
    Credo check that detects code duplication using ExDNA's detection engine.

    Replaces `Credo.Check.Design.DuplicatedCode` with AST-aware detection:
    variable normalization (Type-II), near-miss matching (Type-III),
    pipe normalization, and refactoring suggestions.

    ## Setup

    Add to the `:enabled` list in `.credo.exs`:

        {ExDNA.Credo, []}

    And disable the built-in check:

        {Credo.Check.Design.DuplicatedCode, false}

    ## Parameters

    All ExDNA options are exposed as check params:

        {ExDNA.Credo, [
          min_mass: 40,
          literal_mode: :abstract,
          excluded_macros: [:@, :schema, :pipe_through],
          normalize_pipes: true,
          min_similarity: 0.85
        ]}
    """

    use Credo.Check,
      id: "EX9001",
      run_on_all: true,
      base_priority: :higher,
      category: :design,
      tags: [:ex_dna],
      param_defaults: [
        min_mass: 30,
        literal_mode: :keep,
        excluded_macros: [:@],
        normalize_pipes: false,
        min_similarity: 1.0
      ],
      explanations: [
        check: """
        Code should not be copy-pasted in a codebase when there is room to
        abstract the copied functionality in a meaningful way.

        ExDNA detects three types of clones:

        - **Type I** — exact copies (modulo whitespace/comments)
        - **Type II** — same structure with renamed variables or different literals
        - **Type III** — near-miss clones (similar structure with minor edits)

        Each clone comes with a refactoring suggestion: extract function,
        extract macro, or extract behaviour.

        Run `mix ex_dna.explain N` for a detailed breakdown of any clone.
        """,
        params: [
          min_mass: "Minimum AST node count for a code fragment to be considered.",
          literal_mode:
            "`keep` for exact clones only (Type-I), `abstract` to also detect renamed-variable clones (Type-II).",
          excluded_macros:
            "List of macro names whose bodies are skipped entirely (e.g. `[:schema, :pipe_through]`).",
          normalize_pipes: "When `true`, `x |> f()` and `f(x)` are treated as identical.",
          min_similarity:
            "Similarity threshold for near-miss clones (0.0–1.0). Values below 1.0 enable Type-III detection."
        ]
      ]

    alias Credo.Execution.ExecutionIssues
    alias ExDNA.Config
    alias ExDNA.Detection.Detector

    @doc false
    @impl true
    def run_on_all_source_files(exec, source_files, params) do
      config = build_config(params)
      source_file_index = Map.new(source_files, &{&1.filename, &1})

      file_ast_pairs =
        source_files
        |> Enum.filter(&(&1.status == :valid))
        |> Enum.map(fn sf -> {sf.filename, Credo.SourceFile.ast(sf)} end)

      config
      |> Detector.run(file_ast_pairs)
      |> Enum.each(&append_issues(&1, exec, source_file_index, params))

      :ok
    end

    defp append_issues(clone, exec, source_file_index, params) do
      for {frag, _snippet} <- Enum.zip(clone.fragments, clone.source_snippets),
          source_file = source_file_index[frag.file],
          source_file != nil,
          others = other_locations(clone.fragments, frag),
          others != [] do
        issue_meta = IssueMeta.for(source_file, params)

        issue =
          format_issue(issue_meta,
            message: build_message(clone, format_locations(others)),
            line_no: frag.line,
            trigger: Issue.no_trigger(),
            severity: Severity.compute(length(clone.fragments), 1)
          )

        ExecutionIssues.append(exec, source_file, issue)
      end
    end

    defp other_locations(fragments, current) do
      fragments
      |> Enum.reject(&same_location?(&1, current))
      |> Enum.uniq_by(&{&1.file, &1.line})
    end

    defp same_location?(left, right) do
      left.file == right.file and left.line == right.line
    end

    defp format_locations(fragments) do
      Enum.map_join(fragments, ", ", fn f -> "#{f.file}:#{f.line}" end)
    end

    defp build_config(params) do
      Config.new(
        paths: [],
        reporters: [],
        min_mass: Params.get(params, :min_mass, __MODULE__),
        literal_mode: Params.get(params, :literal_mode, __MODULE__),
        excluded_macros: Params.get(params, :excluded_macros, __MODULE__),
        normalize_pipes: Params.get(params, :normalize_pipes, __MODULE__),
        min_similarity: Params.get(params, :min_similarity, __MODULE__)
      )
    end

    defp build_message(clone, others) do
      type_label =
        case clone.type do
          :type_i -> "exact"
          :type_ii -> "renamed"
          :type_iii -> "near-miss"
        end

      suggestion =
        case clone.suggestion do
          %{kind: :extract_function, name: name, params: p} ->
            args = Enum.join(p, ", ")
            " → extract #{name}(#{args})"

          _ ->
            ""
        end

      "Duplicate code (#{type_label}, mass: #{clone.mass}) also in #{others}.#{suggestion}"
    end
  end
end
