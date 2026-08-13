# Interactions Speech Example
# Run with: mix run examples/18_interactions_speech.exs
#
# Demonstrates:
# - Synthesizing speech through the Interactions API
# - Selecting a voice
# - Writing playable WAV output

defmodule InteractionsSpeechExample do
  alias Gemini.Interactions.Speech

  @output_path "interactions-speech.wav"

  def run do
    print_header("INTERACTIONS SPEECH")

    check_auth!()
    demo_speech_generation()

    print_footer()
  end

  defp demo_speech_generation do
    print_section("1. Generate Speech")

    text = "Say cheerfully: Elixir makes reliable systems a joy to build."

    IO.puts("TEXT:")
    IO.puts("  #{text}")
    IO.puts("")

    case Speech.generate_wav(text,
           model: "gemini-3.1-flash-tts-preview",
           voice: "Kore",
           language: "en-US"
         ) do
      {:ok, wav} when is_binary(wav) ->
        File.write!(@output_path, wav)
        IO.puts("OUTPUT:")
        IO.puts("  wrote #{@output_path} (#{byte_size(wav)} bytes)")
        IO.puts("")
        IO.puts("[OK] Interactions speech generation successful")

      {:ok, stream} ->
        IO.puts("[ERROR] Expected WAV bytes, received stream: #{inspect(stream)}")

      {:error, error} ->
        IO.puts("[ERROR] #{inspect(error)}")
    end

    IO.puts("")
  end

  defp check_auth! do
    cond do
      System.get_env("GEMINI_API_KEY") ->
        key = System.get_env("GEMINI_API_KEY")
        masked = String.slice(key, 0, 4) <> "..." <> String.slice(key, -4, 4)
        IO.puts("AUTH: Using Gemini API Key (#{masked})")
        IO.puts("")

      System.get_env("VERTEX_JSON_FILE") || System.get_env("GOOGLE_APPLICATION_CREDENTIALS") ->
        IO.puts("AUTH: Using Vertex AI / Application Default Credentials")
        IO.puts("")

      true ->
        IO.puts("[ERROR] No authentication configured!")
        IO.puts("Set GEMINI_API_KEY or VERTEX_JSON_FILE environment variable.")
        System.halt(1)
    end
  end

  defp print_header(title) do
    IO.puts("")
    IO.puts(String.duplicate("=", 70))
    IO.puts("  #{title}")
    IO.puts(String.duplicate("=", 70))
    IO.puts("")
  end

  defp print_section(title) do
    IO.puts(String.duplicate("-", 70))
    IO.puts(title)
    IO.puts(String.duplicate("-", 70))
    IO.puts("")
  end

  defp print_footer do
    IO.puts(String.duplicate("=", 70))
    IO.puts("  EXAMPLE COMPLETE")
    IO.puts(String.duplicate("=", 70))
    IO.puts("")
  end
end

InteractionsSpeechExample.run()
