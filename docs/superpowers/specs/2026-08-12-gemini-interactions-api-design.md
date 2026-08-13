# Complete Gemini Interactions API Support

Date: 2026-08-12
Status: Approved for planning
Target release: 0.17.0

## Problem

Google's Gemini API documentation now describes every core capability against
`POST /v1beta/interactions`. The twelve capability pages in scope — text
generation, image generation, video, image understanding, video understanding,
speech generation, document processing, audio, thinking, thought signatures,
structured output, and function calling — all use that endpoint with snake_case
request fields. Only the Veo 3.1 video-generation path still uses
`:predictLongRunning` on `generateContent`-era infrastructure.

`gemini_ex` already ships `Gemini.APIs.Interactions`, but it was written against
an earlier revision of that endpoint. The request side is close to current; the
response and streaming-event side has drifted far enough that a current server's
replies do not parse into meaningful structures.

## Scope

In scope: bring the Interactions surface to full coverage of the twelve
capability pages, add typed capability-level entry points, and refresh the model
registry.

Out of scope: the `generateContent`-based modules (`Gemini.APIs.Coordinator`,
`Gemini.APIs.Images`, `Gemini.APIs.Videos`, `Gemini.APIs.ContextCache`) are left
untouched. They are neither extended nor deprecated. The single exception is a
read-only audit of `Gemini.APIs.Videos` against the Veo 3.1 guide, which
produces a findings document and no code changes.

## Findings that motivate the design

Established by reading `lib/` against the live documentation:

1. `Gemini.Types.Interactions.Interaction` parses an `outputs` field
   (`interaction.ex:23,41,60`). The current API returns `steps`. The string
   `step` does not appear anywhere under `lib/gemini/types/interactions/` or in
   `lib/gemini/apis/interactions.ex`.
2. Streaming events are modeled as `content.start` / `content.delta` /
   `content.stop` (`events.ex:204,248,288,337`). The current API emits
   `step.delta` carrying `delta.type` and an `index`.
3. No `output_text` / `output_image` / `output_audio` accessor exists anywhere
   in `lib/`, though the documentation treats these as the primary read path.
4. `response_format` is forwarded as an untyped map
   (`interactions.ex:336`). Image generation and TTS are both driven entirely
   through `response_format`, so there is no typed way to request either.
5. `Gemini.Types.Interactions.GoogleSearch.to_api/1` emits exactly
   `%{"type" => "google_search"}` (`tool.ex:102`), dropping `search_types`.
6. `media_resolution` exists only on `generateContent` parts
   (`types/common/part.ex`), not on Interactions content blocks.
7. `Gemini.ModelRegistry` tops out at `gemini-3.1-pro-preview` and
   `gemini-3-pro-image-preview`.

The following were checked and found already correct, and must not be
regressed: all content block types in `content.ex`; `store`,
`previous_interaction_id`, `background`, `agent`, `agent_config`,
`system_instruction`, and `tools` in `build_create_body/3`; `thinking_level`,
`thinking_summaries`, `speech_config`, `image_config`, `tool_choice`, and
`allowed_tools` in `config.ex`; SSE streaming with `last_event_id` resumption.

## Design

### 1. Step model

New module `Gemini.Types.Interactions.Step` defines a step union. Each step is a
struct with a `type` string, a `content` list of existing
`Gemini.Types.Interactions.Content` blocks, and any type-specific fields.

Step types to support:

| Step type | Type-specific fields |
|---|---|
| `user_input` | — |
| `model_output` | — |
| `thought` | `signature` (string, required when present), `summary` (content list) |
| `function_call` | `name`, `arguments`, `id` |
| `function_result` | `id`, `signature` |
| `google_search_call` | `signature` |
| `google_search_result` | `signature` |
| `code_execution_call` | — |
| `code_execution_result` | — |
| `url_context_call` | — |
| `url_context_result` | — |
| `mcp_server_tool_call` | — |
| `mcp_server_tool_result` | — |
| `file_search_call` | — |
| `file_search_result` | — |

An unrecognized `type` parses into a permissive fallback struct that retains the
raw map, so a server-side addition degrades rather than crashes.

`Step.from_api/1` and `Step.to_api/1` mirror the existing content-block
conventions in `content.ex`.

`Interaction` gains `field(:steps, [Step.t()])`, parsed from `"steps"`.

### 2. Thought signatures

Per the thinking documentation, signatures appear in exactly two places: on
`thought` steps and on built-in tool steps such as `google_search_call` and
`google_search_result`. In stateless mode (`store: false`), every thought block
and tool-result signature must be resent byte-identical.

