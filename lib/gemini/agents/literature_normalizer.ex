defmodule Gemini.Agents.LiteratureNormalizer do
  @moduledoc """
  G17 — Literature research normalizer.

  Owns S7.1. Extracted from the PerfectPaper review catalog.

  Normalizer: pass the deep-research report text (plus the manuscript)
  as input; it re-encodes the report into canonical findings.
  """

  use Gemini.Agents.Agent,
    id: "G17",
    name: "Literature research normalizer",
    specialties: ["S7.1"],
    profile: :workhorse,
    extra_instructions:
      "Normalize the grounded Deep Research report into canonical findings. Preserve every source URL or DOI and add nothing absent from the report or manuscript."
end
