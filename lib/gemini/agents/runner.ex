defmodule Gemini.Agents.Runner do
  @moduledoc """
  Executes a review agent through the Interactions API.

  Two modes, matching the catalog's call mechanics:

    * standard (`:stream` in the catalog) — one schema-enforced model call.
      `run/2` blocks for its duration (seconds to a few minutes): from a
      LiveView, wrap it in `start_async`/`Task`, never call it in the
      LiveView process.
    * research (`:background`) — a background deep-research run. `start/2`
      returns immediately with the interaction; persist `interaction.id` and
      `await/2` it (65-minute class), or attach a live stream via
      `Gemini.APIs.Interactions.get(id, stream: true)`.

  Tool degradation mirrors the catalog: an unconfigured `:file_search` is
  dropped; an unconfigured `:scholarly_mcp` is substituted with
  `:google_search`. Configure via

      config :gemini_ex, :agents,
        file_search_store_names: ["fileSearchStores/..."],
        scholarly_mcp: %{url: "https://...", name: "...", headers: %{}, allowed_tools: []}
  """

  alias Gemini.APIs.Interactions
  alias Gemini.Agents.{Profiles, Prompts, Schema}
  alias Gemini.Types.Interactions.Interaction

  @agent_config %{
    "type" => "deep-research",
    "thinking_summaries" => "auto",
    "visualization" => "off",
    "collaborative_planning" => false
  }

  @doc """
  Run a standard agent. `input` is Interactions content (a string, or a list of
  content structs/maps — document blocks, text blocks). Returns
  `{:ok, %{findings: [...], overview: nil | text, interaction: %Interaction{}}}`.
  """
  def run(agent_spec, input, opts \\ []) do
    profile = Keyword.get(opts, :profile, agent_spec.profile)

    create_opts =
      [
        model: Profiles.model_id(profile),
        service_tier: Keyword.get(opts, :service_tier, Profiles.tier(profile)),
        system_instruction: Prompts.system_prompt(),
        response_format: %{
          "type" => "text",
          "mime_type" => "application/json",
          "schema" =>
            Schema.findings_schema(agent_spec.specialty_ids, overview: agent_spec.overview?)
        },
        tools: encode_tools(agent_spec.tools, input),
        store: true,
        timeout: Profiles.timeout_ms(profile)
      ]
      |> Keyword.merge(Keyword.get(opts, :create_opts, []))

    with {:ok, %Interaction{} = interaction} <-
           Interactions.create(compose_input(agent_spec, input), create_opts),
         {:ok, json} <- Interaction.output_text_fn(interaction),
         {:ok, decoded} <- Jason.decode(json) do
      {:ok,
       %{
         findings: Map.get(decoded, "findings", []),
         overview: Map.get(decoded, "overview"),
         interaction: interaction
       }}
    else
      {:error, _} = error -> error
    end
  end

  @doc """
  Run with the catalog's attempt ladder: the primary profile at its effective
  tier; the same profile at `"standard"` when the effective tier was flex
  (flex capacity can be exhausted); then the fallback profile at `"standard"`.
  Never crosses modes — a research profile falls back only to the other
  research profile.
  """
  def run_with_fallback(agent_spec, input, opts \\ []) do
    agent_spec
    |> attempts()
    |> Enum.reduce_while({:error, :no_attempts}, fn {profile, tier}, _last ->
      attempt_opts =
        opts |> Keyword.put(:profile, profile) |> Keyword.put(:service_tier, tier)

      case run(agent_spec, input, attempt_opts) do
        {:ok, _} = ok ->
          {:halt, ok}

        # A 429 is a rate limit, not exhausted flex capacity: escalating to
        # the standard tier would re-bill the identical call at full price
        # while still rate-limited. The catalog blocks fallback on 429; so
        # do we. Everything else walks the ladder.
        {:error, %Gemini.Error{http_status: 429}} = error ->
          {:halt, error}

        {:error, _} = error ->
          {:cont, error}
      end
    end)
  end

  defp attempts(agent_spec) do
    primary = agent_spec.profile
    tier = Profiles.tier(primary)
    fallback = Profiles.fallback(primary)

    [{primary, tier}] ++
      if(tier == "flex", do: [{primary, "standard"}], else: []) ++
      if(fallback, do: [{fallback, "standard"}], else: [])
  end

  @doc """
  Start a research agent in the background. Returns `{:ok, %Interaction{}}`
  immediately — persist `interaction.id` before doing anything else.
  """
  def start(agent_spec, input, opts \\ []) do
    create_opts =
      [
        agent: Profiles.model_id(agent_spec.profile),
        agent_config: @agent_config,
        background: true,
        store: true,
        service_tier: Keyword.get(opts, :service_tier, Profiles.tier(agent_spec.profile)),
        tools: encode_tools(agent_spec.tools, input)
      ]
      |> Keyword.merge(Keyword.get(opts, :create_opts, []))

    Interactions.create(compose_input(agent_spec, input), create_opts)
  end

  @doc "Await a research run; returns `{:ok, report_text, %Interaction{}}`."
  def await(interaction_id, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, :timer.minutes(65))

    with {:ok, %Interaction{} = done} <-
           Interactions.wait_for_completion(interaction_id,
             timeout_ms: timeout_ms,
             poll_interval_ms: Keyword.get(opts, :poll_interval_ms, 15_000)
           ),
         {:ok, report} <- full_text(done) do
      {:ok, report, done}
    end
  end

  # Research agents emit long reports across several model_output steps;
  # output_text_fn/1 keeps only the last. Join them all.
  def full_text(%Interaction{} = interaction) do
    text =
      (interaction.steps || [])
      |> Enum.filter(&(is_map(&1) and Map.get(&1, :type) == "model_output"))
      |> Enum.flat_map(&List.wrap(Map.get(&1, :content)))
      |> Enum.map(&((is_map(&1) && Map.get(&1, :text)) || ""))
      |> Enum.join("")

    if text == "", do: Interaction.output_text_fn(interaction), else: {:ok, text}
  end

  # ---------- prompt / input composition ----------

  defp compose_input(agent_spec, input) do
    instruction_block =
      agent_spec.instructions <> "\n\n" <> Prompts.output_contract(agent_spec.specialty_ids)

    List.wrap(input) ++ [%{"type" => "text", "text" => instruction_block}]
  end

  # ---------- tool encoding (Interactions, snake-case) ----------

  defp encode_tools([], _input), do: nil

  defp encode_tools(tools, input) do
    case tools |> resolve_tools(input) |> Enum.map(&encode_tool/1) do
      [] -> nil
      encoded -> encoded
    end
  end

  # Measured 2026-08-15: the API rejects code_execution alongside a PDF
  # document block (400 "application/pdf is not supported for code
  # execution"). Degrade the tool rather than fail the review; text input
  # keeps it.
  defp resolve_tools(tools, input) do
    if :code_execution in tools and pdf_input?(input) do
      resolve_tools(List.delete(tools, :code_execution))
    else
      resolve_tools(tools)
    end
  end

  defp pdf_input?(input) do
    input
    |> List.wrap()
    |> Enum.any?(fn
      %{"type" => "document"} -> true
      %{type: "document"} -> true
      %Gemini.Types.Interactions.DocumentContent{} -> true
      _ -> false
    end)
  end

  # Degradation before encoding, exactly as the catalog specifies.
  defp resolve_tools(tools) do
    config = Application.get_env(:gemini_ex, :agents, [])

    tools
    |> Enum.flat_map(fn
      :file_search ->
        case config[:file_search_store_names] do
          [_ | _] -> [:file_search]
          _ -> []
        end

      :scholarly_mcp ->
        case config[:scholarly_mcp] do
          %{url: url} when is_binary(url) and url != "" -> [:scholarly_mcp]
          _ -> [:google_search]
        end

      tool ->
        [tool]
    end)
    |> Enum.uniq()
    |> Enum.sort_by(&tool_order/1)
  end

  defp tool_order(:google_search), do: 0
  defp tool_order(:url_context), do: 1
  defp tool_order(:file_search), do: 2
  defp tool_order(:code_execution), do: 3
  defp tool_order(:scholarly_mcp), do: 4
  defp tool_order(_), do: 5

  defp encode_tool(:google_search), do: %{"type" => "google_search"}
  defp encode_tool(:url_context), do: %{"type" => "url_context"}
  defp encode_tool(:code_execution), do: %{"type" => "code_execution"}

  defp encode_tool(:file_search) do
    stores = Application.get_env(:gemini_ex, :agents, [])[:file_search_store_names]
    %{"type" => "file_search", "file_search_store_names" => stores}
  end

  defp encode_tool(:scholarly_mcp) do
    mcp = Application.get_env(:gemini_ex, :agents, [])[:scholarly_mcp]

    %{
      "type" => "mcp_server",
      "name" => Map.get(mcp, :name, "Scholarly Sources"),
      "url" => mcp.url
    }
    |> maybe_put("headers", Map.get(mcp, :headers))
    |> maybe_put("allowed_tools", Map.get(mcp, :allowed_tools))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
