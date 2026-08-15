defmodule Gemini.Agents.Methods do
  @moduledoc """
  G13 — Methods and instrument design.

  Owns S8.3, S8.4. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G13",
    name: "Methods and instrument design",
    specialties: ["S8.3", "S8.4"],
    profile: :reasoning,
    tools: [:file_search],
    gut_check: :claude
end
