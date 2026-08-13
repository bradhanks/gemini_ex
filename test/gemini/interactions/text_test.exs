defmodule Gemini.Interactions.TextTest do
  use ExUnit.Case, async: false

  alias Gemini.Error
  alias Gemini.Interactions.Text
  alias Gemini.Types.Interactions.Interaction
  alias Plug.Conn

  setup do
    bypass = Gemini.TestHTTPServer.open()
    :meck.new(Gemini.Auth, [:passthrough])

    on_exit(fn -> :meck.unload() end)

    %{bypass: bypass}
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

  test "generate/2 returns the output text", %{bypass: bypass} do
    respond(bypass, %{
      "id" => "int_1",
      "status" => "completed",
      "steps" => [
        %{"type" => "model_output", "content" => [%{"type" => "text", "text" => "Hi there"}]}
      ]
    })

    assert {:ok, "Hi there"} = Text.generate("Say hi", opts(model: "gemini-3.6-flash"))
  end

  test "generate/2 maps top-level generation options into generation_config", %{bypass: bypass} do
    respond(bypass, %{"id" => "i", "status" => "completed", "output_text" => "ok"})

    {:ok, _} =
      Text.generate(
        "Think",
        opts(
          model: "gemini-3.6-flash",
          thinking_level: "high",
          thinking_summaries: "auto",
          temperature: 0.2
        )
      )

    config = sent_body()["generation_config"]
    assert config["thinking_level"] == "high"
    assert config["thinking_summaries"] == "auto"
    assert config["temperature"] == 0.2
  end

  test "generate/2 passes system_instruction through at the top level", %{bypass: bypass} do
    respond(bypass, %{"id" => "i", "status" => "completed", "output_text" => "ok"})

    {:ok, _} =
      Text.generate("Hi", opts(model: "gemini-3.6-flash", system_instruction: "Be terse"))

    body = sent_body()
    assert body["system_instruction"] == "Be terse"
    refute Map.has_key?(body, "generation_config")
  end

  test "generate/2 preserves an explicit generation_config", %{bypass: bypass} do
    explicit_config = %{temperature: 0.7}
    respond(bypass, %{"id" => "i", "status" => "completed", "output_text" => "ok"})

    {:ok, _} =
      Text.generate(
        "Think",
        opts(
          model: "gemini-3.6-flash",
          generation_config: explicit_config,
          thinking_level: "high"
        )
      )

    assert sent_body()["generation_config"] == %{"temperature" => 0.7}
  end

  test "generate/2 returns :not_found as an error when there is no text", %{bypass: bypass} do
    respond(bypass, %{"id" => "i", "status" => "completed"})

    assert {:error, :not_found} = Text.generate("Hi", opts(model: "gemini-3.6-flash"))
  end

  test "generate_interaction/2 returns the whole interaction", %{bypass: bypass} do
    respond(bypass, %{
      "id" => "int_9",
      "status" => "completed",
      "steps" => [%{"type" => "thought", "signature" => "sig_a"}]
    })

    assert {:ok, %Interaction{id: "int_9"} = interaction} =
             Text.generate_interaction("Hi", opts(model: "gemini-3.6-flash"))

    assert Interaction.thought_signatures(interaction) == ["sig_a"]
  end

  test "generate/2 returns an Interactions stream unchanged", %{bypass: bypass} do
    respond_stream(bypass)

    assert {:ok, stream} =
             Text.generate(
               "Hi",
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

  test "generate/2 leaves missing model validation to Interactions.create/2" do
    assert {:error, %Error{type: :validation_error}} =
             Text.generate("Hi", auth: :gemini, api_key: "test")
  end
end
