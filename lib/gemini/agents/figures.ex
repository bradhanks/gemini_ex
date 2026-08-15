defmodule Gemini.Agents.Figures do
  @moduledoc """
  G07 — Figure review.

  Owns S4.1, S4.2. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G07",
    name: "Figure review",
    specialties: ["S4.1", "S4.2"],
    profile: :workhorse,
    capabilities: [:vision]
end
