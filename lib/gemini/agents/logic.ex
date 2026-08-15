defmodule Gemini.Agents.Logic do
  @moduledoc """
  G12 — Logic and conclusion validity.

  Owns S8.1, S8.2, S8.7. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G12",
    name: "Logic and conclusion validity",
    specialties: ["S8.1", "S8.2", "S8.7"],
    profile: :reasoning,
    gut_check: :claude
end
