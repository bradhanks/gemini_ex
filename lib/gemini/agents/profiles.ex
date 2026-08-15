defmodule Gemini.Agents.Profiles do
  @moduledoc """
  Model-profile resolution for the review agents.

  Defaults mirror the PerfectPaper catalog's `@default_models`; override any
  profile with

      config :gemini_ex, :agent_models, %{workhorse: "gemini-3.7-flash"}

  Fallback chains stay inside a mode: a research (deep-research) profile never
  falls back to a plain model call.
  """

  @default_models %{
    economy: "gemini-3.5-flash-lite",
    economy_fallback: "gemini-3.1-flash-lite",
    workhorse: "gemini-3.6-flash",
    reasoning: "gemini-3.1-pro-preview",
    research_fast: "deep-research-preview-04-2026",
    research_max: "deep-research-max-preview-04-2026",
    # Keep the sibling verifier independent from both the workhorse that
    # produced the findings and the primary verifier that challenges them.
    verifier_primary: "gemini-3.1-pro-preview",
    verifier_sibling: "gemini-3.5-flash"
  }

  @fallbacks %{
    economy: :economy_fallback,
    workhorse: :economy,
    reasoning: :workhorse,
    research_fast: :research_max,
    research_max: :research_fast,
    verifier_primary: :verifier_sibling,
    verifier_sibling: :workhorse
  }

  @research_profiles [:research_fast, :research_max]

  def profiles, do: Map.keys(@default_models)

  def model_id(profile) do
    :gemini_ex
    |> Application.get_env(:agent_models, %{})
    |> Map.get(profile, Map.fetch!(@default_models, profile))
  end

  def fallback(profile), do: Map.get(@fallbacks, profile)

  def research?(profile), do: profile in @research_profiles

  @doc """
  The effective service tier: research profiles default to `"standard"`,
  everything else to `"flex"` — Gemini's discounted tier.

  Measured 2026-08-15: the API also accepts `"flex"` on deep-research
  background runs, so research on flex is available via
  `start(input, service_tier: "flex")` or the app-level override. The
  standard default for research is a reliability choice, not a constraint:
  a preempted 30-minute run re-run at any tier costs more than the discount
  saved — watch completion rates before committing a fleet to it.
  """
  def tier(profile) do
    default = if research?(profile), do: "standard", else: "flex"
    Application.get_env(:gemini_ex, :agents, [])[:service_tier] || default
  end

  @doc "15 minutes for standard agents, 65 for research — the catalog's timeouts."
  def timeout_ms(profile) do
    if research?(profile), do: :timer.minutes(65), else: :timer.minutes(15)
  end
end
