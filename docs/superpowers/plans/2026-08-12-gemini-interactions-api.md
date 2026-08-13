# Complete Gemini Interactions API Support — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `Gemini.APIs.Interactions` to full coverage of the twelve Gemini API capability pages, which are all documented against `POST /v1beta/interactions`.

**Architecture:** The request side is close to current and gets new fields added. The response and streaming-event side was built against an earlier revision and gets realigned: a new `Step` model becomes the real response structure, while the existing `outputs` field and `content.*` events stay as a derived compatibility layer. Five thin capability modules wrap `Interactions.create/2` with typed options.

**Tech Stack:** Elixir ~> 1.14, TypedStruct, Jason, Req, ExUnit, Bypass (via `Gemini.TestHTTPServer`), `:meck`.

**Spec:** `docs/superpowers/specs/2026-08-12-gemini-interactions-api-design.md` — read the Amendments section, which supersedes several earlier sections.

## Global Constraints

- Elixir `~> 1.14`. Two-space indentation, idiomatic Elixir, pattern-matching-friendly APIs.
- Runtime code under `lib/**` must never call `System.get_env`, `System.fetch_env`, `System.put_env`, or `System.delete_env`. Read config through `Gemini.Env`, application config, or explicit caller options.
- Every public module and function that is part of the supported surface needs a `@moduledoc` / `@doc` and a `@spec`.
- Do not modify `Gemini.APIs.Coordinator`, `Gemini.APIs.Images`, `Gemini.APIs.Videos`, or `Gemini.APIs.ContextCache`. The single exception is the `:latest` alias in `Gemini.Config` (Task 12).
- Never remove or change the meaning of an existing public field. New fields are additive; `outputs` and the `content.*` events keep working.
- All new API-facing structs follow the existing convention exactly: `use TypedStruct`, `@derive Jason.Encoder`, `import Gemini.Utils.MapHelpers, only: [maybe_put: 3]`, and a `from_api/1` + `to_api/1` pair whose heads are `nil`, own-struct passthrough, then `%{} = data`. `to_api/1` also has a `def to_api(%{} = map) when not is_struct(map), do: map` clause so raw maps pass through.
- Parsing must never raise on unknown input. Unrecognized union members degrade to a permissive struct or the raw map.
- Do not validate enum-ish values against hardcoded allowlists at build time. The server is authoritative. Document allowed values in `@doc` and expose them as module functions.
- Full QC gate, all must pass: `mix format`, `mix compile --warnings-as-errors`, `mix test`, `mix credo --strict`, `mix docs --warnings-as-errors`, `mix dialyzer`.
- Commit after every task.

---

### Task 1: Step model

**Files:**
- Create: `lib/gemini/types/interactions/step.ex`
- Test: `test/gemini/types/interactions/step_test.exs`

**Interfaces:**
- Consumes: `Gemini.Types.Interactions.Content.from_api/1` and `.to_api/1` (existing, `lib/gemini/types/interactions/content.ex`).
- Produces:
  - `Gemini.Types.Interactions.Step.from_api(map() | nil) :: struct() | nil`
  - `Gemini.Types.Interactions.Step.to_api(struct() | map() | nil) :: map() | nil`
  - `Gemini.Types.Interactions.Step.content(struct()) :: [Content.t()]` — returns `[]` when the step has no content
  - `Gemini.Types.Interactions.Step.signature(struct()) :: String.t() | nil`
  - Structs: `Gemini.Types.Interactions.StandardStep` (fields `type`, `content`, `name`, `id`, `signature`), `Gemini.Types.Interactions.FunctionCallStep` (adds `arguments`), `Gemini.Types.Interactions.FunctionResultStep` (adds `call_id`), `Gemini.Types.Interactions.UnknownStep` (fields `type`, `raw`)

Every step type in the API shares one shape apart from two special cases, so this task models three structs plus a fallback rather than twenty near-identical ones.

- [ ] **Step 1: Write the failing test**

Create `test/gemini/types/interactions/step_test.exs`:

```elixir
defmodule Gemini.Types.Interactions.StepTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.{
    FunctionCallStep,
    FunctionResultStep,
    Step,
    StandardStep,
    TextContent,
    UnknownStep
  }

  describe "from_api/1" do
    test "parses a model_output step with content blocks" do
      step =
        Step.from_api(%{
          "type" => "model_output",
          "content" => [%{"type" => "text", "text" => "Hello"}]
        })

      assert %StandardStep{type: "model_output"} = step
      assert [%TextContent{text: "Hello"}] = step.content
    end

    test "parses a thought step and keeps its signature" do
      step =
        Step.from_api(%{
          "type" => "thought",
          "signature" => "Ci4B1a2b3c",
          "summary" => [%{"type" => "text", "text" => "Considering options"}]
        })

      assert %StandardStep{type: "thought", signature: "Ci4B1a2b3c"} = step
    end

    test "parses a google_search_call step and keeps its signature" do
      step = Step.from_api(%{"type" => "google_search_call", "signature" => "sig_xyz"})

      assert %StandardStep{type: "google_search_call", signature: "sig_xyz"} = step
    end

    test "parses a function_call step with arguments and name" do
      step =
        Step.from_api(%{
          "type" => "function_call",
          "name" => "get_weather",
          "id" => "call_1",
          "arguments" => %{"location" => "Boston"}
        })

      assert %FunctionCallStep{
               type: "function_call",
               name: "get_weather",
               id: "call_1",
               arguments: %{"location" => "Boston"}
             } = step
    end

    test "parses a function_result step with call_id" do
      step =
        Step.from_api(%{
          "type" => "function_result",
          "call_id" => "call_1",
          "content" => [%{"type" => "text", "text" => "72F"}]
        })

      assert %FunctionResultStep{type: "function_result", call_id: "call_1"} = step
    end

    test "degrades an unrecognized step type into UnknownStep retaining the raw map" do
      raw = %{"type" => "future_tool_call", "signature" => "sig_future", "whatever" => 1}

      assert %UnknownStep{type: "future_tool_call", raw: ^raw} = Step.from_api(raw)
    end

    test "returns nil for nil" do
      assert Step.from_api(nil) == nil
    end
  end

  describe "to_api/1" do
    test "round-trips a thought step byte-identically" do
      raw = %{"type" => "thought", "signature" => "Ci4B1a2b3c"}

      assert raw |> Step.from_api() |> Step.to_api() == raw
    end

    test "round-trips an unrecognized step type byte-identically" do
      raw = %{"type" => "future_tool_call", "signature" => "sig_future", "whatever" => 1}

      assert raw |> Step.from_api() |> Step.to_api() == raw
    end

    test "round-trips a function_call step" do
      raw = %{
        "type" => "function_call",
        "name" => "get_weather",
        "id" => "call_1",
        "arguments" => %{"location" => "Boston"}
      }

      assert raw |> Step.from_api() |> Step.to_api() == raw
    end

    test "passes a raw map through unchanged" do
      assert Step.to_api(%{"type" => "model_output"}) == %{"type" => "model_output"}
    end
  end

  describe "content/1 and signature/1" do
    test "content/1 returns [] when the step has no content" do
      assert Step.content(Step.from_api(%{"type" => "thought"})) == []
    end

    test "signature/1 reads the signature off an unknown step's raw map" do
      step = Step.from_api(%{"type" => "future_tool_call", "signature" => "sig_future"})

      assert Step.signature(step) == "sig_future"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/gemini/types/interactions/step_test.exs`
Expected: FAIL — `module Gemini.Types.Interactions.Step is not available`

- [ ] **Step 3: Write the implementation**

Create `lib/gemini/types/interactions/step.ex`:

```elixir
defmodule Gemini.Types.Interactions.StandardStep do
  @moduledoc """
  A step in an Interactions response.

  Covers every step type whose shape is `{type, content, name, id}`, optionally
  carrying a thought signature. See `Gemini.Types.Interactions.Step` for the
  full list of step types and for the two types that need their own structs.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Content

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t())
    field(:content, [Content.t()])
    field(:name, String.t())
    field(:id, String.t())
    field(:signature, String.t())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = step), do: step

  def from_api(%{} = data) do
    %__MODULE__{
      type: Map.get(data, "type"),
      content: map_list(Map.get(data, "content"), &Content.from_api/1),
      name: Map.get(data, "name"),
      id: Map.get(data, "id"),
      signature: Map.get(data, "signature")
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = step) do
    %{}
    |> maybe_put("type", step.type)
    |> maybe_put("content", map_list(step.content, &Content.to_api/1))
    |> maybe_put("name", step.name)
    |> maybe_put("id", step.id)
    |> maybe_put("signature", step.signature)
  end

  defp map_list(nil, _fun), do: nil
  defp map_list(list, fun) when is_list(list), do: Enum.map(list, fun)
end

defmodule Gemini.Types.Interactions.FunctionCallStep do
  @moduledoc """
  A `function_call` step. Adds `arguments` to the standard step shape.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Content

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "function_call")
    field(:content, [Content.t()])
    field(:name, String.t())
    field(:id, String.t())
    field(:arguments, map())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = step), do: step

  def from_api(%{} = data) do
    %__MODULE__{
      type: Map.get(data, "type") || "function_call",
      content: map_list(Map.get(data, "content"), &Content.from_api/1),
      name: Map.get(data, "name"),
      id: Map.get(data, "id"),
      arguments: Map.get(data, "arguments")
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = step) do
    %{"type" => "function_call"}
    |> maybe_put("content", map_list(step.content, &Content.to_api/1))
    |> maybe_put("name", step.name)
    |> maybe_put("id", step.id)
    |> maybe_put("arguments", step.arguments)
  end

  defp map_list(nil, _fun), do: nil
  defp map_list(list, fun) when is_list(list), do: Enum.map(list, fun)
end

defmodule Gemini.Types.Interactions.FunctionResultStep do
  @moduledoc """
  A `function_result` step. Uses `call_id` to link back to its `function_call`.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Content

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "function_result")
    field(:content, [Content.t()])
    field(:name, String.t())
    field(:call_id, String.t())
    field(:signature, String.t())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = step), do: step

  def from_api(%{} = data) do
    %__MODULE__{
      type: Map.get(data, "type") || "function_result",
      content: map_list(Map.get(data, "content"), &Content.from_api/1),
      name: Map.get(data, "name"),
      call_id: Map.get(data, "call_id"),
      signature: Map.get(data, "signature")
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = step) do
    %{"type" => "function_result"}
    |> maybe_put("content", map_list(step.content, &Content.to_api/1))
    |> maybe_put("name", step.name)
    |> maybe_put("call_id", step.call_id)
    |> maybe_put("signature", step.signature)
  end

  defp map_list(nil, _fun), do: nil
  defp map_list(list, fun) when is_list(list), do: Enum.map(list, fun)
end

defmodule Gemini.Types.Interactions.UnknownStep do
  @moduledoc """
  A step whose `type` this library does not model.

  Retains the original map verbatim. This matters for stateless mode: built-in
  tool steps carry thought signatures that must be resent byte-identically, so
  an unmodeled future tool step must survive a `from_api/1` + `to_api/1` round
  trip without losing anything.
  """

  use TypedStruct

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t())
    field(:raw, map())
  end

  @spec from_api(map()) :: t()
  def from_api(%{} = data) do
    %__MODULE__{type: Map.get(data, "type"), raw: data}
  end

  @spec to_api(t()) :: map()
  def to_api(%__MODULE__{raw: raw}), do: raw
end

defmodule Gemini.Types.Interactions.Step do
  @moduledoc """
  Step union for Interactions responses.

  An interaction's `steps` array is the authoritative record of what happened
  during a turn. Step types documented at
  <https://ai.google.dev/api/interactions-api>:

  `user_input`, `model_output`, `thought`, `function_call`, `function_result`,
  `code_execution`, `code_execution_result`, `file_search_call`,
  `file_search_result`, `google_search_call`, `google_search_result`,
  `google_maps_call`, `google_maps_result`, `retrieval_call`,
  `retrieval_result`, `url_context_call`, `url_context_result`,
  `mcp_server_tool_call`, `mcp_server_tool_result`, `computer_use`.

  All but `function_call` and `function_result` share one shape and parse into
  `Gemini.Types.Interactions.StandardStep`. An unrecognized type parses into
  `Gemini.Types.Interactions.UnknownStep`, which retains the raw map.
  """

  alias Gemini.Types.Interactions.{
    FunctionCallStep,
    FunctionResultStep,
    StandardStep,
    UnknownStep
  }

  @type t :: StandardStep.t() | FunctionCallStep.t() | FunctionResultStep.t() | UnknownStep.t()

  @standard_types ~w(
    user_input
    model_output
    thought
    code_execution
    code_execution_call
    code_execution_result
    file_search_call
    file_search_result
    google_search_call
    google_search_result
    google_maps_call
    google_maps_result
    retrieval_call
    retrieval_result
    url_context_call
    url_context_result
    mcp_server_tool_call
    mcp_server_tool_result
    computer_use
  )

  @doc """
  Step types that parse into `Gemini.Types.Interactions.StandardStep`.
  """
  @spec standard_types() :: [String.t()]
  def standard_types, do: @standard_types

  @spec from_api(map() | t() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%_{} = step), do: step

  def from_api(%{} = data) do
    case Map.get(data, "type") do
      "function_call" -> FunctionCallStep.from_api(data)
      "function_result" -> FunctionResultStep.from_api(data)
      type when type in @standard_types -> StandardStep.from_api(data)
      _ -> UnknownStep.from_api(data)
    end
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map
  def to_api(%StandardStep{} = step), do: StandardStep.to_api(step)
  def to_api(%FunctionCallStep{} = step), do: FunctionCallStep.to_api(step)
  def to_api(%FunctionResultStep{} = step), do: FunctionResultStep.to_api(step)
  def to_api(%UnknownStep{} = step), do: UnknownStep.to_api(step)

  @doc """
  Content blocks carried by a step. Returns `[]` when the step has none.
  """
  @spec content(t()) :: list()
  def content(%UnknownStep{raw: raw}), do: Map.get(raw, "content") || []
  def content(%{content: nil}), do: []
  def content(%{content: content}) when is_list(content), do: content
  def content(_), do: []

  @doc """
  Thought signature carried by a step, or `nil`.

  Signatures appear on `thought` steps and on built-in tool steps such as
  `google_search_call`. See <https://ai.google.dev/gemini-api/docs/thinking>.
  """
  @spec signature(t()) :: String.t() | nil
  def signature(%UnknownStep{raw: raw}), do: Map.get(raw, "signature")
  def signature(%{signature: signature}), do: signature
  def signature(_), do: nil
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/gemini/types/interactions/step_test.exs`
Expected: PASS, 12 tests

