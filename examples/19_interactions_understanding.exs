# Interactions Understanding Example
# Run with: mix run examples/19_interactions_understanding.exs
#
# Demonstrates:
# - Analyzing video through the Interactions API
# - Passing a YouTube URL as a media URI
# - Printing the returned text

defmodule InteractionsUnderstandingExample do
  alias Gemini.Interactions.Understanding

  def run do
    print_header("INTERACTIONS UNDERSTANDING")

    check_auth!()
    demo_video_understanding()

    print_footer()
  end

  defp demo_video_understanding do
    print_section("1. Analyze a Video")

    prompt = "Summarize this video in three concise bullet points."
    url = "https://www.youtube.com/watch?v=9hE5-98ZeCg"

    IO.puts("VIDEO:")
    IO.puts("  #{url}")
    IO.puts("")
    IO.puts("PROMPT:")
    IO.puts("  #{prompt}")
    IO.puts("")

    case Understanding.analyze_video(prompt, url, model: "gemini-3.6-flash") do
      {:ok, text} ->
        IO.puts("RESPONSE:")
        IO.puts("  #{text}")
        IO.puts("")
        IO.puts("[OK] Interactions video understanding successful")

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

InteractionsUnderstandingExample.run()