`Step.to_api/1` therefore round-trips `signature` verbatim for every step type
that carries one. The fallback struct for unrecognized step types retains its
raw map for the same reason — an unknown future tool step keeps its signature
through a resend.

`Gemini.Types.Interactions.Interaction.thought_signatures/1` returns every
signature in the interaction, in step order, so callers can construct a
stateless follow-up turn.

### 3. Backward compatibility for `outputs`

`Interaction.outputs` remains and is populated by flattening the `content` list
of every step in order. Callers written against 0.16.0 continue to work.
`steps` is the real structure and is what the new accessors and capability
modules read.

When a response contains `outputs` and no `steps` — an older server, or a
recorded fixture — `outputs` parses as before and `steps` is `nil`. The two
fields are never both authoritative: `steps` wins when present.

### 4. Output accessors

On `Gemini.Types.Interactions.Interaction`:

- `output_text/1` — concatenated text from the last `model_output` step
- `output_image/1` — last image content block
- `output_audio/1` — last audio content block
- `output_video/1` — last video content block

Each returns `{:ok, value}` or `{:error, :not_found}`. Each reads `steps` when
present and falls back to `outputs`.

### 5. Streaming events

New event structs alongside the existing `content.*` ones:

- `step.start`, `step.delta`, `step.stop`, each carrying `index` and `delta`

New `Gemini.Types.Interactions.Delta` variants: `thought_summary` and
`thought_signature`, in addition to the existing `text`. The `audio` and `image`
delta variants carry `data` (base64).

The dispatcher at `events.ex:337` gains clauses for the `step.*` event types.
The existing `content.*` clauses stay. An unrecognized `event_type` continues to
fall through to the existing generic handling.

### 6. Typed `response_format`

New module `Gemini.Types.Interactions.ResponseFormat` with four variants:

| Variant | Fields |
|---|---|
| `Text` | `mime_type` (`"application/json"`), `schema` (map) |
| `Image` | `mime_type` (`"image/jpeg"` \| `"image/png"`), `aspect_ratio`, `image_size` |
| `Audio` | — (`{"type": "audio"}`) |
| `Video` | `aspect_ratio` (`"16:9"` \| `"9:16"`), `delivery` (`"uri"`) |

`aspect_ratio` for images accepts `1:1`, `3:2`, `2:3`, `3:4`, `4:3`, `4:5`,
`5:4`, `9:16`, `16:9`, `21:9`. `image_size` accepts `512px`, `1K`, `2K`, `4K`.

`build_create_body/3` accepts either a `ResponseFormat` struct or a raw map. Raw
maps pass through unchanged, preserving current behavior.

Values are not validated against the allowed sets at build time. Server-side
validation is authoritative, and a hardcoded allowlist becomes wrong the moment
Google adds a value. The allowed values are documented in `@doc` and exposed as
module functions (`ResponseFormat.Image.aspect_ratios/0`) for callers that want
to validate.

### 7. Remaining request-side fields

- `media_resolution` (`"low"` | `"medium"` | `"high"`) added as an optional
  field on the image, video, document, and audio content blocks in
  `content.ex`, emitted only when set.
- `search_types` added to `Gemini.Types.Interactions.GoogleSearch`, a list of
  strings (`"web_search"`, `"image_search"`), emitted only when set so the
  default serialization stays `%{"type" => "google_search"}`.
- `video_config` added to `Gemini.Types.Interactions.Config`, a struct with a
  `task` field (`"text_to_video"` | `"image_to_video"` |
  `"reference_to_video"` | `"edit"`).

### 8. Capability modules

Five new modules under `lib/gemini/interactions/`, each a thin typed wrapper
over `Gemini.APIs.Interactions.create/2`. They construct the right
`response_format` and `generation_config`, call `create/2`, and pull the result
out with the matching output accessor. Every one accepts the same auth,
`api_version`, `timeout`, and `stream` options as `create/2` and passes them
through untouched.

**`Gemini.Interactions.Text`** — `generate/2`. Options `:model`,
`:system_instruction`, `:thinking_level`, `:thinking_summaries`, `:tools`,
`:tool_choice`, `:store`, `:previous_interaction_id`, `:response_format`.
Returns `{:ok, String.t()}` for the non-streaming case.

**`Gemini.Interactions.Image`** — `generate/2` and `edit/3`. Options
`:aspect_ratio`, `:image_size`, `:mime_type`, `:thinking_level`, `:tools`.
`edit/3` takes a prior interaction id or an input image. Returns image content
blocks.

