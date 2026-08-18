defmodule Gemini.APIs.InteractionsHeadersTest do
  use ExUnit.Case, async: false

  alias Gemini.APIs.Interactions

  setup do
    bypass = Bypass.open()

    # `Application.get_env/2` cannot distinguish "unset" from "set to nil", and
    # `:base_url` is genuinely unset in a clean test env. Restoring a literal
    # `nil` would defeat `get_env(:gemini_ex, :base_url, @base_url)`'s default in
    # `Gemini.Auth.GeminiStrategy.base_url/1` for every later test in the same
    # BEAM. Save with `fetch_env/2` and restore absence with `delete_env/2`.
    saved = for key <- [:base_url, :api_key], do: {key, Application.fetch_env(:gemini_ex, key)}

    Application.put_env(:gemini_ex, :base_url, "http://localhost:#{bypass.port}")
    Application.put_env(:gemini_ex, :api_key, "test-key")

    on_exit(fn ->
      Enum.each(saved, fn
        {key, {:ok, value}} -> Application.put_env(:gemini_ex, key, value)
        {key, :error} -> Application.delete_env(:gemini_ex, key)
      end)
    end)

    {:ok, bypass: bypass}
  end

  test "create forwards caller :headers to the wire", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/v1beta/interactions", fn conn ->
      assert Plug.Conn.get_req_header(conn, "api-revision") == ["2026-05-20"]
      Plug.Conn.resp(conn, 200, ~s({"id": "v1_abc", "status": "completed"}))
    end)

    assert {:ok, _} =
             Interactions.create("hi",
               model: "gemini-3.6-flash",
               headers: [{"api-revision", "2026-05-20"}]
             )
  end

  test "get forwards caller :headers to the wire", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/v1beta/interactions/v1_abc", fn conn ->
      assert Plug.Conn.get_req_header(conn, "api-revision") == ["2026-05-20"]
      Plug.Conn.resp(conn, 200, ~s({"id": "v1_abc", "status": "completed"}))
    end)

    assert {:ok, _} =
             Interactions.get("v1_abc",
               headers: [{"api-revision", "2026-05-20"}]
             )
  end

  test "invalid :headers is an error and makes no HTTP call", %{bypass: bypass} do
    hits = :counters.new(1, [:atomics])

    Bypass.stub(bypass, "GET", "/v1beta/interactions/v1_abc", fn conn ->
      :counters.add(hits, 1, 1)
      Plug.Conn.resp(conn, 200, "{}")
    end)

    assert {:error, %Gemini.Error{}} =
             Interactions.get("v1_abc", headers: [:not_a_header])

    assert :counters.get(hits, 1) == 0
  end
end
