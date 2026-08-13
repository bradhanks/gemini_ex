defmodule Gemini.Types.Interactions.ToolTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.GoogleSearch

  test "serializes to just the type when search_types is unset" do
    assert GoogleSearch.to_api(%GoogleSearch{}) == %{"type" => "google_search"}
  end

  test "serializes search_types when set" do
    assert GoogleSearch.to_api(%GoogleSearch{search_types: ["web_search", "image_search"]}) ==
             %{"type" => "google_search", "search_types" => ["web_search", "image_search"]}
  end

  test "parses search_types" do
    assert %GoogleSearch{search_types: ["image_search"]} =
             GoogleSearch.from_api(%{
               "type" => "google_search",
               "search_types" => ["image_search"]
             })
  end
end