**`Gemini.Interactions.Speech`** — `generate/2`. Options `:voice` (single
speaker) or `:speakers` (list of `{speaker, voice}`), `:language`, `:model`.
Emits `response_format: %ResponseFormat.Audio{}` and a `speech_config` list.
Returns `{:ok, binary}` of decoded PCM, plus `generate_wav/2` that wraps the
PCM in a WAV container at 24 kHz, mono, 16-bit. Exposes `voices/0` returning
the 30 documented voice names: Zephyr, Puck, Charon, Kore, Fenrir, Leda, Orus,
Aoede, Callirrhoe, Autonoe, Enceladus, Iapetus, Umbriel, Algieba, Despina,
Erinome, Algenib, Rasalgethi, Laomedeia, Achernar, Alnilam, Schedar, Gacrux,
Pulcherrima, Achird, Zubenelgenubi, Vindemiatrix, Sadachbia, Sadaltager,
Sulafat.

**`Gemini.Interactions.Video`** — `generate/2` for Gemini Omni Flash. Options
`:task`, `:aspect_ratio`, `:delivery`, `:previous_interaction_id`. Handles both
inline base64 and URI delivery; for URI delivery, returns the URI without
downloading. Documents that system instructions, temperature, `top_p`, stop
sequences, and negative prompts are unsupported by this model.

**`Gemini.Interactions.Understanding`** — `analyze/3` taking a prompt and a list
of media inputs (image, video, audio, document), each accepting inline data, a
Files API URI, or — for video — a YouTube URL. Options `:media_resolution`,
`:response_format` (for structured extraction), `:model`. Convenience wrappers
`describe_image/3`, `transcribe_audio/3`, `analyze_document/3`,
`analyze_video/3`.

### 9. Model registry

`Gemini.ModelRegistry` and `Gemini.Config` gain the models currently listed on
the models page and absent from the registry:

`gemini-3.6-flash`, `gemini-3.5-flash`, `gemini-3.5-flash-lite`,
`gemini-3.1-flash-lite`, `gemini-3.1-flash-image`,
`gemini-3.1-flash-lite-image`, `gemini-3-pro-image`,
`gemini-3.1-flash-tts-preview`, `gemini-3.5-live-translate-preview`,
`gemini-omni-flash`, `gemini-embedding-2-preview`.

Each entry follows the existing registry shape, including `source_page`.
Existing entries are not removed.

The models page lists `gemini-omni-flash` while the Omni guide uses
`gemini-omni-flash-preview`. Both are registered, with
`gemini-omni-flash-preview` as an alias of `gemini-omni-flash`, and the
discrepancy noted in a code comment citing both source pages.

`Gemini.Config` default aliases are updated so `:latest` points at
`gemini-3.6-flash`, currently `gemini-3.1-pro-preview` (`config.ex:104`).

This is the one deliberate exception to "legacy untouched." `Gemini.Config` is
shared, so the alias is also what the `generateContent` path resolves when a
caller names no model. Adding models without moving `:latest` would leave the
alias pointing at a superseded preview model, which contradicts the goal of the
work. No other legacy behavior changes: no function signature, no request
shape, no default beyond this alias. It is called out in the changelog.

### 10. Testing

Following the existing convention in `test/gemini/apis/`:

- Request-shape tests asserting the exact JSON emitted by `build_create_body/3`
  for every new field, one test per capability page's documented example.
- Response-parsing tests against fixtures capturing the current `steps` shape,
  including a thought step with a signature, a `google_search_call` with a
  signature, and an unrecognized step type that must round-trip.
- A round-trip test proving `Step.to_api(Step.from_api(x)) == x` for signature
  preservation, since stateless mode requires byte-identical resends.
- Backward-compatibility tests proving an `outputs`-shaped response still parses
  and that a `steps`-shaped response populates both `steps` and a flattened
  `outputs`.
- Streaming tests feeding `step.delta` events through the SSE parser.
- Live tests tagged and excluded by default, per repo convention.

### 11. Documentation

New guides: `guides/interactions_text.md`, `interactions_image_generation.md`,
`interactions_speech.md`, `interactions_video.md`,
`interactions_understanding.md`, `interactions_thinking.md`. Existing guides are
not modified, since the `generateContent` modules they document are unchanged.

New examples following the numbered convention in `examples/`.

`README.md` gains an Interactions section. `CHANGELOG.md` records the added
surface, the `steps` addition, and the `:latest` alias change.

### 12. Veo 3.1 audit