- [ ] **Step 5: Format, compile clean, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/gemini/types/interactions/step.ex test/gemini/types/interactions/step_test.exs
git commit -m "feat(interactions): add Step model for response steps"
```

---

### Task 2: Interaction resource — steps, output fields, compat

**Files:**
- Modify: `lib/gemini/types/interactions/interaction.ex:17-65`
- Test: `test/gemini/types/interactions/interaction_test.exs`

**Interfaces:**
- Consumes: `Step.from_api/1`, `Step.to_api/1`, `Step.content/1`, `Step.signature/1` (Task 1).
- Produces:
  - `Interaction` gains fields: `object`, `steps`, `output_text`, `output_image`, `output_audio`, `output_video`, `input`, `system_instruction`, `tools`, `response_format`, `generation_config`, `agent_config`, `safety_settings`, `service_tier`, `environment`, `environment_id`, `labels`, `webhook_config`, `user_metadata`
  - `Interaction.output_text(t()) :: {:ok, String.t()} | {:error, :not_found}`
  - `Interaction.output_image(t()) :: {:ok, ImageContent.t()} | {:error, :not_found}`
  - `Interaction.output_audio(t()) :: {:ok, AudioContent.t()} | {:error, :not_found}`
  - `Interaction.output_video(t()) :: {:ok, VideoContent.t()} | {:error, :not_found}`
  - `Interaction.thought_signatures(t()) :: [String.t()]`

Note the name collision: `output_text` is both a struct field and a function. In Elixir a field and a same-named function coexist without conflict, and this keeps the API matching the documentation's naming. The functions take one argument, so `Interaction.output_text(interaction)` is unambiguous.

- [ ] **Step 1: Write the failing test**

Create `test/gemini/types/interactions/interaction_test.exs`:

```elixir
defmodule Gemini.Types.Interactions.InteractionTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.{AudioContent, ImageContent, Interaction, TextContent}

  defp steps_response do
    %{
      "id" => "int_123",
      "object" => "interaction",
      "status" => "completed",
      "model" => "gemini-3.6-flash",
      "steps" => [
        %{"type" => "user_input", "content" => [%{"type" => "text", "text" => "Hi"}]},
        %{"type" => "thought", "signature" => "sig_a"},
        %{"type" => "google_search_call", "signature" => "sig_b"},
        %{"type" => "model_output", "content" => [%{"type" => "text", "text" => "Hello!"}]}
      ]
    }
  end

  describe "from_api/1 with steps" do
    test "parses steps" do
      interaction = Interaction.from_api(steps_response())

      assert length(interaction.steps) == 4
    end

    test "derives outputs by flattening every step's content, in order" do
      interaction = Interaction.from_api(steps_response())

      assert [%TextContent{text: "Hi"}, %TextContent{text: "Hello!"}] = interaction.outputs
    end

    test "parses the object field" do
      assert Interaction.from_api(steps_response()).object == "interaction"
    end
  end

  describe "from_api/1 backward compatibility" do
    test "an outputs-shaped response still parses and leaves steps nil" do
      interaction =
        Interaction.from_api(%{
          "id" => "int_1",
          "status" => "completed",
          "outputs" => [%{"type" => "text", "text" => "Legacy"}]
        })

      assert [%TextContent{text: "Legacy"}] = interaction.outputs
      assert interaction.steps == nil
    end
  end

  describe "output accessors" do
    test "output_text/1 prefers the server-provided field" do
      interaction =
        Interaction.from_api(Map.put(steps_response(), "output_text", "From server"))

      assert Interaction.output_text(interaction) == {:ok, "From server"}
    end

    test "output_text/1 falls back to the last model_output step" do
      assert Interaction.output_text(Interaction.from_api(steps_response())) == {:ok, "Hello!"}
    end

    test "output_text/1 returns :not_found when there is no text anywhere" do
      interaction = Interaction.from_api(%{"id" => "i", "status" => "completed"})

      assert Interaction.output_text(interaction) == {:error, :not_found}
    end

    test "output_image/1 falls back to the last image block in steps" do
      response =
        Map.put(steps_response(), "steps", [
          %{
            "type" => "model_output",
            "content" => [%{"type" => "image", "data" => "abc", "mime_type" => "image/png"}]
          }
        ])

      assert {:ok, %ImageContent{data: "abc"}} =
               Interaction.output_image(Interaction.from_api(response))
    end

    test "output_audio/1 falls back to the last audio block in steps" do
      response =
        Map.put(steps_response(), "steps", [
          %{
            "type" => "model_output",
            "content" => [%{"type" => "audio", "data" => "pcm", "mime_type" => "audio/pcm"}]
          }
        ])

      assert {:ok, %AudioContent{data: "pcm"}} =
               Interaction.output_audio(Interaction.from_api(response))
    end
  end

  describe "thought_signatures/1" do
    test "collects signatures from thought and built-in tool steps in order" do
      interaction = Interaction.from_api(steps_response())

      assert Interaction.thought_signatures(interaction) == ["sig_a", "sig_b"]
    end

    test "returns [] when there are no steps" do
      interaction = Interaction.from_api(%{"id" => "i", "status" => "completed"})

      assert Interaction.thought_signatures(interaction) == []
    end
  end

  describe "to_api/1" do
    test "round-trips steps" do
      interaction = Interaction.from_api(steps_response())
      encoded = Interaction.to_api(interaction)

      assert encoded["steps"] == steps_response()["steps"]
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/gemini/types/interactions/interaction_test.exs`
Expected: FAIL — `Interaction.output_text/1 is undefined`

- [ ] **Step 3: Replace the typedstruct block**

In `lib/gemini/types/interactions/interaction.ex`, replace lines 17-28 with:

```elixir
  @derive Jason.Encoder
  typedstruct enforce: true do
    field(:id, String.t())
    field(:status, status())
    field(:object, String.t(), enforce: false)
    field(:agent, String.t(), enforce: false)
    field(:agent_config, map(), enforce: false)
    field(:created, DateTime.t(), enforce: false)
    field(:environment, term(), enforce: false)
    field(:environment_id, String.t(), enforce: false)
    field(:generation_config, map(), enforce: false)
    field(:input, term(), enforce: false)
    field(:labels, map(), enforce: false)
    field(:model, String.t(), enforce: false)
    field(:output_audio, AudioContent.t(), enforce: false)
    field(:output_image, ImageContent.t(), enforce: false)
    field(:output_text, String.t(), enforce: false)
    field(:output_video, VideoContent.t(), enforce: false)
    field(:outputs, [Content.t()], enforce: false)
    field(:previous_interaction_id, String.t(), enforce: false)
    field(:response_format, term(), enforce: false)
    field(:role, String.t(), enforce: false)
    field(:safety_settings, list(), enforce: false)
    field(:service_tier, String.t(), enforce: false)
    field(:steps, [Step.t()], enforce: false)
    field(:system_instruction, String.t(), enforce: false)
    field(:tools, list(), enforce: false)
    field(:updated, DateTime.t(), enforce: false)
    field(:usage, Usage.t(), enforce: false)
    field(:user_metadata, map(), enforce: false)
    field(:webhook_config, map(), enforce: false)
  end
```

Update the alias on line 12 to:

```elixir
  alias Gemini.Types.Interactions.{
    AudioContent,
    Content,
    ImageContent,
    Step,
    Usage,
    VideoContent
  }
```

Update the `@moduledoc` on lines 2-6 to:

```elixir
  @moduledoc """
  Interactions `Interaction` resource.

  JSON keys are snake_case, matching the Interactions API.

  `steps` is the authoritative record of a turn. `outputs` is retained for
  backward compatibility and is derived by flattening each step's content in
  order when the response carries `steps`.

  Documented `status` values are `in_progress`, `requires_action`, `completed`,
  `failed`, `cancelled`, `incomplete`, `budget_exceeded`, and `queued`. The
  field stays a plain string so a new server-side status does not break parsing.

  Reference: <https://ai.google.dev/api/interactions-api>
  """
```

- [ ] **Step 4: Replace from_api/1 and to_api/1**

Replace the `from_api(%{} = data)` clause (lines 34-47) with:

```elixir
  def from_api(%{} = data) do
    steps = map_list(Map.get(data, "steps"), &Step.from_api/1)

    %__MODULE__{
      id: Map.get(data, "id"),
      status: Map.get(data, "status"),
      object: Map.get(data, "object"),
      agent: Map.get(data, "agent"),
      agent_config: Map.get(data, "agent_config"),
      created: parse_datetime(Map.get(data, "created")),
      environment: Map.get(data, "environment"),
      environment_id: Map.get(data, "environment_id"),
      generation_config: Map.get(data, "generation_config"),
      input: Map.get(data, "input"),
      labels: Map.get(data, "labels"),
      model: Map.get(data, "model"),
      output_audio: Content.from_api(Map.get(data, "output_audio")),
      output_image: Content.from_api(Map.get(data, "output_image")),
      output_text: Map.get(data, "output_text"),
      output_video: Content.from_api(Map.get(data, "output_video")),
      outputs: parse_outputs(Map.get(data, "outputs"), steps),
      previous_interaction_id: Map.get(data, "previous_interaction_id"),
      response_format: Map.get(data, "response_format"),
      role: Map.get(data, "role"),
      safety_settings: Map.get(data, "safety_settings"),
      service_tier: Map.get(data, "service_tier"),
      steps: steps,
      system_instruction: Map.get(data, "system_instruction"),
      tools: Map.get(data, "tools"),
      updated: parse_datetime(Map.get(data, "updated")),
      usage: Usage.from_api(Map.get(data, "usage")),
      user_metadata: Map.get(data, "user_metadata"),
      webhook_config: Map.get(data, "webhook_config")
    }
  end
```

Replace the `to_api(%__MODULE__{} = interaction)` clause (lines 53-65) with:

```elixir
  def to_api(%__MODULE__{} = interaction) do
    %{}
    |> maybe_put("id", interaction.id)
    |> maybe_put("status", interaction.status)
    |> maybe_put("object", interaction.object)
    |> maybe_put("agent", interaction.agent)
    |> maybe_put("agent_config", interaction.agent_config)
    |> maybe_put("created", datetime_to_iso8601(interaction.created))
    |> maybe_put("environment", interaction.environment)
    |> maybe_put("environment_id", interaction.environment_id)
    |> maybe_put("generation_config", interaction.generation_config)
    |> maybe_put("input", interaction.input)
    |> maybe_put("labels", interaction.labels)
    |> maybe_put("model", interaction.model)
    |> maybe_put("output_audio", Content.to_api(interaction.output_audio))
    |> maybe_put("output_image", Content.to_api(interaction.output_image))
    |> maybe_put("output_text", interaction.output_text)
    |> maybe_put("output_video", Content.to_api(interaction.output_video))
    |> maybe_put("outputs", map_list(interaction.outputs, &Content.to_api/1))
    |> maybe_put("previous_interaction_id", interaction.previous_interaction_id)
    |> maybe_put("response_format", interaction.response_format)
    |> maybe_put("role", interaction.role)
    |> maybe_put("safety_settings", interaction.safety_settings)
    |> maybe_put("service_tier", interaction.service_tier)
    |> maybe_put("steps", map_list(interaction.steps, &Step.to_api/1))
    |> maybe_put("system_instruction", interaction.system_instruction)
    |> maybe_put("tools", interaction.tools)
    |> maybe_put("updated", datetime_to_iso8601(interaction.updated))
    |> maybe_put("usage", Usage.to_api(interaction.usage))
    |> maybe_put("user_metadata", interaction.user_metadata)
    |> maybe_put("webhook_config", interaction.webhook_config)
  end
