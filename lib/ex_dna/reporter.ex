defmodule ExDNA.Reporter do
  @moduledoc """
  Behaviour for ExDNA output reporters.
  """

  alias ExDNA.Report

  @callback report(Report.t()) :: :ok
end
