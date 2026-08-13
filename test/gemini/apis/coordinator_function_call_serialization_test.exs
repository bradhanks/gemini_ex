defmodule Gemini.APIs.CoordinatorFunctionCallSerializationTest do
  @moduledoc """
  Tests that model turns containing function calls survive request serialization.

  A manual function-calling loop replays the model's function-call turn back to
  the API before appending the tool response. Two shapes reach the coordinator:

    - `%Part{function_call: %Altar.ADM.FunctionCall{}}` — what `Part.from_api/1`
      produces when parsing a response, so this is the shape users get back and
      hand straight to the next request.
    - `%{function_call: %{name: ..., args: ...}}` — what `Gemini.Chat.add_turn/3`
      builds for a `"model"` turn.

  Both must serialize to the wire field `functionCall`.
  """

  # async: false because :meck operates on global module state
  use ExUnit.Case, async: false

  alias Gemini.APIs.Coordinator
  alias Gemini.Types.Content
  alias Gemini.Types.Part

  setup do
    :meck.new(Gemini.Client.HTTP, [:passthrough])

    on_exit(fn ->
      try do
        :meck.unload(Gemini.Client.HTTP)
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

  defp capture_request_body(input, opts \\ []) do
    test_pid = self()

    :meck.expect(Gemini.Client.HTTP, :post, fn _path, body, _opts ->
      send(test_pid, {:captured_body, body})

      {:ok,
       %{"candidates" => [%{"content" => %{"parts" => [%{"text" => "ok"}], "role" => "model"}}]}}
    end)

    _result = Coordinator.generate_content(input, opts)

    receive do
      {:captured_body, body} -> body
    after
      1000 -> flunk("Did not receive captured request body")
    end
  end

  defp model_parts(body) do
    contents = body.contents || body[:contents]

    contents
    |> Enum.find(fn content -> (content[:role] || content["role"]) == "model" end)
    |> then(fn content -> content[:parts] || content["parts"] end)
  end

  describe "%Part{function_call: ...} in a model turn" do
    test "serializes as functionCall with name and args" do
      {:ok, call} =
        Altar.ADM.new_function_call(%{
          call_id: "call_1",
          name: "get_weather",
          args: %{"location" => "Boston"}
        })

      body =
        capture_request_body([
          %Content{role: "user", parts: [Part.text("Weather in Boston?")]},
          %Content{role: "model", parts: [%Part{function_call: call}]}
        ])

      assert [part] = model_parts(body)

      function_call = part[:functionCall] || part["functionCall"]

      assert function_call != nil,
             "expected the model turn to carry a functionCall part, got: #{inspect(part)}"

      assert (function_call[:name] || function_call["name"]) == "get_weather"
      assert (function_call[:args] || function_call["args"]) == %{"location" => "Boston"}
    end

    test "defaults missing args to an empty map" do
      {:ok, call} = Altar.ADM.new_function_call(%{call_id: "call_2", name: "ping", args: %{}})

      body =
        capture_request_body([
          %Content{role: "user", parts: [Part.text("ping")]},
          %Content{role: "model", parts: [%Part{function_call: call}]}
        ])

      assert [part] = model_parts(body)
      function_call = part[:functionCall] || part["functionCall"]
      assert (function_call[:args] || function_call["args"]) == %{}
    end

    test "keeps the thought signature alongside the function call" do
      {:ok, call} = Altar.ADM.new_function_call(%{call_id: "call_3", name: "ping", args: %{}})

      body =
        capture_request_body([
          %Content{role: "user", parts: [Part.text("ping")]},
          %Content{
            role: "model",
            parts: [%Part{function_call: call, thought_signature: "sig-abc"}]
          }
        ])

      assert [part] = model_parts(body)
      assert part[:functionCall] || part["functionCall"]
      assert (part[:thoughtSignature] || part["thoughtSignature"]) == "sig-abc"
    end
  end

  describe "%{function_call: ...} map in a model turn (Gemini.Chat shape)" do
    test "normalizes snake_case function_call to camelCase functionCall" do
      body =
        capture_request_body([
          %Content{role: "user", parts: [Part.text("Weather in Boston?")]},
          %Content{
            role: "model",
            parts: [%{function_call: %{name: "get_weather", args: %{"location" => "Boston"}}}]
          }
        ])

      assert [part] = model_parts(body)

      refute Map.has_key?(part, :function_call),
             "snake_case function_call must not reach the wire: #{inspect(part)}"

      function_call = part[:functionCall] || part["functionCall"]
      assert function_call != nil
      assert (function_call[:name] || function_call["name"]) == "get_weather"
      assert (function_call[:args] || function_call["args"]) == %{"location" => "Boston"}
    end

    test "normalizes string-keyed function_call maps" do
      body =
        capture_request_body([
          %Content{role: "user", parts: [Part.text("hi")]},
          %Content{
            role: "model",
            parts: [%{"function_call" => %{"name" => "ping", "args" => %{}}}]
          }
        ])

      assert [part] = model_parts(body)
      function_call = part[:functionCall] || part["functionCall"]
      assert function_call != nil
      assert (function_call[:name] || function_call["name"]) == "ping"
    end
  end

  describe "Gemini.Chat history round trip" do
    test "a chat-built model turn serializes its function call" do
      {:ok, call} =
        Altar.ADM.new_function_call(%{
          call_id: "call_4",
          name: "get_weather",
          args: %{"location" => "Boston"}
        })

      chat =
        Gemini.Chat.new()
        |> Gemini.Chat.add_turn("user", "Weather in Boston?")
        |> Gemini.Chat.add_turn("model", [call])

      body = capture_request_body(chat.history)

      assert [part] = model_parts(body)
      function_call = part[:functionCall] || part["functionCall"]

      assert function_call != nil,
             "expected the chat-built model turn to carry functionCall, got: #{inspect(part)}"

      assert (function_call[:name] || function_call["name"]) == "get_weather"
    end
  end
end
