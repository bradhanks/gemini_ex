# Speech with the Interactions API

Use `Gemini.Interactions.Speech` to synthesize speech as raw PCM or a complete
WAV file. Output audio is 24 kHz, mono, signed 16-bit little-endian PCM.

## Generate a WAV file

```elixir
{:ok, wav} =
  Gemini.Interactions.Speech.generate_wav("Say cheerfully: welcome to Elixir!",
    model: "gemini-3.1-flash-tts-preview",
    voice: "Kore"
  )

File.write!("welcome.wav", wav)
```

Use `generate/2` instead when your audio pipeline needs decoded PCM without a
container.

## Important options

- `voice:` selects a single speaker voice. Call
  `Gemini.Interactions.Speech.voices/0` for the documented names.
- `language:` supplies an optional BCP-47 language code.
- `speakers:` accepts `{speaker_name, voice_name}` tuples for multi-speaker
  synthesis:

  ```elixir
  Gemini.Interactions.Speech.generate_wav("Joe: Hello! Jane: Good morning!",
    model: "gemini-3.1-flash-tts-preview",
    speakers: [{"Joe", "Kore"}, {"Jane", "Puck"}],
    language: "en-US"
  )
  ```

- An explicit `generation_config:` or `response_format:` takes precedence over
  the corresponding convenience configuration, including when its value is
  `nil`.
- `stream: true` returns the event stream unchanged. Streaming speech is not
  synchronously decoded or WAV-wrapped, so consume the audio events and build a
  container after the stream finishes if needed.

Official capability guide: [Speech generation](https://ai.google.dev/gemini-api/docs/speech-generation).
