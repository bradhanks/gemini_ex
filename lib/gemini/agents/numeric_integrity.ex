defmodule Gemini.Agents.NumericIntegrity do
  @moduledoc """
  G05 — Numeric integrity.

  Owns S3.1, S3.2, S3.3, S5.2. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G05",
    name: "Numeric integrity",
    specialties: ["S3.1", "S3.2", "S3.3", "S5.2"],
    profile: :reasoning,
    tools: [:code_execution],
    gut_check: :claude
end
