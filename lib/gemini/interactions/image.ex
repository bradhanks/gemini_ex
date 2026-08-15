defmodule Gemini.Interactions.Image do
  @moduledoc """
  Image generation and editing through the Interactions API.

  <https://ai.google.dev/gemini-api/docs/image-generation>

  ## Examples

      {:ok, image} =
        Gemini.Interactions.Image.generate("a nano banana in a fancy restaurant",
          model: "gemini-3.1-flash-image",
          aspect_ratio: "16:9",
          image_size: "2K"
        )

      File.write!("out.png", Base.decode64!(image.data))

  Editing continues from an uploaded image. Pass the `uri` field of the uploaded
  file, not its `name`: the API rejects a bare resource name such as
  `"files/abc123"` with `Unsupported file URI type`.

      {:ok, file} = Gemini.APIs.Files.upload("banana.jpg", auth: :gemini)

      {:ok, edited} =
        Gemini.Interactions.Image.edit("give it a chef's hat",
          {:uri, file.uri, "image/jpeg"},
          model: "gemini-3.1-flash-image"
        )

  Or from a previous interaction, which needs no image argument:

      {:ok, edited} =
        Gemini.Interactions.Image.edit("now make it blue", nil,
          model: "gemini-3.1-flash-image",
          previous_interaction_id: interaction.id
        )
  """

  alias Gemini.APIs.Interactions
  alias Gemini.Error
  alias Gemini.Interactions.Text
  alias Gemini.Types.Interactions.{ImageContent, Interaction, ResponseFormat, TextContent}

  @format_keys [:aspect_ratio, :image_size, :mime_type]

  @type image_input ::
          ImageContent.t()
          | {:uri, String.t(), String.t()}
          | {:data, String.t(), String.t()}
          | nil

  @doc """
  Generate an image and return its content block.

  Options `:aspect_ratio`, `:image_size`, and `:mime_type` build an image
  `response_format` when no `:response_format` was supplied. See
  `Gemini.Types.Interactions.ResponseFormat.Image` for documented values. All
  other options go to `Gemini.APIs.Interactions.create/2`, with
  generation-config options folded in as they are for
  `Gemini.Interactions.Text.generate/2`.

  With the default non-streaming request, returns `{:ok, image}` or
  `{:error, :not_found}` when the completed interaction carries no image. With
  `stream: true`, returns `{:ok, stream}` unchanged; the stream yields
  `Gemini.Types.Interactions.Events.InteractionSSEEvent` variants.
  """
  @spec generate(String.t(), keyword()) ::
          {:ok, ImageContent.t() | Enumerable.t()} | {:error, term()}
  def generate(prompt, opts \\ []) when is_binary(prompt) and is_list(opts) do
    case generate_interaction(prompt, opts) do
      {:ok, %Interaction{} = interaction} -> Interaction.output_image(interaction)
      {:ok, stream} -> {:ok, stream}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Generate an image and return the whole interaction.

  Use this for interleaved text and image output, for the thought summary, or
  to capture the interaction id for a follow-up `edit/3`. With `stream: true`,
  returns `{:ok, stream}` instead, where `stream` yields
  `Gemini.Types.Interactions.Events.InteractionSSEEvent` variants.
  """
  @spec generate_interaction(String.t(), keyword()) ::
          {:ok, Interaction.t() | Enumerable.t()} | {:error, term()}
  def generate_interaction(prompt, opts \\ []) when is_binary(prompt) and is_list(opts) do
    Interactions.create(%TextContent{type: "text", text: prompt}, build_opts(opts))
  end

  @doc """
  Edit an image and return its content block.

  Pass the source image as an `ImageContent` struct, `{:uri, uri, mime_type}`
  tuple, or `{:data, base64, mime_type}` tuple. To continue a stored
  interaction, pass `nil` and a non-empty `previous_interaction_id:`.

  A URI must be fully qualified — for an uploaded file that is its `uri` field,
  not its `name`. A bare resource name such as `"files/abc123"` fails with
  `Unsupported file URI type`.

  With the default non-streaming request, returns `{:ok, image}` or
  `{:error, :not_found}` when the completed interaction carries no image. With
  `stream: true`, returns `{:ok, stream}` unchanged; the stream yields
  `Gemini.Types.Interactions.Events.InteractionSSEEvent` variants.
  """
  @spec edit(String.t(), image_input(), keyword()) ::
          {:ok, ImageContent.t() | Enumerable.t()} | {:error, term()}
  def edit(prompt, image, opts \\ [])

  def edit(prompt, %ImageContent{} = image, opts) when is_binary(prompt) and is_list(opts) do
    create_image_edit([image, %TextContent{type: "text", text: prompt}], opts)
  end

  def edit(prompt, {:uri, uri, mime_type}, opts)
      when is_binary(prompt) and is_binary(uri) and is_binary(mime_type) and is_list(opts) do
    create_image_edit(
      [
        %ImageContent{type: "image", uri: uri, mime_type: mime_type},
        %TextContent{type: "text", text: prompt}
      ],
      opts
    )
  end

  def edit(prompt, {:data, data, mime_type}, opts)
      when is_binary(prompt) and is_binary(data) and is_binary(mime_type) and is_list(opts) do
    create_image_edit(
      [
        %ImageContent{type: "image", data: data, mime_type: mime_type},
        %TextContent{type: "text", text: prompt}
      ],
      opts
    )
  end

  def edit(prompt, nil, opts) when is_binary(prompt) and is_list(opts) do
    case Keyword.get(opts, :previous_interaction_id) do
      interaction_id when is_binary(interaction_id) and byte_size(interaction_id) > 0 ->
        create_image_edit([%TextContent{type: "text", text: prompt}], opts)

      _other ->
        {:error,
         Error.validation_error(
           "nil image input requires a non-empty :previous_interaction_id option"
         )}
    end
  end

  defp create_image_edit(input, opts) do
    case Interactions.create(input, build_opts(opts)) do
      {:ok, %Interaction{} = interaction} -> Interaction.output_image(interaction)
      {:ok, stream} -> {:ok, stream}
      {:error, _reason} = error -> error
    end
  end

  defp build_opts(opts) do
    {format_opts, rest} = Keyword.split(opts, @format_keys)
    rest = Text.build_opts(rest)

    if Keyword.has_key?(rest, :response_format) do
      rest
    else
      Keyword.put(rest, :response_format, struct(ResponseFormat.Image, format_opts))
    end
  end
end
