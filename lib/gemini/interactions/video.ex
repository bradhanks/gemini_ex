defmodule Gemini.Interactions.Video do
  @moduledoc """
  Video generation with Gemini Omni through the Interactions API.

  <https://ai.google.dev/gemini-api/docs/omni>

  This module covers Gemini Omni models only. Veo uses a different API and is
  handled by `Gemini.APIs.Videos`.

  Omni does not support system instructions, `temperature`, `top_p`, stop
  sequences, or negative prompts as parameters. Express negative constraints
  in the prompt text instead.

  Videos larger than 4 MB are returned by URI rather than inline. Pass
  `delivery: "uri"` to request URI delivery explicitly.

  ## Examples

      {:ok, video} =
        Gemini.Interactions.Video.generate("a cat surfing a wave",
          model: "gemini-omni-flash",
          aspect_ratio: "16:9",
          delivery: "uri"
        )

  Conversational editing continues from a prior interaction:

      {:ok, edited} =
        Gemini.Interactions.Video.generate("now make it sunset",
          model: "gemini-omni-flash",
          previous_interaction_id: interaction.id
        )
  """

  alias Gemini.APIs.Interactions

  alias Gemini.Types.Interactions.{
    GenerationConfig,
    Interaction,
    ResponseFormat,
    TextContent,
    VideoConfig,
    VideoContent
  }

  @format_keys [:aspect_ratio, :delivery]

  @doc """
  Generate a video and return its content block.

  `:task` is commonly `"text_to_video"`, `"image_to_video"`,
  `"reference_to_video"`, or `"edit"`; values are passed through for forward
  compatibility. `:aspect_ratio` and `:delivery` build the video
  `response_format` when that option is absent.

  An explicitly supplied `:response_format` or `:generation_config` takes
  precedence, including when its value is `nil`.

  With `stream: true`, returns `{:ok, stream}` unchanged. The stream yields
  `Gemini.Types.Interactions.Events.InteractionSSEEvent` variants.
  """
  @spec generate(String.t() | list(), keyword()) ::
          {:ok, VideoContent.t() | Enumerable.t()} | {:error, term()}
  def generate(prompt, opts \\ []) when is_list(opts) do
    case generate_interaction(prompt, opts) do
      {:ok, %Interaction{} = interaction} -> Interaction.output_video(interaction)
      {:ok, stream} -> {:ok, stream}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Generate a video and return the whole interaction.

  Use this to retain the interaction id for conversational editing. With
  `stream: true`, returns `{:ok, stream}` directly from
  `Gemini.APIs.Interactions.create/2`.
  """
  @spec generate_interaction(String.t() | list(), keyword()) ::
          {:ok, Interaction.t() | Enumerable.t()} | {:error, term()}
  def generate_interaction(prompt, opts \\ []) when is_list(opts) do
    Interactions.create(normalize_input(prompt), build_opts(opts))
  end

  defp normalize_input(prompt) when is_binary(prompt),
    do: %TextContent{type: "text", text: prompt}

  defp normalize_input(input), do: input

  defp build_opts(opts) do
    {format_opts, rest} = Keyword.split(opts, @format_keys)
    {task, rest} = Keyword.pop(rest, :task)

    rest
    |> put_response_format(format_opts)
    |> put_video_config(task)
  end

  defp put_response_format(opts, format_opts) do
    if Keyword.has_key?(opts, :response_format) do
      opts
    else
      Keyword.put(opts, :response_format, struct(ResponseFormat.Video, format_opts))
    end
  end

  defp put_video_config(opts, nil), do: opts

  defp put_video_config(opts, task) do
    if Keyword.has_key?(opts, :generation_config) do
      opts
    else
      Keyword.put(opts, :generation_config, %GenerationConfig{
        video_config: %VideoConfig{task: task}
      })
    end
  end
end
