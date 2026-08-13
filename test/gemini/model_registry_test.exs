defmodule Gemini.ModelRegistryTest do
  use ExUnit.Case, async: true

  alias Gemini.ModelRegistry

  describe "get/1" do
    test "resolves canonical model code" do
      assert %{key: :gemini_3_1_pro_preview, code: "gemini-3.1-pro-preview"} =
               ModelRegistry.get("gemini-3.1-pro-preview")
    end

    test "resolves project-scoped resource names with endpoint suffixes" do
      model_name =
        "projects/test/locations/us-central1/publishers/google/models/gemini-2.5-flash-native-audio-preview-12-2025:bidiGenerateContent"

      assert %{key: :gemini_2_5_flash_native_audio_preview_12_2025} =
               ModelRegistry.get(model_name)
    end
  end

  describe "capability helpers" do
    test "supports?/3 returns capability state match" do
      assert ModelRegistry.supports?("gemini-3.1-pro-preview", :thinking)
      refute ModelRegistry.supports?("gemini-3.1-pro-preview", :live_api)
      assert ModelRegistry.supports?("gemini-2.0-flash", :thinking, :experimental)
    end

    test "with_capability/2 returns matching model codes" do
      supported_live_models = ModelRegistry.with_capability(:live_api, :supported)

      assert "gemini-2.5-flash-native-audio-preview-12-2025" in supported_live_models
      refute "gemini-3.1-pro-preview" in supported_live_models
    end
  end

  describe "live_candidates/2" do
    test "returns ordered live candidates for text and audio" do
      text_candidates = ModelRegistry.live_candidates(:text)
      audio_candidates = ModelRegistry.live_candidates(:audio)

      assert hd(audio_candidates) == "gemini-3.1-flash-live-preview"
      assert text_candidates == []
      assert "gemini-2.5-flash-native-audio-preview-12-2025" in audio_candidates
      assert "gemini-2.5-flash-native-audio-latest" in audio_candidates
    end
  end

  describe "live session metadata" do
    test "returns explicit session response modalities and text input method" do
      assert [:audio] ==
               ModelRegistry.live_session_response_modalities("gemini-3.1-flash-live-preview")

      assert :realtime_input ==
               ModelRegistry.live_text_input_method("gemini-3.1-flash-live-preview")

      assert [:audio] ==
               ModelRegistry.live_session_response_modalities(
                 "gemini-2.5-flash-native-audio-preview-12-2025"
               )

      assert :client_content ==
               ModelRegistry.live_text_input_method(
                 "gemini-2.5-flash-native-audio-preview-12-2025"
               )
    end
  end

  describe "current model coverage" do
    @current_models [
      "gemini-3.6-flash",
      "gemini-3.5-flash",
      "gemini-3.5-flash-lite",
      "gemini-3.1-flash-lite",
      "gemini-3.1-flash-image",
      "gemini-3.1-flash-lite-image",
      "gemini-3-pro-image",
      "gemini-3.1-flash-tts-preview",
      "gemini-3.5-live-translate-preview",
      "gemini-omni-flash",
      "gemini-embedding-2-preview"
    ]

    test "every currently documented model is registered" do
      for code <- @current_models do
        assert Gemini.model_exists?(code), "#{code} is not in the model registry"
      end
    end

    test "gemini-omni-flash-preview resolves as an alias of gemini-omni-flash" do
      assert Gemini.model_exists?("gemini-omni-flash-preview")

      assert %{code: "gemini-omni-flash"} =
               ModelRegistry.get("gemini-omni-flash-preview")
    end

    test "previously registered models are still present" do
      for code <- ["gemini-3.1-pro-preview", "gemini-3-pro-preview", "gemini-2.5-flash"] do
        assert Gemini.model_exists?(code), "#{code} was dropped from the registry"
      end
    end

    test "new entries use the established registry shape and documented metadata" do
      expected_keys =
        "gemini-3.1-pro-preview"
        |> ModelRegistry.get()
        |> Map.keys()
        |> Enum.sort()

      for code <- @current_models do
        entry = ModelRegistry.get(code)

        assert Enum.sort(Map.keys(entry)) == expected_keys
        assert entry.source_page == "https://ai.google.dev/gemini-api/docs/models"
      end

      assert %{track: :stable, input_modalities: [:text, :image, :video, :audio, :pdf]} =
               ModelRegistry.get("gemini-3.6-flash")

      assert %{output_modalities: [:embeddings]} =
               ModelRegistry.get("gemini-embedding-2-preview")
    end

    test "specialized model capabilities are recorded conservatively" do
      assert ModelRegistry.supports?("gemini-3.1-flash-image", :image_generation)
      assert ModelRegistry.supports?("gemini-3.1-flash-image", :thinking)
      assert ModelRegistry.supports?("gemini-3-pro-image", :thinking)

      assert ModelRegistry.supports?(
               "gemini-3.1-flash-lite-image",
               :thinking,
               :not_supported
             )

      assert ModelRegistry.supports?("gemini-3.1-flash-tts-preview", :audio_generation)
      assert ModelRegistry.supports?("gemini-omni-flash", :batch_api, :unknown)
      assert ModelRegistry.supports?("gemini-embedding-2-preview", :thinking, :unknown)
    end
  end
end
