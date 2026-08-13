# Veo 3.1 compatibility audit

**Audit date:** 2026-08-12

**Scope:** `Gemini.APIs.Videos` and `Gemini.Types.Generation.Video`, compared first
with the Task 14 request/operation contract and then with the current official
Gemini and Google Cloud references. This is a static audit; no live request was
sent.

## Executive result

`Gemini.APIs.Videos` does **not** fully cover the Veo 3.1 contract. Most Gemini
request fields can be serialized, but the module sends `durationSeconds` with
the wrong Gemini wire type, does not enforce any of the coupled Veo 3.1
constraints, and cannot extract the documented completed Gemini response.
Vertex support is not operationally compatible with the current Google Cloud
shape: both the generation endpoint and polling method/path are wrong, and the
shared parameter and response schemas use the Gemini dialect instead of the
Google Cloud dialect.

The highest-risk gaps are response extraction and the Vertex lifecycle. A call
can be accepted initially yet still be impossible to poll or turn into a
`GeneratedVideo` through the advertised helpers.

## Sources and comparison rules

The primary baseline is the plan-provided contract: Gemini REST
`models/{model}:predictLongRunning`, the request fields and constraints listed
below, GET polling of the returned operation name every 10 seconds, and
`response.generateVideoResponse.generatedSamples[0].video.uri` on completion.

Official sources consulted on 2026-08-12:

