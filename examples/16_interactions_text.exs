# Interactions Text Example
# Run with: mix run examples/16_interactions_text.exs
#
# Demonstrates:
# - Generating text through the Interactions API
# - Passing generation options at the top level
# - Handling success and error results

defmodule InteractionsTextExample do
  alias Gemini.Interactions.Text

  def run do
    print_header("INTERACTIONS TEXT")

    check_auth!()
    demo_text_generation()

    print_footer()
  end

  defp demo_text_generation do
    print_section("1. Generate Text")

    prompt = "Explain why pattern matching is useful in Elixir in two sentences."

    IO.puts("PROMPT:")
    IO.puts("  #{prompt}")
    IO.puts("")

    case Text.generate(prompt,
           model: "gemini-3.6-flash",
           temperature: 0.3,
           max_output_tokens: 200
         ) do
      {:ok, text} ->
        IO.puts("RESPONSE:")
        IO.puts("  #{text}")
        IO.puts("")
        IO.puts("[OK] Interactions text generation successful")

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

InteractionsTextExample.run()
