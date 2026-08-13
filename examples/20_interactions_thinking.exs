# Interactions Thinking Example
# Run with: mix run examples/20_interactions_thinking.exs
#
# Demonstrates:
# - Configuring thinking level and summaries
# - Reading the final text from a complete interaction
# - Collecting thought signatures for continuity checks

defmodule InteractionsThinkingExample do
  alias Gemini.Interactions.Text
  alias Gemini.Types.Interactions.Interaction

  def run do
    print_header("INTERACTIONS THINKING")

    check_auth!()
    demo_thinking()

    print_footer()
  end

  defp demo_thinking do
    print_section("1. Generate with Thinking")

    prompt = "A farmer has 17 rows of 23 trees. How many trees are there?"

    IO.puts("PROMPT:")
    IO.puts("  #{prompt}")
    IO.puts("")

    case Text.generate_interaction(prompt,
           model: "gemini-3.6-flash",
           thinking_level: "high",
           thinking_summaries: "auto"
         ) do
      {:ok, interaction} ->
        print_interaction(interaction)

      {:error, error} ->
        IO.puts("[ERROR] #{inspect(error)}")
    end

    IO.puts("")
  end

  defp print_interaction(interaction) do
    case Interaction.output_text(interaction) do
      {:ok, text} ->
        IO.puts("RESPONSE:")
        IO.puts("  #{text}")

      {:error, :not_found} ->
        IO.puts("[ERROR] Completed interaction had no text output")
    end

    signatures = Interaction.thought_signatures(interaction)

    IO.puts("")
    IO.puts("THOUGHT SIGNATURES:")
    IO.puts("  #{length(signatures)} signature(s) returned")
    IO.puts("")
    IO.puts("[OK] Interactions thinking generation successful")
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

InteractionsThinkingExample.run()
