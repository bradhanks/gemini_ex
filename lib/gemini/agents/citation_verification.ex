defmodule Gemini.Agents.CitationVerification do
  @moduledoc """
  G10 — Semantic and primary-source citation verification.

  Owns S6.3, S6.4. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G10",
    name: "Semantic and primary-source citation verification",
    specialties: ["S6.3", "S6.4"],
    profile: :reasoning,
    tools: [:url_context, :scholarly_mcp],
    gut_check: :claude
end
