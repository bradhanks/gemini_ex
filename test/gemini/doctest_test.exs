defmodule Gemini.DoctestTest do
  @moduledoc """
  Runs the `iex>` examples in public module docs.

  Only modules whose examples are self-contained belong here. Examples that need
  live credentials, a service-account key file, or specific application config
  (`Gemini.Config`, `Gemini.Auth.JWT`, `Gemini.Auth.VertexStrategy`) are
  illustrative, as are examples for response structs the caller never builds
  (`Gemini.Types.Response.Model`); those use plain code blocks instead of `iex>`
  prompts and stay out of this suite.
  """

  use ExUnit.Case, async: true

  # The helper modules document themselves under their short aliases; doctests
  # are evaluated in this module's scope, so the aliases have to exist here too.
  alias Gemini.Utils.MapHelpers
  alias Gemini.Utils.PollingHelpers

  doctest Gemini.SSE.Parser
  doctest Gemini.Telemetry
  doctest Gemini.Types.Content
  doctest Gemini.Types.Generation.Image
  doctest Gemini.Types.Generation.Video
  doctest Gemini.Types.Request.ListModelsRequest
  doctest Gemini.Utils.MapHelpers
  doctest Gemini.Utils.PollingHelpers
  doctest Gemini.Validation.ThinkingConfig
end
