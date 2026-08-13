defmodule Gemini.Types.Interactions.GenerationConfigTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.{GenerationConfig, SpeechConfig, VideoConfig}

  test "serializes video_config" do
    config = %GenerationConfig{video_config: %VideoConfig{task: "image_to_video"}}

    assert GenerationConfig.to_api(config) == %{
             "video_config" => %{"task" => "image_to_video"}
           }
  end

  test "parses video_config" do
    assert %GenerationConfig{video_config: %VideoConfig{task: "edit"}} =
             GenerationConfig.from_api(%{"video_config" => %{"task" => "edit"}})
  end

  test "omits video_config when unset" do
    refute Map.has_key?(GenerationConfig.to_api(%GenerationConfig{}), "video_config")
  end

  test "documented tasks are exposed" do
    assert VideoConfig.tasks() == [
             "text_to_video",
             "image_to_video",
             "reference_to_video",
             "edit"
           ]
  end

  test "existing fields are unaffected" do
    config = %GenerationConfig{
      thinking_level: "high",
      speech_config: [%SpeechConfig{voice: "Kore"}]
    }

    assert GenerationConfig.to_api(config) == %{
             "thinking_level" => "high",
             "speech_config" => [%{"voice" => "Kore"}]
           }
  end
end
