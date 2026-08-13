defmodule Gemini.Types.Interactions.ResponseFormatTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.ResponseFormat

  alias Gemini.Types.Interactions.ResponseFormat.{
    Audio,
    Image,
    JsonObject,
    JsonSchema,
    Text,
    Video
  }

  test "Text with a JSON schema serializes as the structured-output shape" do
    schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}

    assert ResponseFormat.to_api(%Text{mime_type: "application/json", schema: schema}) == %{
             "type" => "text",
             "mime_type" => "application/json",
             "schema" => schema
           }
  end

  test "Text with no fields set serializes to just the type" do
    assert ResponseFormat.to_api(%Text{}) == %{"type" => "text"}
  end

  test "Image serializes aspect_ratio and image_size" do
    assert ResponseFormat.to_api(%Image{
             mime_type: "image/png",
             aspect_ratio: "16:9",
             image_size: "2K"
           }) == %{
             "type" => "image",
             "mime_type" => "image/png",
             "aspect_ratio" => "16:9",
             "image_size" => "2K"
           }
  end

  test "Audio serializes to just the type" do
    assert ResponseFormat.to_api(%Audio{}) == %{"type" => "audio"}
  end

  test "Video serializes aspect_ratio and delivery" do
    assert ResponseFormat.to_api(%Video{aspect_ratio: "9:16", delivery: "uri"}) == %{
             "type" => "video",
             "aspect_ratio" => "9:16",
             "delivery" => "uri"
           }
  end

  test "JsonSchema serializes the nested json_schema object" do
    schema = %{"type" => "object"}

    assert ResponseFormat.to_api(%JsonSchema{name: "Recipe", schema: schema, strict: true}) == %{
             "type" => "json_schema",
             "json_schema" => %{"name" => "Recipe", "schema" => schema, "strict" => true}
           }
  end

  test "JsonObject serializes to just the type" do
    assert ResponseFormat.to_api(%JsonObject{}) == %{"type" => "json_object"}
  end

  test "a raw map passes through unchanged" do
    raw = %{"type" => "image", "aspect_ratio" => "21:9"}

    assert ResponseFormat.to_api(raw) == raw
  end

  test "a list of formats serializes elementwise" do
    assert ResponseFormat.to_api([%Text{}, %Audio{}]) == [
             %{"type" => "text"},
             %{"type" => "audio"}
           ]
  end

  test "nil passes through" do
    assert ResponseFormat.to_api(nil) == nil
  end

  test "from_api parses a known variant" do
    assert %Image{aspect_ratio: "16:9"} =
             ResponseFormat.from_api(%{"type" => "image", "aspect_ratio" => "16:9"})
  end

  test "from_api returns the raw map for an unmodeled type" do
    raw = %{"type" => "hologram"}

    assert ResponseFormat.from_api(raw) == raw
  end

  test "documented allowed values are exposed" do
    assert "21:9" in Image.aspect_ratios()
    assert "4K" in Image.image_sizes()
    assert Video.aspect_ratios() == ["16:9", "9:16"]
  end

  test "variant converters preserve nil, raw maps, and their own structs" do
    raw = %{"mime_type" => "image/png"}

    for {module, struct} <- [
          {Text, %Text{}},
          {Image, %Image{}},
          {Audio, %Audio{}},
          {Video, %Video{}},
          {JsonSchema, %JsonSchema{}},
          {JsonObject, %JsonObject{}}
        ] do
      assert module.from_api(nil) == nil
      assert module.from_api(struct) == struct
      assert module.to_api(nil) == nil
      assert module.to_api(raw) == raw
    end
  end

  test "JsonSchema handles a malformed nested json_schema without raising" do
    assert %JsonSchema{name: nil, schema: nil, strict: nil} =
             ResponseFormat.from_api(%{"type" => "json_schema", "json_schema" => "invalid"})
  end

  test "unmodeled top-level inputs pass through" do
    assert ResponseFormat.from_api(:unknown) == :unknown
    assert ResponseFormat.to_api(:unknown) == :unknown
  end
end
