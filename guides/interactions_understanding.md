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
{:ok, first} = Gemini.APIs.Files.upload("first.jpg", auth: :gemini)
{:ok, second} = Gemini.APIs.Files.upload("second.png", auth: :gemini)

{:ok, answer} =
  Gemini.Interactions.Understanding.analyze(
    "Compare these two images",
    [
      {:image, {:uri, first.uri}, "image/jpeg"},
      {:image, {:uri, second.uri}, "image/png"}
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

A URI must be fully qualified: a Files API URI, a YouTube watch URL, another
HTTPS URL, or a `gs://` object. For an uploaded file that is the `uri` field,
which looks like
`"https://generativelanguage.googleapis.com/v1beta/files/abc123"` — not the
`name` field, which looks like `"files/abc123"` and is only for `Files.get/2`,
`Files.delete/2`, and `Files.wait_for_processing/2`. Passing a bare resource
name into a media block fails with:

```
400 — Unsupported file URI type: files/abc123. File URI must be a File API
      (e.g. https://generativelanguage.googleapis.com/files/<id>), Youtube
      (e.g. https://www.youtube.com/watch?v=<id>), or HTTPS
```

For a single item, use:

- `describe_image/3`
- `analyze_video/3`, including a bare YouTube URL
- `transcribe_audio/3`
- `analyze_document/3`, typically with `mime_type: "application/pdf"`

## Important options

- `resolution:` is applied independently to every non-audio item. Documented
  values are `"unspecified"`, `"low"`, `"medium"`, `"high"`, and
  `"ultra_high"`. Resolution is not sent on audio content, and the Gemini API
  currently rejects it on document blocks with
  `400 Unknown parameter 'resolution'` — use it for images and video only.
- `mime_type:` is the single-item helper option. With `analyze/3`, place each
  MIME type in its media tuple or content struct.
- `response_format:` can be a `ResponseFormat.Text` struct with
  `mime_type: "application/json"` and a schema for structured extraction.
- `analyze_interaction/3` returns the whole interaction when you need steps,
  usage, or thought signatures.
- `stream: true` returns the event stream unchanged; the text accessor applies
  only to a completed, non-streaming interaction.

Official capability guides: [image understanding](https://ai.google.dev/gemini-api/docs/image-understanding), [video understanding](https://ai.google.dev/gemini-api/docs/video-understanding), [audio understanding](https://ai.google.dev/gemini-api/docs/audio), and [document processing](https://ai.google.dev/gemini-api/docs/document-processing).
