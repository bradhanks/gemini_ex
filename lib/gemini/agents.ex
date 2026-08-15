defmodule Gemini.Agents do
  @moduledoc """
  The PerfectPaper review-agent fleet, packaged on gemini_ex.

  Ported from the catalog at `docs/review-engine/agent-catalog-full.md`
  (source commit b84f2eb8): 16 execution agents plus 2 Deep Research
  normalizers, the 30-specialty taxonomy they compose, the shared prompt
  scaffolding, identity-restricted finding schemas, and the adversarial
  verification pass (`Gemini.Agents.Verify`).

  ## Calling from a LiveView

  Standard agents block for seconds to minutes — never call `run/2` in the
  LiveView process. Use `start_async`:

      def handle_event("review", _params, socket) do
        input = socket.assigns.manuscript_input
        {:noreply,
         start_async(socket, :language_review, fn ->
           Gemini.Agents.Language.run(input)
         end)}
      end

      def handle_async(:language_review, {:ok, {:ok, %{findings: findings}}}, socket) do
        {:noreply, stream(socket, :findings, findings)}
      end

  Research agents run 25–65 minutes and survive your process tree: call
  `start/2`, persist the interaction id (your DB, not an assign), and poll
  from a background job — or attach a live stream with
  `Gemini.APIs.Interactions.get(id, stream: true)` and forward events to the
  LiveView via `handle_info`. A LiveView assign is not durable storage for a
  65-minute run id.
  """

  alias Gemini.Agents.Specialties

  @executions [
    Gemini.Agents.StructureLimits,
    Gemini.Agents.AbstractConsistency,
    Gemini.Agents.GuidelineRouter,
    Gemini.Agents.Language,
    Gemini.Agents.NumericIntegrity,
    Gemini.Agents.Terminology,
    Gemini.Agents.Figures,
    Gemini.Agents.TableStructure,
    Gemini.Agents.CitationBasics,
    Gemini.Agents.CitationVerification,
    Gemini.Agents.LiteratureResearch,
    Gemini.Agents.Logic,
    Gemini.Agents.Methods,
    Gemini.Agents.StatisticalCausal,
    Gemini.Agents.JournalResearch,
    Gemini.Agents.Submission
  ]

  @normalizers [
    Gemini.Agents.LiteratureNormalizer,
    Gemini.Agents.JournalNormalizer
  ]

  def executions, do: @executions
  def normalizers, do: @normalizers
  def all, do: @executions ++ @normalizers

  @doc "The prepass wave: G03 and G16, whose results feed later agents."
  def prepass_executions do
    Enum.filter(@executions, &(&1.spec().id in ["G03", "G16"]))
  end

  @doc "Standard wave: every non-research execution except the prepass pair."
  def standard_executions do
    Enum.filter(@executions, fn mod ->
      spec = mod.spec()
      spec.mode == :standard and spec.id not in ["G03", "G16"]
    end)
  end

  @doc "The two background research agents: G11 and G15."
  def research_executions do
    Enum.filter(@executions, &(&1.spec().mode == :research))
  end

  @doc "The normalizer paired with a research agent id."
  def normalizer_for("G11"), do: Gemini.Agents.LiteratureNormalizer
  def normalizer_for("G15"), do: Gemini.Agents.JournalNormalizer

  @doc "Fetch an agent module by its G-id; raises on unknown ids."
  def fetch!(id) do
    Enum.find(all(), &(&1.spec().id == id)) ||
      raise ArgumentError, "unknown agent id #{inspect(id)}"
  end

  @doc """
  The catalog's drift gates: exactly 30 specialties, exactly 18 executions,
  unique ids, every specialty claimed exactly once across `executions/0`
  (normalizers excluded — they legitimately re-claim S7.1 and S9.1), and
  full coverage. Raises on any violation.
  """
  def validate! do
    specs = Enum.map(all(), & &1.spec())

    unless Specialties.count() == 30,
      do: raise("review catalog must define exactly 30 visible specialties")

    unless length(specs) == 18, do: raise("expected 18 execution modules")

    ids = Enum.map(specs, & &1.id)
    unless ids == Enum.uniq(ids), do: raise("duplicate agent ids")

    claimed =
      @executions |> Enum.flat_map(& &1.spec().specialty_ids) |> Enum.frequencies()

    over = for {id, n} <- claimed, n > 1, do: id
    unless over == [], do: raise("specialties claimed more than once: #{inspect(over)}")

    missing = Map.keys(Specialties.all()) -- Map.keys(claimed)
    unless missing == [], do: raise("specialties not claimed: #{inspect(missing)}")

    :ok
  end
end
