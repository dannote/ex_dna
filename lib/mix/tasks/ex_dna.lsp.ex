if Code.ensure_loaded?(GenLSP) do
  defmodule Mix.Tasks.ExDna.Lsp do
    @shortdoc "Start the ExDNA LSP server"
    @moduledoc """
    Starts the ExDNA Language Server Protocol server over stdio.

        $ mix ex_dna.lsp

    Configure your editor to run this command as an LSP server.
    It pushes code clone diagnostics alongside your primary Elixir
    LSP (e.g., Expert, ElixirLS).

    Requires the optional `gen_lsp` dependency:

        {:gen_lsp, "~> 0.11"}

    ## Neovim (nvim-lspconfig)

        vim.lsp.config('ex_dna', {
          cmd = { 'mix', 'ex_dna.lsp' },
          root_markers = { 'mix.exs' },
          filetypes = { 'elixir' },
        })

    ## VS Code (settings.json)

    Use a generic LSP extension and point it at `mix ex_dna.lsp`.
    """

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      ExDNA.LSP.Supervisor.start_link([])

      Process.sleep(:infinity)
    end
  end
end