- The [Gemini Veo 3.1 guide](https://ai.google.dev/gemini-api/docs/veo) documents
  the request fields, parameter values, constraints, raw REST lifecycle, and
  all three requested preview model IDs.
- The formal [Gemini Models API reference](https://ai.google.dev/api/models)
  specifies `models/{model}:predictLongRunning`, an `Operation` response, and
  generic `instances` and `parameters` values.
- The formal Google Cloud
  [`predictLongRunning` reference](https://docs.cloud.google.com/gemini-enterprise-agent-platform/reference/rest/v1beta1/projects.locations.publishers.models/predictLongRunning)
  specifies the publisher-model `:predictLongRunning` method.
- The current Google Cloud
  [Veo text-to-video guide](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/video/generate-videos-from-text)
  documents `sampleCount`, POST `:fetchPredictOperation` with an
  `operationName` body, and completed `response.videos` for the aiplatform
  backend used by Vertex authentication.
- The [Vertex AI release notes](https://docs.cloud.google.com/vertex-ai/docs/release-notes)
  record the retirement of the two Veo 3.1 preview endpoints in favor of
  `veo-3.1-generate-001` and `veo-3.1-fast-generate-001`.

There are two current-source differences worth making explicit:

1. The Gemini Veo page opens with a note saying the feature is available only
   through `generateContent`, but the same page's REST examples still use
   `predictLongRunning`, as does the formal Models API. This audit retains the
   task's explicit raw REST baseline and records the page inconsistency rather
   than inferring an undocumented replacement shape.
2. Gemini and the aiplatform/Vertex backend are not one wire contract. Gemini
   documents string `durationSeconds`, `numberOfVideos`, GET polling, and a
   nested `generateVideoResponse`; the current Google Cloud guide documents an
   integer duration, `sampleCount`, POST `:fetchPredictOperation`, and
   `response.videos`. Statuses below use the task's Gemini contract unless a row
   is explicitly labeled Vertex.

Status meanings: **Full** means the exact required field or lifecycle step is
implemented; **Partial** means a valid value can be passed but support,
validation, or discoverability is incomplete; **Missing** means there is no
implementation; **Incorrect** means the emitted or consumed wire shape conflicts
with the contract.

## Support matrix

| Area | Contract item | Status | Local evidence and finding |
|---|---|---:|---|
| Request | `instances` with one instance | **Full** | `lib/gemini/apis/videos.ex:368-370` constructs the required wrapper and a single instance. |
| Request | `instances[0].prompt` | **Full** | `lib/gemini/apis/videos.ex:357-358` places the caller's prompt in the instance. |
| Request | `instances[0].image` | **Full** | `lib/gemini/apis/videos.ex:359` conditionally emits `image`; `lib/gemini/types/generation/video.ex:232-248` converts blobs and compatible maps to `inlineData.data`/`mimeType`. |
| Request | `instances[0].video` | **Full** | `lib/gemini/apis/videos.ex:360` emits `video`; `lib/gemini/types/generation/video.ex:262-290` supports inline data and URI-backed maps. |
| Constraint | Extension video must be `video/mp4` | **Missing** | `lib/gemini/types/generation/video.ex:262-290` preserves any supplied MIME type and performs no extension-input validation. |
| Request | `instances[0].lastFrame` | **Full** | `lib/gemini/apis/videos.ex:361` emits `lastFrame` through the image converter. |
| Constraint | `lastFrame` requires `image` | **Missing** | `lib/gemini/apis/videos.ex:357-366` adds the fields independently; no combination validation runs before the request is returned at `lib/gemini/apis/videos.ex:373`. |
| Request | `instances[0].referenceImages` | **Full** | `lib/gemini/apis/videos.ex:362-366` maps the configured list into the instance. |
| Request | `referenceImages[].image` | **Full** | `lib/gemini/types/generation/video.ex:294-297` serializes the nested image through the same inline-data converter. |
| Request | `referenceImages[].referenceType` | **Full** | `lib/gemini/types/generation/video.ex:81-89` defaults the field to `"asset"`; `lib/gemini/types/generation/video.ex:294-297` emits `referenceType`. |
| Constraint | At most three reference images | **Missing** | `lib/gemini/types/generation/video.ex:127` accepts an unrestricted list and `lib/gemini/apis/videos.ex:468-469` maps all entries. The current Gemini guide caps the list at three. |
| Request | `parameters` object | **Full** | `lib/gemini/apis/videos.ex:368-370` includes the parameter map produced by `build_generation_params/2`. |
| Request | No duplicate `parameters.prompt` | **Incorrect** | `lib/gemini/types/generation/video.ex:213-220` adds `"prompt"` to `parameters` even though `lib/gemini/apis/videos.ex:357-358` already emits the documented instance prompt. The task and current REST examples contain no parameter-level prompt. |
| Parameter | `aspectRatio` | **Full** | `lib/gemini/types/generation/video.ex:117` defaults to `"16:9"`; `lib/gemini/types/generation/video.ex:218` emits `aspectRatio`. |
| Constraint | `aspectRatio` is `"16:9"` or `"9:16"` | **Missing** | `lib/gemini/types/generation/video.ex:117` accepts any string. The local typedoc also incorrectly advertises `"1:1"` at `lib/gemini/types/generation/video.ex:45-53`. |
| Parameter | `durationSeconds` wire type | **Incorrect** | The Gemini contract requires JSON strings `"4"`, `"6"`, or `"8"`; `lib/gemini/types/generation/video.ex:116` requires an integer and `lib/gemini/types/generation/video.ex:217` emits that integer unchanged. This integer happens to match the current Google Cloud/Vertex dialect, not Gemini. |
| Constraint | `durationSeconds` allowed values | **Missing** | `lib/gemini/types/generation/video.ex:116` accepts any positive integer; there is no `4`/`6`/`8` validation. |
| Constraint | Duration must be `"8"` for extension, reference images, 1080p, or 4k | **Missing** | `lib/gemini/types/generation/video.ex:213-225` builds each parameter independently, and `lib/gemini/apis/videos.ex:354-373` performs no cross-field validation. |
| Parameter | `personGeneration` | **Partial** | `lib/gemini/types/generation/video.ex:203-207` can emit `"allow_all"` and `"allow_adult"`, but `lib/gemini/types/generation/video.ex:124` defaults to `:dont_allow`, which is not a task-listed Veo 3.1 value. The implementation also does not select the value by text/extension versus image/interpolation/reference mode. |
| Parameter | `resolution`, including `"4k"` | **Full** | `lib/gemini/types/generation/video.ex:129` accepts a string and `lib/gemini/types/generation/video.ex:223` emits it unchanged, so `"720p"`, `"1080p"`, and `"4k"` can all reach Gemini. Local docs are stale: `lib/gemini/types/generation/video.ex:63-70` and `lib/gemini/types/generation/video.ex:112` omit 4k. |
| Constraint | Resolution allowed values and Lite's lack of 4k | **Missing** | `lib/gemini/types/generation/video.ex:129` accepts every string, and model selection is independent at `lib/gemini/apis/videos.ex:149-158`; there is no per-model resolution validation. |
| Constraint | Extension resolution must be `"720p"` | **Missing** | `video` and `resolution` are emitted independently at `lib/gemini/apis/videos.ex:360` and `lib/gemini/types/generation/video.ex:223`. |
| Parameter | `numberOfVideos` | **Full** | `lib/gemini/types/generation/video.ex:115` defaults to `1`; `lib/gemini/types/generation/video.ex:216` emits `numberOfVideos`. |
| Constraint | `numberOfVideos` must be `1` for Veo 3.1 | **Missing** | `lib/gemini/types/generation/video.ex:115` accepts any positive integer, while the moduledoc advertises `1-4` at `lib/gemini/types/generation/video.ex:98`. |
| Extra parameter | `negativePrompt` | **Partial** | `lib/gemini/types/generation/video.ex:121` exposes it and `lib/gemini/types/generation/video.ex:224` emits it. It is documented by the current Google Cloud/Vertex guide but is absent from the task shape and current Gemini parameter table, so Gemini support is not established by the cited reference. |
| Extra parameter | `seed` | **Partial** | `lib/gemini/types/generation/video.ex:122` exposes an unrestricted integer and `lib/gemini/types/generation/video.ex:225` emits it. The Gemini guide confirms the parameter but warns it is not deterministic; the Google Cloud guide additionally constrains it to uint32, which is not validated here. |
| Other public config | `fps`, `compression_format`, `safety_filter_level`, `guidance_scale` | **Partial** | Fields exist at `lib/gemini/types/generation/video.ex:118-123`, but the only emitted parameters are listed at `lib/gemini/types/generation/video.ex:213-225`. The local field docs call the first three legacy but do not label `guidance_scale` consistently (`lib/gemini/types/generation/video.ex:101-107`). |
| Backend selection | Per-call Gemini/Vertex auth choice | **Incorrect** | Public generation options list only model/project/location at `lib/gemini/apis/videos.ex:80-84`; routing derives the backend from global `Config.auth_config/0` at `lib/gemini/apis/videos.ex:149-158`, while the original options reach HTTP separately at `lib/gemini/apis/videos.ex:159`. A documented per-call `auth: :vertex_ai` can therefore authenticate one backend while using the other backend's path. |
| Gemini endpoint | POST `models/{model}:predictLongRunning` | **Full** | `lib/gemini/apis/videos.ex:344-346` builds the exact relative Gemini path and `lib/gemini/apis/videos.ex:159` posts to it. |
| Vertex endpoint | POST publisher model `:predictLongRunning` | **Incorrect** | `lib/gemini/apis/videos.ex:335-341` builds `.../{model}:predict`, contrary to the formal/current Google Cloud long-running endpoint. |
| Vertex parameters | `sampleCount` and optional `storageUri` | **Missing** | The shared builder emits `numberOfVideos` and has no storage field (`lib/gemini/types/generation/video.ex:91-130`, `lib/gemini/types/generation/video.ex:213-225`). The current Google Cloud guide uses `sampleCount` and `storageUri`. |
| Vertex person policy | `allow_adult` or `disallow` | **Incorrect** | `lib/gemini/types/generation/video.ex:203-207` maps the no-person atoms to `"dont_allow"`, not the current Google Cloud `"disallow"`, and `lib/gemini/types/generation/video.ex:124` makes that incompatible value the default. |
| Start response | Parse an operation containing `name` | **Full** | `lib/gemini/apis/videos.ex:380-384` accepts a named operation and delegates all fields to `Operation.from_api_response/1`; `lib/gemini/types/operation.ex:93-100` retains `name`, `done`, `error`, and `response`. |
| Poll cadence | Default 10-second interval | **Full** | `lib/gemini/apis/videos.ex:94` sets 10,000 ms and `lib/gemini/apis/videos.ex:246-255` forwards it; `lib/gemini/apis/operations.ex:340-347` sleeps for that interval between GETs. |
| Poll options | Per-call auth/backend propagation | **Missing** | The wait option type excludes auth at `lib/gemini/apis/videos.ex:86-90`, and `lib/gemini/apis/videos.ex:246-255` forwards only interval, timeout, and progress. Consequently the README's `wait_for_completion(..., auth: :vertex_ai)` example cannot pass that choice to `Operations.wait/2`. |
| Gemini poll path | GET `{BASE_URL}/{operation.name}` | **Partial** | `lib/gemini/apis/videos.ex:198-201` delegates to generic operations. That code GETs a normalized path at `lib/gemini/apis/operations.ex:100-104`, but prepends `operations/` to every name not already beginning with that segment at `lib/gemini/apis/operations.ex:322-323`. It therefore does not preserve an arbitrary server-returned full name as the guide requires. |
| Vertex poll method/path | POST model `:fetchPredictOperation` with `operationName` | **Incorrect** | The same delegation (`lib/gemini/apis/videos.ex:198-201`, `lib/gemini/apis/videos.ex:251-255`) can only use generic GET polling. No video-specific Vertex POST body or fetch path exists. |
| Poll response | Stop when `done` is true | **Full** | `lib/gemini/types/operation.ex:93-100` parses `done`; `lib/gemini/apis/operations.ex:390-395` returns completed operations and otherwise continues polling. |
| Gemini completed response | `response.generateVideoResponse.generatedSamples[]` | **Incorrect** | `lib/gemini/types/generation/video.ex:363-369` checks only top-level `response["generatedVideos"]` or `response["predictions"]`, so the documented Gemini response returns `{:ok, []}`. |
| Gemini sample video | `generatedSamples[].video.uri` | **Incorrect** | Even if samples were unwrapped, `lib/gemini/types/generation/video.ex:306-317` expects `videoUri` or `gcsUri` directly on each item and never reads nested `video.uri`. |
| Vertex completed response | `response.videos[]` | **Incorrect** | The current Google Cloud shape uses `response.videos`; `lib/gemini/types/generation/video.ex:363-369` does not inspect that key. Its individual parser does understand each resulting `gcsUri` once unwrapped (`lib/gemini/types/generation/video.ex:306-317`). |
| Model | `veo-3.1-generate-preview` | **Full** | `lib/gemini/apis/videos.ex:149-158` accepts a caller-supplied model string and `lib/gemini/apis/videos.ex:344-346` interpolates it; the model is also listed at `lib/gemini/apis/videos.ex:15`. This is a current Gemini ID, but Vertex retired it in favor of `veo-3.1-generate-001`. |
| Model | `veo-3.1-fast-generate-preview` | **Full** | The arbitrary model path supports it (`lib/gemini/apis/videos.ex:149-158`, `lib/gemini/apis/videos.ex:344-346`) and the moduledoc lists it at `lib/gemini/apis/videos.ex:16`. This is current for Gemini, while Vertex directs callers to `veo-3.1-fast-generate-001`. |
| Model | `veo-3.1-lite-generate-preview` | **Partial** | Passing the literal string works through the same arbitrary model path (`lib/gemini/apis/videos.ex:149-158`, `lib/gemini/apis/videos.ex:344-346`), but it is absent from both supported-model lists (`lib/gemini/apis/videos.ex:12-18`, `lib/gemini/types/generation/video.ex:9-15`) and no Lite restrictions are enforced. The current Gemini guide lists this exact ID; the current Google Cloud guide instead lists `veo-3.1-lite-generate-001`. |
| Model default | Current Veo default/discoverability | **Incorrect** | `lib/gemini/apis/videos.ex:92` defaults to `veo-2.0-generate-001`, and `lib/gemini/apis/videos.ex:14` calls it recommended. The current Gemini guide marks Veo 2 deprecated, and current Vertex release notes direct Veo 2 users to Veo 3.1. |

## Stale local documentation and examples

These are real user-facing mismatches, not merely missing validation:

- `guides/video_generation.md:3-16` says video generation is Vertex-only and
  unavailable on Gemini, while the current Gemini guide documents Gemini API
  access. The README repeats the Vertex-only framing at `README.md:1775-1794`.
- `guides/video_generation.md:54-65` demonstrates two outputs and
  `guides/video_generation.md:523-535` advertises `1..4`; Gemini Veo 3.1 permits
  one video per request. The Google Cloud backend permits up to four but calls
  the parameter `sampleCount`, so the example is not portable to either current
  wire shape through this module.
- `guides/video_generation.md:67-86` omits the 6-second duration and advertises
  unsupported `1:1`; the current Gemini guide lists 4, 6, and 8 seconds and only
  `16:9`/`9:16`.
- `guides/video_generation.md:190-207` and the quick start at
  `guides/video_generation.md:30-38` assume top-level extractable GCS-style
  output, which does not match the documented nested Gemini result and cannot
  work with the current extractor.
- `guides/video_generation.md:236-250` promises identical videos for equal
  seeds. The current Gemini guide explicitly says `seed` does not guarantee
  determinism.
- The module example uses the same stale response shape at
  `lib/gemini/types/generation/video.ex:30-35`; both supported-model moduledocs
  omit Lite (`lib/gemini/apis/videos.ex:12-18`,
  `lib/gemini/types/generation/video.ex:9-15`).
- Unit tests lock in incompatible assumptions: multiple Gemini outputs and
  integer duration at `test/gemini/apis/videos_test.exs:281-300`, and the older
  top-level generated-video response fixture at
  `test/gemini/apis/videos_test.exs:190-219`.

## Recommendation

Follow-up work is warranted and is **medium-sized: about 3-5 engineering days,
plus credentialed Gemini and Vertex live verification**.

1. **P0 — make lifecycle completion reliable.** Add backend-specific initiation
   and polling (`predictLongRunning` plus exact-name GET for Gemini;
   `predictLongRunning` plus `fetchPredictOperation` POST for Vertex), then parse
   both documented completion shapes.
2. **P0 — separate the request dialects.** Emit Gemini string
   `durationSeconds`/`numberOfVideos` and Vertex integer duration/`sampleCount`;
   remove the duplicate parameter-level prompt and map backend-specific person
   policies.
3. **P1 — validate Veo 3.1 constraints before I/O.** Enforce allowed aspect
   ratios, durations, resolutions, one Gemini output, reference-image count,
   last-frame pairing, extension MIME/resolution, and Lite capability limits.
4. **P2 — refresh public guidance and tests.** Document Lite and 4k, choose a
   current backend-aware default, correct the extraction examples and seed
   promise, and replace fixtures that encode the obsolete response shape.

No implementation changes were made as part of this audit.
