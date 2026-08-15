defmodule Gemini.Agents.Language do
  @moduledoc """
  G04 — Language review.

  Owns S2.1, S2.2, S2.3. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G04",
    name: "Language review",
    specialties: ["S2.1", "S2.2", "S2.3"],
    profile: :workhorse,
    tools: [:code_execution]
end
