defmodule Gemini.Interactions.ImageTest do
  use ExUnit.Case, async: false

  alias Gemini.Interactions.Image
  alias Gemini.Types.Interactions.{ImageContent, ResponseFormat}
  alias Plug.Conn

  setup do
    bypass = Gemini.TestHTTPServer.open()
    :meck.new(Gemini.Auth, [:passthrough])

    on_exit(fn -> :meck.unload() end)

    %{bypass: bypass}
  end

  defp image_response do
    %{
      "id" => "int_img",
      "status" => "completed",
      "steps" => [
        %{
          "type" => "model_output",
          "content" => [%{"type" => "image", "data" => "AAAA", "mime_type" => "image/png"}]
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
      assert %{"model" => "gemini-3.1-flash-image", "stream" => true} = Jason.decode!(raw)

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

  test "generate/2 returns the image content block", %{bypass: bypass} do
    respond(bypass, image_response())

    assert {:ok, %ImageContent{data: "AAAA", mime_type: "image/png"}} =
             Image.generate("a nano banana", opts(model: "gemini-3.1-flash-image"))
  end

  test "generate/2 builds an image response_format", %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} =
      Image.generate(
        "a nano banana",
        opts(
          model: "gemini-3.1-flash-image",
          aspect_ratio: "16:9",
          image_size: "2K",
          mime_type: "image/png"
        )
      )

    assert sent_body()["response_format"] == %{
             "type" => "image",
             "aspect_ratio" => "16:9",
             "image_size" => "2K",
             "mime_type" => "image/png"
           }
  end

  test "generate/2 omits response_format keys that were not given", %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} = Image.generate("a nano banana", opts(model: "gemini-3.1-flash-image"))

    assert sent_body()["response_format"] == %{"type" => "image"}
  end

  test "generate/2 preserves an explicit response_format", %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} =
      Image.generate(
        "a nano banana",
        opts(
          model: "gemini-3.1-flash-image",
          response_format: %ResponseFormat.Text{mime_type: "application/json"},
          aspect_ratio: "16:9"
        )
      )

    assert sent_body()["response_format"] == %{
             "type" => "text",
             "mime_type" => "application/json"
           }
  end

  test "generate/2 folds thinking_level into generation_config", %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} =
      Image.generate(
        "a nano banana",
        opts(model: "gemini-3-pro-image", thinking_level: "high", system_instruction: "Be brief")
      )

    body = sent_body()
    assert body["generation_config"]["thinking_level"] == "high"
    assert body["system_instruction"] == "Be brief"
  end

  test "edit/3 prepends a uri image to the input", %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} =
      Image.edit(
        "add a hat",
        {:uri, "files/abc", "image/jpeg"},
        opts(model: "gemini-3.1-flash-image")
      )

    assert [
             %{"type" => "image", "uri" => "files/abc", "mime_type" => "image/jpeg"},
             %{"type" => "text", "text" => "add a hat"}
           ] = sent_body()["input"]
  end

  test "edit/3 prepends inline base64 data", %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} =
      Image.edit(
        "add a hat",
        {:data, "QUJD", "image/png"},
        opts(model: "gemini-3.1-flash-image")
      )

    assert [%{"type" => "image", "data" => "QUJD", "mime_type" => "image/png"} | _] =
             sent_body()["input"]
  end

  test "edit/3 accepts an ImageContent struct", %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} =
      Image.edit(
        "add a hat",
        %ImageContent{type: "image", uri: "files/x", mime_type: "image/png"},
        opts(model: "gemini-3.1-flash-image")
      )

    assert [%{"type" => "image", "uri" => "files/x"} | _] = sent_body()["input"]
  end

  test "edit/3 continues a prior interaction when given previous_interaction_id", %{
    bypass: bypass
  } do
    respond(bypass, image_response())

    {:ok, _} =
      Image.edit(
        "make it blue",
        nil,
        opts(model: "gemini-3.1-flash-image", previous_interaction_id: "int_prev")
      )

    body = sent_body()
    assert body["previous_interaction_id"] == "int_prev"
    assert [%{"type" => "text", "text" => "make it blue"}] = body["input"]
  end

  test "generate/2 returns an Interactions stream unchanged", %{bypass: bypass} do
    respond_stream(bypass)

    assert {:ok, stream} =
             Image.generate(
               "a nano banana",
               opts(
                 model: "gemini-3.1-flash-image",
                 stream: true,
                 connect_timeout: 2_000,
                 max_retries: 0
               )
             )

    assert [%Gemini.Types.Interactions.Events.InteractionEvent{event_id: "evt_1"}] =
             Enum.to_list(stream)
  end

  test "edit/3 returns an Interactions stream unchanged", %{bypass: bypass} do
    respond_stream(bypass)

    assert {:ok, stream} =
             Image.edit(
               "add a hat",
               {:uri, "files/abc", "image/jpeg"},
               opts(
                 model: "gemini-3.1-flash-image",
                 stream: true,
                 connect_timeout: 2_000,
                 max_retries: 0
               )
             )

    assert [%Gemini.Types.Interactions.Events.InteractionEvent{event_id: "evt_1"}] =
             Enum.to_list(stream)
  end
end
