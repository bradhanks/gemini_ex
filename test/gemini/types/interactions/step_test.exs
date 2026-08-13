defmodule Gemini.Types.Interactions.StepTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.{
    FunctionCallStep,
    FunctionResultStep,
    StandardStep,
    Step,
    TextContent,
    UnknownStep
  }

  describe "from_api/1" do
    test "parses a model_output step with content blocks" do
      step =
        Step.from_api(%{
          "type" => "model_output",
          "content" => [%{"type" => "text", "text" => "Hello"}]
        })

      assert %StandardStep{type: "model_output"} = step
      assert [%TextContent{text: "Hello"}] = step.content
    end

    test "parses a thought step and keeps its signature and summary" do
      step =
        Step.from_api(%{
          "type" => "thought",
          "signature" => "Ci4B1a2b3c",
          "summary" => [%{"type" => "text", "text" => "Considering options"}]
        })

      assert %StandardStep{type: "thought", signature: "Ci4B1a2b3c"} = step
      assert [%TextContent{text: "Considering options"}] = step.summary
    end

    test "parses a google_search_call step and keeps its signature" do
      step = Step.from_api(%{"type" => "google_search_call", "signature" => "sig_xyz"})

      assert %StandardStep{type: "google_search_call", signature: "sig_xyz"} = step
    end

    test "parses a function_call step with arguments and name" do
      step =
        Step.from_api(%{
          "type" => "function_call",
          "name" => "get_weather",
          "id" => "call_1",
          "arguments" => %{"location" => "Boston"}
        })

      assert %FunctionCallStep{
               type: "function_call",
               name: "get_weather",
               id: "call_1",
               arguments: %{"location" => "Boston"}
             } = step
    end

    test "parses a function_result step with call_id" do
      step =
        Step.from_api(%{
          "type" => "function_result",
          "call_id" => "call_1",
          "content" => [%{"type" => "text", "text" => "72F"}]
        })

      assert %FunctionResultStep{type: "function_result", call_id: "call_1"} = step
    end

    test "degrades an unrecognized step type into UnknownStep retaining the raw map" do
      raw = %{"type" => "future_tool_call", "signature" => "sig_future", "whatever" => 1}

      assert %UnknownStep{type: "future_tool_call", raw: ^raw} = Step.from_api(raw)
    end

    test "returns nil for nil" do
      assert Step.from_api(nil) == nil
    end
  end

  describe "to_api/1" do
    test "round-trips a thought step byte-identically" do
      raw = %{"type" => "thought", "signature" => "Ci4B1a2b3c"}

      assert raw |> Step.from_api() |> Step.to_api() == raw
    end

    test "round-trips a thought summary byte-identically" do
      raw = %{
        "type" => "thought",
        "summary" => [%{"type" => "text", "text" => "Considering options"}]
      }

      assert raw |> Step.from_api() |> Step.to_api() == raw
    end

    test "round-trips an unrecognized step type byte-identically" do
      raw = %{"type" => "future_tool_call", "signature" => "sig_future", "whatever" => 1}

      assert raw |> Step.from_api() |> Step.to_api() == raw
    end

    test "round-trips a function_call step" do
      raw = %{
        "type" => "function_call",
        "name" => "get_weather",
        "id" => "call_1",
        "arguments" => %{"location" => "Boston"}
      }

      assert raw |> Step.from_api() |> Step.to_api() == raw
    end

    test "passes a raw map through unchanged" do
      assert Step.to_api(%{"type" => "model_output"}) == %{"type" => "model_output"}
    end
  end

  describe "content/1 and signature/1" do
    test "content/1 returns [] when the step has no content" do
      assert Step.content(Step.from_api(%{"type" => "thought"})) == []
    end

    test "signature/1 reads the signature off an unknown step's raw map" do
      step = Step.from_api(%{"type" => "future_tool_call", "signature" => "sig_future"})

      assert Step.signature(step) == "sig_future"
    end
  end

  describe "UnknownStep conversions" do
    test "supports nil, passthrough, and map conversion heads" do
      raw = %{"type" => "future_tool_call"}
      step = UnknownStep.from_api(raw)

      assert UnknownStep.from_api(nil) == nil
      assert UnknownStep.from_api(step) == step
      assert UnknownStep.to_api(nil) == nil
      assert UnknownStep.to_api(raw) == raw
      assert UnknownStep.to_api(step) == raw
    end
  end
end
