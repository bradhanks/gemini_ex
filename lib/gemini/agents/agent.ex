defmodule Gemini.Agents.Agent do
  @moduledoc """
  Declaration macro for one review execution agent.

  Each agent module declares its identity and the specialties it owns; the
  macro derives the composed instruction block, the restricted finding schema,
  and `run/2` (standard) or `start/2` + `await/2` (research) via
  `Gemini.Agents.Runner`. Instruction text comes from
  `Gemini.Agents.Specialties` — one source of truth, verbatim from the catalog.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      alias Gemini.Agents.{Prompts, Runner, Specialties}

      @agent_id Keyword.fetch!(opts, :id)
      @agent_name Keyword.fetch!(opts, :name)
      @specialty_ids Keyword.fetch!(opts, :specialties)
      @profile Keyword.fetch!(opts, :profile)
      @tools Keyword.get(opts, :tools, [])
      @capabilities Keyword.get(opts, :capabilities, [])
      @gut_check Keyword.get(opts, :gut_check, :none)
      @extra_instructions Keyword.get(opts, :extra_instructions, "")
      @mode Keyword.get(opts, :mode, :standard)

      @doc "This agent's spec — identity, specialties, profile, tools, mode."
      def spec do
        %{
          id: @agent_id,
          name: @agent_name,
          specialty_ids: @specialty_ids,
          specialties: Enum.map(@specialty_ids, &Specialties.fetch!/1),
          profile: @profile,
          tools: @tools,
          capabilities: @capabilities,
          gut_check: @gut_check,
          mode: @mode,
          overview?: false,
          instructions: instructions()
        }
      end

      @doc "The composed instruction block: emission standard + assignments + extras."
      def instructions do
        @specialty_ids
        |> Enum.map(&Specialties.fetch!/1)
        |> Prompts.group_instructions(@extra_instructions)
      end

      # Every agent consumes a document or text: a %Document{} (cached by
      # default), a text binary, a {:pdf, path} tuple, or a prepared content
      # list for full control.
      defp normalize_input(%Gemini.Agents.Document{} = doc),
        do: Gemini.Agents.Document.to_input(doc)

      defp normalize_input({:pdf, _path} = source),
        do: source |> Gemini.Agents.Document.prepare() |> Gemini.Agents.Document.to_input()

      defp normalize_input(text) when is_binary(text),
        do: text |> Gemini.Agents.Document.prepare() |> Gemini.Agents.Document.to_input()

      defp normalize_input(list) when is_list(list), do: list

      if @mode == :standard do
        @doc "Run this agent on a Document, text, {:pdf, path}, or content list."
        def run(input, opts \\ []),
          do: Runner.run_with_fallback(spec(), normalize_input(input), opts)
      else
        @doc "Start this research agent in the background; persist the returned id."
        def start(input, opts \\ []), do: Runner.start(spec(), normalize_input(input), opts)

        @doc "Await a started research run by interaction id."
        def await(interaction_id, opts \\ []), do: Runner.await(interaction_id, opts)
      end
    end
  end
end
