# Upstream issue notes

Findings that belong to upstream `gemini_ex`, deliberately **not** fixed in this
fork. Each one either sits in an upstream-owned module where a fork edit would
widen the `git pull upstream main` conflict surface for no local benefit, or is
a policy decision upstream should make. Report them upstream; do not patch them
here without a reason to.

## 1. `Config.base_url/0` reads the `:gemini` app key, not `:gemini_ex`

`lib/gemini/config.ex:1057`

```elixir
_ ->
  Application.get_env(:gemini, :base_url, "https://generativelanguage.googleapis.com/v1beta")
```

Every other config read in the package uses `:gemini_ex`. This one uses
`:gemini`, so an operator who sets `config :gemini_ex, :base_url, ...` and lands
in this branch silently gets the hardcoded default instead.

Blast radius is small: it is the third `case` branch of `Config.base_url/0`,
reachable only when `auth_config/0` matches neither the `:gemini` nor the
`:vertex_ai` clause. `Gemini.APIs.Interactions` never calls `Config.base_url/0`
(it uses `Config.current_api_type/0` and `Config.timeout/0`), and base-URL
resolution for Interactions goes through `Gemini.Auth.GeminiStrategy.base_url/1`,
which reads `:gemini_ex` correctly.

## 2. `GeminiStrategy.base_url/1` returns unvalidated config under a `String.t()` spec

`lib/gemini/auth/gemini_strategy.ex:36`

```elixir
@impl true
def base_url(_credentials) do
  Application.get_env(:gemini_ex, :base_url, @base_url)
end
```

The `Gemini.Auth` behaviour specs the callback as `String.t() | {:error, term()}`,
but `Application.get_env/3` returns whatever the operator configured, and its
default only applies when the key is *absent* — an explicitly-stored `nil` comes
straight back. So the function can return a value its own spec forbids, and
dialyzer (correctly trusting the spec) cannot see it. Any caller that pattern
matches on `String.t() | {:error, _}` raises instead.

`Gemini.APIs.Interactions` defends itself at the boundary — `base_url_root/2`
turns a non-binary into a `%Gemini.Error{type: :config_error}` — but the source
should validate: return `{:error, ...}` when the configured value is not a
binary, so the contract the spec advertises is the contract callers get. Fixing
it in the strategy is an upstream call because every auth strategy shares the
behaviour.

## 3. `HTTPStreaming.stream_with_retries/6` retries non-retryable 4xx

`lib/gemini/client/http_streaming.ex:228-262`

The retry clause is `{:error, error} when attempt < config.max_retries` — **any**
error, with no classification. A 400 (malformed request) or a 401 (bad key) on a
stream is retried three more times by default with exponential backoff, and a
429's `retry-after` header is ignored in favour of `1000 * 2^attempt`. Every
attempt is billed. Since `Interactions.stream_request/5` only forwards
`:max_retries` when the caller sets it, a streamed `Interactions.create/2` that
400s hits the wire four times.

Suggested fix: classify on `%Gemini.Error{http_status: status}` and honour
`retry-after`.

## 4. `retry: false` is hand-copied at 3 of ~20 Req call sites

`grep -rn "retry:" lib/` finds it only in `apis/interactions.ex:411`,
`client/http_streaming.ex:315`, and `client/http.ex:148`. Still on Req's default
`:safe_transient` (which does silently retry safe methods on 429/5xx):
`apis/tunings.ex:120,167`, `apis/files.ex:586-588`, and
`auth/metadata_server.ex:84,142,182,222`, plus the POST sites that
`:safe_transient` leaves alone today but that a policy change would sweep in.

There is no shared option builder, so the invariant is three comments that have
to be remembered a fourth time. A `Gemini.Client.ReqOptions.base/1` — or even a
single module attribute with one canonical comment — would make it structural.

## 5. `interaction.failed` error placement is asserted against a hand-written fixture

`lib/gemini/types/interactions/interaction.ex:47` ·
`lib/gemini/types/interactions/events.ex` (`InteractionEvent.from_api/1`)

`Interaction.error` is an untyped passthrough map (consistent with
`agent_config` / `labels` / `safety_settings`, and the safer default). The open
question is placement, not typing: the suite asserts the error nests under
`interaction.error` for an `interaction.failed` event, against a fixture rather
than a captured live response. If the API puts the error at the *event* top
level, `InteractionEvent.from_api/1` drops it — it reads only `event_id`,
`event_type`, and `interaction`. Confirm against a real `interaction.failed`
frame before relying on it.
