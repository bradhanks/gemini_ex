defmodule Gemini.Agents.JournalResearch do
  @moduledoc """
  G15 — Journal fit and alternatives.

  Owns S9.1. Extracted from the PerfectPaper review catalog.

  Research agent: `start/2` then `await/2`; its report is normalized
  into findings by the paired normalizer agent.
  """

  use Gemini.Agents.Agent,
    id: "G15",
    name: "Journal fit and alternatives",
    specialties: ["S9.1"],
    profile: :research_fast,
    tools: [:google_search, :url_context],
    gut_check: :claude,
    mode: :research
end
