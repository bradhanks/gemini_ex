defmodule Gemini.Agents.StatisticalCausal do
  @moduledoc """
  G14 — Statistical and causal inference.

  Owns S8.5, S8.6. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G14",
    name: "Statistical and causal inference",
    specialties: ["S8.5", "S8.6"],
    profile: :reasoning,
    tools: [:code_execution],
    gut_check: :claude
end
