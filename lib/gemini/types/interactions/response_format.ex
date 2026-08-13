defmodule Gemini.Types.Interactions.ResponseFormat.Text do
  @moduledoc """
  Text response format.

  Set `mime_type` to `"application/json"` and supply a `schema` for structured
  output.

  <https://ai.google.dev/gemini-api/docs/structured-output>
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "text")
    field(:mime_type, String.t())
    field(:schema, map())
  end

  @doc """
  Builds a text response format from an API map.
  """
  @spec from_api(t() | map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = format), do: format

  def from_api(%{} = data) do
    %__MODULE__{
      mime_type: Map.get(data, "mime_type"),
      schema: Map.get(data, "schema")
    }
  end

  @doc """
  Serializes a text response format for the API.
  """
  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = format) do
    %{"type" => "text"}
    |> maybe_put("mime_type", format.mime_type)
    |> maybe_put("schema", format.schema)
  end
end

defmodule Gemini.Types.Interactions.ResponseFormat.Image do
  @moduledoc """
  Image response format, used to request image generation.

  <https://ai.google.dev/gemini-api/docs/image-generation>
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @aspect_ratios ~w(1:1 3:2 2:3 3:4 4:3 4:5 5:4 9:16 16:9 21:9)
  @image_sizes ~w(512px 1K 2K 4K)

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "image")
    field(:mime_type, String.t())
    field(:aspect_ratio, String.t())
    field(:image_size, String.t())
  end

  @doc """
  Returns the documented image aspect ratios.

  Values are not enforced locally; the API performs validation.
  """
  @spec aspect_ratios() :: [String.t()]
  def aspect_ratios, do: @aspect_ratios

  @doc """
  Returns the documented image sizes.
  """
  @spec image_sizes() :: [String.t()]
  def image_sizes, do: @image_sizes

  @doc """
  Builds an image response format from an API map.
  """
  @spec from_api(t() | map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = format), do: format

  def from_api(%{} = data) do
    %__MODULE__{
      mime_type: Map.get(data, "mime_type"),
      aspect_ratio: Map.get(data, "aspect_ratio"),
      image_size: Map.get(data, "image_size")
    }
  end

  @doc """
  Serializes an image response format for the API.
  """
  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = format) do
    %{"type" => "image"}
    |> maybe_put("mime_type", format.mime_type)
    |> maybe_put("aspect_ratio", format.aspect_ratio)
    |> maybe_put("image_size", format.image_size)
  end
end

defmodule Gemini.Types.Interactions.ResponseFormat.Audio do
  @moduledoc """
  Audio response format, used to request speech generation.

  <https://ai.google.dev/gemini-api/docs/speech-generation>
  """

  use TypedStruct

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "audio")
  end

  @doc """
  Builds an audio response format from an API map.
  """
  @spec from_api(t() | map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = format), do: format
  def from_api(%{}), do: %__MODULE__{}

  @doc """
  Serializes an audio response format for the API.
  """
  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map
  def to_api(%__MODULE__{}), do: %{"type" => "audio"}
end

defmodule Gemini.Types.Interactions.ResponseFormat.Video do
  @moduledoc """
  Video response format, used to request video generation with Gemini Omni.

  Set `delivery` to `"uri"` for videos larger than 4 MB.

  <https://ai.google.dev/gemini-api/docs/omni>
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @aspect_ratios ~w(16:9 9:16)

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "video")
    field(:aspect_ratio, String.t())
    field(:delivery, String.t())
  end

  @doc """
  Returns the documented video aspect ratios.
  """
  @spec aspect_ratios() :: [String.t()]
  def aspect_ratios, do: @aspect_ratios

  @doc """
  Builds a video response format from an API map.
  """
  @spec from_api(t() | map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = format), do: format

  def from_api(%{} = data) do
    %__MODULE__{
      aspect_ratio: Map.get(data, "aspect_ratio"),
      delivery: Map.get(data, "delivery")
    }
  end

  @doc """
  Serializes a video response format for the API.
  """
  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = format) do
    %{"type" => "video"}
    |> maybe_put("aspect_ratio", format.aspect_ratio)
    |> maybe_put("delivery", format.delivery)
  end
end

defmodule Gemini.Types.Interactions.ResponseFormat.JsonSchema do
  @moduledoc """
  The `json_schema` response format from the Interactions API reference.

  <https://ai.google.dev/api/interactions-api>
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "json_schema")
    field(:name, String.t())
    field(:schema, map())
    field(:strict, boolean())
  end

  @doc """
  Builds a JSON Schema response format from an API map.
  """
  @spec from_api(t() | map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = format), do: format

  def from_api(%{} = data) do
    nested =
      case Map.get(data, "json_schema") do
        %{} = value -> value
        _ -> %{}
      end

    %__MODULE__{
      name: Map.get(nested, "name"),
      schema: Map.get(nested, "schema"),
      strict: Map.get(nested, "strict")
    }
  end

  @doc """
  Serializes a JSON Schema response format for the API.
  """
  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = format) do
    nested =
      %{}
      |> maybe_put("name", format.name)
      |> maybe_put("schema", format.schema)
      |> maybe_put("strict", format.strict)

    %{"type" => "json_schema"}
    |> maybe_put("json_schema", nested)
  end
