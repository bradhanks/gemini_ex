defmodule Gemini.APIs.InteractionsRetryTest do
  use ExUnit.Case, async: false

  alias Gemini.APIs.Interactions
  alias Gemini.TestHTTPServer
  alias Plug.Conn

  setup do
    server = TestHTTPServer.open()

    # See the note in interactions_headers_test.exs: restore *absence*, not
    # `nil`, or every later `:base_url` read in this BEAM returns `nil`.
    saved = for key <- [:base_url, :api_key], do: {key, Application.fetch_env(:gemini_ex, key)}

    Application.put_env(:gemini_ex, :base_url, "http://localhost:#{server.port}")
    Application.put_env(:gemini_ex, :api_key, "test-key")

    on_exit(fn ->
      Enum.each(saved, fn
        {key, {:ok, value}} -> Application.put_env(:gemini_ex, key, value)
        {key, :error} -> Application.delete_env(:gemini_ex, key)
      end)
    end)

    {:ok, server: server}
  end

  test "a 429 on a non-stream get is NOT transport-retried", %{server: server} do
    counter = :counters.new(1, [:atomics])

    TestHTTPServer.expect(server, "GET", "/v1beta/interactions/v1_abc", fn conn ->
      :counters.add(counter, 1, 1)
      Conn.resp(conn, 429, ~s({"error": {"message": "rate limited"}}))
    end)

    {:error, _} = Interactions.get("v1_abc")
    assert :counters.get(counter, 1) == 1
  end
end
