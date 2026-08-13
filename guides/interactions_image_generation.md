# Image Generation with the Interactions API

Use `Gemini.Interactions.Image` to generate an image, edit an uploaded image,
or continue a stored image interaction. It returns the last generated
`Gemini.Types.Interactions.ImageContent` block.

## Generate an image

```elixir
{:ok, image} =
  Gemini.Interactions.Image.generate("a watercolor fox reading an Elixir book",
    model: "gemini-3.1-flash-image",
    aspect_ratio: "16:9",
    image_size: "2K"
  )

File.write!("fox.png", Base.decode64!(image.data))
```

Use `generate_interaction/2` when you need interleaved output, usage, thought
steps, or an interaction id for a follow-up edit.

## Edit an image

An edit accepts an image content struct, an inline base64 tuple, or a file URI
tuple:

```elixir
data = "source.jpg" |> File.read!() |> Base.encode64()

{:ok, edited} =
  Gemini.Interactions.Image.edit(
    "replace the background with a mountain lake",
    {:data, data, "image/jpeg"},
    model: "gemini-3.1-flash-image",
    aspect_ratio: "4:3"
  )

File.write!("edited.png", Base.decode64!(edited.data))
```

To edit a stored interaction, pass `nil` instead of an image and provide
`previous_interaction_id:`.

## Important options

- `aspect_ratio:` accepts `"1:1"`, `"3:2"`, `"2:3"`, `"3:4"`, `"4:3"`,
  `"4:5"`, `"5:4"`, `"9:16"`, `"16:9"`, or `"21:9"`.
- `image_size:` accepts `"512px"`, `"1K"`, `"2K"`, or `"4K"`.
- `mime_type:` requests an output MIME type.
- An explicit `response_format:` takes precedence over those three convenience
  options, including when its value is `nil`.
- Text generation options such as `thinking_level:`, `temperature:`, and
  `max_output_tokens:` are also accepted.
- `stream: true` returns the event stream unchanged; image accessors apply only
  to a completed, non-streaming interaction.

Official capability guide: [Image generation](https://ai.google.dev/gemini-api/docs/image-generation).