A findings document at `docs/veo-3.1-audit.md` comparing `Gemini.APIs.Videos`
against the Veo guide. Points to check: `referenceImages` with `referenceType`,
`lastFrame`, `resolution` including `4k`, the `durationSeconds` constraint that
1080p/4k/reference-image requests must use `"8"`, `numberOfVideos`,
`personGeneration`, and the model IDs `veo-3.1-generate-preview`,
`veo-3.1-fast-generate-preview`, `veo-3.1-lite-generate-preview`. No code
changes; the document ends with a recommendation.

## Verification

Per `AGENTS.md`, all of the following must pass before the work is complete:

```
mix format
mix compile --warnings-as-errors
mix test
mix credo --strict
mix docs --warnings-as-errors
mix dialyzer
```

Runtime code under `lib/**` must not call `System.get_env` or its siblings.

## Risks

**Documentation is the only source of truth for the wire format.** The `steps`
shape is taken from documented examples, not from a captured live response. If
the real payload differs in detail, the parsing tests encode the wrong shape.
Mitigation: the fallback struct for unrecognized step types means a mismatch
degrades to a raw map rather than a crash, and a single live test against a real
key confirms the shape before release.

**`:latest` alias change is user-visible.** Callers who pass no model get a
different one after upgrading. Mitigated by the changelog entry; not by a
deprecation cycle, since the alias means "latest" by definition.

**Two representations coexist.** `outputs` alongside `steps`, and `content.*`
events alongside `step.*`, is redundancy that a future major version should
remove. Accepted deliberately to avoid breaking 0.16.0 callers.

## Amendments

Added after the design was approved, from the formal API reference at
`https://ai.google.dev/api/interactions-api` and
`https://ai.google.dev/gemini-api/docs/interactions/media-resolution`, which
were not found during the first research pass. These supersede the sections
they name.

**A1 — supersedes §7 on `media_resolution`.** The field is named `resolution`,
not `media_resolution`, and its values are `unspecified`, `low`, `medium`,
`high`, `ultra_high` (`ultra_high` per-content-item only, Gemini 3 only). It
already exists and is correct on `ImageContent` (`content.ex:94-128`) and
`VideoContent` (`content.ex:229-263`). The only work is adding it to
`DocumentContent`, which the document-processing page documents as accepting
per-part resolution. `AudioContent` is left alone — no source documents
resolution on audio.

**A2 — supersedes §4 on output accessors.** `output_text`, `output_image`,
`output_audio`, and `output_video` are fields the server actually returns on the
Interaction resource, not client-side conveniences. They are parsed as struct
fields. The accessor functions remain, returning the parsed field when present
and computing from `steps` when absent.

**A3 — extends §1 on the step schema.** A step is `{type, content, name, id}`,
plus `arguments` on `function_call` and `call_id` (not `id`) linking
`function_result` to its call. The full step type list adds `code_execution`
(the reference's name; `code_execution_call` is not in it), `google_maps_call`,
`google_maps_result`, `retrieval_call`, `retrieval_result`, and `computer_use`.
The permissive fallback for unrecognized types is unchanged and now also covers
any of these the implementation does not model explicitly.

**A4 — corrects §5 on event names.** The current event names are wrong, not
merely incomplete: the code dispatches `interaction.start` and
`interaction.complete` (`events.ex:338-339`), but the API emits
`interaction.created` and `interaction.completed`. Both spellings are accepted
on parse. The full event set is `interaction.created`,
`interaction.status_update`, `step.start`, `step.delta`, `step.stop`,
`interaction.completed`, `error`.

`Delta` is already near-complete. Missing variants to add:
`text_annotation_delta`, `arguments_delta`, `google_maps_call`,
`google_maps_result`, `retrieval_call`, `retrieval_result`, `file_search_call`.

**A5 — extends §6 on `response_format`.** The reference documents
`{"type": "json_schema", "json_schema": {name, schema, strict}}` and
`{"type": "json_object"}`, which conflicts with the capability pages'
`{"type": "text"|"image"|"audio"|"video", ...}`. Both shapes are supported:
typed constructors for all six, and raw maps continue to pass through. The
conflict is noted in the module doc with both source URLs. `response_format`
also accepts a list, per the reference's `ResponseFormat|array`.

**A6 — new request and resource fields.** `build_create_body/3` does not emit
`safety_settings`, `service_tier`, `environment`, `labels`, `webhook_config`, or
`user_metadata`. All six are added. The `Interaction` struct additionally gains
`object`, `input`, `system_instruction`, `tools`, `response_format`, and
`generation_config`, which the resource returns but the struct drops.

The documented `status` values are `in_progress`, `requires_action`,
`completed`, `failed`, `cancelled`, `incomplete`, `budget_exceeded`, `queued`.
`status` stays a plain string — no enum validation — so a new server-side status
does not break parsing.
