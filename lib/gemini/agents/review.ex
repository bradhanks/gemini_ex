defmodule Gemini.Agents.Review do
  @moduledoc """
  Run a fleet of agents over one document and fire a callback with the
  finished dossier.

      Gemini.Agents.Review.run(document,
        agents: Gemini.Agents.standard_executions(),
        on_complete: fn dossier_md, results ->
          MyApp.Reviews.deliver!(dossier_md, results)
        end
      )

  Standard agents run concurrently (`Task.async_stream`); when every one has
  finished, the dossier is built from whatever succeeded and `:on_complete`
  fires exactly once. Failed agents appear in the returned `errors` list and
  in the dossier's run log by absence — a review is not held hostage by one
  agent's bad day.

  This is deliberately the *simple* orchestration: no waves, no prepass
  feeding, no anchor gauntlet — those are application policy. From a
  LiveView, run the whole thing inside `start_async` and treat the callback
  as your delivery seam; for the 30–65-minute research agents, `start/2`
  them separately and append their reports via the dossier's `:research`
  option when they land.
  """

  alias Gemini.Agents.Dossier

  @default_concurrency 6

  @doc """
  Run `:agents` (modules) over `document`. Returns
  `{:ok, %{dossier: md, results: [...], errors: [...]}}`.

  Options: `:agents` (default `Gemini.Agents.standard_executions/0`),
  `:concurrency`, `:timeout_ms` per agent, `:on_complete` (arity-2 fun),
  `:dossier` (opts forwarded to `Dossier.build/2`).
  """
  def run(document, opts \\ []) do
    agents = Keyword.get(opts, :agents, Gemini.Agents.standard_executions())
    timeout = Keyword.get(opts, :timeout_ms, :timer.minutes(20))

    {results, errors} =
      agents
      |> Task.async_stream(
        fn agent -> {agent.spec().id, agent.run(document)} end,
        max_concurrency: Keyword.get(opts, :concurrency, @default_concurrency),
        timeout: timeout,
        on_timeout: :kill_task,
        zip_input_on_exit: true
      )
      |> Enum.reduce({[], []}, fn
        {:ok, {id, {:ok, result}}}, {ok, errs} -> {[{id, result} | ok], errs}
        {:ok, {id, {:error, reason}}}, {ok, errs} -> {ok, [{id, reason} | errs]}
        {:exit, {agent, reason}}, {ok, errs} -> {ok, [{agent.spec().id, {:exit, reason}} | errs]}
      end)

    results = Enum.reverse(results)
    dossier = Dossier.build(results, Keyword.get(opts, :dossier, []))

    case Keyword.get(opts, :on_complete) do
      fun when is_function(fun, 2) -> fun.(dossier, results)
      nil -> :ok
    end

    {:ok, %{dossier: dossier, results: results, errors: Enum.reverse(errors)}}
  end
end
