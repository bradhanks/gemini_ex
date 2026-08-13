defmodule Gemini.Types.Interactions.InteractionTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.{AudioContent, ImageContent, Interaction, TextContent}

  defp steps_response do
    %{
      "id" => "int_123",
      "object" => "interaction",
      "status" => "completed",
      "model" => "gemini-3.6-flash",
      "steps" => [
        %{"type" => "user_input", "content" => [%{"type" => "text", "text" => "Hi"}]},
        %{"type" => "thought", "signature" => "sig_a"},
        %{"type" => "google_search_call", "signature" => "sig_b"},
        %{"type" => "model_output", "content" => [%{"type" => "text", "text" => "Hello!"}]}
      ]
    }
  end

  describe "from_api/1 with steps" do
    test "parses steps" do
      interaction = Interaction.from_api(steps_response())

      assert length(interaction.steps) == 4
    end

    test "derives outputs by flattening every step's content, in order" do
      interaction = Interaction.from_api(steps_response())

      assert [%TextContent{text: "Hi"}, %TextContent{text: "Hello!"}] = interaction.outputs
    end

    test "malformed known and unknown step content never leaks into typed outputs" do
      response = %{
        "id" => "int_malformed",
        "status" => "completed",
        "steps" => [
          %{"type" => "model_output", "content" => %{"type" => "text", "text" => "scalar"}},
          %{
            "type" => "future_tool_call",
            "content" => [
              %{"type" => "text", "text" => "kept"},
              %{"type" => "future_content", "value" => 1},
              %{"text" => "missing type"},
              false
            ],
            "opaque" => %{"preserved" => true}
          },
          "malformed step"
        ]
      }

      interaction = Interaction.from_api(response)

      assert [%TextContent{text: "kept"}] = interaction.outputs
      assert Enum.all?(interaction.outputs, &is_struct/1)
      assert Interaction.output_text(interaction) == {:error, :not_found}
      assert Interaction.output_image(interaction) == {:error, :not_found}
      assert Interaction.output_audio(interaction) == {:error, :not_found}
      assert Interaction.output_video(interaction) == {:error, :not_found}
    end

    test "parses the object field" do
      assert Interaction.from_api(steps_response()).object == "interaction"
    end
  end

  describe "from_api/1 backward compatibility" do
    test "an outputs-shaped response still parses and leaves steps nil" do
      interaction =
        Interaction.from_api(%{
          "id" => "int_1",
          "status" => "completed",
          "outputs" => [%{"type" => "text", "text" => "Legacy"}]
        })

      assert [%TextContent{text: "Legacy"}] = interaction.outputs
      assert interaction.steps == nil
    end
  end

  describe "output accessors" do
    test "output_text/1 prefers the server-provided field" do
      interaction =
        Interaction.from_api(Map.put(steps_response(), "output_text", "From server"))

      assert Interaction.output_text(interaction) == {:ok, "From server"}
    end

    test "output_text/1 preserves an explicitly empty server-provided field" do
      interaction = Interaction.from_api(Map.put(steps_response(), "output_text", ""))

      assert Interaction.output_text(interaction) == {:ok, ""}
    end

    test "output_text/1 falls back to the last model_output step" do
      assert Interaction.output_text(Interaction.from_api(steps_response())) == {:ok, "Hello!"}
    end

    test "output_text/1 does not treat user_input step content as output" do
      interaction =
        Interaction.from_api(
          Map.put(steps_response(), "steps", [
            %{"type" => "user_input", "content" => [%{"type" => "text", "text" => "Hi"}]}
          ])
        )

      assert Interaction.output_text(interaction) == {:error, :not_found}
    end

    test "output_text/1 returns :not_found when there is no text anywhere" do
      interaction = Interaction.from_api(%{"id" => "i", "status" => "completed"})

      assert Interaction.output_text(interaction) == {:error, :not_found}
    end

    test "output_text/1 ignores text blocks whose text value is not binary" do
      interaction =
        Interaction.from_api(%{
          "id" => "i",
          "status" => "completed",
          "steps" => [
            %{
              "type" => "model_output",
              "content" => [%{"type" => "text", "text" => %{"malformed" => true}}]
            }
          ]
        })

      assert Interaction.output_text(interaction) == {:error, :not_found}
    end

    test "output_image/1 falls back to the last image block in steps" do
      response =
        Map.put(steps_response(), "steps", [
          %{
            "type" => "model_output",
            "content" => [%{"type" => "image", "data" => "abc", "mime_type" => "image/png"}]
          }
        ])

      assert {:ok, %ImageContent{data: "abc"}} =
               Interaction.output_image(Interaction.from_api(response))
    end

    test "output_audio/1 falls back to the last audio block in steps" do
      response =
        Map.put(steps_response(), "steps", [
          %{
            "type" => "model_output",
            "content" => [%{"type" => "audio", "data" => "pcm", "mime_type" => "audio/pcm"}]
          }
        ])

      assert {:ok, %AudioContent{data: "pcm"}} =
               Interaction.output_audio(Interaction.from_api(response))
    end
  end

  describe "thought_signatures/1" do
    test "collects signatures from thought and built-in tool steps in order" do
      interaction = Interaction.from_api(steps_response())

      assert Interaction.thought_signatures(interaction) == ["sig_a", "sig_b"]
    end

    test "returns [] when there are no steps" do
      interaction = Interaction.from_api(%{"id" => "i", "status" => "completed"})

      assert Interaction.thought_signatures(interaction) == []
    end
  end

  describe "to_api/1" do
    test "round-trips steps" do
      interaction = Interaction.from_api(steps_response())
      encoded = Interaction.to_api(interaction)

      assert encoded["steps"] == steps_response()["steps"]
    end
  end
end
