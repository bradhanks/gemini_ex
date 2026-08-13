defmodule Gemini.Types.Interactions.StandardStep do
  @moduledoc """
  A step in an Interactions response.

  Covers every step type whose shape is `{type, content, name, id}`, optionally
  carrying a thought signature and summary. See `Gemini.Types.Interactions.Step`
  for the full list of step types and for the two types that need their own
  structs.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Content

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t())
    field(:content, [Content.t()])
    field(:name, String.t())
    field(:id, String.t())
    field(:signature, String.t())
    field(:summary, [Content.t()])
  end

  @doc """
  Parses a standard response step from an API map.
  """
  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = step), do: step

  def from_api(%{} = data) do
    %__MODULE__{
      type: Map.get(data, "type"),
      content: parse_content_list(Map.get(data, "content")),
      name: Map.get(data, "name"),
      id: Map.get(data, "id"),
      signature: Map.get(data, "signature"),
      summary: parse_content_list(Map.get(data, "summary"))
    }
  end

  @doc """
  Serializes a standard response step for the API.
  """
  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = step) do
    %{}
    |> maybe_put("type", step.type)
    |> maybe_put("content", map_list(step.content, &Content.to_api/1))
    |> maybe_put("name", step.name)
    |> maybe_put("id", step.id)
    |> maybe_put("signature", step.signature)
    |> maybe_put("summary", map_list(step.summary, &Content.to_api/1))
  end

  defp map_list(nil, _fun), do: nil
  defp map_list(list, fun) when is_list(list), do: Enum.map(list, fun)

  defp parse_content_list(nil), do: nil

  defp parse_content_list(list) when is_list(list) do
    list
    |> Enum.map(&Content.from_api/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_content_list(_), do: nil
end

defmodule Gemini.Types.Interactions.FunctionCallStep do
  @moduledoc """
  A `function_call` step. Adds `arguments` to the standard step shape.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Content

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "function_call")
    field(:content, [Content.t()])
    field(:name, String.t())
    field(:id, String.t())
    field(:arguments, map())
  end

  @doc """
  Parses a function-call step from an API map.
  """
  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = step), do: step

  def from_api(%{} = data) do
    %__MODULE__{
      type: Map.get(data, "type") || "function_call",
      content: parse_content_list(Map.get(data, "content")),
      name: Map.get(data, "name"),
      id: Map.get(data, "id"),
      arguments: Map.get(data, "arguments")
    }
  end

  @doc """
  Serializes a function-call step for the API.
  """
  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = step) do
    %{"type" => "function_call"}
    |> maybe_put("content", map_list(step.content, &Content.to_api/1))
    |> maybe_put("name", step.name)
    |> maybe_put("id", step.id)
    |> maybe_put("arguments", step.arguments)
  end

  defp map_list(nil, _fun), do: nil
  defp map_list(list, fun) when is_list(list), do: Enum.map(list, fun)

  defp parse_content_list(nil), do: nil

  defp parse_content_list(list) when is_list(list) do
    list
    |> Enum.map(&Content.from_api/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_content_list(_), do: nil
end

defmodule Gemini.Types.Interactions.FunctionResultStep do
  @moduledoc """
  A `function_result` step. Uses `call_id` to link back to its `function_call`.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Content

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "function_result")
    field(:content, [Content.t()])
    field(:name, String.t())
    field(:call_id, String.t())
    field(:signature, String.t())
  end

  @doc """
  Parses a function-result step from an API map.
  """
  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = step), do: step

  def from_api(%{} = data) do
    %__MODULE__{
      type: Map.get(data, "type") || "function_result",
      content: parse_content_list(Map.get(data, "content")),
      name: Map.get(data, "name"),
      call_id: Map.get(data, "call_id"),
      signature: Map.get(data, "signature")
    }
  end

  @doc """
  Serializes a function-result step for the API.
  """
  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = step) do
    %{"type" => "function_result"}
    |> maybe_put("content", map_list(step.content, &Content.to_api/1))
    |> maybe_put("name", step.name)
    |> maybe_put("call_id", step.call_id)
    |> maybe_put("signature", step.signature)
  end

  defp map_list(nil, _fun), do: nil
  defp map_list(list, fun) when is_list(list), do: Enum.map(list, fun)

  defp parse_content_list(nil), do: nil

  defp parse_content_list(list) when is_list(list) do
    list
    |> Enum.map(&Content.from_api/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_content_list(_), do: nil
end

defmodule Gemini.Types.Interactions.UnknownStep do
  @moduledoc """
  A step whose `type` this library does not model.

  Retains the original map verbatim so forward-compatible step types survive a
  `from_api/1` and `to_api/1` round trip without losing data.
  """

  use TypedStruct

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t())
    field(:raw, map())
  end

  @doc """
  Parses an unknown response step while retaining its raw API map.
  """
  @spec from_api(map() | t() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = step), do: step
  def from_api(%{} = data), do: %__MODULE__{type: Map.get(data, "type"), raw: data}

  @doc """
  Serializes an unknown response step using its preserved raw API map.
  """
  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map
  def to_api(%__MODULE__{raw: raw}), do: raw
end

defmodule Gemini.Types.Interactions.Step do
  @moduledoc """
  Step union for Interactions responses.

  An interaction's `steps` array is the authoritative record of what happened
  during a turn. Standard API step types parse into
  `Gemini.Types.Interactions.StandardStep`; `function_call` and
  `function_result` use dedicated structs. Unrecognized types parse into
  `Gemini.Types.Interactions.UnknownStep`, retaining their raw map.
  """

  alias Gemini.Types.Interactions.{
    Content,
    FunctionCallStep,
    FunctionResultStep,
    StandardStep,
    UnknownStep
  }

  @type t :: StandardStep.t() | FunctionCallStep.t() | FunctionResultStep.t() | UnknownStep.t()

  @standard_types ~w(
    user_input
    model_output
    thought
    code_execution
    code_execution_result
    file_search_call
    file_search_result
    google_search_call
    google_search_result
    google_maps_call
    google_maps_result
    retrieval_call
    retrieval_result
    url_context_call
    url_context_result
    mcp_server_tool_call
    mcp_server_tool_result
    computer_use
  )

  @doc """
  Step types that parse into `Gemini.Types.Interactions.StandardStep`.
  """
  @spec standard_types() :: [String.t()]
  def standard_types, do: @standard_types

  @doc """
  Parses an API response step into its typed representation.
  """
  @spec from_api(term()) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%StandardStep{} = step), do: step
  def from_api(%FunctionCallStep{} = step), do: step
  def from_api(%FunctionResultStep{} = step), do: step
  def from_api(%UnknownStep{} = step), do: step
  def from_api(%_{}), do: nil

  def from_api(%{} = data) do
    case Map.get(data, "type") do
      "function_call" -> FunctionCallStep.from_api(data)
      "function_result" -> FunctionResultStep.from_api(data)
      type when type in @standard_types -> StandardStep.from_api(data)
      _ -> UnknownStep.from_api(data)
    end
  end

  def from_api(_), do: nil

  @doc """
  Serializes a response step for the API.
  """
  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map
  def to_api(%StandardStep{} = step), do: StandardStep.to_api(step)
  def to_api(%FunctionCallStep{} = step), do: FunctionCallStep.to_api(step)
  def to_api(%FunctionResultStep{} = step), do: FunctionResultStep.to_api(step)
  def to_api(%UnknownStep{} = step), do: UnknownStep.to_api(step)

  @doc """
  Recognized, typed content blocks carried by a step. Returns `[]` when the
  step has none and excludes malformed or unrecognized blocks.
  """
  @spec content(t()) :: [Gemini.Types.Interactions.Content.t()]
  def content(%UnknownStep{raw: raw}) when is_map(raw),
    do: parse_content_list(Map.get(raw, "content"))

  def content(%{content: content}), do: parse_content_list(content)
  def content(_), do: []

  @doc """
  Thought signature carried by a step, or `nil`.
  """
  @spec signature(t()) :: String.t() | nil
  def signature(%UnknownStep{raw: raw}), do: Map.get(raw, "signature")
  def signature(%{signature: signature}), do: signature
  def signature(_), do: nil

  defp parse_content_list(list) when is_list(list) do
    list
    |> Enum.map(&Content.from_api/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_content_list(_), do: []
end
