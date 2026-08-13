# Interactions Image Example
# Run with: mix run examples/17_interactions_image.exs
#
# Demonstrates:
# - Generating an image through the Interactions API
# - Setting the image aspect ratio and size
# - Saving inline output or reporting a returned URI

defmodule InteractionsImageExample do
  alias Gemini.Interactions.Image
  alias Gemini.Types.Interactions.ImageContent

  @output_path "interactions-image.png"

  def run do
    print_header("INTERACTIONS IMAGE")

    check_auth!()
    demo_image_generation()

    print_footer()
  end

  defp demo_image_generation do
    print_section("1. Generate an Image")

    prompt = "A tiny robot tending an alpine flower garden, watercolor illustration"

    IO.puts("PROMPT:")
    IO.puts("  #{prompt}")
    IO.puts("")

    case Image.generate(prompt,
           model: "gemini-3.1-flash-image",
           aspect_ratio: "16:9",
           image_size: "2K"
         ) do
      {:ok, %ImageContent{data: data}} when is_binary(data) ->
        File.write!(@output_path, Base.decode64!(data))
        IO.puts("OUTPUT:")
        IO.puts("  wrote #{@output_path}")
        IO.puts("")
        IO.puts("[OK] Interactions image generation successful")

      {:ok, %ImageContent{uri: uri}} when is_binary(uri) ->
        IO.puts("OUTPUT URI:")
        IO.puts("  #{uri}")
        IO.puts("")
        IO.puts("[OK] Interactions image generation successful")

      {:ok, image} ->
        IO.puts("[ERROR] Image response had no inline data or URI: #{inspect(image)}")

      {:error, error} ->
        IO.puts("[ERROR] #{inspect(error)}")
    end

    IO.puts("")
  end

  defp check_auth! do
    cond do
      System.get_env("GEMINI_API_KEY") ->
        key = System.get_env("GEMINI_API_KEY")
        masked = String.slice(key, 0, 4) <> "..." <> String.slice(key, -4, 4)
        IO.puts("AUTH: Using Gemini API Key (#{masked})")
        IO.puts("")

      System.get_env("VERTEX_JSON_FILE") || System.get_env("GOOGLE_APPLICATION_CREDENTIALS") ->
        IO.puts("AUTH: Using Vertex AI / Application Default Credentials")
        IO.puts("")

      true ->
        IO.puts("[ERROR] No authentication configured!")
        IO.puts("Set GEMINI_API_KEY or VERTEX_JSON_FILE environment variable.")
        System.halt(1)
    end
  end

  defp print_header(title) do
    IO.puts("")
    IO.puts(String.duplicate("=", 70))
    IO.puts("  #{title}")
    IO.puts(String.duplicate("=", 70))
    IO.puts("")
  end

  defp print_section(title) do
    IO.puts(String.duplicate("-", 70))
    IO.puts(title)
    IO.puts(String.duplicate("-", 70))
    IO.puts("")
  end

  defp print_footer do
    IO.puts(String.duplicate("=", 70))
    IO.puts("  EXAMPLE COMPLETE")
    IO.puts(String.duplicate("=", 70))
    IO.puts("")
  end
end

InteractionsImageExample.run()
