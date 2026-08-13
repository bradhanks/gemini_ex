defmodule Gemini.Interactions.VideoTest do
  use ExUnit.Case, async: false

  alias Gemini.Interactions.Video
  alias Gemini.Types.Interactions.{GenerationConfig, ResponseFormat, VideoContent}
  alias Plug.Conn

  setup do
    bypass = Gemini.TestHTTPServer.open()
    :meck.new(Gemini.Auth, [:passthrough])

    on_exit(fn -> :meck.unload() end)

    %{bypass: bypass}
  end

  defp video_response do
    %{
      "id" => "int_vid",
      "status" => "completed",
      "steps" => [
        %{
          "type" => "model_output",
          "content" => [
            %{"type" => "video", "uri" => "https://example.com/v.mp4", "mime_type" => "video/mp4"}
          ]
        }
      ]
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
      {:ok, raw, conn} = Conn.read_body(conn)
      assert %{"model" => "gemini-omni-flash", "stream" => true} = Jason.decode!(raw)

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

  test "generate/2 returns the video content block", %{bypass: bypass} do
    respond(bypass, video_response())

    assert {:ok, %VideoContent{uri: "https://example.com/v.mp4"}} =
             Video.generate("a cat surfing", opts(model: "gemini-omni-flash"))
  end

  test "generate/2 builds a video response_format with aspect_ratio and delivery",
       %{bypass: bypass} do
    respond(bypass, video_response())

    {:ok, _} =
      Video.generate(
        "a cat surfing",
        opts(model: "gemini-omni-flash", aspect_ratio: "9:16", delivery: "uri")
      )

    assert sent_body()["response_format"] == %{
             "type" => "video",
             "aspect_ratio" => "9:16",
             "delivery" => "uri"
           }
  end

  test "generate/2 maps task into generation_config.video_config", %{bypass: bypass} do
    respond(bypass, video_response())

    {:ok, _} =
      Video.generate(
        "animate this",
        opts(model: "gemini-omni-flash", task: "image_to_video")
      )

    assert sent_body()["generation_config"]["video_config"] == %{"task" => "image_to_video"}
  end

  test "generate/2 preserves an explicit response_format including nil", %{bypass: bypass} do
    respond(bypass, video_response())

    {:ok, _} =
      Video.generate(
        "a cat surfing",
        opts(model: "gemini-omni-flash", response_format: nil, aspect_ratio: "9:16")
      )

    refute Map.has_key?(sent_body(), "response_format")
  end

  test "generate/2 preserves an explicit generation_config including nil", %{bypass: bypass} do
    respond(bypass, video_response())

    {:ok, _} =
      Video.generate(
        "animate this",
        opts(model: "gemini-omni-flash", generation_config: nil, task: "edit")
      )

    refute Map.has_key?(sent_body(), "generation_config")
  end

  test "generate/2 preserves a structured explicit generation_config and response_format",
       %{bypass: bypass} do
    respond(bypass, video_response())

    {:ok, _} =
      Video.generate(
        "animate this",
        opts(
          model: "gemini-omni-flash",
          generation_config: %GenerationConfig{temperature: 0.4},
          response_format: %ResponseFormat.Text{mime_type: "application/json"},
          task: "edit",
          delivery: "uri"
        )
      )

    body = sent_body()
    assert body["generation_config"] == %{"temperature" => 0.4}
    assert body["response_format"] == %{"type" => "text", "mime_type" => "application/json"}
  end

  test "generate/2 passes previous_interaction_id for stateful editing", %{bypass: bypass} do
    respond(bypass, video_response())

    {:ok, _} =
      Video.generate(
        "make it night",
        opts(model: "gemini-omni-flash", previous_interaction_id: "int_prev")
      )

    assert sent_body()["previous_interaction_id"] == "int_prev"
  end

  test "generate/2 returns an Interactions stream unchanged", %{bypass: bypass} do
    respond_stream(bypass)

    assert {:ok, stream} =
             Video.generate(
               "a cat surfing",
               opts(
                 model: "gemini-omni-flash",
                 stream: true,
                 connect_timeout: 2_000,
                 max_retries: 0
               )
             )

    assert [%Gemini.Types.Interactions.Events.InteractionEvent{event_id: "evt_1"}] =
             Enum.to_list(stream)
  end

  test "generate_interaction/2 returns an Interactions stream unchanged", %{bypass: bypass} do
    respond_stream(bypass)

    assert {:ok, stream} =
             Video.generate_interaction(
               "a cat surfing",
               opts(
                 model: "gemini-omni-flash",
                 stream: true,
                 connect_timeout: 2_000,
                 max_retries: 0
               )
             )

    assert [%Gemini.Types.Interactions.Events.InteractionEvent{event_id: "evt_1"}] =
             Enum.to_list(stream)
  end
end
