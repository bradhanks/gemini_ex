# Text with the Interactions API

Use `Gemini.Interactions.Text` when you want text output with server-managed
conversation state, thinking, tools, or the Interactions API's streaming event
model. The convenience function returns the generated string directly.

## Generate text

```elixir
{:ok, text} =
  Gemini.Interactions.Text.generate("Explain pattern matching in one paragraph",
    model: "gemini-3.6-flash"
  )

IO.puts(text)
```

Use `generate_interaction/2` when you also need the interaction id, steps,
usage, or thought signatures:

```elixir
{:ok, interaction} =
  Gemini.Interactions.Text.generate_interaction("Give me three project names",
    model: "gemini-3.6-flash"
  )

{:ok, text} = Gemini.Types.Interactions.Interaction.output_text(interaction)
IO.puts(text)
```

## Important options

Common generation options can be passed directly:

```elixir
Gemini.Interactions.Text.generate("Write a compact release announcement",
  model: "gemini-3.6-flash",
  system_instruction: "Use a friendly, professional tone.",
  temperature: 0.4,
  max_output_tokens: 300,
  thinking_level: "low",
  thinking_summaries: "auto"
)
```

- `model:` is required unless you use an `agent:` through the lower-level
  `Gemini.APIs.Interactions.create/2` API.
- `previous_interaction_id:` continues a stored conversation without resending
  its history.
- `generation_config:` accepts a
  `Gemini.Types.Interactions.GenerationConfig` struct or map. When supplied, it
  takes precedence over the convenience options above, including when its value
  is `nil`.
- `response_format:` accepts the typed variants under
  `Gemini.Types.Interactions.ResponseFormat`, raw maps, or a list of formats.
- `stream: true` returns the SSE stream unchanged. Consume its
  `Gemini.Types.Interactions.Events.InteractionSSEEvent` values instead of
  calling synchronous interaction accessors on the stream. An event type this
  library does not model arrives as a
  `Gemini.Types.Interactions.Events.UnknownEvent` holding the raw map, so match
  the variants you care about and keep a catch-all clause — see
  [Which events a stream yields](interactions.md#which-events-a-stream-yields).

For interaction CRUD, background execution, and stream resumption, see the
[Interactions API guide](interactions.md).

Official capability guide: [Text generation](https://ai.google.dev/gemini-api/docs/text-generation).
