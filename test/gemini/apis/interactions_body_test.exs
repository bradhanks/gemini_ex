defmodule Gemini.APIs.InteractionsBodyTest do
  use ExUnit.Case, async: false

  alias Gemini.APIs.Interactions
  alias Gemini.Types.Interactions.ResponseFormat
  alias Plug.Conn

  setup do
    bypass = Gemini.TestHTTPServer.open()

    :meck.new(Gemini.Auth, [:passthrough])
    on_exit(fn -> :meck.unload() end)

    %{bypass: bypass}
  end

  # Captures the request body the client actually sent, so assertions are on
  # the wire format rather than on an internal function.
  defp capture_body(bypass, opts) do
    parent = self()

    :meck.expect(Gemini.Auth, :get_base_url, fn _type, _credentials ->
      "http://localhost:#{bypass.port}"
    end)

    Gemini.TestHTTPServer.expect_once(bypass, "POST", "/v1beta/interactions", fn conn ->
      {:ok, raw, conn} = Conn.read_body(conn)
      send(parent, {:body, Jason.decode!(raw)})

      conn
      |> Conn.put_resp_content_type("application/json")
      |> Conn.resp(200, Jason.encode!(%{"id" => "int_1", "status" => "completed"}))
    end)

    {:ok, _} =
      Interactions.create(
        "hello",
        Keyword.merge([auth: :gemini, api_key: "test", timeout: 2_000], opts)
      )

    receive do
      {:body, body} -> body
    after
      1_000 -> flunk("no request body captured")
    end
  end

  test "emits the new top-level request fields", %{bypass: bypass} do
    body =
      capture_body(bypass,
        model: "gemini-3.6-flash",
        safety_settings: [
          %{"category" => "HARM_CATEGORY_HARASSMENT", "threshold" => "BLOCK_NONE"}
        ],
        service_tier: "flex",
        environment: "default",
        labels: %{"team" => "search"},
        webhook_config: %{"url" => "https://example.com/hook"},
        user_metadata: %{"user_id" => "u1"}
      )

    assert body["service_tier"] == "flex"
    assert body["environment"] == "default"
    assert body["labels"] == %{"team" => "search"}
    assert body["webhook_config"] == %{"url" => "https://example.com/hook"}
    assert body["user_metadata"] == %{"user_id" => "u1"}
    assert [%{"category" => "HARM_CATEGORY_HARASSMENT"}] = body["safety_settings"]
  end

  test "omits fields that were not provided", %{bypass: bypass} do
    body = capture_body(bypass, model: "gemini-3.6-flash")

    refute Map.has_key?(body, "service_tier")
    refute Map.has_key?(body, "labels")
    refute Map.has_key?(body, "safety_settings")
  end

  test "serializes a ResponseFormat struct", %{bypass: bypass} do
    body =
      capture_body(bypass,
        model: "gemini-3.1-flash-image",
        response_format: %ResponseFormat.Image{aspect_ratio: "16:9", image_size: "2K"}
      )

    assert body["response_format"] == %{
             "type" => "image",
             "aspect_ratio" => "16:9",
             "image_size" => "2K"
           }
  end

  test "still accepts a raw response_format map", %{bypass: bypass} do
    body =
      capture_body(bypass,
        model: "gemini-3.6-flash",
        response_format: %{"type" => "text", "mime_type" => "application/json"}
      )

    assert body["response_format"] == %{
             "type" => "text",
             "mime_type" => "application/json"
           }
  end

  test "accepts a list of response formats", %{bypass: bypass} do
    body =
      capture_body(bypass,
        model: "gemini-3.6-flash",
        response_format: [%ResponseFormat.Text{}, %ResponseFormat.Audio{}]
      )

    assert body["response_format"] == [%{"type" => "text"}, %{"type" => "audio"}]
  end
end
