# Video with the Interactions API

Use `Gemini.Interactions.Video` for video generation and conversational editing
with Gemini Omni. This wrapper is not for Veo: use `Gemini.APIs.Videos` for Veo
models and operations.

## Generate a video

```elixir
{:ok, video} =
  Gemini.Interactions.Video.generate("a paper airplane gliding through a library",
    model: "gemini-omni-flash",
    task: "text_to_video",
    aspect_ratio: "16:9",
    delivery: "uri"
  )

IO.puts(video.uri)
```

Use `generate_interaction/2` to retain the interaction id, then continue a
stored interaction with `previous_interaction_id:`:

```elixir
{:ok, first} =
  Gemini.Interactions.Video.generate_interaction("a paper airplane in a library",
    model: "gemini-omni-flash",
    delivery: "uri"
  )

{:ok, edited} =
  Gemini.Interactions.Video.generate("make the scene take place at sunset",
    model: "gemini-omni-flash",
    previous_interaction_id: first.id,
    delivery: "uri"
  )

IO.puts(edited.uri)
```

## Important options

- `task:` commonly uses `"text_to_video"`, `"image_to_video"`,
  `"reference_to_video"`, or `"edit"`. Values pass through for forward
  compatibility.
- `aspect_ratio:` accepts `"16:9"` or `"9:16"`.
- `delivery: "uri"` requests URI delivery. Videos larger than 4 MB are returned
  by URI even when it is not requested explicitly.
- An explicit `generation_config:` or `response_format:` takes precedence over
  the convenience configuration, including when its value is `nil`.
- Gemini Omni does not accept system instructions, `temperature`, `top_p`, stop
  sequences, or a negative-prompt parameter. Put negative constraints in the
  prompt itself.
- `stream: true` returns the event stream unchanged; video accessors apply only
  to a completed, non-streaming interaction.

Official capability guide: [Gemini Omni](https://ai.google.dev/gemini-api/docs/omni).
