defmodule Gemini.Agents.GuidelineRouter do
  @moduledoc """
  G03 — Study design and reporting guideline.

  Owns S1.4. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G03",
    name: "Study design and reporting guideline",
    specialties: ["S1.4"],
    profile: :workhorse,
    tools: [:file_search],
    gut_check: :claude
end
