defmodule Gemini.Types.Interactions.ContentResolutionTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.{Content, DocumentContent, ImageContent, VideoContent}

  test "DocumentContent parses and emits resolution" do
    raw = %{
      "type" => "document",
      "uri" => "files/abc",
      "mime_type" => "application/pdf",
      "resolution" => "high"
    }

    assert %DocumentContent{resolution: "high"} = Content.from_api(raw)
    assert Content.to_api(Content.from_api(raw)) == raw
  end

  test "DocumentContent accepts the documented unspecified resolution" do
    raw = %{"type" => "document", "uri" => "files/abc", "resolution" => "unspecified"}

    assert %DocumentContent{resolution: "unspecified"} = Content.from_api(raw)
    assert Content.to_api(Content.from_api(raw)) == raw
  end

  test "DocumentContent omits resolution when unset" do
    raw = %{"type" => "document", "uri" => "files/abc", "mime_type" => "application/pdf"}

    refute Map.has_key?(Content.to_api(Content.from_api(raw)), "resolution")
  end

  test "ImageContent resolution still round-trips, including ultra_high" do
    raw = %{"type" => "image", "uri" => "files/i", "resolution" => "ultra_high"}

    assert %ImageContent{resolution: "ultra_high"} = Content.from_api(raw)
    assert Content.to_api(Content.from_api(raw)) == raw
  end

  test "VideoContent resolution still round-trips" do
    raw = %{"type" => "video", "uri" => "files/v", "resolution" => "low"}

    assert %VideoContent{resolution: "low"} = Content.from_api(raw)
  end
end
