defmodule Gemini.APIs.InteractionsRetryTest do
  use ExUnit.Case, async: false

  setup do
    bypass = Bypass.open()
    prev_url = Application.get_env(:gemini_ex, :base_url)
    prev_key = Application.get_env(:gemini_ex, :api_key)
    Application.put_env(:gemini_ex, :base_url, "http://localhost:#{bypass.port}")
    Application.put_env(:gemini_ex, :api_key, "test-key")

    on_exit(fn ->
      Application.put_env(:gemini_ex, :base_url, prev_url)
      Application.put_env(:gemini_ex, :api_key, prev_key)
    end)

    {:ok, bypass: bypass}
  end

  test "a 429 on a non-stream get is NOT transport-retried", %{bypass: bypass} do
    counter = :counters.new(1, [:atomics])

    Bypass.expect(bypass, "GET", "/v1beta/interactions/v1_abc", fn conn ->
      :counters.add(counter, 1, 1)
      Plug.Conn.resp(conn, 429, ~s({"error": {"message": "rate limited"}}))
    end)

    {:error, _} = Gemini.APIs.Interactions.get("v1_abc")
    assert :counters.get(counter, 1) == 1
  end
end