end

defmodule Gemini.Types.Interactions.ResponseFormat.JsonObject do
  @moduledoc """
  The `json_object` response format from the Interactions API reference.
  """

  use TypedStruct

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "json_object")
  end

  @doc """
  Builds a JSON Object response format from an API map.
  """
  @spec from_api(t() | map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = format), do: format
  def from_api(%{}), do: %__MODULE__{}

  @doc """
  Serializes a JSON Object response format for the API.
  """
  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map
  def to_api(%__MODULE__{}), do: %{"type" => "json_object"}
end

defmodule Gemini.Types.Interactions.ResponseFormat do
  @moduledoc """
  Response format union for Interactions requests.

  The modality-typed shapes are `text`, `image`, `audio`, and `video`. The
  Interactions API reference additionally documents `json_schema` and
  `json_object`. Raw maps pass through untouched, which permits callers to use
  an API shape not yet modeled by this module. Lists are accepted and
  serialized elementwise.

  Sources:

  - <https://ai.google.dev/gemini-api/docs/structured-output>
  - <https://ai.google.dev/gemini-api/docs/image-generation>
  - <https://ai.google.dev/gemini-api/docs/speech-generation>
  - <https://ai.google.dev/api/interactions-api>
  """

  alias Gemini.Types.Interactions.ResponseFormat.{
    Audio,
    Image,
    JsonObject,
    JsonSchema,
    Text,
    Video
  }

  @type t ::
          Text.t()
          | Image.t()
          | Audio.t()
          | Video.t()
          | JsonSchema.t()
          | JsonObject.t()
          | map()
          | [t()]

  @type_to_module %{
    "text" => Text,
    "image" => Image,
    "audio" => Audio,
    "video" => Video,
    "json_schema" => JsonSchema,
    "json_object" => JsonObject
  }

  @doc """
  Parses a response format received from the API.

  Known type-tagged maps become typed variants. Unknown maps and unmodeled
  values pass through unchanged.
  """
  @spec from_api(term()) :: term()
  def from_api(nil), do: nil
  def from_api(%_{} = format), do: format
  def from_api(list) when is_list(list), do: Enum.map(list, &from_api/1)

  def from_api(%{} = data) do
    case Map.get(@type_to_module, Map.get(data, "type")) do
      nil -> data
      module -> module.from_api(data)
    end
  end

  def from_api(other), do: other

  @doc """
  Serializes a response format for the API.

  Raw maps and unmodeled values pass through unchanged.
  """
  @spec to_api(term()) :: term()
  def to_api(nil), do: nil
  def to_api(list) when is_list(list), do: Enum.map(list, &to_api/1)
  def to_api(%{} = map) when not is_struct(map), do: map
  def to_api(%Text{} = format), do: Text.to_api(format)
  def to_api(%Image{} = format), do: Image.to_api(format)
  def to_api(%Audio{} = format), do: Audio.to_api(format)
  def to_api(%Video{} = format), do: Video.to_api(format)
  def to_api(%JsonSchema{} = format), do: JsonSchema.to_api(format)
  def to_api(%JsonObject{} = format), do: JsonObject.to_api(format)
  def to_api(other), do: other
end