```

- [ ] **Step 5: Add the accessors and private helpers**

Insert immediately after the `to_api/1` clauses, before `defp parse_datetime`:

```elixir
  @doc """
  Text output of the interaction.

  Returns the server-provided `output_text` when present, otherwise the
  concatenated text of the last `model_output` step, otherwise the last text
  block in `outputs`.
  """
  @spec output_text(t()) :: {:ok, String.t()} | {:error, :not_found}
  def output_text(%__MODULE__{output_text: text}) when is_binary(text) and text != "",
    do: {:ok, text}

  def output_text(%__MODULE__{} = interaction) do
    interaction
    |> last_model_output_text()
    |> case do
      nil -> {:error, :not_found}
      text -> {:ok, text}
    end
  end

  @doc """
  Last image block produced by the interaction.
  """
  @spec output_image(t()) :: {:ok, ImageContent.t()} | {:error, :not_found}
  def output_image(%__MODULE__{output_image: %ImageContent{} = image}), do: {:ok, image}
  def output_image(%__MODULE__{} = interaction), do: last_block(interaction, ImageContent)

  @doc """
  Last audio block produced by the interaction.
  """
  @spec output_audio(t()) :: {:ok, AudioContent.t()} | {:error, :not_found}
  def output_audio(%__MODULE__{output_audio: %AudioContent{} = audio}), do: {:ok, audio}
  def output_audio(%__MODULE__{} = interaction), do: last_block(interaction, AudioContent)

  @doc """
  Last video block produced by the interaction.
  """
  @spec output_video(t()) :: {:ok, VideoContent.t()} | {:error, :not_found}
  def output_video(%__MODULE__{output_video: %VideoContent{} = video}), do: {:ok, video}
  def output_video(%__MODULE__{} = interaction), do: last_block(interaction, VideoContent)

  @doc """
  Every thought signature in the interaction, in step order.

  In stateless mode (`store: false`) these must be resent byte-identically on
  the following turn. See <https://ai.google.dev/gemini-api/docs/thinking>.
  """
  @spec thought_signatures(t()) :: [String.t()]
  def thought_signatures(%__MODULE__{steps: nil}), do: []

  def thought_signatures(%__MODULE__{steps: steps}) do
    steps
    |> Enum.map(&Step.signature/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_outputs(nil, nil), do: nil
  defp parse_outputs(nil, steps) when is_list(steps), do: Enum.flat_map(steps, &Step.content/1)
  defp parse_outputs(outputs, _steps), do: map_list(outputs, &Content.from_api/1)

  defp last_model_output_text(%__MODULE__{steps: steps}) when is_list(steps) do
    steps
    |> Enum.filter(&(step_type(&1) == "model_output"))
    |> List.last()
    |> case do
      nil -> nil
      step -> step |> Step.content() |> text_of()
    end
  end

  defp last_model_output_text(%__MODULE__{outputs: outputs}) when is_list(outputs),
    do: text_of(outputs)

  defp last_model_output_text(_), do: nil

  defp text_of(blocks) do
    blocks
    |> Enum.filter(&is_struct(&1, TextContent))
    |> Enum.map_join("", & &1.text)
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp step_type(%{type: type}), do: type
  defp step_type(_), do: nil

  defp last_block(%__MODULE__{} = interaction, module) do
    interaction
    |> all_blocks()
    |> Enum.filter(&is_struct(&1, module))
    |> List.last()
    |> case do
      nil -> {:error, :not_found}
      block -> {:ok, block}
    end
  end

  defp all_blocks(%__MODULE__{steps: steps}) when is_list(steps),
    do: Enum.flat_map(steps, &Step.content/1)

  defp all_blocks(%__MODULE__{outputs: outputs}) when is_list(outputs), do: outputs
  defp all_blocks(_), do: []
```

Add `TextContent` to the alias list from Step 3, making it:

```elixir
  alias Gemini.Types.Interactions.{
    AudioContent,
    Content,
    ImageContent,
    Step,
    TextContent,
    Usage,
    VideoContent
  }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/gemini/types/interactions/interaction_test.exs test/gemini/apis/interactions_test.exs`
Expected: PASS. The existing `interactions_test.exs` must still pass unchanged — it uses an `outputs`-shaped fixture, which is exactly the compatibility path.

- [ ] **Step 7: Format, compile clean, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/gemini/types/interactions/interaction.ex test/gemini/types/interactions/interaction_test.exs
git commit -m "feat(interactions): parse steps and output fields on Interaction"
```

---

### Task 3: SSE event realignment

**Files:**
- Modify: `lib/gemini/types/interactions/events.ex` — add step event structs, extend the dispatcher at lines 325-348
- Test: `test/gemini/types/interactions/events_test.exs`

**Interfaces:**
- Consumes: `Delta.from_api/1`, `Delta.to_api/1` (existing, `delta.ex`); `Step.from_api/1` (Task 1).
- Produces: `Gemini.Types.Interactions.Events.StepStart`, `.StepDelta`, `.StepStop`, each with `from_api/1` and `to_api/1` and fields `event_id`, `event_type`, `index`, plus `delta` on `StepDelta` and `step` on `StepStart`/`StepStop`.

The current dispatcher maps `interaction.start` and `interaction.complete`. The API emits `interaction.created` and `interaction.completed`. Both spellings must parse.

- [ ] **Step 1: Write the failing test**

Create `test/gemini/types/interactions/events_test.exs`:

```elixir
defmodule Gemini.Types.Interactions.EventsTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.{DeltaTextDelta, DeltaThoughtSignatureDelta}

  alias Gemini.Types.Interactions.Events.{
    InteractionEvent,
    InteractionSSEEvent,
    StepDelta,
    StepStart,
    StepStop
  }

  describe "InteractionSSEEvent.from_api/1" do
    test "dispatches step.delta with a text delta" do
      event =
        InteractionSSEEvent.from_api(%{
          "event_type" => "step.delta",
          "event_id" => "e1",
          "index" => 0,
          "delta" => %{"type" => "text", "text" => "Hel"}
        })

      assert %StepDelta{index: 0, delta: %DeltaTextDelta{text: "Hel"}} = event
    end

    test "dispatches step.delta with a thought_signature delta" do
      event =
        InteractionSSEEvent.from_api(%{
          "event_type" => "step.delta",
          "index" => 1,
          "delta" => %{"type" => "thought_signature", "signature" => "sig_a"}
        })

      assert %StepDelta{delta: %DeltaThoughtSignatureDelta{}} = event
    end

    test "dispatches step.start" do
      assert %StepStart{index: 0} =
               InteractionSSEEvent.from_api(%{"event_type" => "step.start", "index" => 0})
    end

    test "dispatches step.stop" do
      assert %StepStop{index: 2} =
               InteractionSSEEvent.from_api(%{"event_type" => "step.stop", "index" => 2})
    end

    test "dispatches interaction.created" do
      assert %InteractionEvent{} =
               InteractionSSEEvent.from_api(%{
                 "event_type" => "interaction.created",
                 "interaction" => %{"id" => "i", "status" => "in_progress"}
               })
    end

    test "dispatches interaction.completed" do
      assert %InteractionEvent{} =
               InteractionSSEEvent.from_api(%{
                 "event_type" => "interaction.completed",
                 "interaction" => %{"id" => "i", "status" => "completed"}
               })
    end

    test "still dispatches the legacy interaction.start spelling" do
      assert %InteractionEvent{} =
               InteractionSSEEvent.from_api(%{
                 "event_type" => "interaction.start",
                 "interaction" => %{"id" => "i", "status" => "in_progress"}
               })
    end

    test "returns nil for an unrecognized event_type" do
      assert InteractionSSEEvent.from_api(%{"event_type" => "nope"}) == nil
    end
  end

  describe "to_api/1" do
    test "StepDelta round-trips" do
      raw = %{
        "event_type" => "step.delta",
        "event_id" => "e1",
        "index" => 0,
        "delta" => %{"type" => "text", "text" => "Hel"}
      }

      assert raw |> StepDelta.from_api() |> StepDelta.to_api() == raw
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/gemini/types/interactions/events_test.exs`
Expected: FAIL — `Gemini.Types.Interactions.Events.StepDelta is not available`

- [ ] **Step 3: Add the three step event structs**

Insert into `lib/gemini/types/interactions/events.ex`, immediately before `defmodule Gemini.Types.Interactions.Events.InteractionSSEEvent`:

```elixir
defmodule Gemini.Types.Interactions.Events.StepStart do
  @moduledoc """
  Interactions SSE event: `step.start`.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Step

  @derive Jason.Encoder
  typedstruct do
    field(:event_id, String.t())
    field(:event_type, String.t())
    field(:index, non_neg_integer())
    field(:step, Step.t())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = event), do: event

  def from_api(%{} = data) do
    %__MODULE__{
      event_id: Map.get(data, "event_id"),
      event_type: Map.get(data, "event_type"),
      index: Map.get(data, "index"),
      step: Step.from_api(Map.get(data, "step"))
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = event) do
    %{"event_type" => "step.start"}
    |> maybe_put("event_id", event.event_id)
    |> maybe_put("index", event.index)
    |> maybe_put("step", Step.to_api(event.step))
  end
end

defmodule Gemini.Types.Interactions.Events.StepDelta do
  @moduledoc """
  Interactions SSE event: `step.delta`.

  Carries one `Gemini.Types.Interactions.Delta` variant. Delta types include
  `text`, `thought_summary`, `thought_signature`, `audio`, `image`, `video`,
  and the tool call/result variants.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Delta

  @derive Jason.Encoder
  typedstruct do
    field(:event_id, String.t())
    field(:event_type, String.t())
    field(:index, non_neg_integer())
    field(:delta, Delta.t())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = event), do: event

  def from_api(%{} = data) do
    %__MODULE__{
      event_id: Map.get(data, "event_id"),
      event_type: Map.get(data, "event_type"),
      index: Map.get(data, "index"),
      delta: Delta.from_api(Map.get(data, "delta"))
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = event) do
    %{"event_type" => "step.delta"}
    |> maybe_put("event_id", event.event_id)
    |> maybe_put("index", event.index)
    |> maybe_put("delta", Delta.to_api(event.delta))
  end
end

defmodule Gemini.Types.Interactions.Events.StepStop do
  @moduledoc """
  Interactions SSE event: `step.stop`.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  alias Gemini.Types.Interactions.Step

  @derive Jason.Encoder
  typedstruct do
    field(:event_id, String.t())
    field(:event_type, String.t())
    field(:index, non_neg_integer())
    field(:step, Step.t())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = event), do: event

  def from_api(%{} = data) do
    %__MODULE__{
      event_id: Map.get(data, "event_id"),
      event_type: Map.get(data, "event_type"),
      index: Map.get(data, "index"),
      step: Step.from_api(Map.get(data, "step"))
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = event) do
    %{"event_type" => "step.stop"}
    |> maybe_put("event_id", event.event_id)
    |> maybe_put("index", event.index)
    |> maybe_put("step", Step.to_api(event.step))
  end
end
```

- [ ] **Step 4: Extend the dispatcher**

In `lib/gemini/types/interactions/events.ex`, replace the alias block and `case` inside `InteractionSSEEvent.from_api/1` (lines ~325-348) with:

```elixir
  alias Gemini.Types.Interactions.Events.{
    ContentDelta,
    ContentStart,
    ContentStop,
    ErrorEvent,
    InteractionEvent,
    InteractionSSEEvent,
    InteractionStatusUpdate,
    StepDelta,
    StepStart,
    StepStop
  }

  @spec from_api(map() | InteractionSSEEvent.t() | nil) :: InteractionSSEEvent.t() | nil
  def from_api(nil), do: nil
  def from_api(%_{} = event), do: event

  def from_api(%{} = data) do
    case Map.get(data, "event_type") do
      "interaction.created" -> InteractionEvent.from_api(data)
      "interaction.completed" -> InteractionEvent.from_api(data)
      "interaction.status_update" -> InteractionStatusUpdate.from_api(data)
      "step.start" -> StepStart.from_api(data)
      "step.delta" -> StepDelta.from_api(data)
      "step.stop" -> StepStop.from_api(data)
      "error" -> ErrorEvent.from_api(data)
      # Superseded spellings, retained so existing callers and older servers
      # keep working. See the design doc's Amendment A4.
      "interaction.start" -> InteractionEvent.from_api(data)
      "interaction.complete" -> InteractionEvent.from_api(data)
      "content.start" -> ContentStart.from_api(data)
      "content.delta" -> ContentDelta.from_api(data)
      "content.stop" -> ContentStop.from_api(data)
      _ -> nil
    end
  end
```

Note: `ContentStart` was referenced but missing from the original alias list — the existing code relies on it resolving by full name. Adding it to the alias is a fix, not a behavior change.

Update the module's `@moduledoc` to say "Union type for Interactions SSE events" without a variant count, since the count is now larger and would drift.

- [ ] **Step 5: Add an end-to-end streaming test**

Unit-testing the structs is not enough — the events must survive the real SSE path. Append to `test/gemini/apis/interactions_test.exs`, matching the streaming-test style already in that file:

```elixir
  describe "create/2 streaming with step.* events" do
    test "yields StepDelta events from an SSE stream", %{bypass: bypass} do
      body =
        [
          ~s(data: {"event_type":"interaction.created","interaction":{"id":"i","status":"in_progress"}}\n\n),
          ~s(data: {"event_type":"step.start","index":0}\n\n),
          ~s(data: {"event_type":"step.delta","index":0,"delta":{"type":"text","text":"Hel"}}\n\n),
          ~s(data: {"event_type":"step.delta","index":0,"delta":{"type":"text","text":"lo"}}\n\n),
          ~s(data: {"event_type":"step.stop","index":0}\n\n),
          ~s(data: [DONE]\n\n)
        ]
        |> Enum.join()

      Bypass.expect_once(bypass, "POST", "/v1beta/interactions", fn conn ->
        conn
        |> Conn.put_resp_content_type("text/event-stream")
        |> Conn.resp(200, body)
      end)

      {:ok, stream} = Interactions.create("hi", model: "gemini-3.6-flash", stream: true)

      events = Enum.to_list(stream)

      text =
        events
        |> Enum.filter(&is_struct(&1, Gemini.Types.Interactions.Events.StepDelta))
        |> Enum.map(& &1.delta.text)
        |> Enum.join()

      assert text == "Hello"

      assert Enum.any?(events, &is_struct(&1, Gemini.Types.Interactions.Events.StepStart))
      assert Enum.any?(events, &is_struct(&1, Gemini.Types.Interactions.Events.StepStop))
    end
  end
```

Add `StepDelta`, `StepStart`, and `StepStop` to that file's existing `alias Gemini.Types.Interactions.Events.{...}` block.

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/gemini/types/interactions/events_test.exs test/gemini/apis/interactions_test.exs`
Expected: PASS, including the pre-existing streaming tests that use `content.*`

- [ ] **Step 7: Format, compile clean, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/gemini/types/interactions/events.ex test/gemini/types/interactions/events_test.exs test/gemini/apis/interactions_test.exs
git commit -m "feat(interactions): add step.* SSE events and correct interaction event names"
```

---

### Task 4: Missing Delta variants

**Files:**
- Modify: `lib/gemini/types/interactions/delta.ex` — add structs, extend `@type_to_module` (line ~950) and the `to_api/1` clause list
- Test: `test/gemini/types/interactions/delta_test.exs`

**Interfaces:**
- Produces: `DeltaTextAnnotationDelta`, `DeltaArgumentsDelta`, `DeltaGoogleMapsCallDelta`, `DeltaGoogleMapsResultDelta`, `DeltaRetrievalCallDelta`, `DeltaRetrievalResultDelta`, `DeltaFileSearchCallDelta`, each under `Gemini.Types.Interactions.` with `from_api/1` and `to_api/1`.

`Delta.from_api/1` already falls back to returning the raw map for unknown types, so these additions are about typed access, not preventing crashes.

- [ ] **Step 1: Write the failing test**

Create `test/gemini/types/interactions/delta_test.exs`:

```elixir
defmodule Gemini.Types.Interactions.DeltaTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.{
    Delta,
    DeltaArgumentsDelta,
    DeltaFileSearchCallDelta,
    DeltaGoogleMapsCallDelta,
    DeltaGoogleMapsResultDelta,
    DeltaRetrievalCallDelta,
    DeltaRetrievalResultDelta,
    DeltaTextAnnotationDelta
  }

  test "parses arguments_delta, which streams function call arguments" do
    assert %DeltaArgumentsDelta{arguments: "{\"loc"} =
             Delta.from_api(%{"type" => "arguments_delta", "arguments" => "{\"loc"})
  end

  test "parses text_annotation_delta" do
    assert %DeltaTextAnnotationDelta{} =
             Delta.from_api(%{
               "type" => "text_annotation_delta",
               "annotation" => %{"type" => "url_citation", "uri" => "https://example.com"}
             })
  end

  test "parses google_maps_call and google_maps_result" do
    assert %DeltaGoogleMapsCallDelta{} = Delta.from_api(%{"type" => "google_maps_call"})
    assert %DeltaGoogleMapsResultDelta{} = Delta.from_api(%{"type" => "google_maps_result"})
  end

  test "parses retrieval_call and retrieval_result" do
    assert %DeltaRetrievalCallDelta{} = Delta.from_api(%{"type" => "retrieval_call"})
    assert %DeltaRetrievalResultDelta{} = Delta.from_api(%{"type" => "retrieval_result"})
  end

  test "parses file_search_call" do
    assert %DeltaFileSearchCallDelta{} = Delta.from_api(%{"type" => "file_search_call"})
  end

  test "still returns the raw map for a type it does not model" do
    raw = %{"type" => "something_new", "x" => 1}

    assert Delta.from_api(raw) == raw
  end

  test "round-trips arguments_delta" do
    raw = %{"type" => "arguments_delta", "arguments" => "{\"loc"}

    assert raw |> Delta.from_api() |> Delta.to_api() == raw
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/gemini/types/interactions/delta_test.exs`
Expected: FAIL — `DeltaArgumentsDelta.__struct__/0 is undefined`

- [ ] **Step 3: Add the seven structs**

Insert into `lib/gemini/types/interactions/delta.ex`, immediately before `defmodule Gemini.Types.Interactions.Delta`. Each follows the same shape; here is the full set:

```elixir
defmodule Gemini.Types.Interactions.DeltaArgumentsDelta do
  @moduledoc """
  Delta variant `arguments_delta`: a chunk of a streaming function call's
  arguments. Concatenate `arguments` across deltas, then decode as JSON.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "arguments_delta")
    field(:arguments, String.t())
    field(:id, String.t())
    field(:name, String.t())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = delta), do: delta

  def from_api(%{} = data) do
    %__MODULE__{
      type: Map.get(data, "type") || "arguments_delta",
      arguments: Map.get(data, "arguments"),
      id: Map.get(data, "id"),
      name: Map.get(data, "name")
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = delta) do
    %{"type" => "arguments_delta"}
    |> maybe_put("arguments", delta.arguments)
    |> maybe_put("id", delta.id)
    |> maybe_put("name", delta.name)
  end
end

defmodule Gemini.Types.Interactions.DeltaTextAnnotationDelta do
  @moduledoc """
  Delta variant `text_annotation_delta`: a citation or annotation attached to
  streamed text.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "text_annotation_delta")
    field(:annotation, map())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = delta), do: delta

  def from_api(%{} = data) do
    %__MODULE__{
      type: Map.get(data, "type") || "text_annotation_delta",
      annotation: Map.get(data, "annotation")
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = delta) do
    %{"type" => "text_annotation_delta"}
    |> maybe_put("annotation", delta.annotation)
  end
end
```

For the remaining five — `DeltaGoogleMapsCallDelta` (`"google_maps_call"`), `DeltaGoogleMapsResultDelta` (`"google_maps_result"`), `DeltaRetrievalCallDelta` (`"retrieval_call"`), `DeltaRetrievalResultDelta` (`"retrieval_result"`), and `DeltaFileSearchCallDelta` (`"file_search_call"`) — use this template, substituting the module name and type string. They have no documented type-specific fields beyond `id` and a passthrough `result`, so all five are identical apart from the literal:

```elixir
defmodule Gemini.Types.Interactions.DeltaGoogleMapsCallDelta do
  @moduledoc """
  Delta variant `google_maps_call`.
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "google_maps_call")
    field(:id, String.t())
    field(:result, term())
  end

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = delta), do: delta

  def from_api(%{} = data) do
    %__MODULE__{
      type: Map.get(data, "type") || "google_maps_call",
      id: Map.get(data, "id"),
      result: Map.get(data, "result")
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = delta) do
    %{"type" => "google_maps_call"}
    |> maybe_put("id", delta.id)
    |> maybe_put("result", delta.result)
  end
end
```

- [ ] **Step 4: Register them in the dispatcher**

Add to the `@type_to_module` map in `Gemini.Types.Interactions.Delta`:

```elixir
    "arguments_delta" => DeltaArgumentsDelta,
    "text_annotation_delta" => DeltaTextAnnotationDelta,
    "google_maps_call" => DeltaGoogleMapsCallDelta,
    "google_maps_result" => DeltaGoogleMapsResultDelta,
    "retrieval_call" => DeltaRetrievalCallDelta,
    "retrieval_result" => DeltaRetrievalResultDelta,
    "file_search_call" => DeltaFileSearchCallDelta,
```

Add the matching `to_api/1` clauses at the end of the existing list:

```elixir
  def to_api(%DeltaArgumentsDelta{} = delta), do: DeltaArgumentsDelta.to_api(delta)
  def to_api(%DeltaTextAnnotationDelta{} = delta), do: DeltaTextAnnotationDelta.to_api(delta)
  def to_api(%DeltaGoogleMapsCallDelta{} = delta), do: DeltaGoogleMapsCallDelta.to_api(delta)
  def to_api(%DeltaGoogleMapsResultDelta{} = delta), do: DeltaGoogleMapsResultDelta.to_api(delta)
  def to_api(%DeltaRetrievalCallDelta{} = delta), do: DeltaRetrievalCallDelta.to_api(delta)
  def to_api(%DeltaRetrievalResultDelta{} = delta), do: DeltaRetrievalResultDelta.to_api(delta)
  def to_api(%DeltaFileSearchCallDelta{} = delta), do: DeltaFileSearchCallDelta.to_api(delta)
```

Add all seven module names to the module's `alias Gemini.Types.Interactions.{...}` list.

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/gemini/types/interactions/delta_test.exs`
Expected: PASS, 7 tests

- [ ] **Step 6: Format, compile clean, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/gemini/types/interactions/delta.ex test/gemini/types/interactions/delta_test.exs
git commit -m "feat(interactions): add remaining Delta variants"
```

---

### Task 5: Typed ResponseFormat

**Files:**
- Create: `lib/gemini/types/interactions/response_format.ex`
- Test: `test/gemini/types/interactions/response_format_test.exs`

**Interfaces:**
- Produces:
  - `Gemini.Types.Interactions.ResponseFormat.to_api(term()) :: term()` — accepts any variant struct, a raw map, or a list
  - Structs `ResponseFormat.Text` (`mime_type`, `schema`), `.Image` (`mime_type`, `aspect_ratio`, `image_size`), `.Audio` (no fields), `.Video` (`aspect_ratio`, `delivery`), `.JsonSchema` (`name`, `schema`, `strict`), `.JsonObject` (no fields)
  - `ResponseFormat.Image.aspect_ratios() :: [String.t()]`, `.image_sizes() :: [String.t()]`
  - `ResponseFormat.Video.aspect_ratios() :: [String.t()]`

- [ ] **Step 1: Write the failing test**

Create `test/gemini/types/interactions/response_format_test.exs`:

```elixir
defmodule Gemini.Types.Interactions.ResponseFormatTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.ResponseFormat

  alias Gemini.Types.Interactions.ResponseFormat.{
    Audio,
    Image,
    JsonObject,
    JsonSchema,
    Text,
    Video
  }

  test "Text with a JSON schema serializes as the structured-output shape" do
    schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}

    assert ResponseFormat.to_api(%Text{mime_type: "application/json", schema: schema}) == %{
             "type" => "text",
             "mime_type" => "application/json",
             "schema" => schema
           }
  end

  test "Text with no fields set serializes to just the type" do
    assert ResponseFormat.to_api(%Text{}) == %{"type" => "text"}
  end

  test "Image serializes aspect_ratio and image_size" do
    assert ResponseFormat.to_api(%Image{
             mime_type: "image/png",
             aspect_ratio: "16:9",
             image_size: "2K"
           }) == %{
             "type" => "image",
             "mime_type" => "image/png",
             "aspect_ratio" => "16:9",
             "image_size" => "2K"
           }
  end

  test "Audio serializes to just the type" do
    assert ResponseFormat.to_api(%Audio{}) == %{"type" => "audio"}
  end

  test "Video serializes aspect_ratio and delivery" do
    assert ResponseFormat.to_api(%Video{aspect_ratio: "9:16", delivery: "uri"}) == %{
             "type" => "video",
             "aspect_ratio" => "9:16",
             "delivery" => "uri"
           }
  end

  test "JsonSchema serializes the nested json_schema object" do
    schema = %{"type" => "object"}

    assert ResponseFormat.to_api(%JsonSchema{name: "Recipe", schema: schema, strict: true}) == %{
             "type" => "json_schema",
             "json_schema" => %{"name" => "Recipe", "schema" => schema, "strict" => true}
           }
  end

  test "JsonObject serializes to just the type" do
    assert ResponseFormat.to_api(%JsonObject{}) == %{"type" => "json_object"}
  end

  test "a raw map passes through unchanged" do
    raw = %{"type" => "image", "aspect_ratio" => "21:9"}

    assert ResponseFormat.to_api(raw) == raw
  end

  test "a list of formats serializes elementwise" do
    assert ResponseFormat.to_api([%Text{}, %Audio{}]) == [
             %{"type" => "text"},
             %{"type" => "audio"}
           ]
  end

  test "nil passes through" do
    assert ResponseFormat.to_api(nil) == nil
  end

  test "from_api parses a known variant" do
    assert %Image{aspect_ratio: "16:9"} =
             ResponseFormat.from_api(%{"type" => "image", "aspect_ratio" => "16:9"})
  end

  test "from_api returns the raw map for an unmodeled type" do
    raw = %{"type" => "hologram"}

    assert ResponseFormat.from_api(raw) == raw
  end

  test "documented allowed values are exposed" do
    assert "21:9" in Image.aspect_ratios()
    assert "4K" in Image.image_sizes()
    assert Video.aspect_ratios() == ["16:9", "9:16"]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/gemini/types/interactions/response_format_test.exs`
Expected: FAIL — `Gemini.Types.Interactions.ResponseFormat is not available`

- [ ] **Step 3: Write the implementation**

Create `lib/gemini/types/interactions/response_format.ex`:

```elixir
defmodule Gemini.Types.Interactions.ResponseFormat.Text do
  @moduledoc """
  Text response format. Set `mime_type` to `"application/json"` and supply a
  `schema` for structured output.

  <https://ai.google.dev/gemini-api/docs/structured-output>
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "text")
    field(:mime_type, String.t())
    field(:schema, map())
  end

  @spec from_api(map()) :: t()
  def from_api(%{} = data) do
    %__MODULE__{
      mime_type: Map.get(data, "mime_type"),
      schema: Map.get(data, "schema")
    }
  end

  @spec to_api(t()) :: map()
  def to_api(%__MODULE__{} = format) do
    %{"type" => "text"}
    |> maybe_put("mime_type", format.mime_type)
    |> maybe_put("schema", format.schema)
  end
end

defmodule Gemini.Types.Interactions.ResponseFormat.Image do
  @moduledoc """
  Image response format, used to request image generation.

  <https://ai.google.dev/gemini-api/docs/image-generation>
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @aspect_ratios ~w(1:1 3:2 2:3 3:4 4:3 4:5 5:4 9:16 16:9 21:9)
  @image_sizes ~w(512px 1K 2K 4K)

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "image")
    field(:mime_type, String.t())
    field(:aspect_ratio, String.t())
    field(:image_size, String.t())
  end

  @doc """
  Documented aspect ratios: #{Enum.join(@aspect_ratios, ", ")}.

  Not enforced — the server validates. Provided so callers can validate.
  """
  @spec aspect_ratios() :: [String.t()]
  def aspect_ratios, do: @aspect_ratios

  @doc """
  Documented image sizes: #{Enum.join(@image_sizes, ", ")}.
  """
  @spec image_sizes() :: [String.t()]
  def image_sizes, do: @image_sizes

  @spec from_api(map()) :: t()
  def from_api(%{} = data) do
    %__MODULE__{
      mime_type: Map.get(data, "mime_type"),
      aspect_ratio: Map.get(data, "aspect_ratio"),
      image_size: Map.get(data, "image_size")
    }
  end

  @spec to_api(t()) :: map()
  def to_api(%__MODULE__{} = format) do
    %{"type" => "image"}
    |> maybe_put("mime_type", format.mime_type)
    |> maybe_put("aspect_ratio", format.aspect_ratio)
    |> maybe_put("image_size", format.image_size)
  end
end

defmodule Gemini.Types.Interactions.ResponseFormat.Audio do
  @moduledoc """
  Audio response format, used to request speech generation.

  <https://ai.google.dev/gemini-api/docs/speech-generation>
  """

  use TypedStruct

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "audio")
  end

  @spec from_api(map()) :: t()
  def from_api(%{}), do: %__MODULE__{}

  @spec to_api(t()) :: map()
  def to_api(%__MODULE__{}), do: %{"type" => "audio"}
end

defmodule Gemini.Types.Interactions.ResponseFormat.Video do
  @moduledoc """
  Video response format, used to request video generation with Gemini Omni.

  Set `delivery` to `"uri"` for videos larger than 4 MB.

  <https://ai.google.dev/gemini-api/docs/omni>
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @aspect_ratios ~w(16:9 9:16)

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "video")
    field(:aspect_ratio, String.t())
    field(:delivery, String.t())
  end

  @doc """
  Documented aspect ratios: #{Enum.join(@aspect_ratios, ", ")}.
  """
  @spec aspect_ratios() :: [String.t()]
  def aspect_ratios, do: @aspect_ratios

  @spec from_api(map()) :: t()
  def from_api(%{} = data) do
    %__MODULE__{
      aspect_ratio: Map.get(data, "aspect_ratio"),
      delivery: Map.get(data, "delivery")
    }
  end

  @spec to_api(t()) :: map()
  def to_api(%__MODULE__{} = format) do
    %{"type" => "video"}
    |> maybe_put("aspect_ratio", format.aspect_ratio)
    |> maybe_put("delivery", format.delivery)
  end
end

defmodule Gemini.Types.Interactions.ResponseFormat.JsonSchema do
  @moduledoc """
  `json_schema` response format from the API reference.

  <https://ai.google.dev/api/interactions-api>
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "json_schema")
    field(:name, String.t())
    field(:schema, map())
    field(:strict, boolean())
  end

  @spec from_api(map()) :: t()
  def from_api(%{} = data) do
    nested = Map.get(data, "json_schema") || %{}

    %__MODULE__{
      name: Map.get(nested, "name"),
      schema: Map.get(nested, "schema"),
      strict: Map.get(nested, "strict")
    }
  end

  @spec to_api(t()) :: map()
  def to_api(%__MODULE__{} = format) do
    nested =
      %{}
      |> maybe_put("name", format.name)
      |> maybe_put("schema", format.schema)
      |> maybe_put("strict", format.strict)

    %{"type" => "json_schema"}
    |> maybe_put("json_schema", nested)
  end
end

defmodule Gemini.Types.Interactions.ResponseFormat.JsonObject do
  @moduledoc """
  `json_object` response format from the API reference.
  """

  use TypedStruct

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), default: "json_object")
  end

  @spec from_api(map()) :: t()
  def from_api(%{}), do: %__MODULE__{}

  @spec to_api(t()) :: map()
  def to_api(%__MODULE__{}), do: %{"type" => "json_object"}
end

defmodule Gemini.Types.Interactions.ResponseFormat do
  @moduledoc """
  Response format union for Interactions requests.

  Two families of shapes are documented, and both are supported here.

  The capability guides use a modality-typed shape — `{"type": "text",
  "mime_type": "application/json", "schema": {...}}` for structured output,
  `{"type": "image", "aspect_ratio": ..., "image_size": ...}` for image
  generation, `{"type": "audio"}` for speech, and `{"type": "video",
  "aspect_ratio": ..., "delivery": ...}` for Omni video.

  The API reference additionally documents `{"type": "json_schema",
  "json_schema": {...}}` and `{"type": "json_object"}`.

  Raw maps pass through untouched, so any shape this module does not model is
  still usable. A list is also accepted, per the reference's
  `ResponseFormat|array`.

  Sources:
  - <https://ai.google.dev/gemini-api/docs/structured-output>
  - <https://ai.google.dev/gemini-api/docs/image-generation>
  - <https://ai.google.dev/gemini-api/docs/speech-generation>
  - <https://ai.google.dev/api/interactions-api>
  """

  alias Gemini.Types.Interactions.ResponseFormat.{
    Audio,
    Image,
    JsonObject,
    JsonSchema,
    Text,
    Video
  }

  @type t ::
          Text.t()
          | Image.t()
          | Audio.t()
          | Video.t()
          | JsonSchema.t()
          | JsonObject.t()
          | map()
          | [t()]

  @type_to_module %{
    "text" => Text,
    "image" => Image,
    "audio" => Audio,
    "video" => Video,
    "json_schema" => JsonSchema,
    "json_object" => JsonObject
  }

  @spec from_api(term()) :: term()
  def from_api(nil), do: nil
  def from_api(%_{} = format), do: format
  def from_api(list) when is_list(list), do: Enum.map(list, &from_api/1)

  def from_api(%{} = data) do
    case Map.get(@type_to_module, Map.get(data, "type")) do
      nil -> data
      module -> module.from_api(data)
    end
  end

  def from_api(other), do: other

  @spec to_api(term()) :: term()
  def to_api(nil), do: nil
  def to_api(list) when is_list(list), do: Enum.map(list, &to_api/1)
  def to_api(%{} = map) when not is_struct(map), do: map
  def to_api(%Text{} = format), do: Text.to_api(format)
  def to_api(%Image{} = format), do: Image.to_api(format)
  def to_api(%Audio{} = format), do: Audio.to_api(format)
  def to_api(%Video{} = format), do: Video.to_api(format)
  def to_api(%JsonSchema{} = format), do: JsonSchema.to_api(format)
  def to_api(%JsonObject{} = format), do: JsonObject.to_api(format)
  def to_api(other), do: other
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/gemini/types/interactions/response_format_test.exs`
Expected: PASS, 13 tests

- [ ] **Step 5: Format, compile clean, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/gemini/types/interactions/response_format.ex test/gemini/types/interactions/response_format_test.exs
git commit -m "feat(interactions): add typed ResponseFormat variants"
```

---

### Task 6: DocumentContent resolution, GoogleSearch search_types, VideoConfig

**Files:**
- Modify: `lib/gemini/types/interactions/content.ex` — `DocumentContent` at lines 176-219
- Modify: `lib/gemini/types/interactions/tool.ex` — `GoogleSearch` at lines 82-103
- Modify: `lib/gemini/types/interactions/config.ex` — add `VideoConfig`, add the field to `GenerationConfig` at lines 161-209
- Test: `test/gemini/types/interactions/content_resolution_test.exs`, `test/gemini/types/interactions/tool_test.exs`, `test/gemini/types/interactions/generation_config_test.exs`

**Interfaces:**
- Produces:
  - `DocumentContent` gains `resolution`
  - `GoogleSearch` gains `search_types :: [String.t()]`
  - `Gemini.Types.Interactions.VideoConfig` with `task`, `from_api/1`, `to_api/1`, `tasks/0`
  - `GenerationConfig` gains `video_config`

`ImageContent` and `VideoContent` already have `resolution` and are correct — do not touch them.

- [ ] **Step 1: Write the failing tests**

Create `test/gemini/types/interactions/content_resolution_test.exs`:

```elixir
defmodule Gemini.Types.Interactions.ContentResolutionTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.{Content, DocumentContent, ImageContent, VideoContent}

  test "DocumentContent parses and emits resolution" do
    raw = %{
      "type" => "document",
      "uri" => "files/abc",
      "mime_type" => "application/pdf",
      "resolution" => "high"
    }

    assert %DocumentContent{resolution: "high"} = Content.from_api(raw)
    assert Content.to_api(Content.from_api(raw)) == raw
  end

  test "DocumentContent omits resolution when unset" do
    raw = %{"type" => "document", "uri" => "files/abc", "mime_type" => "application/pdf"}

    refute Map.has_key?(Content.to_api(Content.from_api(raw)), "resolution")
  end

  test "ImageContent resolution still round-trips, including ultra_high" do
    raw = %{"type" => "image", "uri" => "files/i", "resolution" => "ultra_high"}

    assert %ImageContent{resolution: "ultra_high"} = Content.from_api(raw)
    assert Content.to_api(Content.from_api(raw)) == raw
  end

  test "VideoContent resolution still round-trips" do
    raw = %{"type" => "video", "uri" => "files/v", "resolution" => "low"}

    assert %VideoContent{resolution: "low"} = Content.from_api(raw)
  end
end
```

Create `test/gemini/types/interactions/tool_test.exs`:

```elixir
defmodule Gemini.Types.Interactions.ToolTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.GoogleSearch

  test "serializes to just the type when search_types is unset" do
    assert GoogleSearch.to_api(%GoogleSearch{}) == %{"type" => "google_search"}
  end

  test "serializes search_types when set" do
    assert GoogleSearch.to_api(%GoogleSearch{search_types: ["web_search", "image_search"]}) ==
             %{"type" => "google_search", "search_types" => ["web_search", "image_search"]}
  end

  test "parses search_types" do
    assert %GoogleSearch{search_types: ["image_search"]} =
             GoogleSearch.from_api(%{
               "type" => "google_search",
               "search_types" => ["image_search"]
             })
  end
end
```

Create `test/gemini/types/interactions/generation_config_test.exs`:

```elixir
defmodule Gemini.Types.Interactions.GenerationConfigTest do
  use ExUnit.Case, async: true

  alias Gemini.Types.Interactions.{GenerationConfig, SpeechConfig, VideoConfig}

  test "serializes video_config" do
    config = %GenerationConfig{video_config: %VideoConfig{task: "image_to_video"}}

    assert GenerationConfig.to_api(config) == %{
             "video_config" => %{"task" => "image_to_video"}
           }
  end

  test "parses video_config" do
    assert %GenerationConfig{video_config: %VideoConfig{task: "edit"}} =
             GenerationConfig.from_api(%{"video_config" => %{"task" => "edit"}})
  end

  test "omits video_config when unset" do
    refute Map.has_key?(GenerationConfig.to_api(%GenerationConfig{}), "video_config")
  end

  test "documented tasks are exposed" do
    assert VideoConfig.tasks() == [
             "text_to_video",
             "image_to_video",
             "reference_to_video",
             "edit"
           ]
  end

  test "existing fields are unaffected" do
    config = %GenerationConfig{
      thinking_level: "high",
      speech_config: [%SpeechConfig{voice: "Kore"}]
    }

    assert GenerationConfig.to_api(config) == %{
             "thinking_level" => "high",
             "speech_config" => [%{"voice" => "Kore"}]
           }
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/gemini/types/interactions/content_resolution_test.exs test/gemini/types/interactions/tool_test.exs test/gemini/types/interactions/generation_config_test.exs`
Expected: FAIL — `key :resolution not found`, `key :search_types not found`, `VideoConfig is not available`

- [ ] **Step 3: Add resolution to DocumentContent**

In `lib/gemini/types/interactions/content.ex`, in `defmodule Gemini.Types.Interactions.DocumentContent`, add to the `typedstruct` block after the `mime_type` field:

```elixir
    field(:resolution, resolution(), enforce: false)
```

Add above the `typedstruct` block:

```elixir
  @type resolution :: :low | :medium | :high | :ultra_high | String.t()
```

Add to the `from_api(%{} = data)` map:

```elixir
      resolution: Map.get(data, "resolution")
```

Add to the `to_api/1` pipeline:

```elixir
    |> maybe_put("resolution", content.resolution)
```

- [ ] **Step 4: Add search_types to GoogleSearch**

In `lib/gemini/types/interactions/tool.ex`, replace `defmodule Gemini.Types.Interactions.GoogleSearch` entirely with:

```elixir
defmodule Gemini.Types.Interactions.GoogleSearch do
  @moduledoc """
  Built-in Google Search tool.

  `search_types` narrows what is searched. Documented values are
  `"web_search"` and `"image_search"`; image search is available on
  `gemini-3.1-flash-image`. When unset, the tool serializes to
  `%{"type" => "google_search"}` and the server picks the default.

  <https://ai.google.dev/gemini-api/docs/image-generation>
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @search_types ~w(web_search image_search)

  @derive Jason.Encoder
  typedstruct do
    field(:type, String.t(), enforce: true, default: "google_search")
    field(:search_types, [String.t()], enforce: false)
  end

  @doc """
  Documented search types: #{Enum.join(@search_types, ", ")}.
  """
  @spec search_types() :: [String.t()]
  def search_types, do: @search_types

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = tool), do: tool

  def from_api(%{} = data) do
    %__MODULE__{
      type: Map.get(data, "type") || "google_search",
      search_types: Map.get(data, "search_types")
    }
  end

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = tool) do
    %{"type" => "google_search"}
    |> maybe_put("search_types", tool.search_types)
  end
end
```

Check whether the original `GoogleSearch` had a `from_api/1` — if it did not, adding it is additive. Confirm the tool union dispatcher in `tool.ex` still routes `"google_search"` to this module.

- [ ] **Step 5: Add VideoConfig and wire it into GenerationConfig**

In `lib/gemini/types/interactions/config.ex`, insert before `defmodule Gemini.Types.Interactions.GenerationConfig`:

```elixir
defmodule Gemini.Types.Interactions.VideoConfig do
  @moduledoc """
  Video generation config for Gemini Omni.

  <https://ai.google.dev/gemini-api/docs/omni>
  """

  use TypedStruct

  import Gemini.Utils.MapHelpers, only: [maybe_put: 3]

  @tasks ~w(text_to_video image_to_video reference_to_video edit)

  @derive Jason.Encoder
  typedstruct do
    field(:task, String.t())
  end

  @doc """
  Documented tasks: #{Enum.join(@tasks, ", ")}.
  """
  @spec tasks() :: [String.t()]
  def tasks, do: @tasks

  @spec from_api(map() | nil) :: t() | nil
  def from_api(nil), do: nil
  def from_api(%__MODULE__{} = config), do: config
  def from_api(%{} = data), do: %__MODULE__{task: Map.get(data, "task")}

  @spec to_api(t() | map() | nil) :: map() | nil
  def to_api(nil), do: nil
  def to_api(%{} = map) when not is_struct(map), do: map

  def to_api(%__MODULE__{} = config) do
    %{}
    |> maybe_put("task", config.task)
  end
end
```

In `GenerationConfig`, add to the alias list `VideoConfig`, add the field after `tool_choice`:

```elixir
    field(:video_config, VideoConfig.t())
```

Add to `from_api/1`:

```elixir
      video_config: VideoConfig.from_api(Map.get(data, "video_config")),
```

Add to `to_api/1`:

```elixir
    |> maybe_put("video_config", VideoConfig.to_api(config.video_config))
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/gemini/types/interactions/`
Expected: PASS

- [ ] **Step 7: Format, compile clean, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/gemini/types/interactions/content.ex lib/gemini/types/interactions/tool.ex lib/gemini/types/interactions/config.ex test/gemini/types/interactions/
git commit -m "feat(interactions): document resolution, search_types, video_config"
```

---

### Task 7: Request body — new fields and typed response_format

**Files:**
- Modify: `lib/gemini/apis/interactions.ex:320-346` (`build_create_body/3`)
- Test: `test/gemini/apis/interactions_body_test.exs`

**Interfaces:**
- Consumes: `ResponseFormat.to_api/1` (Task 5).
- Produces: `create/2` accepts `:safety_settings`, `:service_tier`, `:environment`, `:labels`, `:webhook_config`, `:user_metadata`, and a `ResponseFormat` struct or list for `:response_format`.

`build_create_body/3` is private. Test it through the public `create/2` by asserting on what the Bypass server receives, matching the pattern already used in `test/gemini/apis/interactions_test.exs`.

- [ ] **Step 1: Write the failing test**

Create `test/gemini/apis/interactions_body_test.exs`:

```elixir
defmodule Gemini.APIs.InteractionsBodyTest do
  use ExUnit.Case, async: false

  alias Gemini.APIs.Interactions
  alias Gemini.Types.Interactions.ResponseFormat
  alias Plug.Conn

  setup do
    bypass = Gemini.TestHTTPServer.open()

    :meck.new(Gemini.Auth, [:passthrough])
    on_exit(fn -> :meck.unload() end)

    %{bypass: bypass}
  end

  # Captures the request body the client actually sent, so assertions are on
  # the wire format rather than on an internal function.
  defp capture_body(bypass, opts) do
    parent = self()

    Bypass.expect_once(bypass, "POST", "/v1beta/interactions", fn conn ->
      {:ok, raw, conn} = Conn.read_body(conn)
      send(parent, {:body, Jason.decode!(raw)})

      conn
      |> Conn.put_resp_content_type("application/json")
      |> Conn.resp(200, Jason.encode!(%{"id" => "int_1", "status" => "completed"}))
    end)

    {:ok, _} = Interactions.create("hello", opts)

    receive do
      {:body, body} -> body
    after
      1_000 -> flunk("no request body captured")
    end
  end

  test "emits the new top-level request fields", %{bypass: bypass} do
    body =
      capture_body(bypass,
        model: "gemini-3.6-flash",
        safety_settings: [%{"category" => "HARM_CATEGORY_HARASSMENT", "threshold" => "BLOCK_NONE"}],
        service_tier: "flex",
        environment: "default",
        labels: %{"team" => "search"},
        webhook_config: %{"url" => "https://example.com/hook"},
        user_metadata: %{"user_id" => "u1"}
      )

    assert body["service_tier"] == "flex"
    assert body["environment"] == "default"
    assert body["labels"] == %{"team" => "search"}
    assert body["webhook_config"] == %{"url" => "https://example.com/hook"}
    assert body["user_metadata"] == %{"user_id" => "u1"}
    assert [%{"category" => "HARM_CATEGORY_HARASSMENT"}] = body["safety_settings"]
  end

  test "omits fields that were not provided", %{bypass: bypass} do
    body = capture_body(bypass, model: "gemini-3.6-flash")

    refute Map.has_key?(body, "service_tier")
    refute Map.has_key?(body, "labels")
    refute Map.has_key?(body, "safety_settings")
  end

  test "serializes a ResponseFormat struct", %{bypass: bypass} do
    body =
      capture_body(bypass,
        model: "gemini-3.1-flash-image",
        response_format: %ResponseFormat.Image{aspect_ratio: "16:9", image_size: "2K"}
      )

    assert body["response_format"] == %{
             "type" => "image",
             "aspect_ratio" => "16:9",
             "image_size" => "2K"
           }
  end

  test "still accepts a raw response_format map", %{bypass: bypass} do
    body =
      capture_body(bypass,
        model: "gemini-3.6-flash",
        response_format: %{"type" => "text", "mime_type" => "application/json"}
      )

    assert body["response_format"] == %{
             "type" => "text",
             "mime_type" => "application/json"
           }
  end

  test "accepts a list of response formats", %{bypass: bypass} do
    body =
      capture_body(bypass,
        model: "gemini-3.6-flash",
        response_format: [%ResponseFormat.Text{}, %ResponseFormat.Audio{}]
      )

    assert body["response_format"] == [%{"type" => "text"}, %{"type" => "audio"}]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/gemini/apis/interactions_body_test.exs`
Expected: FAIL — `service_tier` missing from the body; `response_format` serialized as a struct rather than the API shape

- [ ] **Step 3: Update build_create_body/3**

In `lib/gemini/apis/interactions.ex`, replace the `body` pipeline inside `build_create_body/3` (lines 327-341) with:

```elixir
    body =
      %{}
      |> Map.put("input", Input.to_api(input))
      |> maybe_put("model", model)
      |> maybe_put("agent", agent)
      |> maybe_put("background", Keyword.get(opts, :background))
      |> maybe_put("environment", Keyword.get(opts, :environment))
      |> maybe_put("generation_config", generation_config)
      |> maybe_put("agent_config", agent_config)
      |> maybe_put("labels", Keyword.get(opts, :labels))
      |> maybe_put("previous_interaction_id", Keyword.get(opts, :previous_interaction_id))
      |> maybe_put("response_format", ResponseFormat.to_api(Keyword.get(opts, :response_format)))
      |> maybe_put("response_mime_type", Keyword.get(opts, :response_mime_type))
      |> maybe_put("response_modalities", Keyword.get(opts, :response_modalities))
      |> maybe_put("safety_settings", Keyword.get(opts, :safety_settings))
      |> maybe_put("service_tier", Keyword.get(opts, :service_tier))
      |> maybe_put("store", Keyword.get(opts, :store))
      |> maybe_put("system_instruction", Keyword.get(opts, :system_instruction))
      |> maybe_put("tools", tools)
      |> maybe_put("user_metadata", Keyword.get(opts, :user_metadata))
      |> maybe_put("webhook_config", Keyword.get(opts, :webhook_config))
```

Add `ResponseFormat` to the module's alias list.

- [ ] **Step 4: Document the new options**

Update the `@doc` on `create/2` (lines 39-52) to list every accepted option. Add this block after the existing "## Streaming" section:

```elixir
  ## Options

  - `:model` or `:agent` — one is required
  - `:system_instruction` — string
  - `:tools` — list of tool structs or maps
  - `:generation_config` — `Gemini.Types.Interactions.GenerationConfig` or map
  - `:agent_config` — map, when using `:agent`
  - `:response_format` — a `Gemini.Types.Interactions.ResponseFormat` variant,
    a raw map, or a list of either
  - `:previous_interaction_id` — string, to continue a stored interaction
  - `:store` — boolean; when `false`, thought signatures must be resent
  - `:background` — boolean, to run asynchronously
  - `:stream` — boolean
  - `:safety_settings` — list of safety setting maps
  - `:service_tier` — string
  - `:environment` — string or environment config map
  - `:labels` — map of string keys to string values
  - `:webhook_config` — map
  - `:user_metadata` — map
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/gemini/apis/`
Expected: PASS, including the pre-existing `interactions_test.exs`

- [ ] **Step 6: Format, compile clean, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/gemini/apis/interactions.ex test/gemini/apis/interactions_body_test.exs
git commit -m "feat(interactions): emit remaining request fields and typed response_format"
```

---

### Task 8: Gemini.Interactions.Text

**Files:**
- Create: `lib/gemini/interactions/text.ex`
- Test: `test/gemini/interactions/text_test.exs`

**Interfaces:**
- Consumes: `Gemini.APIs.Interactions.create/2`; `Interaction.output_text/1` (Task 2); `GenerationConfig` (Task 6).
- Produces:
  - `Gemini.Interactions.Text.generate(input, opts) :: {:ok, String.t()} | {:error, Gemini.Error.t() | term()}`
  - `Gemini.Interactions.Text.generate_interaction(input, opts) :: {:ok, Interaction.t()} | {:error, term()}`

`generate/2` returns just the text. `generate_interaction/2` returns the whole interaction, for callers that need `steps`, signatures, or usage. Both build the same request. This split is repeated in the other capability modules.

- [ ] **Step 1: Write the failing test**

Create `test/gemini/interactions/text_test.exs`:

```elixir
defmodule Gemini.Interactions.TextTest do
  use ExUnit.Case, async: false

  alias Gemini.Interactions.Text
  alias Gemini.Types.Interactions.Interaction
  alias Plug.Conn

  setup do
    bypass = Gemini.TestHTTPServer.open()
    :meck.new(Gemini.Auth, [:passthrough])
    on_exit(fn -> :meck.unload() end)
    %{bypass: bypass}
  end

  defp respond(bypass, response) do
    parent = self()

    Bypass.expect_once(bypass, "POST", "/v1beta/interactions", fn conn ->
      {:ok, raw, conn} = Conn.read_body(conn)
      send(parent, {:body, Jason.decode!(raw)})

      conn
      |> Conn.put_resp_content_type("application/json")
      |> Conn.resp(200, Jason.encode!(response))
    end)
  end

  defp sent_body do
    receive do
      {:body, body} -> body
    after
      1_000 -> flunk("no request body captured")
    end
  end

  test "generate/2 returns the output text", %{bypass: bypass} do
    respond(bypass, %{
      "id" => "int_1",
      "status" => "completed",
      "steps" => [
        %{"type" => "model_output", "content" => [%{"type" => "text", "text" => "Hi there"}]}
      ]
    })

    assert {:ok, "Hi there"} = Text.generate("Say hi", model: "gemini-3.6-flash")
  end

  test "generate/2 maps thinking_level into generation_config", %{bypass: bypass} do
    respond(bypass, %{"id" => "i", "status" => "completed", "output_text" => "ok"})

    {:ok, _} = Text.generate("Think", model: "gemini-3.6-flash", thinking_level: "high")

    assert sent_body()["generation_config"]["thinking_level"] == "high"
  end

  test "generate/2 maps thinking_summaries and temperature", %{bypass: bypass} do
    respond(bypass, %{"id" => "i", "status" => "completed", "output_text" => "ok"})

    {:ok, _} =
      Text.generate("Think",
        model: "gemini-3.6-flash",
        thinking_summaries: "auto",
        temperature: 0.2
      )

    config = sent_body()["generation_config"]
    assert config["thinking_summaries"] == "auto"
    assert config["temperature"] == 0.2
  end

  test "generate/2 passes system_instruction through at the top level", %{bypass: bypass} do
    respond(bypass, %{"id" => "i", "status" => "completed", "output_text" => "ok"})

    {:ok, _} =
      Text.generate("Hi", model: "gemini-3.6-flash", system_instruction: "Be terse")

    assert sent_body()["system_instruction"] == "Be terse"
    refute Map.has_key?(sent_body(), "generation_config")
  end

  test "generate/2 returns :not_found as an error when there is no text", %{bypass: bypass} do
    respond(bypass, %{"id" => "i", "status" => "completed"})

    assert {:error, :not_found} = Text.generate("Hi", model: "gemini-3.6-flash")
  end

  test "generate_interaction/2 returns the whole interaction", %{bypass: bypass} do
    respond(bypass, %{
      "id" => "int_9",
      "status" => "completed",
      "steps" => [%{"type" => "thought", "signature" => "sig_a"}]
    })

    assert {:ok, %Interaction{id: "int_9"} = interaction} =
             Text.generate_interaction("Hi", model: "gemini-3.6-flash")

    assert Interaction.thought_signatures(interaction) == ["sig_a"]
  end

  test "generate/2 defaults to no model, letting create/2 validate", %{bypass: bypass} do
    respond(bypass, %{"id" => "i", "status" => "completed", "output_text" => "ok"})

    assert {:ok, "ok"} = Text.generate("Hi", model: "gemini-3.6-flash")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/gemini/interactions/text_test.exs`
Expected: FAIL — `Gemini.Interactions.Text is not available`

- [ ] **Step 3: Write the implementation**

Create `lib/gemini/interactions/text.ex`:

```elixir
defmodule Gemini.Interactions.Text do
  @moduledoc """
  Text generation through the Interactions API.

  <https://ai.google.dev/gemini-api/docs/text-generation>

  ## Examples

      {:ok, text} =
        Gemini.Interactions.Text.generate("Explain how AI works in a few words",
          model: "gemini-3.6-flash"
        )

  Thinking is configured with `:thinking_level` and `:thinking_summaries`:

      {:ok, text} =
        Gemini.Interactions.Text.generate("Solve this puzzle",
          model: "gemini-3.6-flash",
          thinking_level: "high",
          thinking_summaries: "auto"
        )
  """

  alias Gemini.APIs.Interactions
  alias Gemini.Types.Interactions.{GenerationConfig, Interaction}

  @generation_config_keys [
    :image_config,
    :max_output_tokens,
    :seed,
    :speech_config,
    :stop_sequences,
    :temperature,
    :thinking_level,
    :thinking_summaries,
    :tool_choice,
    :top_p,
    :video_config
  ]

  @doc """
  Generate text and return it.

  Accepts every option `Gemini.APIs.Interactions.create/2` accepts. Options
  belonging to the generation config — `:thinking_level`,
  `:thinking_summaries`, `:temperature`, `:top_p`, `:max_output_tokens`,
  `:seed`, `:stop_sequences`, `:tool_choice` — may be passed at the top level
  and are folded into `generation_config` for you. An explicit
  `:generation_config` takes precedence and is passed through untouched.

  Returns `{:error, :not_found}` when the response carries no text.
  """
  @spec generate(term(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate(input, opts \\ []) do
    with {:ok, interaction} <- generate_interaction(input, opts) do
      Interaction.output_text(interaction)
    end
  end

  @doc """
  Generate text and return the whole `Gemini.Types.Interactions.Interaction`.

  Use this when you need `steps`, thought signatures, or usage metadata.
  """
  @spec generate_interaction(term(), keyword()) :: {:ok, Interaction.t()} | {:error, term()}
  def generate_interaction(input, opts \\ []) do
    Interactions.create(input, build_opts(opts))
  end

  @doc false
  @spec build_opts(keyword()) :: keyword()
  def build_opts(opts) do
    {config_opts, rest} = Keyword.split(opts, @generation_config_keys)

    case {Keyword.get(rest, :generation_config), config_opts} do
      {nil, []} -> rest
      {nil, _} -> Keyword.put(rest, :generation_config, struct(GenerationConfig, config_opts))
      {_existing, _} -> rest
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/gemini/interactions/text_test.exs`
Expected: PASS, 7 tests

- [ ] **Step 5: Format, compile clean, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/gemini/interactions/text.ex test/gemini/interactions/text_test.exs
git commit -m "feat(interactions): add Gemini.Interactions.Text"
```

---

### Task 9: Gemini.Interactions.Image

**Files:**
- Create: `lib/gemini/interactions/image.ex`
- Test: `test/gemini/interactions/image_test.exs`

**Interfaces:**
- Consumes: `Text.build_opts/1` (Task 8) for generation-config folding; `ResponseFormat.Image` (Task 5); `Interaction.output_image/1` (Task 2).
- Produces:
  - `Gemini.Interactions.Image.generate(prompt, opts) :: {:ok, ImageContent.t()} | {:error, term()}`
  - `Gemini.Interactions.Image.edit(prompt, image, opts) :: {:ok, ImageContent.t()} | {:error, term()}`
  - `Gemini.Interactions.Image.generate_interaction(prompt, opts) :: {:ok, Interaction.t()} | {:error, term()}`

`edit/3` accepts either an `ImageContent` struct, a `{:uri, uri, mime_type}` tuple, or a `{:data, base64, mime_type}` tuple, and prepends it to the input alongside the prompt.

- [ ] **Step 1: Write the failing test**

Create `test/gemini/interactions/image_test.exs`:

```elixir
defmodule Gemini.Interactions.ImageTest do
  use ExUnit.Case, async: false

  alias Gemini.Interactions.Image
  alias Gemini.Types.Interactions.ImageContent
  alias Plug.Conn

  setup do
    bypass = Gemini.TestHTTPServer.open()
    :meck.new(Gemini.Auth, [:passthrough])
    on_exit(fn -> :meck.unload() end)
    %{bypass: bypass}
  end

  defp image_response do
    %{
      "id" => "int_img",
      "status" => "completed",
      "steps" => [
        %{
          "type" => "model_output",
          "content" => [%{"type" => "image", "data" => "AAAA", "mime_type" => "image/png"}]
        }
      ]
    }
  end

  defp respond(bypass, response) do
    parent = self()

    Bypass.expect_once(bypass, "POST", "/v1beta/interactions", fn conn ->
      {:ok, raw, conn} = Conn.read_body(conn)
      send(parent, {:body, Jason.decode!(raw)})

      conn
      |> Conn.put_resp_content_type("application/json")
      |> Conn.resp(200, Jason.encode!(response))
    end)
  end

  defp sent_body do
    receive do
      {:body, body} -> body
    after
      1_000 -> flunk("no request body captured")
    end
  end

  test "generate/2 returns the image content block", %{bypass: bypass} do
    respond(bypass, image_response())

    assert {:ok, %ImageContent{data: "AAAA", mime_type: "image/png"}} =
             Image.generate("a nano banana", model: "gemini-3.1-flash-image")
  end

  test "generate/2 builds an image response_format", %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} =
      Image.generate("a nano banana",
        model: "gemini-3.1-flash-image",
        aspect_ratio: "16:9",
        image_size: "2K",
        mime_type: "image/png"
      )

    assert sent_body()["response_format"] == %{
             "type" => "image",
             "aspect_ratio" => "16:9",
             "image_size" => "2K",
             "mime_type" => "image/png"
           }
  end

  test "generate/2 omits response_format keys that were not given", %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} = Image.generate("a nano banana", model: "gemini-3.1-flash-image")

    assert sent_body()["response_format"] == %{"type" => "image"}
  end

  test "generate/2 folds thinking_level into generation_config", %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} =
      Image.generate("a nano banana", model: "gemini-3-pro-image", thinking_level: "high")

    assert sent_body()["generation_config"]["thinking_level"] == "high"
  end

  test "edit/3 prepends a uri image to the input", %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} =
      Image.edit("add a hat", {:uri, "files/abc", "image/jpeg"},
        model: "gemini-3.1-flash-image"
      )

    assert [
             %{"type" => "image", "uri" => "files/abc", "mime_type" => "image/jpeg"},
             %{"type" => "text", "text" => "add a hat"}
           ] = sent_body()["input"]
  end

  test "edit/3 prepends inline base64 data", %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} =
      Image.edit("add a hat", {:data, "QUJD", "image/png"}, model: "gemini-3.1-flash-image")

    assert [%{"type" => "image", "data" => "QUJD", "mime_type" => "image/png"} | _] =
             sent_body()["input"]
  end

  test "edit/3 accepts an ImageContent struct", %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} =
      Image.edit("add a hat", %ImageContent{uri: "files/x", mime_type: "image/png"},
        model: "gemini-3.1-flash-image"
      )

    assert [%{"type" => "image", "uri" => "files/x"} | _] = sent_body()["input"]
  end

  test "edit/3 continues a prior interaction when given previous_interaction_id",
       %{bypass: bypass} do
    respond(bypass, image_response())

    {:ok, _} =
      Image.edit("make it blue", nil,
        model: "gemini-3.1-flash-image",
        previous_interaction_id: "int_prev"
      )

    body = sent_body()
    assert body["previous_interaction_id"] == "int_prev"
    assert [%{"type" => "text", "text" => "make it blue"}] = body["input"]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/gemini/interactions/image_test.exs`
Expected: FAIL — `Gemini.Interactions.Image is not available`

- [ ] **Step 3: Write the implementation**

Create `lib/gemini/interactions/image.ex`:

```elixir
defmodule Gemini.Interactions.Image do
  @moduledoc """
  Image generation and editing through the Interactions API.

  <https://ai.google.dev/gemini-api/docs/image-generation>

  ## Examples

      {:ok, image} =
        Gemini.Interactions.Image.generate("a nano banana in a fancy restaurant",
          model: "gemini-3.1-flash-image",
          aspect_ratio: "16:9",
          image_size: "2K"
        )

      File.write!("out.png", Base.decode64!(image.data))

  Editing continues from an uploaded image:

      {:ok, edited} =
        Gemini.Interactions.Image.edit("give it a chef's hat",
          {:uri, "files/abc123", "image/jpeg"},
          model: "gemini-3.1-flash-image"
        )

  Or from a previous interaction, which needs no image argument:

      {:ok, edited} =
        Gemini.Interactions.Image.edit("now make it blue", nil,
          model: "gemini-3.1-flash-image",
          previous_interaction_id: interaction.id
        )
  """

  alias Gemini.APIs.Interactions
  alias Gemini.Interactions.Text
  alias Gemini.Types.Interactions.{ImageContent, Interaction, ResponseFormat, TextContent}

  @format_keys [:aspect_ratio, :image_size, :mime_type]

  @type image_input ::
          ImageContent.t()
          | {:uri, String.t(), String.t()}
          | {:data, String.t(), String.t()}
          | nil

  @doc """
  Generate an image and return its content block.

  Options `:aspect_ratio`, `:image_size`, and `:mime_type` build the
  `response_format`. See `Gemini.Types.Interactions.ResponseFormat.Image` for
  documented values. All other options go to
  `Gemini.APIs.Interactions.create/2`, with generation-config options folded in
  as they are for `Gemini.Interactions.Text.generate/2`.
  """
  @spec generate(String.t(), keyword()) :: {:ok, ImageContent.t()} | {:error, term()}
  def generate(prompt, opts \\ []) when is_binary(prompt) do
    with {:ok, interaction} <- generate_interaction(prompt, opts) do
      Interaction.output_image(interaction)
    end
  end

  @doc """
  Generate an image and return the whole interaction.

  Use this for interleaved text and image output, for the thought summary, or
  to capture the interaction id for a follow-up `edit/3`.
  """
  @spec generate_interaction(String.t(), keyword()) :: {:ok, Interaction.t()} | {:error, term()}
  def generate_interaction(prompt, opts \\ []) when is_binary(prompt) do
    Interactions.create(%TextContent{text: prompt}, build_opts(opts))
  end

  @doc """
  Edit an image.

  Pass the source image as the second argument, or pass `nil` together with
  `previous_interaction_id:` to continue editing the result of an earlier
  interaction.
  """
  @spec edit(String.t(), image_input(), keyword()) ::
          {:ok, ImageContent.t()} | {:error, term()}
  def edit(prompt, image, opts \\ []) when is_binary(prompt) do
    input = build_input(prompt, image)

    with {:ok, interaction} <- Interactions.create(input, build_opts(opts)) do
      Interaction.output_image(interaction)
    end
  end

  defp build_input(prompt, nil), do: [%TextContent{text: prompt}]

  defp build_input(prompt, image),
    do: [to_image_content(image), %TextContent{text: prompt}]

  defp to_image_content(%ImageContent{} = image), do: image

  defp to_image_content({:uri, uri, mime_type}),
    do: %ImageContent{uri: uri, mime_type: mime_type}

  defp to_image_content({:data, data, mime_type}),
    do: %ImageContent{data: data, mime_type: mime_type}

  defp build_opts(opts) do
    {format_opts, rest} = Keyword.split(opts, @format_keys)

    rest = Text.build_opts(rest)

    case Keyword.get(rest, :response_format) do
      nil -> Keyword.put(rest, :response_format, struct(ResponseFormat.Image, format_opts))
      _existing -> rest
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/gemini/interactions/image_test.exs`
Expected: PASS, 8 tests

- [ ] **Step 5: Format, compile clean, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/gemini/interactions/image.ex test/gemini/interactions/image_test.exs
git commit -m "feat(interactions): add Gemini.Interactions.Image"
```

---

### Task 10: Gemini.Interactions.Speech

**Files:**
- Create: `lib/gemini/interactions/speech.ex`
- Test: `test/gemini/interactions/speech_test.exs`

**Interfaces:**
- Consumes: `ResponseFormat.Audio` (Task 5); `SpeechConfig` (existing, `config.ex:107`); `Interaction.output_audio/1` (Task 2).
- Produces:
  - `Gemini.Interactions.Speech.generate(text, opts) :: {:ok, binary()} | {:error, term()}` — returns raw decoded PCM
  - `Gemini.Interactions.Speech.generate_wav(text, opts) :: {:ok, binary()} | {:error, term()}` — PCM wrapped in a WAV container
  - `Gemini.Interactions.Speech.voices() :: [String.t()]`
  - `Gemini.Interactions.Speech.wav_header(byte_size :: non_neg_integer()) :: binary()`

Output audio is 24 kHz, mono, 16-bit signed little-endian PCM.

- [ ] **Step 1: Write the failing test**

Create `test/gemini/interactions/speech_test.exs`:

```elixir
defmodule Gemini.Interactions.SpeechTest do
  use ExUnit.Case, async: false

  alias Gemini.Interactions.Speech
  alias Plug.Conn

  setup do
    bypass = Gemini.TestHTTPServer.open()
    :meck.new(Gemini.Auth, [:passthrough])
    on_exit(fn -> :meck.unload() end)
    %{bypass: bypass}
  end

  defp audio_response(data) do
    %{
      "id" => "int_tts",
      "status" => "completed",
      "output_audio" => %{"type" => "audio", "data" => data, "mime_type" => "audio/pcm"}
    }
  end

  defp respond(bypass, response) do
    parent = self()

    Bypass.expect_once(bypass, "POST", "/v1beta/interactions", fn conn ->
      {:ok, raw, conn} = Conn.read_body(conn)
      send(parent, {:body, Jason.decode!(raw)})

      conn
      |> Conn.put_resp_content_type("application/json")
      |> Conn.resp(200, Jason.encode!(response))
    end)
  end

  defp sent_body do
    receive do
      {:body, body} -> body
    after
      1_000 -> flunk("no request body captured")
    end
  end

  test "generate/2 returns decoded PCM", %{bypass: bypass} do
    respond(bypass, audio_response(Base.encode64("RAWPCM")))

    assert {:ok, "RAWPCM"} =
             Speech.generate("Say hi", model: "gemini-3.1-flash-tts-preview", voice: "Kore")
  end

  test "generate/2 sends an audio response_format", %{bypass: bypass} do
    respond(bypass, audio_response(Base.encode64("x")))

    {:ok, _} = Speech.generate("Say hi", model: "gemini-3.1-flash-tts-preview", voice: "Kore")

    assert sent_body()["response_format"] == %{"type" => "audio"}
  end

  test "generate/2 builds a single-speaker speech_config", %{bypass: bypass} do
    respond(bypass, audio_response(Base.encode64("x")))

    {:ok, _} = Speech.generate("Say hi", model: "gemini-3.1-flash-tts-preview", voice: "Kore")

    assert sent_body()["generation_config"]["speech_config"] == [%{"voice" => "Kore"}]
  end

  test "generate/2 builds a multi-speaker speech_config", %{bypass: bypass} do
    respond(bypass, audio_response(Base.encode64("x")))

    {:ok, _} =
      Speech.generate("Joe: Hi\nJane: Hello",
        model: "gemini-3.1-flash-tts-preview",
        speakers: [{"Joe", "Kore"}, {"Jane", "Puck"}]
      )

    assert sent_body()["generation_config"]["speech_config"] == [
             %{"speaker" => "Joe", "voice" => "Kore"},
             %{"speaker" => "Jane", "voice" => "Puck"}
           ]
  end

  test "generate/2 includes language when given", %{bypass: bypass} do
    respond(bypass, audio_response(Base.encode64("x")))

    {:ok, _} =
      Speech.generate("Hola",
        model: "gemini-3.1-flash-tts-preview",
        voice: "Kore",
        language: "es"
      )

    assert sent_body()["generation_config"]["speech_config"] == [
             %{"voice" => "Kore", "language" => "es"}
           ]
  end

  test "generate_wav/2 prefixes a 44-byte RIFF header", %{bypass: bypass} do
    pcm = String.duplicate("ab", 10)
    respond(bypass, audio_response(Base.encode64(pcm)))

    {:ok, wav} =
      Speech.generate_wav("Say hi", model: "gemini-3.1-flash-tts-preview", voice: "Kore")

    assert byte_size(wav) == 44 + byte_size(pcm)
    assert <<"RIFF", _size::little-32, "WAVE", _rest::binary>> = wav
  end

  test "wav_header/1 encodes 24kHz mono 16-bit" do
    header = Speech.wav_header(100)

    assert <<
             "RIFF",
             riff_size::little-32,
             "WAVE",
             "fmt ",
             16::little-32,
             1::little-16,
             1::little-16,
             24_000::little-32,
             48_000::little-32,
             2::little-16,
             16::little-16,
             "data",
             100::little-32
           >> = header

    assert riff_size == 36 + 100
  end

  test "voices/0 lists the 30 documented voices" do
    voices = Speech.voices()

    assert length(voices) == 30
    assert "Kore" in voices
    assert "Zephyr" in voices
    assert "Sulafat" in voices
  end

  test "generate/2 errors when the response carries no audio", %{bypass: bypass} do
    respond(bypass, %{"id" => "i", "status" => "completed"})

    assert {:error, :not_found} =
             Speech.generate("Say hi", model: "gemini-3.1-flash-tts-preview", voice: "Kore")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/gemini/interactions/speech_test.exs`
Expected: FAIL — `Gemini.Interactions.Speech is not available`

- [ ] **Step 3: Write the implementation**

Create `lib/gemini/interactions/speech.ex`:

```elixir
defmodule Gemini.Interactions.Speech do
  @moduledoc """
  Text-to-speech through the Interactions API.

  <https://ai.google.dev/gemini-api/docs/speech-generation>

  Output is 24 kHz, mono, 16-bit signed little-endian PCM. `generate/2` returns
  that PCM decoded from base64; `generate_wav/2` wraps it in a WAV container so
  it can be written straight to a playable file.

  ## Examples

      {:ok, wav} =
        Gemini.Interactions.Speech.generate_wav("Say cheerfully: have a great day!",
          model: "gemini-3.1-flash-tts-preview",
          voice: "Kore"
        )

      File.write!("out.wav", wav)

  Multi-speaker:

      {:ok, wav} =
        Gemini.Interactions.Speech.generate_wav(transcript,
          model: "gemini-3.1-flash-tts-preview",
          speakers: [{"Joe", "Kore"}, {"Jane", "Puck"}]
        )
  """

  alias Gemini.APIs.Interactions
  alias Gemini.Types.Interactions.{GenerationConfig, Interaction, ResponseFormat, SpeechConfig}

  @sample_rate 24_000
  @channels 1
  @bits_per_sample 16

  @voices ~w(
    Zephyr Puck Charon Kore Fenrir Leda Orus Aoede Callirrhoe Autonoe
    Enceladus Iapetus Umbriel Algieba Despina Erinome Algenib Rasalgethi
    Laomedeia Achernar Alnilam Schedar Gacrux Pulcherrima Achird
    Zubenelgenubi Vindemiatrix Sadachbia Sadaltager Sulafat
  )

  @doc """
  The 30 documented voice names.
  """
  @spec voices() :: [String.t()]
  def voices, do: @voices

  @doc """
  Synthesize speech and return raw PCM.

  Pass `:voice` for a single speaker, or `:speakers` as a list of
  `{speaker_name, voice_name}` tuples for multi-speaker. `:language` is an
  optional BCP-47 code applied to every speaker.
  """
  @spec generate(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate(text, opts \\ []) when is_binary(text) do
    with {:ok, interaction} <- Interactions.create(text, build_opts(opts)),
         {:ok, audio} <- Interaction.output_audio(interaction) do
      decode_audio(audio.data)
    end
  end

  @doc """
  Synthesize speech and return a complete WAV file.
  """
  @spec generate_wav(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def generate_wav(text, opts \\ []) when is_binary(text) do
    with {:ok, pcm} <- generate(text, opts) do
      {:ok, wav_header(byte_size(pcm)) <> pcm}
    end
  end

  @doc """
  A 44-byte canonical WAV header for `byte_size` bytes of 24 kHz mono 16-bit PCM.
  """
  @spec wav_header(non_neg_integer()) :: binary()
  def wav_header(byte_size) when is_integer(byte_size) and byte_size >= 0 do
    block_align = div(@channels * @bits_per_sample, 8)
    byte_rate = @sample_rate * block_align

    <<
      "RIFF",
      36 + byte_size::little-32,
      "WAVE",
      "fmt ",
      16::little-32,
      1::little-16,
      @channels::little-16,
      @sample_rate::little-32,
      byte_rate::little-32,
      block_align::little-16,
      @bits_per_sample::little-16,
      "data",
      byte_size::little-32
    >>
  end

  defp decode_audio(nil), do: {:error, :not_found}

  defp decode_audio(data) when is_binary(data) do
    case Base.decode64(data) do
      {:ok, pcm} -> {:ok, pcm}
      :error -> {:error, {:invalid_audio_encoding, data}}
    end
  end

  defp build_opts(opts) do
    {speech_opts, rest} = Keyword.split(opts, [:voice, :speakers, :language])

    rest
    |> Keyword.put_new(:response_format, %ResponseFormat.Audio{})
    |> put_speech_config(speech_opts)
  end

  defp put_speech_config(opts, speech_opts) do
    case {Keyword.get(opts, :generation_config), speech_config(speech_opts)} do
      {nil, nil} ->
        opts

      {nil, config} ->
        Keyword.put(opts, :generation_config, %GenerationConfig{speech_config: config})

      {_existing, _} ->
        opts
    end
  end

  defp speech_config(opts) do
    language = Keyword.get(opts, :language)

    cond do
      speakers = Keyword.get(opts, :speakers) ->
        Enum.map(speakers, fn {speaker, voice} ->
          %SpeechConfig{speaker: speaker, voice: voice, language: language}
        end)

      voice = Keyword.get(opts, :voice) ->
        [%SpeechConfig{voice: voice, language: language}]

      true ->
        nil
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/gemini/interactions/speech_test.exs`
Expected: PASS, 9 tests

- [ ] **Step 5: Format, compile clean, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/gemini/interactions/speech.ex test/gemini/interactions/speech_test.exs
git commit -m "feat(interactions): add Gemini.Interactions.Speech with WAV output"
```

---

### Task 11: Gemini.Interactions.Video and Gemini.Interactions.Understanding

**Files:**
- Create: `lib/gemini/interactions/video.ex`
- Create: `lib/gemini/interactions/understanding.ex`
- Test: `test/gemini/interactions/video_test.exs`
- Test: `test/gemini/interactions/understanding_test.exs`

**Interfaces:**
- Consumes: `ResponseFormat.Video` (Task 5); `VideoConfig` (Task 6); `Interaction.output_video/1` and `output_text/1` (Task 2); `Text.build_opts/1` (Task 8).
- Produces:
  - `Gemini.Interactions.Video.generate(prompt, opts) :: {:ok, VideoContent.t()} | {:error, term()}`
  - `Gemini.Interactions.Understanding.analyze(prompt, media, opts) :: {:ok, String.t()} | {:error, term()}`
  - `Gemini.Interactions.Understanding.analyze_interaction(prompt, media, opts) :: {:ok, Interaction.t()} | {:error, term()}`
  - `Gemini.Interactions.Understanding.describe_image/3`, `.analyze_video/3`, `.transcribe_audio/3`, `.analyze_document/3`

`media` is a list of `{kind, source, mime_type}` tuples or content structs, where `kind` is `:image | :video | :audio | :document` and `source` is `{:uri, uri}` or `{:data, base64}`. A bare URL string is treated as a URI, which is how YouTube links are passed.

- [ ] **Step 1: Write the failing tests**

Create `test/gemini/interactions/video_test.exs`:

```elixir
defmodule Gemini.Interactions.VideoTest do
  use ExUnit.Case, async: false

  alias Gemini.Interactions.Video
  alias Gemini.Types.Interactions.VideoContent
  alias Plug.Conn

  setup do
    bypass = Gemini.TestHTTPServer.open()
    :meck.new(Gemini.Auth, [:passthrough])
    on_exit(fn -> :meck.unload() end)
    %{bypass: bypass}
  end

  defp video_response do
    %{
      "id" => "int_vid",
      "status" => "completed",
      "steps" => [
        %{
          "type" => "model_output",
          "content" => [
            %{"type" => "video", "uri" => "https://example.com/v.mp4", "mime_type" => "video/mp4"}
          ]
        }
      ]
    }
  end

  defp respond(bypass, response) do
    parent = self()

    Bypass.expect_once(bypass, "POST", "/v1beta/interactions", fn conn ->
      {:ok, raw, conn} = Conn.read_body(conn)
      send(parent, {:body, Jason.decode!(raw)})

      conn
      |> Conn.put_resp_content_type("application/json")
      |> Conn.resp(200, Jason.encode!(response))
    end)
  end

  defp sent_body do
    receive do
      {:body, body} -> body
    after
      1_000 -> flunk("no request body captured")
    end
  end

  test "generate/2 returns the video content block", %{bypass: bypass} do
    respond(bypass, video_response())

    assert {:ok, %VideoContent{uri: "https://example.com/v.mp4"}} =
             Video.generate("a cat surfing", model: "gemini-omni-flash")
  end

  test "generate/2 builds a video response_format with aspect_ratio and delivery",
       %{bypass: bypass} do
    respond(bypass, video_response())

    {:ok, _} =
      Video.generate("a cat surfing",
        model: "gemini-omni-flash",
        aspect_ratio: "9:16",
        delivery: "uri"
      )

    assert sent_body()["response_format"] == %{
             "type" => "video",
             "aspect_ratio" => "9:16",
             "delivery" => "uri"
           }
  end

  test "generate/2 maps task into generation_config.video_config", %{bypass: bypass} do
    respond(bypass, video_response())

    {:ok, _} = Video.generate("animate this", model: "gemini-omni-flash", task: "image_to_video")

    assert sent_body()["generation_config"]["video_config"] == %{"task" => "image_to_video"}
  end

  test "generate/2 passes previous_interaction_id for stateful editing", %{bypass: bypass} do
    respond(bypass, video_response())

    {:ok, _} =
      Video.generate("make it night",
        model: "gemini-omni-flash",
        previous_interaction_id: "int_prev"
      )

    assert sent_body()["previous_interaction_id"] == "int_prev"
  end
end
```

Create `test/gemini/interactions/understanding_test.exs`:

```elixir
defmodule Gemini.Interactions.UnderstandingTest do
  use ExUnit.Case, async: false

  alias Gemini.Interactions.Understanding
  alias Plug.Conn

  setup do
    bypass = Gemini.TestHTTPServer.open()
    :meck.new(Gemini.Auth, [:passthrough])
    on_exit(fn -> :meck.unload() end)
    %{bypass: bypass}
  end

  defp respond(bypass, text) do
    parent = self()

    Bypass.expect_once(bypass, "POST", "/v1beta/interactions", fn conn ->
      {:ok, raw, conn} = Conn.read_body(conn)
      send(parent, {:body, Jason.decode!(raw)})

      conn
      |> Conn.put_resp_content_type("application/json")
      |> Conn.resp(200, Jason.encode!(%{
        "id" => "i",
        "status" => "completed",
        "output_text" => text
      }))
    end)
  end

  defp sent_body do
    receive do
      {:body, body} -> body
    after
      1_000 -> flunk("no request body captured")
    end
  end

  test "analyze/3 puts media before the prompt", %{bypass: bypass} do
    respond(bypass, "A cat.")

    assert {:ok, "A cat."} =
             Understanding.analyze(
               "What is this?",
               [{:image, {:uri, "files/abc"}, "image/jpeg"}],
               model: "gemini-3.6-flash"
             )

    assert [
             %{"type" => "image", "uri" => "files/abc", "mime_type" => "image/jpeg"},
             %{"type" => "text", "text" => "What is this?"}
           ] = sent_body()["input"]
  end

  test "analyze/3 sets per-item resolution", %{bypass: bypass} do
    respond(bypass, "ok")

    {:ok, _} =
      Understanding.analyze(
        "Read the text",
        [{:image, {:uri, "files/abc"}, "image/jpeg"}],
        model: "gemini-3.6-flash",
        resolution: "high"
      )

    assert [%{"resolution" => "high"} | _] = sent_body()["input"]
  end

  test "analyze/3 supports inline base64 data", %{bypass: bypass} do
    respond(bypass, "ok")

    {:ok, _} =
      Understanding.analyze(
        "What is this?",
        [{:document, {:data, "QUJD"}, "application/pdf"}],
        model: "gemini-3.6-flash"
      )

    assert [%{"type" => "document", "data" => "QUJD"} | _] = sent_body()["input"]
  end

  test "analyze/3 treats a bare URL string as a URI, for YouTube", %{bypass: bypass} do
    respond(bypass, "ok")

    {:ok, _} =
      Understanding.analyze(
        "Summarize",
        [{:video, "https://www.youtube.com/watch?v=abc", nil}],
        model: "gemini-3.6-flash"
      )

    assert [%{"type" => "video", "uri" => "https://www.youtube.com/watch?v=abc"} | _] =
             sent_body()["input"]

    refute Map.has_key?(hd(sent_body()["input"]), "mime_type")
  end

  test "analyze/3 accepts multiple media items in order", %{bypass: bypass} do
    respond(bypass, "ok")

    {:ok, _} =
      Understanding.analyze(
        "Compare",
        [
          {:image, {:uri, "files/a"}, "image/png"},
          {:image, {:uri, "files/b"}, "image/png"}
        ],
        model: "gemini-3.6-flash"
      )

    assert [%{"uri" => "files/a"}, %{"uri" => "files/b"}, %{"type" => "text"}] =
             sent_body()["input"]
  end

  test "describe_image/3 wraps analyze/3", %{bypass: bypass} do
    respond(bypass, "A cat.")

    assert {:ok, "A cat."} =
             Understanding.describe_image("What is this?", {:uri, "files/abc"},
               model: "gemini-3.6-flash",
               mime_type: "image/jpeg"
             )

    assert [%{"type" => "image", "mime_type" => "image/jpeg"} | _] = sent_body()["input"]
  end

  test "transcribe_audio/3 sends an audio block", %{bypass: bypass} do
    respond(bypass, "Hello.")

    assert {:ok, "Hello."} =
             Understanding.transcribe_audio("Transcribe", {:uri, "files/a"},
               model: "gemini-3.6-flash",
               mime_type: "audio/mp3"
             )

    assert [%{"type" => "audio", "mime_type" => "audio/mp3"} | _] = sent_body()["input"]
  end

  test "analyze_document/3 sends a document block", %{bypass: bypass} do
    respond(bypass, "Summary.")

    assert {:ok, "Summary."} =
             Understanding.analyze_document("Summarize", {:uri, "files/d"},
               model: "gemini-3.6-flash",
               mime_type: "application/pdf"
             )

    assert [%{"type" => "document"} | _] = sent_body()["input"]
  end

  test "analyze/3 forwards response_format for structured extraction", %{bypass: bypass} do
    respond(bypass, ~s({"boxes":[]}))

    schema = %{"type" => "object"}

    {:ok, _} =
      Understanding.analyze(
        "Detect objects",
        [{:image, {:uri, "files/abc"}, "image/jpeg"}],
        model: "gemini-3.6-flash",
        response_format: %Gemini.Types.Interactions.ResponseFormat.Text{
          mime_type: "application/json",
          schema: schema
        }
      )

    assert sent_body()["response_format"] == %{
             "type" => "text",
             "mime_type" => "application/json",
             "schema" => schema
           }
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/gemini/interactions/video_test.exs test/gemini/interactions/understanding_test.exs`
Expected: FAIL — modules not available

- [ ] **Step 3: Write Gemini.Interactions.Video**

Create `lib/gemini/interactions/video.ex`:

```elixir
defmodule Gemini.Interactions.Video do
  @moduledoc """
  Video generation with Gemini Omni through the Interactions API.

  <https://ai.google.dev/gemini-api/docs/omni>

  This covers the Omni models only. Veo 3.1 uses a different endpoint and is
  handled by `Gemini.APIs.Videos`.

  Omni does not support system instructions, `temperature`, `top_p`, stop
  sequences, or negative prompts as parameters. Express negatives in the prompt
  text instead.

  Videos larger than 4 MB are returned by URI rather than inline. Pass
  `delivery: "uri"` to request that explicitly.

  ## Examples

      {:ok, video} =
        Gemini.Interactions.Video.generate("a cat surfing a wave",
          model: "gemini-omni-flash",
          aspect_ratio: "16:9",
          delivery: "uri"
        )

  Conversational editing continues from a prior interaction:

      {:ok, edited} =
        Gemini.Interactions.Video.generate("now make it sunset",
          model: "gemini-omni-flash",
          previous_interaction_id: interaction.id
        )
  """

  alias Gemini.APIs.Interactions
  alias Gemini.Types.Interactions.{
    GenerationConfig,
    Interaction,
    ResponseFormat,
    TextContent,
    VideoConfig,
    VideoContent
  }

  @format_keys [:aspect_ratio, :delivery]

  @doc """
  Generate a video and return its content block.

  `:task` is one of `"text_to_video"`, `"image_to_video"`,
  `"reference_to_video"`, or `"edit"` — see `Gemini.Types.Interactions.VideoConfig`.
  `:aspect_ratio` and `:delivery` build the `response_format`.
  """
  @spec generate(String.t() | list(), keyword()) :: {:ok, VideoContent.t()} | {:error, term()}
  def generate(prompt, opts \\ []) do
    with {:ok, interaction} <- generate_interaction(prompt, opts) do
      Interaction.output_video(interaction)
    end
  end

  @doc """
  Generate a video and return the whole interaction.
  """
  @spec generate_interaction(String.t() | list(), keyword()) ::
          {:ok, Interaction.t()} | {:error, term()}
  def generate_interaction(prompt, opts \\ []) do
    Interactions.create(normalize_input(prompt), build_opts(opts))
  end

  defp normalize_input(prompt) when is_binary(prompt), do: %TextContent{text: prompt}
  defp normalize_input(input), do: input

  defp build_opts(opts) do
    {format_opts, rest} = Keyword.split(opts, @format_keys)
    {task, rest} = Keyword.pop(rest, :task)

    rest
    |> put_response_format(format_opts)
    |> put_video_config(task)
  end

  defp put_response_format(opts, format_opts) do
    case Keyword.get(opts, :response_format) do
      nil -> Keyword.put(opts, :response_format, struct(ResponseFormat.Video, format_opts))
      _existing -> opts
    end
  end

  defp put_video_config(opts, nil), do: opts

  defp put_video_config(opts, task) do
    case Keyword.get(opts, :generation_config) do
      nil ->
        Keyword.put(opts, :generation_config, %GenerationConfig{
          video_config: %VideoConfig{task: task}
        })

      _existing ->
        opts
    end
  end
end
```

- [ ] **Step 4: Write Gemini.Interactions.Understanding**

Create `lib/gemini/interactions/understanding.ex`:

```elixir
defmodule Gemini.Interactions.Understanding do
  @moduledoc """
  Image, video, audio, and document understanding through the Interactions API.

  - <https://ai.google.dev/gemini-api/docs/image-understanding>
  - <https://ai.google.dev/gemini-api/docs/video-understanding>
  - <https://ai.google.dev/gemini-api/docs/audio>
  - <https://ai.google.dev/gemini-api/docs/document-processing>

  Media is placed before the prompt, which is what the documented examples do.

  ## Examples

      {:ok, text} =
        Gemini.Interactions.Understanding.analyze(
          "What is in this image?",
          [{:image, {:uri, "files/abc123"}, "image/jpeg"}],
          model: "gemini-3.6-flash"
        )

  A YouTube URL is passed as a bare string:

      {:ok, summary} =
        Gemini.Interactions.Understanding.analyze(
          "Summarize this video",
          [{:video, "https://www.youtube.com/watch?v=9hE5-98ZeCg", nil}],
          model: "gemini-3.6-flash"
        )

  Structured extraction — object detection returns normalized 0-1000 boxes:

      schema = %{
        "type" => "object",
        "properties" => %{
          "boxes" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "box_2d" => %{"type" => "array", "items" => %{"type" => "integer"}},
                "label" => %{"type" => "string"}
              }
            }
          }
        }
      }

      {:ok, json} =
        Gemini.Interactions.Understanding.analyze(
          "Detect all objects",
          [{:image, {:uri, "files/abc"}, "image/jpeg"}],
          model: "gemini-3.6-flash",
          response_format: %Gemini.Types.Interactions.ResponseFormat.Text{
            mime_type: "application/json",
            schema: schema
          }
        )
  """

  alias Gemini.APIs.Interactions
  alias Gemini.Interactions.Text

  alias Gemini.Types.Interactions.{
    AudioContent,
    DocumentContent,
    ImageContent,
    Interaction,
    TextContent,
    VideoContent
  }

  @type source :: {:uri, String.t()} | {:data, String.t()} | String.t()
  @type media :: {:image | :video | :audio | :document, source(), String.t() | nil} | struct()

  @kind_to_module %{
    image: ImageContent,
    video: VideoContent,
    audio: AudioContent,
    document: DocumentContent
  }

  @doc """
  Analyze media and return the model's text response.

  `:resolution` sets the per-content-item media resolution on every media block
  — `"low"`, `"medium"`, `"high"`, or `"ultra_high"`. It is Gemini 3 only.
  """
  @spec analyze(String.t(), [media()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def analyze(prompt, media, opts \\ []) when is_binary(prompt) and is_list(media) do
    with {:ok, interaction} <- analyze_interaction(prompt, media, opts) do
      Interaction.output_text(interaction)
    end
  end

  @doc """
  Analyze media and return the whole interaction.
  """
  @spec analyze_interaction(String.t(), [media()], keyword()) ::
          {:ok, Interaction.t()} | {:error, term()}
  def analyze_interaction(prompt, media, opts \\ []) when is_binary(prompt) and is_list(media) do
    {resolution, opts} = Keyword.pop(opts, :resolution)

    input = Enum.map(media, &to_content(&1, resolution)) ++ [%TextContent{text: prompt}]

    Interactions.create(input, Text.build_opts(opts))
  end

  @doc """
  Describe a single image. `:mime_type` sets the image's MIME type.
  """
  @spec describe_image(String.t(), source(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def describe_image(prompt, source, opts \\ []), do: single(:image, prompt, source, opts)

  @doc """
  Analyze a single video. Pass a YouTube URL as a bare string.
  """
  @spec analyze_video(String.t(), source(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def analyze_video(prompt, source, opts \\ []), do: single(:video, prompt, source, opts)

  @doc """
  Transcribe or analyze a single audio file.
  """
  @spec transcribe_audio(String.t(), source(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def transcribe_audio(prompt, source, opts \\ []), do: single(:audio, prompt, source, opts)

  @doc """
  Analyze a single document, typically a PDF.
  """
  @spec analyze_document(String.t(), source(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def analyze_document(prompt, source, opts \\ []), do: single(:document, prompt, source, opts)

  defp single(kind, prompt, source, opts) do
    {mime_type, opts} = Keyword.pop(opts, :mime_type)

    analyze(prompt, [{kind, source, mime_type}], opts)
  end

  defp to_content(%_{} = content, _resolution), do: content

  defp to_content({kind, source, mime_type}, resolution) do
    module = Map.fetch!(@kind_to_module, kind)

    module
    |> struct(source_fields(source))
    |> put_if(:mime_type, mime_type)
    |> put_if(:resolution, resolution_for(module, resolution))
  end

  defp source_fields({:uri, uri}), do: %{uri: uri}
  defp source_fields({:data, data}), do: %{data: data}
  defp source_fields(uri) when is_binary(uri), do: %{uri: uri}

  defp put_if(struct, _key, nil), do: struct
  defp put_if(struct, key, value), do: Map.put(struct, key, value)

  # AudioContent has no resolution field; the API documents resolution for
  # image, video, and document parts only.
  defp resolution_for(AudioContent, _resolution), do: nil
  defp resolution_for(_module, resolution), do: resolution
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/gemini/interactions/`
Expected: PASS

- [ ] **Step 6: Format, compile clean, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/gemini/interactions/video.ex lib/gemini/interactions/understanding.ex test/gemini/interactions/video_test.exs test/gemini/interactions/understanding_test.exs
git commit -m "feat(interactions): add Video and Understanding capability modules"
```

---

### Task 12: Model registry refresh

**Files:**
- Modify: `lib/gemini/model_registry.ex`
- Modify: `lib/gemini/config.ex:63-104`
- Test: `test/gemini/model_registry_test.exs` (existing — extend)

**Interfaces:**
- Produces: new registry entries reachable through the existing `Gemini.ModelRegistry` API and new `Gemini.Config` alias atoms.

Before writing entries, read an existing one in full (for example `gemini_3_1_pro_preview` at `model_registry.ex:48-68`) and copy its field set exactly. Every new entry must have the same keys — do not invent or omit fields.

- [ ] **Step 1: Write the failing test**

Append to `test/gemini/model_registry_test.exs`:

```elixir
  describe "current model coverage" do
    @current_models [
      "gemini-3.6-flash",
      "gemini-3.5-flash",
      "gemini-3.5-flash-lite",
      "gemini-3.1-flash-lite",
      "gemini-3.1-flash-image",
      "gemini-3.1-flash-lite-image",
      "gemini-3-pro-image",
      "gemini-3.1-flash-tts-preview",
      "gemini-3.5-live-translate-preview",
      "gemini-omni-flash",
      "gemini-embedding-2-preview"
    ]

    test "every currently documented model is registered" do
      for code <- @current_models do
        assert Gemini.model_exists?(code), "#{code} is not in the model registry"
      end
    end

    test "gemini-omni-flash-preview resolves as an alias of gemini-omni-flash" do
      assert Gemini.model_exists?("gemini-omni-flash-preview")
    end

    test "previously registered models are still present" do
      for code <- ["gemini-3.1-pro-preview", "gemini-3-pro-preview", "gemini-2.5-flash"] do
        assert Gemini.model_exists?(code), "#{code} was dropped from the registry"
      end
    end
  end
```

Append to `test/gemini/config_test.exs`:

```elixir
  describe "model aliases" do
    test ":latest resolves to gemini-3.6-flash" do
      assert Gemini.Config.get_model(:latest) == "gemini-3.6-flash"
    end
  end
```

Confirm the accessor name by reading `lib/gemini/config.ex` — if aliases are resolved by a differently-named function, use that name in the test instead.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/gemini/model_registry_test.exs test/gemini/config_test.exs`
Expected: FAIL — `gemini-3.6-flash is not in the model registry`

- [ ] **Step 3: Add the registry entries**

In `lib/gemini/model_registry.ex`, add one entry per model in `@current_models` to the `@entries` list. Every entry must carry the full key set the existing entries use. Here is `gemini-3.6-flash` written out completely — use it as the template and vary only the values:

```elixir
    %{
      key: :gemini_3_6_flash,
      code: "gemini-3.6-flash",
      source_page: "https://ai.google.dev/gemini-api/docs/models",
      track: :stable,
      latest_update: "August 2026",
      input_modalities: [:text, :image, :video, :audio, :pdf],
      output_modalities: [:text, :image, :video, :audio],
      capabilities: %{
        audio_generation: :supported,
        batch_api: :supported,
        caching: :supported,
        function_calling: :supported,
        image_generation: :supported,
        live_api: :not_supported,
        structured_outputs: :supported,
        thinking: :supported
      },
      aliases: [],
      live_modalities: [],
      notes: nil
    },
```

Set `track: :preview` for any code ending in `-preview`, `:stable` otherwise. For the image-only models set `output_modalities: [:image]` and `image_generation: :supported` with `thinking: :supported` on `gemini-3.1-flash-image` and `gemini-3-pro-image` (both support reasoning per the image-generation guide) and `thinking: :not_supported` on `gemini-3.1-flash-lite-image`. For the TTS model set `output_modalities: [:audio]`, `audio_generation: :supported`, and everything else `:not_supported`. For `gemini-embedding-2-preview` set `output_modalities: [:text]` with a `notes:` string recording that its real output is embeddings.

Modality data from `https://ai.google.dev/gemini-api/docs/models`:

| code | input | output |
|---|---|---|
| `gemini-3.6-flash` | text, image, video, audio | text, image, video, audio |
| `gemini-3.5-flash` | text, image, video, audio | text, image, video, audio |
| `gemini-3.5-flash-lite` | text, image, video, audio | text, image, video, audio |
| `gemini-3.1-flash-lite` | text, image, video, audio | text, image, video, audio |
| `gemini-3.1-flash-image` | text, image | image |
| `gemini-3.1-flash-lite-image` | text, image | image |
| `gemini-3-pro-image` | text, image | image |
| `gemini-3.1-flash-tts-preview` | text | audio |
| `gemini-3.5-live-translate-preview` | audio | audio |
| `gemini-omni-flash` | text, image, video | video |
| `gemini-embedding-2-preview` | text, image, video, audio, pdf | embeddings |

Set `source_page` to `"https://ai.google.dev/gemini-api/docs/models"` for each, since these are listed there rather than each having its own page.

Give `gemini-omni-flash` this aliases entry and comment:

```elixir
      # The models page lists this as `gemini-omni-flash`; the Omni guide at
      # https://ai.google.dev/gemini-api/docs/omni uses
      # `gemini-omni-flash-preview`. Both resolve here so either spelling works.
      aliases: ["gemini-omni-flash-preview"],
```

Do not remove any existing entry.

- [ ] **Step 4: Update Config aliases**

In `lib/gemini/config.ex`, add to the model alias map (lines 63-104):

```elixir
    flash_3_6: "gemini-3.6-flash",
    flash_3_5: "gemini-3.5-flash",
    flash_3_5_lite: "gemini-3.5-flash-lite",
    flash_3_1_lite: "gemini-3.1-flash-lite",
    flash_3_1_image: "gemini-3.1-flash-image",
    flash_3_1_lite_image: "gemini-3.1-flash-lite-image",
    pro_3_image: "gemini-3-pro-image",
    flash_3_1_preview_tts: "gemini-3.1-flash-tts-preview",
    live_translate_3_5_preview: "gemini-3.5-live-translate-preview",
    omni_flash: "gemini-omni-flash",
    embedding_2_preview: "gemini-embedding-2-preview",
```

Change line 104 from `latest: "gemini-3.1-pro-preview",` to:

```elixir
    latest: "gemini-3.6-flash",
```

- [ ] **Step 5: Run the full suite**

Run: `mix test`
Expected: PASS. If any test asserted the old `:latest` value, update that assertion — the change is intentional and documented in the spec's §9.

- [ ] **Step 6: Format, compile clean, commit**

```bash
mix format
mix compile --warnings-as-errors
git add lib/gemini/model_registry.ex lib/gemini/config.ex test/gemini/model_registry_test.exs test/gemini/config_test.exs
git commit -m "feat(models): register current Gemini models and move :latest to gemini-3.6-flash"
```

---

### Task 13: Guides, examples, README, CHANGELOG

**Files:**
- Create: `guides/interactions_text.md`, `guides/interactions_image_generation.md`, `guides/interactions_speech.md`, `guides/interactions_video.md`, `guides/interactions_understanding.md`, `guides/interactions_thinking.md`
- Create: `examples/16_interactions_text.exs`, `examples/17_interactions_image.exs`, `examples/18_interactions_speech.exs`, `examples/19_interactions_understanding.exs`, `examples/20_interactions_thinking.exs`
- Modify: `README.md`, `CHANGELOG.md`, `mix.exs` (docs `extras` list)

**Interfaces:**
- Consumes: every public function from Tasks 8-12.
- Produces: no code interfaces. This task is documentation.

Do not modify the existing guides — the `generateContent` modules they document are unchanged.

- [ ] **Step 1: Write the guides**

Each guide covers one capability page: what it does, a minimal runnable example, the options that matter, and a link to the corresponding `ai.google.dev` page. Use only functions that exist after Tasks 8-12 — every code block must be copy-pasteable.

`guides/interactions_thinking.md` must additionally explain thought signatures: that `store: false` requires resending every signature byte-identically, that `Interaction.thought_signatures/1` collects them, and that `Step.to_api/1` round-trips unmodeled step types precisely so their signatures survive.

- [ ] **Step 2: Write the examples**

Follow the existing style in `examples/01_basic_generation.exs`. Read that file first and match its structure — the header comment, how it reads credentials, and how it prints output.

- [ ] **Step 3: Register the guides in mix.exs**

Add all six new guide paths to the `extras` list in the `docs/0` function so they appear in the generated docs.

- [ ] **Step 4: Update README.md**

Add an "Interactions API" section after the existing quick-start. Lead with the fact that Interactions is the surface Google documents for all current capabilities, show a `Gemini.Interactions.Text.generate/2` call, and link to the six guides. Note that the `generateContent`-based functions remain supported and unchanged.

- [ ] **Step 5: Update CHANGELOG.md**

Add a `0.17.0` entry recording: the `steps` field and `Step` model; the `output_*` accessors; the `step.*` SSE events and corrected `interaction.created`/`interaction.completed` names; typed `ResponseFormat`; the new request fields; the five capability modules; the new models; and — called out separately, since it is user-visible — that `:latest` now resolves to `gemini-3.6-flash` instead of `gemini-3.1-pro-preview`.

- [ ] **Step 6: Verify docs build clean**

Run: `mix docs --warnings-as-errors`
Expected: PASS with no warnings. A broken cross-reference or a link to a nonexistent module fails this.

- [ ] **Step 7: Commit**

```bash
mix format
git add guides examples README.md CHANGELOG.md mix.exs
git commit -m "docs: guides and examples for the Interactions API"
```

---

### Task 14: Veo 3.1 audit

**Files:**
- Create: `docs/veo-3.1-audit.md`
- Read only: `lib/gemini/apis/videos.ex`, `lib/gemini/types/generation/video.ex`

**Interfaces:**
- Consumes: nothing.
- Produces: a findings document. **No code changes.** If you find a bug, write it down; do not fix it.

- [ ] **Step 1: Read the current implementation**

Read `lib/gemini/apis/videos.ex` and `lib/gemini/types/generation/video.ex` in full. Note every request field it builds and every parameter it supports.

- [ ] **Step 2: Compare against the Veo 3.1 reference**

The documented request shape at `https://ai.google.dev/gemini-api/docs/veo`, endpoint `{BASE_URL}/models/{model}:predictLongRunning`:

```json
{
  "instances": [{
    "prompt": "string",
    "image": {"inlineData": {"mimeType": "string", "data": "base64"}},
    "video": {"inlineData": {"mimeType": "video/mp4", "data": "base64"}},
    "lastFrame": {"inlineData": {"mimeType": "string", "data": "base64"}},
    "referenceImages": [
      {"image": {"inlineData": {"mimeType": "string", "data": "base64"}},
       "referenceType": "asset"}
    ]
  }],
  "parameters": {
    "aspectRatio": "16:9|9:16",
    "durationSeconds": "4|6|8",
    "personGeneration": "allow_all|allow_adult",
    "resolution": "720p|1080p|4k",
    "numberOfVideos": 1
  }
}
```

Polling: POST returns an operation with `name`; GET `{BASE_URL}/{operation.name}` every 10s; when `done` is true read `response.generateVideoResponse.generatedSamples[0].video.uri`.

Model IDs: `veo-3.1-generate-preview`, `veo-3.1-fast-generate-preview`, `veo-3.1-lite-generate-preview`.

Constraints to check: `durationSeconds` must be `"8"` for 1080p, 4k, or reference-image requests; `resolution` `720p` only for extension; `numberOfVideos` is 1 per request.

- [ ] **Step 3: Write the findings document**

Create `docs/veo-3.1-audit.md` with one row per field: the field, whether `Gemini.APIs.Videos` supports it, and the file and line number of the evidence. End with a recommendation on whether follow-up work is warranted and how large it looks. State plainly if everything is already covered.

- [ ] **Step 4: Commit**

```bash
git add docs/veo-3.1-audit.md
git commit -m "docs: audit Gemini.APIs.Videos against the Veo 3.1 reference"
```

---

### Task 15: Full QC gate

**Files:** none — verification only.

- [ ] **Step 1: Run the complete gate**

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict
mix docs --warnings-as-errors
mix dialyzer
```

Every one must pass. Do not claim completion until you have seen each command's output.

- [ ] **Step 2: Confirm no runtime env access was introduced**

```bash
grep -rn "System.get_env\|System.fetch_env\|System.put_env\|System.delete_env" lib/
```

Expected: no output. Any hit violates the `AGENTS.md` rule and must be moved behind `Gemini.Env`.

- [ ] **Step 3: Confirm the legacy surface is untouched**

```bash
git diff --stat main -- lib/gemini/apis/coordinator.ex lib/gemini/apis/images.ex lib/gemini/apis/videos.ex lib/gemini/apis/context_cache.ex
```

Expected: no output. `lib/gemini/config.ex` is the one permitted exception and is not in this list.

- [ ] **Step 4: Fix anything that failed, then commit**

```bash
git add -A
git commit -m "chore: QC gate for Interactions API support"
```

---

## Post-implementation verification

The plan's request shapes come from documented examples rather than captured live traffic. Before releasing, run one live call against a real key and confirm the response parses into `steps` rather than falling back to `outputs`:

```elixir
{:ok, interaction} =
  Gemini.APIs.Interactions.create("Say hi", model: "gemini-3.6-flash")

# steps must be a non-empty list, not nil
interaction.steps
```

Per `AGENTS.md`, run live provider checks through `~/scripts/with_bash_secrets <command>` and never print secrets. If `steps` comes back `nil`, the wire format differs from the documentation and Tasks 1-3 need revisiting before release.
