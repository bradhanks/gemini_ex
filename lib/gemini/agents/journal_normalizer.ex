defmodule Gemini.Agents.JournalNormalizer do
  @moduledoc """
  G18 — Journal-fit research normalizer.

  Owns S9.1. Extracted from the PerfectPaper review catalog.

  Normalizer: pass the deep-research report text (plus the manuscript)
  as input; it re-encodes the report into canonical findings.
  """

  use Gemini.Agents.Agent,
    id: "G18",
    name: "Journal-fit research normalizer",
    specialties: ["S9.1"],
    profile: :workhorse,
    extra_instructions:
      "Normalize the grounded Deep Research report into canonical findings. Preserve every source URL and access date and add nothing absent from the report or manuscript."
end
