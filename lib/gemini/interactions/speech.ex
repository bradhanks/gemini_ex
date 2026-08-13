defmodule Gemini.Interactions.Speech do
  @moduledoc """
  Text-to-speech through the Interactions API.

  <https://ai.google.dev/gemini-api/docs/speech-generation>

  Output is 24 kHz, mono, 16-bit signed little-endian PCM. `generate/2`
  decodes and returns that PCM; `generate_wav/2` wraps it in a WAV container
  suitable for writing directly to a playable file.

  ## Examples

      {:ok, wav} =
        Gemini.Interactions.Speech.generate_wav("Say cheerfully: have a great day!",
          model: "gemini-3.1-flash-tts-preview",
          voice: "Kore"
        )

      File.write!("out.wav", wav)

  For multiple speakers, pass `{speaker_name, voice_name}` tuples:

      Gemini.Interactions.Speech.generate_wav(transcript,
        model: "gemini-3.1-flash-tts-preview",
        speakers: [{"Joe", "Kore"}, {"Jane", "Puck"}]
      )
  """

  alias Gemini.APIs.Interactions
  alias Gemini.Error
  alias Gemini.Interactions.Text

  alias Gemini.Types.Interactions.{
    GenerationConfig,
    Interaction,
    ResponseFormat,
    SpeechConfig
  }

  @sample_rate 24_000
  @channels 1
  @bits_per_sample 16
  @speech_option_keys [:voice, :speakers, :language]

  @voices ~w(
    Zephyr Puck Charon Kore Fenrir Leda Orus Aoede Callirrhoe Autonoe
    Enceladus Iapetus Umbriel Algieba Despina Erinome Algenib Rasalgethi
    Laomedeia Achernar Alnilam Schedar Gacrux Pulcherrima Achird
    Zubenelgenubi Vindemiatrix Sadachbia Sadaltager Sulafat
  )

  @doc """
  The 30 documented voice names.
  """
  @spec voices() :: [String.t()]
  def voices, do: @voices

  @doc """
  Synthesize speech and return raw decoded PCM.

  Pass `:voice` for a single speaker, or `:speakers` as a list of
  `{speaker_name, voice_name}` tuples for multi-speaker output. `:language` is
  an optional BCP-47 code applied to every speaker. All other options are
  passed to `Gemini.APIs.Interactions.create/2` and its normal top-level
  generation-config options are supported.

  When `stream: true` is passed, returns `{:ok, stream}` unchanged. The stream
  yields `Gemini.Types.Interactions.Events.InteractionSSEEvent` variants and is
  not decoded synchronously.
  """
  @spec generate(String.t(), keyword()) ::
          {:ok, binary() | Enumerable.t()} | {:error, term()}
  def generate(text, opts \\ []) when is_binary(text) and is_list(opts) do
    with {:ok, opts} <- build_opts(opts),
         {:ok, result} <- Interactions.create(text, opts) do
      decode_result(result)
    end
  end

  @doc """
  Synthesize speech and return a complete WAV file.

  The WAV file contains 24 kHz mono signed 16-bit little-endian PCM. With
  `stream: true`, returns `{:ok, stream}` unchanged because a stream cannot be
  synchronously wrapped in a WAV container.
  """
  @spec generate_wav(String.t(), keyword()) ::
          {:ok, binary() | Enumerable.t()} | {:error, term()}
  def generate_wav(text, opts \\ []) when is_binary(text) and is_list(opts) do
    case generate(text, opts) do
      {:ok, pcm} when is_binary(pcm) -> {:ok, wav_header(byte_size(pcm)) <> pcm}
      {:ok, stream} -> {:ok, stream}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Returns a 44-byte canonical WAV header for `byte_size` bytes of 24 kHz mono
  16-bit PCM.
  """
  @spec wav_header(non_neg_integer()) :: binary()
  def wav_header(byte_size) when is_integer(byte_size) and byte_size >= 0 do
    block_align = div(@channels * @bits_per_sample, 8)
    byte_rate = @sample_rate * block_align

    <<
      "RIFF",
      36 + byte_size::little-32,
      "WAVE",
      "fmt ",
      16::little-32,
      1::little-16,
      @channels::little-16,
      @sample_rate::little-32,
      byte_rate::little-32,
      block_align::little-16,
      @bits_per_sample::little-16,
      "data",
      byte_size::little-32
    >>
  end

  defp decode_result(%Interaction{} = interaction) do
    with {:ok, audio} <- Interaction.output_audio(interaction) do
      decode_audio(audio.data)
    end
  end

  defp decode_result(stream), do: {:ok, stream}

  defp decode_audio(nil), do: {:error, :not_found}

  defp decode_audio(data) when is_binary(data) do
    case Base.decode64(data) do
      {:ok, pcm} -> {:ok, pcm}
      :error -> {:error, :invalid_audio_encoding}
    end
  end

  defp decode_audio(_data), do: {:error, :invalid_audio_data}

  defp build_opts(opts) do
    explicit_generation_config? = Keyword.has_key?(opts, :generation_config)
    {speech_opts, rest} = Keyword.split(opts, @speech_option_keys)

    with {:ok, speech_config} <- speech_config(speech_opts) do
      rest
      |> Text.build_opts()
      |> put_response_format()
      |> put_speech_config(speech_config, explicit_generation_config?)
      |> then(&{:ok, &1})
    end
  end

  defp put_response_format(opts) do
    if Keyword.has_key?(opts, :response_format) do
      opts
    else
      Keyword.put(opts, :response_format, %ResponseFormat.Audio{})
    end
  end

  defp put_speech_config(opts, nil, _explicit_generation_config?), do: opts
  defp put_speech_config(opts, _speech_config, true), do: opts

  defp put_speech_config(opts, speech_config, false) do
    case Keyword.fetch(opts, :generation_config) do
      {:ok, %GenerationConfig{} = generation_config} ->
        Keyword.put(opts, :generation_config, %{generation_config | speech_config: speech_config})

      :error ->
        Keyword.put(opts, :generation_config, %GenerationConfig{speech_config: speech_config})
    end
  end

  defp speech_config(opts) do
    language = Keyword.get(opts, :language)

    case Keyword.fetch(opts, :speakers) do
      {:ok, speakers} -> speakers_config(speakers, language)
      :error -> voice_config(Keyword.fetch(opts, :voice), language)
    end
  end

  defp speakers_config(speakers, language) when is_list(speakers) do
    speakers
    |> Enum.reduce_while({:ok, []}, fn
      {speaker, voice}, {:ok, configs} when is_binary(speaker) and is_binary(voice) ->
        {:cont,
         {:ok, [%SpeechConfig{speaker: speaker, voice: voice, language: language} | configs]}}

      _speaker, _configs ->
        {:halt,
         {:error,
          Error.validation_error(
            "expected :speakers to be a list of {speaker, voice} string tuples"
          )}}
    end)
    |> case do
      {:ok, configs} -> {:ok, Enum.reverse(configs)}
      {:error, _reason} = error -> error
    end
  end

  defp speakers_config(_speakers, _language) do
    {:error,
     Error.validation_error("expected :speakers to be a list of {speaker, voice} string tuples")}
  end

  defp voice_config({:ok, voice}, language) when is_binary(voice),
    do: {:ok, [%SpeechConfig{voice: voice, language: language}]}

  defp voice_config({:ok, _voice}, _language),
    do: {:error, Error.validation_error("expected :voice to be a string")}

  defp voice_config(:error, _language), do: {:ok, nil}
end
