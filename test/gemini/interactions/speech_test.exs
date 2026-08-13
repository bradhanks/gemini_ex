defmodule Gemini.Interactions.SpeechTest do
  use ExUnit.Case, async: false

  alias Gemini.Error
  alias Gemini.Interactions.Speech
  alias Gemini.Types.Interactions.{GenerationConfig, ResponseFormat}
  alias Plug.Conn

  setup do
    bypass = Gemini.TestHTTPServer.open()
    :meck.new(Gemini.Auth, [:passthrough])
    on_exit(fn -> :meck.unload() end)
    %{bypass: bypass}
  end

  defp audio_response(data) do
    %{
      "id" => "int_tts",
      "status" => "completed",
      "output_audio" => %{"type" => "audio", "data" => data, "mime_type" => "audio/pcm"}
    }
  end

  defp respond(bypass, response) do
    parent = self()

    :meck.expect(Gemini.Auth, :get_base_url, fn _type, _credentials ->
      "http://localhost:#{bypass.port}"
    end)

    Gemini.TestHTTPServer.expect_once(bypass, "POST", "/v1beta/interactions", fn conn ->
      {:ok, raw, conn} = Conn.read_body(conn)
      send(parent, {:body, Jason.decode!(raw)})

      conn
      |> Conn.put_resp_content_type("application/json")
      |> Conn.resp(200, Jason.encode!(response))
    end)
  end

  defp respond_stream(bypass) do
    :meck.expect(Gemini.Auth, :get_base_url, fn _type, _credentials ->
      "http://localhost:#{bypass.port}"
    end)

    Gemini.TestHTTPServer.expect_once(bypass, "POST", "/v1beta/interactions", fn conn ->
      conn =
        conn
        |> Conn.put_resp_content_type("text/event-stream")
        |> Conn.send_chunked(200)

      {:ok, conn} =
        Conn.chunk(
          conn,
          "data: " <>
            Jason.encode!(%{
              "event_id" => "evt_1",
              "event_type" => "interaction.start",
              "interaction" => %{"id" => "int_tts", "status" => "in_progress"}
            }) <> "\n\n"
        )

      {:ok, conn} = Conn.chunk(conn, "data: [DONE]\n\n")
      conn
    end)
  end

  defp sent_body do
    receive do
      {:body, body} -> body
    after
      1_000 -> flunk("no request body captured")
    end
  end

  defp opts(opts), do: Keyword.merge([auth: :gemini, api_key: "test", timeout: 2_000], opts)

  test "generate/2 returns decoded PCM", %{bypass: bypass} do
    respond(bypass, audio_response(Base.encode64("RAWPCM")))

    assert {:ok, "RAWPCM"} =
             Speech.generate("Say hi", opts(model: "gemini-3.1-flash-tts-preview", voice: "Kore"))
  end

  test "generate/2 sends an audio response_format", %{bypass: bypass} do
    respond(bypass, audio_response(Base.encode64("x")))

    {:ok, _} =
      Speech.generate("Say hi", opts(model: "gemini-3.1-flash-tts-preview", voice: "Kore"))

    assert sent_body()["response_format"] == %{"type" => "audio"}
  end

  test "generate/2 builds single- and multi-speaker speech configs", %{bypass: bypass} do
    respond(bypass, audio_response(Base.encode64("x")))

    {:ok, _} =
      Speech.generate(
        "Say hi",
        opts(model: "gemini-3.1-flash-tts-preview", voice: "Kore", language: "es")
      )

    assert sent_body()["generation_config"]["speech_config"] == [
             %{"voice" => "Kore", "language" => "es"}
           ]

    respond(bypass, audio_response(Base.encode64("x")))

    {:ok, _} =
      Speech.generate(
        "Joe: Hi\nJane: Hello",
        opts(
          model: "gemini-3.1-flash-tts-preview",
          speakers: [{"Joe", "Kore"}, {"Jane", "Puck"}]
        )
      )

    assert sent_body()["generation_config"]["speech_config"] == [
             %{"speaker" => "Joe", "voice" => "Kore"},
             %{"speaker" => "Jane", "voice" => "Puck"}
           ]
  end

  test "explicit generation_config and response_format win even when nil", %{bypass: bypass} do
    respond(bypass, audio_response(Base.encode64("x")))

    {:ok, _} =
      Speech.generate(
        "Say hi",
        opts(
          model: "gemini-3.1-flash-tts-preview",
          voice: "Kore",
          generation_config: nil,
          response_format: nil
        )
      )

    body = sent_body()
    refute Map.has_key?(body, "generation_config")
    refute Map.has_key?(body, "response_format")
  end

  test "explicit generation_config and response_format are passed through unchanged", %{
    bypass: bypass
  } do
    respond(bypass, audio_response(Base.encode64("x")))

    {:ok, _} =
      Speech.generate(
        "Say hi",
        opts(
          model: "gemini-3.1-flash-tts-preview",
          voice: "Kore",
          generation_config: %GenerationConfig{temperature: 0.2},
          response_format: %ResponseFormat.Text{}
        )
      )

    body = sent_body()
    assert body["generation_config"] == %{"temperature" => 0.2}
    assert body["response_format"] == %{"type" => "text"}
  end

  test "generate_wav/2 prefixes a 44-byte RIFF header", %{bypass: bypass} do
    pcm = String.duplicate("ab", 10)
    respond(bypass, audio_response(Base.encode64(pcm)))

    {:ok, wav} =
      Speech.generate_wav("Say hi", opts(model: "gemini-3.1-flash-tts-preview", voice: "Kore"))

    assert byte_size(wav) == 44 + byte_size(pcm)
    assert <<"RIFF", _size::little-32, "WAVE", _rest::binary>> = wav
  end

  test "wav_header/1 encodes 24kHz mono 16-bit" do
    assert <<
             "RIFF",
             136::little-32,
             "WAVE",
             "fmt ",
             16::little-32,
             1::little-16,
             1::little-16,
             24_000::little-32,
             48_000::little-32,
             2::little-16,
             16::little-16,
             "data",
             100::little-32
           >> = Speech.wav_header(100)
  end

  test "voices/0 lists the 30 documented voices" do
    assert 30 = Speech.voices() |> length()
    assert "Kore" in Speech.voices()
    assert "Zephyr" in Speech.voices()
    assert "Sulafat" in Speech.voices()
  end

  test "generate/2 reports missing or invalid audio safely", %{bypass: bypass} do
    respond(bypass, %{"id" => "i", "status" => "completed"})

    assert {:error, :not_found} =
             Speech.generate("Say hi", opts(model: "gemini-3.1-flash-tts-preview"))

    respond(bypass, audio_response("not valid base64!!!"))

    assert {:error, :invalid_audio_encoding} =
             Speech.generate("Say hi", opts(model: "gemini-3.1-flash-tts-preview"))
  end

  test "generate/2 returns streams unchanged and generate_wav/2 does not wrap them", %{
    bypass: bypass
  } do
    respond_stream(bypass)

    assert {:ok, stream} =
             Speech.generate(
               "Say hi",
               opts(model: "gemini-3.1-flash-tts-preview", stream: true, max_retries: 0)
             )

    assert [%Gemini.Types.Interactions.Events.InteractionEvent{event_id: "evt_1"}] =
             Enum.to_list(stream)

    respond_stream(bypass)

    assert {:ok, stream} =
             Speech.generate_wav(
               "Say hi",
               opts(model: "gemini-3.1-flash-tts-preview", stream: true, max_retries: 0)
             )

    assert [%Gemini.Types.Interactions.Events.InteractionEvent{event_id: "evt_1"}] =
             Enum.to_list(stream)
  end

  test "generate/2 returns a validation error for malformed speakers" do
    assert {:error,
            %Error{
              type: :validation_error,
              message: "expected :speakers to be a list of {speaker, voice} string tuples"
            }} =
             Speech.generate("Say hi", speakers: ["Kore"])
  end
end
