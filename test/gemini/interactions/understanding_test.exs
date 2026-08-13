defmodule Gemini.Interactions.UnderstandingTest do
  use ExUnit.Case, async: false

  alias Gemini.Error
  alias Gemini.Interactions.Understanding

  alias Gemini.Types.Interactions.{
    AudioContent,
    DocumentContent,
    ImageContent,
    ResponseFormat,
    VideoContent
  }

  alias Plug.Conn

  setup do
    bypass = Gemini.TestHTTPServer.open()
    :meck.new(Gemini.Auth, [:passthrough])

    on_exit(fn -> :meck.unload() end)

    %{bypass: bypass}
  end

  defp respond(bypass, text) do
    parent = self()

    :meck.expect(Gemini.Auth, :get_base_url, fn _type, _credentials ->
      "http://localhost:#{bypass.port}"
    end)

    Gemini.TestHTTPServer.expect_once(bypass, "POST", "/v1beta/interactions", fn conn ->
      {:ok, raw, conn} = Conn.read_body(conn)
      send(parent, {:body, Jason.decode!(raw)})

      conn
      |> Conn.put_resp_content_type("application/json")
      |> Conn.resp(
        200,
        Jason.encode!(%{
          "id" => "i",
          "status" => "completed",
          "output_text" => text
        })
      )
    end)
  end

  defp respond_stream(bypass) do
    :meck.expect(Gemini.Auth, :get_base_url, fn _type, _credentials ->
      "http://localhost:#{bypass.port}"
    end)

    Gemini.TestHTTPServer.expect_once(bypass, "POST", "/v1beta/interactions", fn conn ->
      {:ok, raw, conn} = Conn.read_body(conn)
      assert %{"model" => "gemini-3.6-flash", "stream" => true} = Jason.decode!(raw)

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
              "interaction" => %{"id" => "int_1", "status" => "in_progress"}
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

  test "analyze/3 puts media before the prompt", %{bypass: bypass} do
    respond(bypass, "A cat.")

    assert {:ok, "A cat."} =
             Understanding.analyze(
               "What is this?",
               [{:image, {:uri, "files/abc"}, "image/jpeg"}],
               opts(model: "gemini-3.6-flash")
             )

    assert [
             %{"type" => "image", "uri" => "files/abc", "mime_type" => "image/jpeg"},
             %{"type" => "text", "text" => "What is this?"}
           ] = sent_body()["input"]
  end

  test "analyze/3 sets per-item resolution", %{bypass: bypass} do
    respond(bypass, "ok")

    {:ok, _} =
      Understanding.analyze(
        "Read the text",
        [{:image, {:uri, "files/abc"}, "image/jpeg"}],
        opts(model: "gemini-3.6-flash", resolution: "high")
      )

    assert [%{"resolution" => "high"} | _] = sent_body()["input"]
  end

  test "analyze/3 applies resolution to caller-supplied non-audio structs only",
       %{bypass: bypass} do
    respond(bypass, "ok")

    {:ok, _} =
      Understanding.analyze(
        "Compare",
        [
          %ImageContent{type: "image", uri: "files/i"},
          %VideoContent{type: "video", uri: "files/v"},
          %AudioContent{type: "audio", uri: "files/a"},
          %DocumentContent{type: "document", uri: "files/d"}
        ],
        opts(model: "gemini-3.6-flash", resolution: "ultra_high")
      )

    [image, video, audio, document, _prompt] = sent_body()["input"]
    assert image["resolution"] == "ultra_high"
    assert video["resolution"] == "ultra_high"
    refute Map.has_key?(audio, "resolution")
    assert document["resolution"] == "ultra_high"
  end

  test "analyze/3 supports inline base64 data", %{bypass: bypass} do
    respond(bypass, "ok")

    {:ok, _} =
      Understanding.analyze(
        "What is this?",
        [{:document, {:data, "QUJD"}, "application/pdf"}],
        opts(model: "gemini-3.6-flash")
      )

    assert [%{"type" => "document", "data" => "QUJD"} | _] = sent_body()["input"]
  end

  test "analyze/3 treats a bare URL string as a URI, for YouTube", %{bypass: bypass} do
    respond(bypass, "ok")

    {:ok, _} =
      Understanding.analyze(
        "Summarize",
        [{:video, "https://www.youtube.com/watch?v=abc", nil}],
        opts(model: "gemini-3.6-flash")
      )

    body = sent_body()

    assert [%{"type" => "video", "uri" => "https://www.youtube.com/watch?v=abc"} | _] =
             body["input"]

    refute Map.has_key?(hd(body["input"]), "mime_type")
  end

  test "analyze/3 accepts multiple media items in order", %{bypass: bypass} do
    respond(bypass, "ok")

    {:ok, _} =
      Understanding.analyze(
        "Compare",
        [
          {:image, {:uri, "files/a"}, "image/png"},
          {:image, {:uri, "files/b"}, "image/png"}
        ],
        opts(model: "gemini-3.6-flash")
      )

    assert [%{"uri" => "files/a"}, %{"uri" => "files/b"}, %{"type" => "text"}] =
             sent_body()["input"]
  end

  test "describe_image/3 wraps analyze/3 and forwards options", %{bypass: bypass} do
    respond(bypass, "A cat.")

    assert {:ok, "A cat."} =
             Understanding.describe_image(
               "What is this?",
               {:uri, "files/abc"},
               opts(
                 model: "gemini-3.6-flash",
                 mime_type: "image/jpeg",
                 resolution: "high",
                 temperature: 0.2
               )
             )

    body = sent_body()

    assert [%{"type" => "image", "mime_type" => "image/jpeg", "resolution" => "high"} | _] =
             body["input"]

    assert body["generation_config"]["temperature"] == 0.2
  end

  test "analyze_video/3 sends a video block and forwards MIME type", %{bypass: bypass} do
    respond(bypass, "Summary.")

    assert {:ok, "Summary."} =
             Understanding.analyze_video(
               "Summarize",
               "https://www.youtube.com/watch?v=abc",
               opts(model: "gemini-3.6-flash", mime_type: "video/mp4")
             )

    assert [%{"type" => "video", "mime_type" => "video/mp4"} | _] = sent_body()["input"]
  end

  test "transcribe_audio/3 sends an audio block without resolution", %{bypass: bypass} do
    respond(bypass, "Hello.")

    assert {:ok, "Hello."} =
             Understanding.transcribe_audio(
               "Transcribe",
               {:uri, "files/a"},
               opts(model: "gemini-3.6-flash", mime_type: "audio/mp3", resolution: "high")
             )

    [audio | _] = sent_body()["input"]
    assert %{"type" => "audio", "mime_type" => "audio/mp3"} = audio
    refute Map.has_key?(audio, "resolution")
  end

  test "analyze_document/3 sends a document block", %{bypass: bypass} do
    respond(bypass, "Summary.")

    assert {:ok, "Summary."} =
             Understanding.analyze_document(
               "Summarize",
               {:uri, "files/d"},
               opts(model: "gemini-3.6-flash", mime_type: "application/pdf")
             )

    assert [%{"type" => "document", "mime_type" => "application/pdf"} | _] =
             sent_body()["input"]
  end

  test "analyze/3 forwards response_format for structured extraction", %{bypass: bypass} do
    respond(bypass, ~s({"boxes":[]}))
    schema = %{"type" => "object"}

    {:ok, _} =
      Understanding.analyze(
        "Detect objects",
        [{:image, {:uri, "files/abc"}, "image/jpeg"}],
        opts(
          model: "gemini-3.6-flash",
          response_format: %ResponseFormat.Text{
            mime_type: "application/json",
            schema: schema
          }
        )
      )

    assert sent_body()["response_format"] == %{
             "type" => "text",
             "mime_type" => "application/json",
             "schema" => schema
           }
  end

  test "analyze/3 returns an Interactions stream unchanged", %{bypass: bypass} do
    respond_stream(bypass)

    assert {:ok, stream} =
             Understanding.analyze(
               "What is this?",
               [{:image, {:uri, "files/abc"}, "image/jpeg"}],
               opts(
                 model: "gemini-3.6-flash",
                 stream: true,
                 connect_timeout: 2_000,
                 max_retries: 0
               )
             )

    assert [%Gemini.Types.Interactions.Events.InteractionEvent{event_id: "evt_1"}] =
             Enum.to_list(stream)
  end

  test "analyze_interaction/3 returns an Interactions stream unchanged", %{bypass: bypass} do
    respond_stream(bypass)

    assert {:ok, stream} =
             Understanding.analyze_interaction(
               "What is this?",
               [{:image, {:uri, "files/abc"}, "image/jpeg"}],
               opts(
                 model: "gemini-3.6-flash",
                 stream: true,
                 connect_timeout: 2_000,
                 max_retries: 0
               )
             )

    assert [%Gemini.Types.Interactions.Events.InteractionEvent{event_id: "evt_1"}] =
             Enum.to_list(stream)
  end

  test "analyze/3 returns a public validation error for an unknown media kind" do
    assert {:error, %Error{type: :validation_error, message: message}} =
             Understanding.analyze(
               "Inspect",
               [{:archive, {:uri, "files/a"}, "application/zip"}],
               opts(model: "gemini-3.6-flash")
             )

    assert message =~ "unknown media kind"
    assert message =~ ":archive"
  end

  test "analyze/3 returns a public validation error for malformed media sources" do
    assert {:error, %Error{type: :validation_error, message: message}} =
             Understanding.analyze(
               "Inspect",
               [{:image, {:path, "/tmp/a.png"}, "image/png"}],
               opts(model: "gemini-3.6-flash")
             )

    assert message =~ "invalid media source"
  end

  test "analyze/3 returns a public validation error for malformed media entries" do
    assert {:error, %Error{type: :validation_error, message: message}} =
             Understanding.analyze(
               "Inspect",
               [{:image, "files/a"}],
               opts(model: "gemini-3.6-flash")
             )

    assert message =~ "invalid media item"
  end
end
