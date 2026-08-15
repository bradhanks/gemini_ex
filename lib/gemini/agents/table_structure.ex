defmodule Gemini.Agents.TableStructure do
  @moduledoc """
  G08 — Table structure.

  Owns S5.1. Extracted from the PerfectPaper review catalog.
  """

  use Gemini.Agents.Agent,
    id: "G08",
    name: "Table structure",
    specialties: ["S5.1"],
    profile: :economy
end
