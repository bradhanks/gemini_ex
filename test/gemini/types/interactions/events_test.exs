defmodule Gemini.Types.Interactions.EventsTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.{DeltaTextDelta, DeltaThoughtSignatureDelta}

  alias Gemini.Types.Interactions.Events.{
    InteractionEvent,
    InteractionSSEEvent,
    StepDelta,
    StepStart,
    StepStop
  }

  describe "InteractionSSEEvent.from_api/1" do
    test "dispatches step.delta with a text delta" do
      event =
        InteractionSSEEvent.from_api(%{
          "event_type" => "step.delta",
          "event_id" => "e1",
          "index" => 0,
          "delta" => %{"type" => "text", "text" => "Hel"}
        })

      assert %StepDelta{index: 0, delta: %DeltaTextDelta{text: "Hel"}} = event
    end

    test "dispatches step.delta with a thought_signature delta" do
      event =
        InteractionSSEEvent.from_api(%{
          "event_type" => "step.delta",
          "index" => 1,
          "delta" => %{"type" => "thought_signature", "signature" => "sig_a"}
        })

      assert %StepDelta{delta: %DeltaThoughtSignatureDelta{}} = event
    end

    test "dispatches step.start" do
      assert %StepStart{index: 0} =
               InteractionSSEEvent.from_api(%{"event_type" => "step.start", "index" => 0})
    end

    test "dispatches step.stop" do
      assert %StepStop{index: 2} =
               InteractionSSEEvent.from_api(%{"event_type" => "step.stop", "index" => 2})
    end

    test "dispatches interaction.created" do
      assert %InteractionEvent{} =
               InteractionSSEEvent.from_api(%{
                 "event_type" => "interaction.created",
                 "interaction" => %{"id" => "i", "status" => "in_progress"}
               })
    end

    test "dispatches interaction.completed" do
      assert %InteractionEvent{} =
               InteractionSSEEvent.from_api(%{
                 "event_type" => "interaction.completed",
                 "interaction" => %{"id" => "i", "status" => "completed"}
               })
    end

    test "still dispatches the legacy interaction.start spelling" do
      assert %InteractionEvent{} =
               InteractionSSEEvent.from_api(%{
                 "event_type" => "interaction.start",
                 "interaction" => %{"id" => "i", "status" => "in_progress"}
               })
    end

    test "returns nil for an unrecognized event_type" do
      assert InteractionSSEEvent.from_api(%{"event_type" => "nope"}) == nil
    end
  end

  describe "to_api/1" do
    test "StepDelta round-trips" do
      raw = %{
        "event_type" => "step.delta",
        "event_id" => "e1",
        "index" => 0,
        "delta" => %{"type" => "text", "text" => "Hel"}
      }

      assert raw |> StepDelta.from_api() |> StepDelta.to_api() == raw
    end
  end
end
