defmodule Gemini.Types.Interactions.DeltaTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.{
    Delta,
    DeltaArgumentsDelta,
    DeltaFileSearchCallDelta,
    DeltaGoogleMapsCallDelta,
    DeltaGoogleMapsResultDelta,
    DeltaRetrievalCallDelta,
    DeltaRetrievalResultDelta,
    DeltaTextAnnotationDelta
  }

  test "parses arguments_delta, which streams function call arguments" do
    assert %DeltaArgumentsDelta{arguments: "{\"loc"} =
             Delta.from_api(%{"type" => "arguments_delta", "arguments" => "{\"loc"})
  end

  test "parses text_annotation_delta" do
    assert %DeltaTextAnnotationDelta{} =
             Delta.from_api(%{
               "type" => "text_annotation_delta",
               "annotation" => %{"type" => "url_citation", "uri" => "https://example.com"}
             })
  end

  test "parses google_maps_call and google_maps_result" do
    assert %DeltaGoogleMapsCallDelta{} = Delta.from_api(%{"type" => "google_maps_call"})
    assert %DeltaGoogleMapsResultDelta{} = Delta.from_api(%{"type" => "google_maps_result"})
  end

  test "parses retrieval_call and retrieval_result" do
    assert %DeltaRetrievalCallDelta{} = Delta.from_api(%{"type" => "retrieval_call"})
    assert %DeltaRetrievalResultDelta{} = Delta.from_api(%{"type" => "retrieval_result"})
  end

  test "parses file_search_call" do
    assert %DeltaFileSearchCallDelta{} = Delta.from_api(%{"type" => "file_search_call"})
  end

  test "still returns the raw map for a type it does not model" do
    raw = %{"type" => "something_new", "x" => 1}

    assert Delta.from_api(raw) == raw
  end

  test "round-trips arguments_delta" do
    raw = %{"type" => "arguments_delta", "arguments" => "{\"loc"}

    assert raw |> Delta.from_api() |> Delta.to_api() == raw
  end
end
