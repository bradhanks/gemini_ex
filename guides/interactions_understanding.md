# Media Understanding with the Interactions API

Use `Gemini.Interactions.Understanding` to ask questions about images, videos,
audio, and documents. Media may be inline base64, a Files API URI, another URI,
or a YouTube URL for video input.

## Analyze an image

```elixir
data = "photo.jpg" |> File.read!() |> Base.encode64()

{:ok, description} =
  Gemini.Interactions.Understanding.describe_image(
    "Describe this image in one paragraph",
    {:data, data},
    model: "gemini-3.6-flash",
    mime_type: "image/jpeg",
    resolution: "high"
  )

IO.puts(description)
```

`analyze/3` accepts multiple media items and places them before the prompt:

```elixir
{:ok, answer} =
  Gemini.Interactions.Understanding.analyze(
    "Compare these two images",
    [
      {:image, {:uri, "files/first"}, "image/jpeg"},
      {:image, {:uri, "files/second"}, "image/png"}
    ],
    model: "gemini-3.6-flash",
    resolution: "medium"
  )

IO.puts(answer)
```

## Input forms and helpers

Each media tuple has the form `{kind, source, mime_type}`. The kind is
`:image`, `:video`, `:audio`, or `:document`; the source is `{:uri, uri}`,
`{:data, base64}`, or a bare URI string. Typed `ImageContent`, `VideoContent`,
`AudioContent`, and `DocumentContent` structs are also accepted.

For a single item, use:

- `describe_image/3`
- `analyze_video/3`, including a bare YouTube URL
- `transcribe_audio/3`
- `analyze_document/3`, typically with `mime_type: "application/pdf"`

## Important options

- `resolution:` is applied independently to every non-audio item. Documented
  values are `"unspecified"`, `"low"`, `"medium"`, `"high"`, and
  `"ultra_high"`. Resolution is not sent on audio content.
- `mime_type:` is the single-item helper option. With `analyze/3`, place each
  MIME type in its media tuple or content struct.
- `response_format:` can be a `ResponseFormat.Text` struct with
  `mime_type: "application/json"` and a schema for structured extraction.
- `analyze_interaction/3` returns the whole interaction when you need steps,
  usage, or thought signatures.
- `stream: true` returns the event stream unchanged; the text accessor applies
  only to a completed, non-streaming interaction.

Official capability guides: [image understanding](https://ai.google.dev/gemini-api/docs/image-understanding), [video understanding](https://ai.google.dev/gemini-api/docs/video-understanding), [audio understanding](https://ai.google.dev/gemini-api/docs/audio), and [document processing](https://ai.google.dev/gemini-api/docs/document-processing).
