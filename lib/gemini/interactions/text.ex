defmodule Gemini.Interactions.Text do
  @moduledoc """
  Text generation through the Interactions API.

  <https://ai.google.dev/gemini-api/docs/text-generation>

  ## Examples

      {:ok, text} =
        Gemini.Interactions.Text.generate("Explain how AI works in a few words",
          model: "gemini-3.6-flash"
        )

  Thinking is configured with `:thinking_level` and `:thinking_summaries`:

      {:ok, text} =
        Gemini.Interactions.Text.generate("Solve this puzzle",
          model: "gemini-3.6-flash",
          thinking_level: "high",
          thinking_summaries: "auto"
        )
  """

  alias Gemini.APIs.Interactions
  alias Gemini.Types.Interactions.{GenerationConfig, Interaction}

  @generation_config_keys [
    :image_config,
    :max_output_tokens,
    :seed,
    :speech_config,
    :stop_sequences,
    :temperature,
    :thinking_level,
    :thinking_summaries,
    :tool_choice,
    :top_p,
    :video_config
  ]

  @doc """
  Generate text and return it.

  Accepts every option `Gemini.APIs.Interactions.create/2` accepts. Options
  belonging to the generation config — `:thinking_level`,
  `:thinking_summaries`, `:temperature`, `:top_p`, `:max_output_tokens`,
  `:seed`, `:stop_sequences`, and `:tool_choice` — may be passed at the top
  level and are folded into `generation_config` for you. An explicit
  `:generation_config` takes precedence and is passed through untouched.

  With the default non-streaming request, returns `{:ok, text}` or
  `{:error, :not_found}` when the completed interaction carries no text. With
  `stream: true`, returns `{:ok, stream}` unchanged; the stream yields
  `Gemini.Types.Interactions.Events.InteractionSSEEvent` variants.
  """
  @spec generate(term(), keyword()) ::
          {:ok, String.t() | Enumerable.t()} | {:error, term()}
  def generate(input, opts \\ []) do
    case generate_interaction(input, opts) do
      {:ok, %Interaction{} = interaction} -> Interaction.output_text(interaction)
      {:ok, stream} -> {:ok, stream}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Generate text and return the whole interaction.

  Use this when you need `steps`, thought signatures, or usage metadata. With
  `stream: true`, returns `{:ok, stream}` instead, where `stream` yields
  `Gemini.Types.Interactions.Events.InteractionSSEEvent` variants.
  """
  @spec generate_interaction(term(), keyword()) ::
          {:ok, Interaction.t() | Enumerable.t()} | {:error, term()}
  def generate_interaction(input, opts \\ []) do
    Interactions.create(input, build_opts(opts))
  end

  @doc false
  @spec build_opts(keyword()) :: keyword()
  def build_opts(opts) do
    {config_opts, rest} = Keyword.split(opts, @generation_config_keys)

    case {Keyword.get(rest, :generation_config), config_opts} do
      {nil, []} ->
        rest

      {nil, _config_opts} ->
        Keyword.put(rest, :generation_config, struct(GenerationConfig, config_opts))

      {_existing, _config_opts} ->
        rest
    end
  end
end
