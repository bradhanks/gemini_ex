defmodule Gemini.Types.Interactions.Events.Error do
  @moduledoc """
  Error payload inside an Interactions SSE `error` event.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @derive Jason.Encoder
  typedstruct do
    field(:code, String.t())
    field(:message, String.t())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = err), do: err

  def from_api(%{} = data) do
    %__MODULE__{
      code: Map.get(data, "code"),
      message: Map.get(data, "message")
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = err) do
    %{}
    |> maybe_put("code", err.code)
    |> maybe_put("message", err.message)
  end
end

defmodule Gemini.Types.Interactions.Events.ErrorEvent do
  @moduledoc """
  Interactions SSE event: `event_type: "error"`.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Events.Error

  @derive Jason.Encoder
  typedstruct do
    field(:event_id, String.t())
    field(:event_type, String.t())
    field(:error, Error.t())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = event), do: event

  def from_api(%{} = data) do
    %__MODULE__{
      event_id: Map.get(data, "event_id"),
      event_type: Map.get(data, "event_type"),
      error: Error.from_api(Map.get(data, "error"))
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = event) do
    %{"event_type" => "error"}
    |> maybe_put("event_id", event.event_id)
    |> maybe_put("error", Error.to_api(event.error))
  end
end

defmodule Gemini.Types.Interactions.Events.InteractionEvent do
  @moduledoc """
  Interactions SSE event: `interaction.created` or `interaction.completed`.

  The legacy `interaction.start` and `interaction.complete` spellings are also
  supported.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Interaction

  @type event_type :: String.t()

  @derive Jason.Encoder
  typedstruct do
    field(:event_id, String.t())
    field(:event_type, event_type())
    field(:interaction, Interaction.t())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = event), do: event

  def from_api(%{} = data) do
    %__MODULE__{
      event_id: Map.get(data, "event_id"),
      event_type: Map.get(data, "event_type"),
      interaction: Interaction.from_api(Map.get(data, "interaction"))
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = event) do
    %{}
    |> maybe_put("event_id", event.event_id)
    |> maybe_put("event_type", event.event_type)
    |> maybe_put("interaction", Interaction.to_api(event.interaction))
  end
end

defmodule Gemini.Types.Interactions.Events.InteractionStatusUpdate do
  @moduledoc """
  Interactions SSE event: `interaction.status_update`.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Interaction

  @derive Jason.Encoder
  typedstruct do
    field(:event_id, String.t())
    field(:event_type, String.t())
    field(:interaction_id, String.t())
    field(:status, Interaction.status())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = event), do: event

  def from_api(%{} = data) do
    %__MODULE__{
      event_id: Map.get(data, "event_id"),
      event_type: Map.get(data, "event_type"),
      interaction_id: Map.get(data, "interaction_id"),
      status: Map.get(data, "status")
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = event) do
    %{"event_type" => "interaction.status_update"}
    |> maybe_put("event_id", event.event_id)
    |> maybe_put("interaction_id", event.interaction_id)
    |> maybe_put("status", event.status)
  end
end

defmodule Gemini.Types.Interactions.Events.ContentStart do
  @moduledoc """
  Interactions SSE event: `content.start`.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Content

  @derive Jason.Encoder
  typedstruct do
    field(:event_id, String.t())
    field(:event_type, String.t())
    field(:index, non_neg_integer())
    field(:content, Content.t())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = event), do: event

  def from_api(%{} = data) do
    %__MODULE__{
      event_id: Map.get(data, "event_id"),
      event_type: Map.get(data, "event_type"),
      index: Map.get(data, "index"),
      content: Content.from_api(Map.get(data, "content"))
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = event) do
    %{"event_type" => "content.start"}
    |> maybe_put("event_id", event.event_id)
    |> maybe_put("index", event.index)
    |> maybe_put("content", Content.to_api(event.content))
  end
end

defmodule Gemini.Types.Interactions.Events.ContentDelta do
  @moduledoc """
  Interactions SSE event: `content.delta`.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Delta

  @derive Jason.Encoder
  typedstruct do
    field(:event_id, String.t())
    field(:event_type, String.t())
    field(:index, non_neg_integer())
    field(:delta, Delta.t())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = event), do: event

  def from_api(%{} = data) do
    %__MODULE__{
      event_id: Map.get(data, "event_id"),
      event_type: Map.get(data, "event_type"),
      index: Map.get(data, "index"),
      delta: Delta.from_api(Map.get(data, "delta"))
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = event) do
    %{"event_type" => "content.delta"}
    |> maybe_put("event_id", event.event_id)
    |> maybe_put("index", event.index)
    |> maybe_put("delta", Delta.to_api(event.delta))
  end
end

defmodule Gemini.Types.Interactions.Events.ContentStop do
  @moduledoc """
  Interactions SSE event: `content.stop`.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @derive Jason.Encoder
  typedstruct do
    field(:event_id, String.t())
    field(:event_type, String.t())
    field(:index, non_neg_integer())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = event), do: event

  def from_api(%{} = data) do
    %__MODULE__{
      event_id: Map.get(data, "event_id"),
      event_type: Map.get(data, "event_type"),
      index: Map.get(data, "index")
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = event) do
    %{"event_type" => "content.stop"}
    |> maybe_put("event_id", event.event_id)
    |> maybe_put("index", event.index)
  end
end

defmodule Gemini.Types.Interactions.Events.StepStart do
  @moduledoc """
  Interactions SSE event: `step.start`.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Step

  @derive Jason.Encoder
  typedstruct do
    field(:event_id, String.t())
    field(:event_type, String.t())
    field(:index, non_neg_integer())
    field(:step, Step.t())
  end

  @spec from_api(map() | t() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = event), do: event

  def from_api(%{} = data) do
    %__MODULE__{
      event_id: Map.get(data, "event_id"),
      event_type: Map.get(data, "event_type"),
      index: Map.get(data, "index"),
      step: Step.from_api(Map.get(data, "step"))
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = event) do
    %{"event_type" => "step.start"}
    |> maybe_put("event_id", event.event_id)
    |> maybe_put("index", event.index)
    |> maybe_put("step", Step.to_api(event.step))
  end
