# Thinking with the Interactions API

Thinking models can spend additional reasoning effort before answering. The
Interactions API exposes that work as chronological `thought` steps and can
optionally include summaries of the reasoning.

## Generate with thinking

```elixir
alias Gemini.Types.Interactions.Interaction

{:ok, interaction} =
  Gemini.Interactions.Text.generate_interaction("Solve: 17 * 23",
    model: "gemini-3.6-flash",
    thinking_level: "high",
    thinking_summaries: "auto"
  )

{:ok, answer} = Interaction.output_text(interaction)
IO.puts(answer)
IO.inspect(Interaction.thought_signatures(interaction), label: "signatures")
```

`thinking_level:` controls reasoning effort; supported levels depend on the
model. `thinking_summaries: "auto"` asks for summaries, but a thought step may
still have no summary. `generate_interaction/2` is necessary when you need the
steps, usage, or signatures; `generate/2` returns only the final text.

## Stateful conversations

Stored interactions are the simplest way to preserve reasoning context. Pass
the prior id on the next turn and the server manages the full history,
including thought and built-in-tool signatures:

```elixir
{:ok, first} =
  Gemini.Interactions.Text.generate_interaction("I have two dogs",
    model: "gemini-3.6-flash",
    store: true
  )

{:ok, answer} =
  Gemini.Interactions.Text.generate("How many paws is that?",
    model: "gemini-3.6-flash",
    previous_interaction_id: first.id,
    store: true
  )

IO.puts(answer)
```

## Stateless conversations and signature safety

With `store: false`, your application owns the complete history. You must
resend every model-generated step on each later turn. Every thought signature,
including signatures on built-in tool call and result steps, must be resent
byte-identically: do not trim, decode, rewrite, or omit it.

`Interaction.thought_signatures/1` collects every signature in step order for
inspection or persistence checks. The strings alone are not a replacement for
the steps: resend the complete serialized steps.

```elixir
alias Gemini.Types.Interactions.{Interaction, Step}

history = [
  %{
    "type" => "user_input",
    "content" => [%{"type" => "text", "text" => "I have two dogs"}]
  }
]

{:ok, first} =
  Gemini.Interactions.Text.generate_interaction(history,
    model: "gemini-3.6-flash",
    store: false
  )

IO.inspect(Interaction.thought_signatures(first), label: "signatures to preserve")

history =
  history ++
    Enum.map(first.steps || [], &Step.to_api/1) ++
    [
      %{
        "type" => "user_input",
        "content" => [%{"type" => "text", "text" => "How many paws is that?"}]
      }
    ]

{:ok, second} =
  Gemini.Interactions.Text.generate_interaction(history,
    model: "gemini-3.6-flash",
    store: false
  )

{:ok, answer} = Interaction.output_text(second)
IO.puts(answer)
```

`Step.from_api/1` parses known step types into typed structs. If the server adds
an unmodeled type, it becomes an `UnknownStep` whose original raw map is
retained. `Step.to_api/1` returns that map precisely, so unmodeled fields and
their signatures survive the round trip:

```elixir
raw = %{"type" => "future_tool_result", "signature" => "opaque-bytes", "new" => true}

true = raw == raw |> Step.from_api() |> Step.to_api()
```

`store: false` cannot be combined with `previous_interaction_id:` or background
execution. For streaming requests, collect all events through completion so no
signature-bearing step is lost.

Official capability guide: [Gemini thinking](https://ai.google.dev/gemini-api/docs/thinking).
