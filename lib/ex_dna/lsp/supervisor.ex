defmodule ExDNA.LSP.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Task.Supervisor, name: ExDNA.LSP.TaskSupervisor},
      {GenLSP.Buffer, name: ExDNA.LSP.Buffer},
      {ExDNA.LSP,
       buffer: ExDNA.LSP.Buffer, task_supervisor: ExDNA.LSP.TaskSupervisor, name: ExDNA.LSP.Server}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
