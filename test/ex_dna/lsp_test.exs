defmodule ExDNA.LSPTest do
  use ExUnit.Case, async: true

  import GenLSP.Test

  setup do
    dir = Path.join(System.tmp_dir!(), "ex_dna_lsp_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    File.write!(Path.join(dir, "a.ex"), """
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

    File.write!(Path.join(dir, "b.ex"), """
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

    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "responds to initialize with server capabilities", %{dir: dir} do
    server = server(ExDNA.LSP, config_overrides: [min_mass: 5])
    client = client(server)

    root_uri = "file://#{dir}"

    request(client, %{
      method: "initialize",
      id: 1,
      jsonrpc: "2.0",
      params: %{capabilities: %{}, rootUri: root_uri}
    })

    assert_result(1, %{
      "capabilities" => %{
        "textDocumentSync" => %{
          "openClose" => true,
          "save" => %{"includeText" => false},
          "change" => 1
        }
      },
      "serverInfo" => %{"name" => "ExDNA", "version" => "0.1.0"}
    })

    shutdown_client!(client)
    shutdown_server!(server)
  end

  test "pushes diagnostics on initialized notification", %{dir: dir} do
    server = server(ExDNA.LSP, config_overrides: [min_mass: 5])
    client = client(server)

    root_uri = "file://#{dir}"

    request(client, %{
      method: "initialize",
      id: 1,
      jsonrpc: "2.0",
      params: %{capabilities: %{}, rootUri: root_uri}
    })

    assert_result(1, _)

    notify(client, %{method: "initialized", jsonrpc: "2.0", params: %{}})

    assert_notification(
      "textDocument/publishDiagnostics",
      %{
        "uri" => _uri,
        "diagnostics" => diagnostics
      },
      5_000
    )

    assert diagnostics != []
    [diag | _] = diagnostics
    assert diag["source"] == "ExDNA"
    assert diag["message"] =~ "Code clone"
    assert diag["severity"] == 2

    shutdown_client!(client)
    shutdown_server!(server)
  end
end
