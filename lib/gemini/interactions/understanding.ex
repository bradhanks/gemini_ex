defmodule Gemini.Interactions.Understanding do
  @moduledoc """
  Image, video, audio, and document understanding through the Interactions API.

  - <https://ai.google.dev/gemini-api/docs/image-understanding>
  - <https://ai.google.dev/gemini-api/docs/video-understanding>
  - <https://ai.google.dev/gemini-api/docs/audio>
  - <https://ai.google.dev/gemini-api/docs/document-processing>

  Media is placed before the prompt, matching the documented API examples.

  Media URIs must be fully qualified. For an uploaded file that is the `uri`
  field, not the `name`: the API rejects a bare resource name such as
  `"files/abc123"` with `Unsupported file URI type`.

  ## Examples

      {:ok, file} = Gemini.APIs.Files.upload("photo.jpg", auth: :gemini)

      {:ok, text} =
        Gemini.Interactions.Understanding.analyze(
          "What is in this image?",
          [{:image, {:uri, file.uri}, "image/jpeg"}],
          model: "gemini-3.6-flash"
        )

  A bare string is treated as a URI, including for YouTube URLs:

      {:ok, summary} =
        Gemini.Interactions.Understanding.analyze(
          "Summarize this video",
          [{:video, "https://www.youtube.com/watch?v=9hE5-98ZeCg", nil}],
          model: "gemini-3.6-flash"
        )

  Structured extraction uses a text response format:

      schema = %{
        "type" => "object",
        "properties" => %{
          "boxes" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "box_2d" => %{"type" => "array", "items" => %{"type" => "integer"}},
                "label" => %{"type" => "string"}
              }
            }
          }
        }
      }

      {:ok, json} =
        Gemini.Interactions.Understanding.analyze(
          "Detect all objects",
          [{:image, {:uri, file.uri}, "image/jpeg"}],
          model: "gemini-3.6-flash",
          response_format: %Gemini.Types.Interactions.ResponseFormat.Text{
            mime_type: "application/json",
            schema: schema
          }
        )
  """

  alias Gemini.APIs.Interactions
  alias Gemini.Error
  alias Gemini.Interactions.Text

  alias Gemini.Types.Interactions.{
    AudioContent,
    DocumentContent,
    ImageContent,
    Interaction,
    TextContent,
    VideoContent
  }

  @type source :: {:uri, String.t()} | {:data, String.t()} | String.t()

  @type media_content ::
          ImageContent.t() | VideoContent.t() | AudioContent.t() | DocumentContent.t()

  @type media ::
          {:image | :video | :audio | :document, source(), String.t() | nil} | media_content()

  @kind_to_module %{
    image: ImageContent,
    video: VideoContent,
    audio: AudioContent,
    document: DocumentContent
  }

  @doc """
  Analyze media and return the model's text response.

  Media items may be content structs or `{kind, source, mime_type}` tuples.
  Sources accept `{:uri, uri}`, `{:data, base64}`, or a bare URI string.

  A URI must be fully qualified — a Files API URI
  (`"https://generativelanguage.googleapis.com/v1beta/files/abc123"`, which is
  the `uri` field of an uploaded file rather than its `name`), a YouTube watch
  URL, another HTTPS URL, or a `gs://` object. Passing a bare resource name
  such as `"files/abc123"` fails with `Unsupported file URI type`.

  `:resolution` sets the per-content-item media resolution on every image,
  video, and document block, including caller-supplied structs. It is not sent
  on audio blocks. Resolution values are passed through without local enum
  validation. Note that the Gemini API currently rejects `resolution` on
  document blocks (`400 Unknown parameter 'resolution'`), so set it only when
  the media is images or video.

  With `stream: true`, returns `{:ok, stream}` unchanged. The stream yields
  `Gemini.Types.Interactions.Events.InteractionSSEEvent` variants.
  """
  @spec analyze(String.t(), [media()], keyword()) ::
          {:ok, String.t() | Enumerable.t()} | {:error, term()}
  def analyze(prompt, media, opts \\ [])
      when is_binary(prompt) and is_list(media) and is_list(opts) do
    case analyze_interaction(prompt, media, opts) do
      {:ok, %Interaction{} = interaction} -> Interaction.output_text(interaction)
      {:ok, stream} -> {:ok, stream}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Analyze media and return the whole interaction.

  With `stream: true`, returns `{:ok, stream}` directly from
  `Gemini.APIs.Interactions.create/2`.
  """
  @spec analyze_interaction(String.t(), [media()], keyword()) ::
          {:ok, Interaction.t() | Enumerable.t()} | {:error, term()}
  def analyze_interaction(prompt, media, opts \\ [])
      when is_binary(prompt) and is_list(media) and is_list(opts) do
    {resolution, opts} = Keyword.pop(opts, :resolution)

    with {:ok, content} <- build_media(media, resolution) do
      input = content ++ [%TextContent{type: "text", text: prompt}]
      Interactions.create(input, Text.build_opts(opts))
    end
  end

  @doc """
  Describe a single image.

  `:mime_type` sets the image MIME type. All remaining options are forwarded
  to `analyze/3`.
  """
  @spec describe_image(String.t(), source(), keyword()) ::
          {:ok, String.t() | Enumerable.t()} | {:error, term()}
  def describe_image(prompt, source, opts \\ []), do: single(:image, prompt, source, opts)

  @doc """
  Analyze a single video.

  Pass a YouTube URL as a bare string. `:mime_type` sets the video MIME type;
  all remaining options are forwarded to `analyze/3`.
  """
  @spec analyze_video(String.t(), source(), keyword()) ::
          {:ok, String.t() | Enumerable.t()} | {:error, term()}
  def analyze_video(prompt, source, opts \\ []), do: single(:video, prompt, source, opts)

  @doc """
  Transcribe or analyze a single audio file.

  `:mime_type` sets the audio MIME type. All remaining options are forwarded
  to `analyze/3`; `:resolution` is ignored for the audio content block.
  """
  @spec transcribe_audio(String.t(), source(), keyword()) ::
          {:ok, String.t() | Enumerable.t()} | {:error, term()}
  def transcribe_audio(prompt, source, opts \\ []), do: single(:audio, prompt, source, opts)

  @doc """
  Analyze a single document, typically a PDF.

  `:mime_type` sets the document MIME type. All remaining options are
  forwarded to `analyze/3`.
  """
  @spec analyze_document(String.t(), source(), keyword()) ::
          {:ok, String.t() | Enumerable.t()} | {:error, term()}
  def analyze_document(prompt, source, opts \\ []),
    do: single(:document, prompt, source, opts)

  defp single(kind, prompt, source, opts) when is_list(opts) do
    {mime_type, opts} = Keyword.pop(opts, :mime_type)
    analyze(prompt, [{kind, source, mime_type}], opts)
  end

  defp build_media(media, resolution) do
    media
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, content} ->
      case to_content(item, resolution) do
        {:ok, block} -> {:cont, {:ok, [block | content]}}
        {:error, %Error{} = error} -> {:halt, {:error, add_media_index(error, index)}}
      end
    end)
    |> case do
      {:ok, content} -> {:ok, Enum.reverse(content)}
      {:error, _reason} = error -> error
    end
  end

  defp to_content(%ImageContent{} = content, resolution),
    do: {:ok, put_resolution(content, resolution)}

  defp to_content(%VideoContent{} = content, resolution),
    do: {:ok, put_resolution(content, resolution)}

  defp to_content(%DocumentContent{} = content, resolution),
    do: {:ok, put_resolution(content, resolution)}

  defp to_content(%AudioContent{} = content, _resolution), do: {:ok, content}

  defp to_content({kind, source, mime_type}, resolution) do
    with {:ok, module} <- media_module(kind),
         {:ok, source_fields} <- source_fields(source),
         :ok <- validate_mime_type(mime_type) do
      content =
        module
        |> struct(source_fields)
        |> put_if(:mime_type, mime_type)
        |> put_content_resolution(resolution)

      {:ok, content}
    end
  end

  defp to_content(item, _resolution) do
    {:error,
     Error.validation_error(
       "invalid media item #{inspect(item)}; expected a supported content struct or " <>
         "{kind, source, mime_type} tuple"
     )}
  end

  defp media_module(kind) do
    case Map.fetch(@kind_to_module, kind) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, Error.validation_error("unknown media kind #{inspect(kind)}")}
    end
  end

  defp source_fields({:uri, uri}) when is_binary(uri), do: {:ok, %{uri: uri}}
  defp source_fields({:data, data}) when is_binary(data), do: {:ok, %{data: data}}
  defp source_fields(uri) when is_binary(uri), do: {:ok, %{uri: uri}}

  defp source_fields(source) do
    {:error,
     Error.validation_error(
       "invalid media source #{inspect(source)}; expected {:uri, uri}, {:data, base64}, " <>
         "or a bare URI string"
     )}
  end

  defp validate_mime_type(nil), do: :ok
  defp validate_mime_type(mime_type) when is_binary(mime_type), do: :ok

  defp validate_mime_type(mime_type) do
    {:error,
     Error.validation_error(
       "invalid media MIME type #{inspect(mime_type)}; expected a string or nil"
     )}
  end

  defp put_if(content, _key, nil), do: content
  defp put_if(content, key, value), do: Map.put(content, key, value)

  defp put_content_resolution(%AudioContent{} = content, _resolution), do: content
  defp put_content_resolution(content, resolution), do: put_resolution(content, resolution)

  defp put_resolution(content, nil), do: content
  defp put_resolution(content, resolution), do: %{content | resolution: resolution}

  defp add_media_index(%Error{} = error, index) do
    %{error | message: "media item at index #{index}: #{error.message}"}
  end
end
