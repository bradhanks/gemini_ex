defmodule Gemini.APIs.InteractionsHeadersTest do
  use ExUnit.Case, async: false

  alias Gemini.APIs.Interactions

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
