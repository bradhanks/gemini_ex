# Interactions API

The Interactions API provides **stateful, server-managed conversations** with:

- CRUD lifecycle (`create`, `get`, `cancel`, `delete`)
- Background execution (`background: true`) with polling/cancel
- SSE streaming with resumable `last_event_id`

This is different from `generateContent`-style calls, which are stateless and require you to manage conversation state client-side.

## Model availability

Model availability for Interactions can vary by account/region. If you see errors like `"Model family ... is not supported"`, try `gemini-2.5-flash` (or set your own `model:` explicitly).

## Create (non-streaming)

```elixir
alias Gemini.APIs.Interactions

{:ok, interaction} =
  Interactions.create("What is the capital of France?",
    model: "gemini-2.5-flash"
  )

IO.inspect(interaction.id, label: "interaction.id")
IO.inspect(interaction.status, label: "interaction.status")
```

Agent-based interactions use `agent:` instead of `model:`:

```elixir
alias Gemini.APIs.Interactions

{:ok, interaction} =
  Interactions.create("Research the history of quantum computing",
    agent: "deep-research-pro-preview-12-2025",
    background: true,
    store: true
  )
```

## Create (streaming SSE)

Streaming is enabled via `stream: true` and ends when the server sends `[DONE]`.

```elixir
alias Gemini.APIs.Interactions
alias Gemini.Types.Interactions.Events.ContentDelta
alias Gemini.Types.Interactions.DeltaTextDelta

{:ok, stream} =
  Interactions.create("Write a short poem about Elixir",
    model: "gemini-2.5-flash",
    stream: true
  )

for event <- stream do
  case event do
    %ContentDelta{delta: %DeltaTextDelta{text: text}} when is_binary(text) ->
      IO.write(text)

    _ ->
      :ok
  end
end
```

### Which events a stream yields

Every SSE frame decodes to one of these structs under
`Gemini.Types.Interactions.Events`:

| Event type | Struct |
| --- | --- |
| `content.start` / `content.delta` / `content.stop` | `ContentStart` / `ContentDelta` / `ContentStop` |
| `step.start` / `step.delta` / `step.stop` | `StepStart` / `StepDelta` / `StepStop` |
| `interaction.status_update` | `InteractionStatusUpdate` |
| `interaction.created`, plus `interaction.<status>` for every status in `Gemini.Types.Interactions.Interaction.statuses/0` (`queued`, `in_progress`, `requires_action`, `completed`, `failed`, `cancelled`, `incomplete`, `budget_exceeded`), plus the legacy `interaction.start` / `interaction.complete` | `InteractionEvent` (the exact spelling is preserved in `event_type`) |
| `error` | `ErrorEvent` |
| anything else | `UnknownEvent` |

`UnknownEvent` retains the original map verbatim in its `raw` field, so an
event type this library does not model yet reaches you instead of being dropped
mid-stream. Match it — or keep a catch-all clause — rather than assuming the
list of known structs is exhaustive.

Terminal state is easiest to watch through `InteractionEvent`, since a
cancellation and a budget exceedance arrive the same way a completion does:

```elixir
alias Gemini.Types.Interactions.Events.InteractionEvent
alias Gemini.Types.Interactions.Interaction

terminal = Interaction.terminal_statuses()

Enum.find(stream, fn
  %InteractionEvent{interaction: %Interaction{status: status}} -> status in terminal
  _other -> false
end)
```

## Custom request headers

`create/2`, `get/2`, `cancel/2`, and `delete/2` all accept `:headers` — extra
request headers as `{name, value}` string tuples, appended after the auth
headers. They apply to JSON and streaming requests alike.

```elixir
{:ok, interaction} =
  Interactions.create("What is the capital of France?",
    model: "gemini-2.5-flash",
    headers: [{"api-revision", "2026-05-20"}]
  )
```

A value that is not a list of string/string tuples returns
`{:error, %Gemini.Error{type: :validation_error}}` before any request is made.
Names are not deduplicated against the auth headers, so do not use `:headers`
to override `Authorization` or `x-goog-api-key` — configure auth instead.

## Resumption (`last_event_id`)

If your stream is interrupted, persist the `interaction_id` and the last `event_id` you processed, then resume with `get(stream: true, last_event_id: ...)`.

```elixir
alias Gemini.APIs.Interactions
alias Gemini.Types.Interactions.Events.InteractionEvent

{:ok, stream} =
  Interactions.create("Write a longer story in multiple paragraphs",
    model: "gemini-2.5-flash",
    stream: true
  )

# Simulate a disconnect by stopping early (after a few events),
# while keeping track of the interaction id + last event id we saw.
state =
  Enum.reduce_while(stream, %{interaction_id: nil, last_event_id: nil, seen: 0}, fn event, acc ->
    acc =
      case event do
        %InteractionEvent{event_type: "interaction.start", interaction: interaction} ->
          %{acc | interaction_id: interaction.id}

        _ ->
          acc
      end

    acc = %{acc | last_event_id: Map.get(event, :event_id), seen: acc.seen + 1}

    if acc.seen >= 5 do
      {:halt, acc}
    else
      {:cont, acc}
    end
  end)

{:ok, resumed} =
  Interactions.get(state.interaction_id,
    stream: true,
    last_event_id: state.last_event_id
  )

Enum.each(resumed, fn _event -> :ok end)
```

## Background + cancel + delete

Note: The API may reject `background: true` for model-based interactions; background execution is commonly supported for **agent interactions**.

```elixir
alias Gemini.APIs.Interactions

{:ok, interaction} =
  Interactions.create("Draft a detailed outline for a technical blog post about OTP supervision trees",
    agent: "deep-research-pro-preview-12-2025",
    background: true,
    store: true
  )

# Poll until terminal status (completed/failed/cancelled/requires_action)
{:ok, final} = Interactions.wait_for_completion(interaction.id, timeout_ms: 120_000)

# Cancel (only applies while a background interaction is still running)
_ = Interactions.cancel(interaction.id)

# Delete (best-effort cleanup)
:ok = Interactions.delete(interaction.id)
```

## Gemini vs Vertex routing (and quota project)

`gemini_ex` supports both Gemini and Vertex AI auth for Interactions:

- **Gemini** uses `x-goog-api-key` and requests under `/v1beta/...`.
- **Vertex** uses `Authorization: Bearer ...` and requests under `/v1beta1/...`.
  - Create is project/location-scoped:
    `https://{location}-aiplatform.googleapis.com/v1beta1/projects/{project}/locations/{location}/interactions`
  - Get/cancel/delete are not project/location-scoped (Python parity):
    `https://{location}-aiplatform.googleapis.com/v1beta1/interactions/{id}`

If you configure a **Vertex quota project** (`quota_project_id`, `VERTEX_QUOTA_PROJECT_ID`, or `GOOGLE_CLOUD_QUOTA_PROJECT`), requests include:

- `x-goog-user-project: <quota_project_id>`