end

defmodule Gemini.Types.Interactions.Events.StepDelta do
  @moduledoc """
  Interactions SSE event: `step.delta`.

  Carries one `Gemini.Types.Interactions.Delta` variant. Delta types include
  `text`, `thought_summary`, `thought_signature`, `audio`, `image`, `video`,
  and the tool call/result variants.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Delta

  @derive Jason.Encoder
  typedstruct do
    field(:event_id, String.t())
    field(:event_type, String.t())
    field(:index, non_neg_integer())
    field(:delta, Delta.t())
  end

  @spec from_api(map() | t() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = event), do: event

  def from_api(%{} = data) do
    %__MODULE__{
      event_id: Map.get(data, "event_id"),
      event_type: Map.get(data, "event_type"),
      index: Map.get(data, "index"),
      delta: Delta.from_api(Map.get(data, "delta"))
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = event) do
    %{"event_type" => "step.delta"}
    |> maybe_put("event_id", event.event_id)
    |> maybe_put("index", event.index)
    |> maybe_put("delta", Delta.to_api(event.delta))
  end
end

defmodule Gemini.Types.Interactions.Events.StepStop do
  @moduledoc """
  Interactions SSE event: `step.stop`.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Step

  @derive Jason.Encoder
  typedstruct do
    field(:event_id, String.t())
    field(:event_type, String.t())
    field(:index, non_neg_integer())
    field(:step, Step.t())
  end

  @spec from_api(map() | t() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = event), do: event

  def from_api(%{} = data) do
    %__MODULE__{
      event_id: Map.get(data, "event_id"),
      event_type: Map.get(data, "event_type"),
      index: Map.get(data, "index"),
      step: Step.from_api(Map.get(data, "step"))
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = event) do
    %{"event_type" => "step.stop"}
    |> maybe_put("event_id", event.event_id)
    |> maybe_put("index", event.index)
    |> maybe_put("step", Step.to_api(event.step))
  end
end

defmodule Gemini.Types.Interactions.Events.InteractionSSEEvent do
  @moduledoc """
  Union type for Interactions SSE events.
  """

  alias Gemini.Types.Interactions.Events.{
    ContentDelta,
    ContentStart,
    ContentStop,
    ErrorEvent,
    InteractionEvent,
    InteractionStatusUpdate,
    StepDelta,
    StepStart,
    StepStop
  }

  @type t ::
          InteractionEvent.t()
          | InteractionStatusUpdate.t()
          | ContentStart.t()
          | ContentDelta.t()
          | ContentStop.t()
          | StepStart.t()
          | StepDelta.t()
          | StepStop.t()
          | ErrorEvent.t()

  @doc """
  Decodes an Interactions SSE event payload.

  Current `interaction.created` and `interaction.completed` spellings, as
  well as the legacy `interaction.start` and `interaction.complete` spellings,
  decode as `InteractionEvent`.
  """
  @spec from_api(map() | t() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%InteractionEvent{} = event), do: event
  def from_api(%InteractionStatusUpdate{} = event), do: event
  def from_api(%ContentStart{} = event), do: event
  def from_api(%ContentDelta{} = event), do: event
  def from_api(%ContentStop{} = event), do: event
  def from_api(%StepStart{} = event), do: event
  def from_api(%StepDelta{} = event), do: event
  def from_api(%StepStop{} = event), do: event
  def from_api(%ErrorEvent{} = event), do: event

  def from_api(%{} = data) do
    case Map.get(data, "event_type") do
      "interaction.created" -> InteractionEvent.from_api(data)
      "interaction.completed" -> InteractionEvent.from_api(data)
      "interaction.status_update" -> InteractionStatusUpdate.from_api(data)
      "step.start" -> StepStart.from_api(data)
      "step.delta" -> StepDelta.from_api(data)
      "step.stop" -> StepStop.from_api(data)
      "error" -> ErrorEvent.from_api(data)
      "interaction.start" -> InteractionEvent.from_api(data)
      "interaction.complete" -> InteractionEvent.from_api(data)
      "content.start" -> ContentStart.from_api(data)
      "content.delta" -> ContentDelta.from_api(data)
      "content.stop" -> ContentStop.from_api(data)
      _ -> nil
    end
  end
end

defmodule Gemini.Types.Interactions.Events do
  @moduledoc """
  Helpers for decoding Interactions SSE events.
  """

  alias Gemini.Types.Interactions.Events.{
    InteractionSSEEvent
  }

  @doc """
  Decodes an Interactions SSE event payload.

  Delegates to `InteractionSSEEvent.from_api/1`; retained for backwards
  compatibility with the existing transport entry point.
  """
  @spec from_api(map() | InteractionSSEEvent.t() | nil) :: InteractionSSEEvent.t() | nil
  defdelegate from_api(data), to: InteractionSSEEvent
end
