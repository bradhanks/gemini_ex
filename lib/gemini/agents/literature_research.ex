defmodule Gemini.Agents.LiteratureResearch do
  @moduledoc """
  G11 — Missing prior work and positioning.

  Owns S7.1. Extracted from the PerfectPaper review catalog.

  Research agent: `start/2` then `await/2`; its report is normalized
  into findings by the paired normalizer agent.
  """

  use Gemini.Agents.Agent,
    id: "G11",
    name: "Missing prior work and positioning",
    specialties: ["S7.1"],
    profile: :research_fast,
    tools: [:google_search, :url_context, :scholarly_mcp],
    gut_check: :claude,
    mode: :research
end
