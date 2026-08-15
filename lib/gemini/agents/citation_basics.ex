defmodule Gemini.Agents.CitationBasics do
  @moduledoc """
  G09 — Reference existence, style, and citation gaps.

  Owns S6.1, S6.2. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G09",
    name: "Reference existence, style, and citation gaps",
    specialties: ["S6.1", "S6.2"],
    profile: :workhorse,
    tools: [:url_context, :scholarly_mcp]
end
