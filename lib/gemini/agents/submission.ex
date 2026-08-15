defmodule Gemini.Agents.Submission do
  @moduledoc """
  G16 — Submission requirements and cover letter.

  Owns S9.2, S9.3. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G16",
    name: "Submission requirements and cover letter",
    specialties: ["S9.2", "S9.3"],
    profile: :workhorse,
    tools: [:google_search, :url_context]
end
