defmodule Gemini.Agents.StructureLimits do
  @moduledoc """
  G01 — Structure and journal limits.

  Owns S1.1, S1.3. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G01",
    name: "Structure and journal limits",
    specialties: ["S1.1", "S1.3"],
    profile: :economy,
    tools: [:code_execution]
end
