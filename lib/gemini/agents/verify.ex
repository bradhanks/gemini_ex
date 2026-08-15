defmodule Gemini.Agents.Verify do
  @moduledoc """
  The global adversarial verification pass.

  Built on demand per (batch, variant) pair, exactly as the catalog's
  `Catalog.verification/3`: the primary verifier challenges the candidates;
  the sibling runs on a model kept independent from both the workhorse that
  produced the findings and the primary that challenges them.

  Pass the candidate findings (and any grounding) in the input; the schema
  carries the `overview` property no other agent has.
  """

  alias Gemini.Agents.{Profiles, Prompts, Runner}

  @doc """
  Build the verification spec for the given candidate specialty ids.

    * `batch` — `:standard` or `:research`
    * `variant` — `:primary` or `:sibling`
  """
  def spec(source_ids, batch, variant)
      when is_list(source_ids) and source_ids != [] and
             batch in [:standard, :research] and variant in [:primary, :sibling] do
    profile = if variant == :primary, do: :verifier_primary, else: :verifier_sibling

    %{
      id: "VERIFY.#{String.upcase(to_string(batch))}.#{String.upcase(to_string(variant))}",
      name: "Global adversarial verification",
      specialty_ids: Enum.uniq(source_ids),
      profile: profile,
      tools: [],
      capabilities: [],
      gut_check: :none,
      mode: :standard,
      overview?: true,
      instructions: Prompts.verification_instructions()
    }
  end

  @doc """
  Run verification over candidates. `candidates_input` should carry the
  manuscript plus the candidate findings (and grounding) as content blocks;
  the verifier's one-line user prompt is appended for you.
  """
  def run(source_ids, batch, variant, candidates_input, opts \\ []) do
    verify_spec = spec(source_ids, batch, variant)

    input =
      List.wrap(candidates_input) ++
        [%{"type" => "text", "text" => Prompts.verifier_user_prompt()}]

    case Runner.run(verify_spec, input, opts) do
      {:ok, _} = ok ->
        ok

      {:error, _} = error ->
        case Profiles.fallback(verify_spec.profile) do
          nil -> error
          fallback -> Runner.run(verify_spec, input, Keyword.put(opts, :profile, fallback))
        end
    end
  end
end
