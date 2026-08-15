defmodule Gemini.Agents.AbstractConsistency do
  @moduledoc """
  G02 — Abstract-to-body consistency.

  Owns S1.2. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G02",
    name: "Abstract-to-body consistency",
    specialties: ["S1.2"],
    profile: :workhorse,
    tools: [:code_execution]
end
