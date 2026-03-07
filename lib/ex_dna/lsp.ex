if Code.ensure_loaded?(GenLSP) do
  defmodule ExDNA.LSP do
    @moduledoc """
    Language Server Protocol server for ExDNA.

    Pushes code clone diagnostics to editors via the standard LSP protocol.
    Runs alongside other LSP servers (e.g., Expert) — editors like Neovim
    and VS Code support multiple servers per filetype.

    Requires the optional `gen_lsp` dependency.

    ## Usage

        mix ex_dna.lsp

    Or configure in your editor as a command: `mix ex_dna.lsp`
    """

    use GenLSP

    alias GenLSP.Enumerations.{DiagnosticSeverity, TextDocumentSyncKind}

    alias GenLSP.Notifications.{
      Exit,
      Initialized,
      TextDocumentDidChange,
      TextDocumentDidOpen,
      TextDocumentDidSave
    }

    alias GenLSP.Requests.{Initialize, Shutdown}

    alias GenLSP.Structures.{
      Diagnostic,
      InitializeParams,
      InitializeResult,
      Position,
      Range,
      SaveOptions,
      ServerCapabilities,
      TextDocumentSyncOptions
    }

    alias ExDNA.Config
    alias ExDNA.Detection.Detector

    def start_link(opts) do
      {init_opts, gen_opts} = Keyword.split(opts, [:root_uri, :config_overrides])

      GenLSP.start_link(__MODULE__, init_opts, gen_opts)
    end

    @impl true
    def init(lsp, args) do
      root_uri = Keyword.get(args, :root_uri)
      config_overrides = Keyword.get(args, :config_overrides, [])
      {:ok, assign(lsp, root_uri: root_uri, clones: [], config_overrides: config_overrides)}
    end

    @impl true
    def handle_request(
          %Initialize{params: %InitializeParams{root_uri: root_uri}},
          lsp
        ) do
      {:reply,
       %InitializeResult{
         capabilities: %ServerCapabilities{
           text_document_sync: %TextDocumentSyncOptions{
             open_close: true,
             save: %SaveOptions{include_text: false},
             change: TextDocumentSyncKind.full()
           }
         },
         server_info: %{name: "ExDNA", version: "1.0.0"}
       }, assign(lsp, root_uri: root_uri)}
    end

    def handle_request(%Shutdown{}, lsp) do
      {:reply, nil, lsp}
    end

    @impl true
    def handle_notification(%Initialized{}, lsp) do
      run_analysis(lsp)
    end

    def handle_notification(%TextDocumentDidSave{}, lsp) do
      run_analysis(lsp)
    end

    def handle_notification(%TextDocumentDidOpen{}, lsp) do
      {:noreply, lsp}
    end

    def handle_notification(%TextDocumentDidChange{}, lsp) do
      {:noreply, lsp}
    end

    def handle_notification(%Exit{}, lsp) do
      System.halt(0)
      {:noreply, lsp}
    end

    def handle_notification(_notification, lsp) do
      {:noreply, lsp}
    end

    defp run_analysis(lsp) do
      assigns = GenLSP.LSP.assigns(lsp)
      root_path = uri_to_path(assigns.root_uri)
      overrides = Map.get(assigns, :config_overrides, [])
      config = Config.new(overrides ++ [paths: [root_path], reporters: []])
      clones = Detector.run(config)

      diagnostics_by_file = build_diagnostics(clones)

      for {file, diags} <- diagnostics_by_file do
        GenLSP.notify(lsp, %GenLSP.Notifications.TextDocumentPublishDiagnostics{
          params: %GenLSP.Structures.PublishDiagnosticsParams{
            uri: path_to_uri(file),
            diagnostics: diags
          }
        })
      end

      old_files =
        Map.get(assigns, :clones, [])
        |> Enum.flat_map(fn c -> Enum.map(c.fragments, & &1.file) end)
        |> Enum.uniq()

      new_files = Map.keys(diagnostics_by_file)

      for file <- old_files, file not in new_files do
        GenLSP.notify(lsp, %GenLSP.Notifications.TextDocumentPublishDiagnostics{
          params: %GenLSP.Structures.PublishDiagnosticsParams{
            uri: path_to_uri(file),
            diagnostics: []
          }
        })
      end

      {:noreply, assign(lsp, clones: clones)}
    end

    defp build_diagnostics(clones) do
      clones
      |> Enum.flat_map(&diagnostics_for_clone/1)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    end

    defp diagnostics_for_clone(clone) do
      other_locations =
        Enum.map(clone.fragments, fn f ->
          path = Path.relative_to_cwd(f.file)
          if f.line > 0, do: "#{path}:#{f.line}", else: path
        end)

      Enum.map(clone.fragments, fn frag ->
        others =
          other_locations
          |> Enum.reject(&String.starts_with?(&1, Path.relative_to_cwd(frag.file)))
          |> Enum.join(", ")

        line = max(frag.line, 1)

        diag = %Diagnostic{
          range: %Range{
            start: %Position{line: line - 1, character: 0},
            end: %Position{line: line - 1, character: 999}
          },
          severity: DiagnosticSeverity.warning(),
          source: "ExDNA",
          message: clone_message(clone, others)
        }

        {frag.file, diag}
      end)
    end

    defp clone_message(clone, others) do
      type_label =
        case clone.type do
          :type_i -> "exact"
          :type_ii -> "renamed"
          :type_iii -> "near-miss (#{Float.round((clone.similarity || 0.0) * 100, 1)}%)"
        end

      suggestion =
        case clone.suggestion do
          %{kind: :extract_function, name: name} -> " → extract #{name}()"
          %{kind: :extract_macro, name: name} -> " → consider defmacro #{name}()"
          _ -> ""
        end

      "Code clone (#{type_label}, #{clone.mass} nodes) also in: #{others}#{suggestion}"
    end

    defp uri_to_path("file://" <> path), do: URI.decode(path)
    defp uri_to_path(path), do: path

    defp path_to_uri(path) do
      abs = Path.expand(path)
      "file://#{abs}"
    end
  end
end
