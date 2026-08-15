defmodule Gemini.Agents.Dossier do
  @moduledoc """
  The consolidated report for a finished review — every agent's verified
  output in one document.

  `build/2` consumes the results a review collected and returns markdown:
  headline counts, the verifier's editorial overview when present, findings
  grouped by author-facing category with severity, research reports appended
  verbatim, and a run log (agent, model, tier, finding count, interaction id)
  that doubles as the audit trail.

  Rendering to PDF is the caller's concern (pandoc/wkhtmltopdf/ChromicPDF —
  binaries a library should not shell out to). The markdown is
  pandoc-clean.
  """

  alias Gemini.Agents.Specialties

  @severity_order ~w(major minor suggestion)

  @doc """
  Build the dossier.

    * `results` — `[{agent_id, %{findings: [...], overview: ..., interaction: ...}}]`
      as collected from agent runs (and optionally the verify pass).
    * `opts` — `:title`, `:prepared` (date string), `:research`
      (`[{agent_id, report_text}]`), `:overview` (overrides any per-result one).
  """
  def build(results, opts \\ []) do
    findings = Enum.flat_map(results, fn {_id, r} -> r.findings end)

    overview =
      Keyword.get(opts, :overview) ||
        Enum.find_value(results, fn {_id, r} -> r[:overview] end)

    [
      header(Keyword.get(opts, :title, "Manuscript Review"), Keyword.get(opts, :prepared)),
      summary(findings, results),
      overview_section(overview),
      findings_sections(findings),
      research_sections(Keyword.get(opts, :research, [])),
      run_log(results)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp header(title, prepared) do
    prepared_line = if prepared, do: "\\\n**Prepared:** #{prepared}", else: ""
    "# #{title} — Review Dossier\n\n**Scope:** full agent review#{prepared_line}"
  end

  defp summary(findings, results) do
    by_sev = Enum.frequencies_by(findings, & &1["severity"])
    agents_run = length(results)

    sev_cells =
      Enum.map_join(@severity_order, " · ", fn s -> "#{s}: **#{Map.get(by_sev, s, 0)}**" end)

    """
    ## Summary

    **#{length(findings)} verified findings** from **#{agents_run} agents** — #{sev_cells}.
    """
  end

  defp overview_section(nil), do: ""

  defp overview_section(overview) do
    "## Editorial overview\n\n#{overview}"
  end

  defp findings_sections([]), do: "## Findings\n\nNo findings — a clean result is a valid result."

  defp findings_sections(findings) do
    sections =
      findings
      |> Enum.group_by(fn f -> Specialties.category(f["agent"]) end)
      |> Enum.sort_by(fn {cat, group} -> {-length(group), cat} end)
      |> Enum.map_join("\n\n", fn {category, group} ->
        cards =
          group
          |> Enum.sort_by(fn f ->
            Enum.find_index(@severity_order, &(&1 == f["severity"])) || 9
          end)
          |> Enum.map_join("\n\n", &finding_card/1)

        "### #{category_label(category)} (#{length(group)})\n\n" <> cards
      end)

    "## Findings\n\n" <> sections
  end

  defp finding_card(f) do
    anchor = f["anchor"] || %{}
    location = anchor["section"] || "unlocated"
    quote_text = anchor["quote"] || ""

    suggestion =
      case f["suggestion"] do
        s when is_binary(s) and s != "" -> "\n**Suggested:** #{s}"
        _ -> ""
      end

    """
    **[#{f["severity"]}] #{f["title"]}** — _#{location}_ (#{f["agent"]})\\
    **Quoted:** #{quote_text}\\
    #{f["explanation"]}#{suggestion}
    """
    |> String.trim()
  end

  defp research_sections([]), do: ""

  defp research_sections(research) do
    Enum.map_join(research, "\n\n", fn {agent_id, report} ->
      "## Research report — #{agent_id}\n\n#{demote_headings(report)}"
    end)
  end

  # A research report arrives as its own document; demote its headings so it
  # nests under this dossier instead of outranking it.
  defp demote_headings(text) do
    text
    |> String.replace(~r/\A# [^\n]*\n+/, "")
    |> String.replace(~r/^(\#{1,5}) /m, "#\\1 ")
  end

  defp run_log(results) do
    rows =
      Enum.map_join(results, "\n", fn {id, r} ->
        i = r[:interaction]

        model = (i && i.model) || "-"
        tier = (i && i.service_tier) || "-"
        iid = (i && i.id && String.slice(i.id, 0, 20) <> "…") || "-"
        "| #{id} | #{model} | #{tier} | #{length(r.findings)} | `#{iid}` |"
      end)

    """
    ## Run log

    | Agent | Model | Tier | Findings | Interaction |
    |---|---|---|---|---|
    #{rows}
    """
  end

  defp category_label(:figures_tables), do: "Figures & tables"
  defp category_label(cat), do: cat |> Atom.to_string() |> String.capitalize()
end
