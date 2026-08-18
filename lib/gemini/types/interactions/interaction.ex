defmodule Gemini.Types.Interactions.Interaction do
  @moduledoc """
  Interactions `Interaction` resource.

  JSON keys are snake_case, matching the Interactions API.

  `steps` is the authoritative record of a turn. `outputs` is retained for
  backward compatibility and is derived by flattening each step's content in
  order when the response carries `steps`.

  Documented `status` values are `in_progress`, `requires_action`, `completed`,
  `failed`, `cancelled`, `incomplete`, `budget_exceeded`, and `queued`. The
  field stays a plain string so a new server-side status does not break parsing.

  Reference: <https://ai.google.dev/api/interactions-api>
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.{
    AudioContent,
    Content,
    ImageContent,
    Step,
    TextContent,
    Usage,
    VideoContent
  }

  @type status :: String.t()

  @terminal_statuses ~w(requires_action completed failed cancelled incomplete budget_exceeded)
  @statuses ~w(queued in_progress) ++ @terminal_statuses

  @derive Jason.Encoder
  typedstruct enforce: true do
    field(:id, String.t())
    field(:status, status())
    field(:object, String.t(), enforce: false)
    field(:agent, String.t(), enforce: false)
    field(:agent_config, map(), enforce: false)
    field(:created, DateTime.t(), enforce: false)
    field(:environment, term(), enforce: false)
    field(:environment_id, String.t(), enforce: false)
    field(:error, map(), enforce: false)
    field(:generation_config, map(), enforce: false)
    field(:input, term(), enforce: false)
    field(:labels, map(), enforce: false)
    field(:model, String.t(), enforce: false)
    field(:output_audio, AudioContent.t(), enforce: false)
    field(:output_image, ImageContent.t(), enforce: false)
    field(:output_text, String.t(), enforce: false)
    field(:output_video, VideoContent.t(), enforce: false)
    field(:outputs, [Content.t()], enforce: false)
    field(:previous_interaction_id, String.t(), enforce: false)
    field(:response_format, term(), enforce: false)
    field(:role, String.t(), enforce: false)
    field(:safety_settings, list(), enforce: false)
    field(:service_tier, String.t(), enforce: false)
    field(:steps, [Step.t()], enforce: false)
    field(:system_instruction, String.t(), enforce: false)
    field(:tools, list(), enforce: false)
    field(:updated, DateTime.t(), enforce: false)
    field(:usage, Usage.t(), enforce: false)
    field(:user_metadata, map(), enforce: false)
    field(:webhook_config, map(), enforce: false)
  end

  @doc """
  The documented `status` values, in lifecycle order.

  The `status` field itself stays a plain string, so a status the server adds
  later still parses; this list is the vocabulary the library models today and
  is the single source for `terminal_statuses/0`, for
  `Gemini.APIs.Interactions.wait_for_completion/2`'s stop condition, and for the
  `interaction.<status>` SSE event spellings in
  `Gemini.Types.Interactions.Events.InteractionSSEEvent`.
  """
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc """
  The statuses at which an interaction stops advancing.

  A poller may stop, and a stream consumer may treat the turn as finished.
  """
  @spec terminal_statuses() :: [status()]
  def terminal_statuses, do: @terminal_statuses

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = interaction), do: interaction

  def from_api(%{} = data) do
    steps = parse_steps(Map.get(data, "steps"))

    %__MODULE__{
      id: Map.get(data, "id"),
      status: Map.get(data, "status"),
      object: Map.get(data, "object"),
      agent: Map.get(data, "agent"),
      agent_config: Map.get(data, "agent_config"),
      created: parse_datetime(Map.get(data, "created")),
      environment: Map.get(data, "environment"),
      environment_id: Map.get(data, "environment_id"),
      error: Map.get(data, "error"),
      generation_config: Map.get(data, "generation_config"),
      input: Map.get(data, "input"),
      labels: Map.get(data, "labels"),
      model: Map.get(data, "model"),
      output_audio: Content.from_api(Map.get(data, "output_audio")),
      output_image: Content.from_api(Map.get(data, "output_image")),
      output_text: Map.get(data, "output_text"),
      output_video: Content.from_api(Map.get(data, "output_video")),
      outputs: parse_outputs(Map.get(data, "outputs"), steps),
      previous_interaction_id: Map.get(data, "previous_interaction_id"),
      response_format: Map.get(data, "response_format"),
      role: Map.get(data, "role"),
      safety_settings: Map.get(data, "safety_settings"),
      service_tier: Map.get(data, "service_tier"),
      steps: steps,
      system_instruction: Map.get(data, "system_instruction"),
      tools: Map.get(data, "tools"),
      updated: parse_datetime(Map.get(data, "updated")),
      usage: Usage.from_api(Map.get(data, "usage")),
      user_metadata: Map.get(data, "user_metadata"),
      webhook_config: Map.get(data, "webhook_config")
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = interaction) do
    %{}
    |> maybe_put("id", interaction.id)
    |> maybe_put("status", interaction.status)
    |> maybe_put("object", interaction.object)
    |> maybe_put("agent", interaction.agent)
    |> maybe_put("agent_config", interaction.agent_config)
    |> maybe_put("created", datetime_to_iso8601(interaction.created))
    |> maybe_put("environment", interaction.environment)
    |> maybe_put("environment_id", interaction.environment_id)
    |> maybe_put("error", interaction.error)
    |> maybe_put("generation_config", interaction.generation_config)
    |> maybe_put("input", interaction.input)
    |> maybe_put("labels", interaction.labels)
    |> maybe_put("model", interaction.model)
    |> maybe_put("output_audio", Content.to_api(interaction.output_audio))
    |> maybe_put("output_image", Content.to_api(interaction.output_image))
    |> maybe_put("output_text", interaction.output_text)
    |> maybe_put("output_video", Content.to_api(interaction.output_video))
    |> maybe_put("outputs", map_list(interaction.outputs, &Content.to_api/1))
    |> maybe_put("previous_interaction_id", interaction.previous_interaction_id)
    |> maybe_put("response_format", interaction.response_format)
    |> maybe_put("role", interaction.role)
    |> maybe_put("safety_settings", interaction.safety_settings)
    |> maybe_put("service_tier", interaction.service_tier)
    |> maybe_put("steps", map_list(interaction.steps, &Step.to_api/1))
    |> maybe_put("system_instruction", interaction.system_instruction)
    |> maybe_put("tools", interaction.tools)
    |> maybe_put("updated", datetime_to_iso8601(interaction.updated))
    |> maybe_put("usage", Usage.to_api(interaction.usage))
    |> maybe_put("user_metadata", interaction.user_metadata)
    |> maybe_put("webhook_config", interaction.webhook_config)
  end

  @doc """
  Text output of the interaction.

  Returns the server-provided `output_text` when present. Otherwise, it returns
  the concatenated text of the last `model_output` step when `steps` are
  present, or text in legacy `outputs` when `steps` are absent.
  """
  @spec output_text(t()) :: {:ok, String.t()} | {:error, :not_found}
  def output_text(%__MODULE__{output_text: text}) when is_binary(text),
    do: {:ok, text}

  def output_text(%__MODULE__{} = interaction) do
    interaction
    |> last_model_output_text()
    |> case do
      nil -> {:error, :not_found}
      text -> {:ok, text}
    end
  end

  @doc """
  Same as `output_text/1`, under a name that cannot be confused with the
  `:output_text` struct field.

  The field is only what the server chose to set — routinely `nil` even when
  the interaction produced text, because the text lives in `steps`. This
  function (like `output_text/1`) falls back to the last `model_output` step.
  Prefer it in code where the field/function ambiguity could mislead a reader.
  """
  @spec output_text_fn(t()) :: {:ok, String.t()} | {:error, :not_found}
  def output_text_fn(%__MODULE__{} = interaction), do: output_text(interaction)

  @doc """
  Last image block produced by the interaction.
  """
  @spec output_image(t()) :: {:ok, ImageContent.t()} | {:error, :not_found}
  def output_image(%__MODULE__{output_image: %ImageContent{} = image}), do: {:ok, image}
  def output_image(%__MODULE__{} = interaction), do: last_block(interaction, ImageContent)

  @doc """
  Last audio block produced by the interaction.
  """
  @spec output_audio(t()) :: {:ok, AudioContent.t()} | {:error, :not_found}
  def output_audio(%__MODULE__{output_audio: %AudioContent{} = audio}), do: {:ok, audio}
  def output_audio(%__MODULE__{} = interaction), do: last_block(interaction, AudioContent)

  @doc """
  Last video block produced by the interaction.
  """
  @spec output_video(t()) :: {:ok, VideoContent.t()} | {:error, :not_found}
  def output_video(%__MODULE__{output_video: %VideoContent{} = video}), do: {:ok, video}
  def output_video(%__MODULE__{} = interaction), do: last_block(interaction, VideoContent)

  @doc """
  Every thought signature in the interaction, in step order.

  In stateless mode (`store: false`) these must be resent byte-identically on
  the following turn. See <https://ai.google.dev/gemini-api/docs/thinking>.
  """
  @spec thought_signatures(t()) :: [String.t()]
  def thought_signatures(%__MODULE__{steps: nil}), do: []

  def thought_signatures(%__MODULE__{steps: steps}) when is_list(steps) do
    steps
    |> Enum.map(&Step.signature/1)
    |> Enum.filter(&is_binary/1)
  end

  def thought_signatures(_), do: []

  defp parse_outputs(_outputs, steps) when is_list(steps),
    do: Enum.flat_map(steps, &Step.content/1)

  defp parse_outputs(nil, nil), do: nil

  defp parse_outputs(outputs, nil) when is_list(outputs) do
    outputs
    |> Enum.map(&Content.from_api/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_outputs(_outputs, nil), do: nil

  defp last_model_output_text(%__MODULE__{steps: steps}) when is_list(steps) do
    steps
    |> Enum.filter(&(step_type(&1) == "model_output"))
    |> List.last()
    |> case do
      nil -> nil
      step -> text_of(Step.content(step))
    end
  end

  defp last_model_output_text(%__MODULE__{outputs: outputs}) when is_list(outputs),
    do: text_of(outputs)

  defp last_model_output_text(_), do: nil

  defp text_of(blocks) when is_list(blocks) do
    blocks
    |> Enum.flat_map(fn
      %TextContent{text: text} when is_binary(text) -> [text]
      _ -> []
    end)
    |> Enum.join()
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp text_of(_), do: nil

  defp step_type(%{type: type}), do: type
  defp step_type(_), do: nil

  defp last_block(%__MODULE__{} = interaction, module) do
    interaction
    |> all_blocks()
    |> Enum.filter(&is_struct(&1, module))
    |> List.last()
    |> case do
      nil -> {:error, :not_found}
      block -> {:ok, block}
    end
  end

  defp all_blocks(%__MODULE__{steps: steps}) when is_list(steps),
    do: Enum.flat_map(steps, &Step.content/1)

  defp all_blocks(%__MODULE__{outputs: outputs}) when is_list(outputs), do: outputs
  defp all_blocks(_), do: []

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp datetime_to_iso8601(nil), do: nil
  defp datetime_to_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp parse_steps(nil), do: nil

  defp parse_steps(steps) when is_list(steps) do
    steps
    |> Enum.map(&Step.from_api/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_steps(_), do: nil

  defp map_list(nil, _fun), do: nil

  defp map_list(list, fun) when is_list(list) do
    Enum.map(list, fun)
  end

  defp map_list(_, _fun), do: nil
end

defmodule Gemini.Types.Interactions.Turn do
  @moduledoc """
  A conversation turn in the Interactions API.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Content

  @type content :: String.t() | [Content.t()] | nil

  @derive Jason.Encoder
  typedstruct do
    field(:role, String.t())
    field(:content, content())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = turn), do: turn

  def from_api(%{} = data) do
    %__MODULE__{
      role: Map.get(data, "role"),
      content: parse_content(Map.get(data, "content"))
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = turn) do
    %{}
    |> maybe_put("role", turn.role)
    |> maybe_put("content", serialize_content(turn.content))
  end

  defp parse_content(nil), do: nil
  defp parse_content(value) when is_binary(value), do: value

  defp parse_content(value) when is_list(value) do
    Enum.map(value, &Content.from_api/1)
  end

  defp parse_content(_), do: nil

  defp serialize_content(nil), do: nil
  defp serialize_content(value) when is_binary(value), do: value

  defp serialize_content(value) when is_list(value) do
    Enum.map(value, &Content.to_api/1)
  end
end

defmodule Gemini.Types.Interactions.Input do
  @moduledoc """
  Input union for Interactions `create`.

  Mirrors Python:
  - string
  - single content block
  - list of content blocks
  - list of turns
  """

  alias Gemini.Types.Interactions.{Content, Turn}

  @type t ::
          String.t()
          | Content.t()
          | [Content.t()]
          | [Turn.t()]
          | map()
          | [map()]

  @spec to_api(t()) :: term()
  def to_api(value) when is_binary(value), do: value
  def to_api(%Turn{} = turn), do: Turn.to_api(turn)
  def to_api(%_{} = content), do: Content.to_api(content)
  def to_api(%{} = map), do: map

  def to_api(list) when is_list(list) do
    case list do
      [%Turn{} | _] -> Enum.map(list, &Turn.to_api/1)
      [%_{} | _] -> Enum.map(list, &Content.to_api/1)
      [%{} | _] -> list
      _ -> list
    end
  end

  def to_api(other), do: other
end
