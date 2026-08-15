defmodule Gemini.Agents.Terminology do
  @moduledoc """
  G06 — Terminology and units consistency.

  Owns S3.4. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G06",
    name: "Terminology and units consistency",
    specialties: ["S3.4"],
    profile: :economy
end
