defmodule Gemini.Agents.Specialties do
  @moduledoc """
  The 30 visible specialties of the PerfectPaper review taxonomy.

  Extracted verbatim from `docs/review-engine/agent-catalog-full.md`
  (source commit b84f2eb8). Specialties are the product/UI contract carried on
  every finding; they are never executed directly — the execution agents under
  `Gemini.Agents.*` compose their instruction text. Do not edit instruction
  strings here without updating the catalog document.
  """

  @specialties %{
    "S1.1" => %{
      id: "S1.1",
      name: "IMRaD completeness and section ordering",
      c_code: "C1",
      category: :structure,
      instructions:
        "Map the manuscript sections; check required front/back matter, section order, missing limitations, and content placed in the wrong section. Respect legitimate journal variants supplied in cached requirements."
    },
    "S1.2" => %{
      id: "S1.2",
      name: "Abstract-to-body consistency",
      c_code: "C1",
      category: :structure,
      instructions:
        "Match every abstract sample size, estimate, result, primary outcome, direction, and conclusion to the body. Allow declared rounding tolerance; flag abstract-only results and material mismatches."
    },
    "S1.3" => %{
      id: "S1.3",
      name: "Journal limits compliance",
      c_code: "C1",
      category: :structure,
      instructions:
        "Compare abstract/main-text words and figure, table, reference, and section counts with sourced target-journal requirements. Separate supplements and never infer an unstated limit."
    },
    "S1.4" => %{
      id: "S1.4",
      name: "Reporting-guideline router and compliance",
      c_code: "C1",
      category: :structure,
      instructions:
        "Classify study design from Title, Abstract, and Methods; route to all applicable EQUATOR guidelines, including extensions such as RECORD with STROBE; then identify missing or partial checklist items. If classification is genuinely ambiguous, emit that ambiguity instead of guessing."
    },
    "S2.1" => %{
      id: "S2.1",
      name: "Grammar and spelling",
      c_code: "C2",
      category: :language,
      instructions:
        "Flag genuine grammar, spelling, agreement, article, and punctuation errors with exact-span rewrites. Preserve domain terms, gene names, taxonomy, caption fragments, and the journal's spelling variant."
    },
    "S2.2" => %{
      id: "S2.2",
      name: "Readability and flow",
      c_code: "C2",
      category: :language,
      instructions:
        "Find only the worst sentence-length, nominalization, cohesion, topic-sentence, or avoidable-passive-voice problems. Interpret readability metrics in section and discipline context and provide concrete rewrites."
    },
    "S2.3" => %{
      id: "S2.3",
      name: "Word choice and terminological precision",
      c_code: "C2",
      category: :language,
      instructions:
        "Detect imprecise hedges, causal wording unsupported by design, jargon drift, and misuse of statistical terminology. Do not police correct field idioms or correct uses of statistically significant."
    },
    "S3.1" => %{
      id: "S3.1",
      name: "Cohort accounting and N reconciliation",
      c_code: "C3",
      category: :consistency,
      instructions:
        "Reconcile enrollment, exclusions, analysis samples, subgroups, denominators, flow diagrams, Table 1, and model-specific N. Account for complete-case or weighted analyses. Report imbalances without inventing which participants are missing."
    },
    "S3.2" => %{
      id: "S3.2",
      name: "Arithmetic and cross-table consistency",
      c_code: "C3",
      category: :consistency,
      instructions:
        "Recompute derivable counts, percentages, totals, repeated values, and unit conversions with explicit rounding tolerance. Recognize weighted percentages and legitimate truncation conventions."
    },
    "S3.3" => %{
      id: "S3.3",
      name: "Confidence-interval and p-value coherence",
      c_code: "C3",
      category: :consistency,
      instructions:
        "Check estimate/CI/sample-size plausibility and recover approximate p-values using the appropriate log scale for ratios, correct CI divisor, and Altman-Bland cautions. Do not overstate normal approximations, especially small continuous-outcome samples; never manufacture parameters."
    },
    "S3.4" => %{
      id: "S3.4",
      name: "Terminology, abbreviation, and units consistency",
      c_code: "C3",
      category: :consistency,
      instructions:
        "Build a symbol, abbreviation, variable, unit, and precision map; flag undefined use, conflicting definitions, name drift, unit drift, and unjustified decimal inconsistency while allowing journal-standard abbreviations."
    },
    "S4.1" => %{
      id: "S4.1",
      name: "Figure integrity and data-ink",
      c_code: "C4",
      category: :figures_tables,
      instructions:
        "Inspect each supplied figure and caption for labels, units, scale distortion, defined error bars, accessible color, legibility, sample size, log axes, dual-axis distortion, and chartjunk. Ground visual claims in legible labels or caption text."
    },
    "S4.2" => %{
      id: "S4.2",
      name: "Figure-to-text-to-caption consistency",
      c_code: "C4",
      category: :figures_tables,
      instructions:
        "Map figure citations in order and compare described numbers and trends with the image and caption. Check panel coverage, caption sample size, tests, and abbreviation definitions without demanding verbatim duplication."
    },
    "S5.1" => %{
      id: "S5.1",
      name: "Table structure and completeness",
      c_code: "C5",
      category: :figures_tables,
      instructions:
        "Check table citation order, headers and units, denominators, missing-data disclosure, footnotes, abbreviations, symbols, precision, and expected totals while respecting sparse and supplementary-table conventions."
    },
    "S5.2" => %{
      id: "S5.2",
      name: "Table numeric integrity and Table 2 fallacy",
      c_code: "C5",
      category: :figures_tables,
      instructions:
        "Check table arithmetic, crude-to-adjusted direction against the stated confounding story, event-per-variable risk, and causal interpretation of multiple coefficients from one model. Report risks and ratios without proposing hidden data or a uniquely true confounder structure."
    },
    "S6.1" => %{
      id: "S6.1",
      name: "Citation formatting and style",
      c_code: "C6",
      category: :citations,
      instructions:
        "Check in-text and reference-list style against sourced journal requirements; validate fields, DOI resolution, duplicates, ordering, and reference existence. For references without a DOI, verify existence by title and author search. Allow valid books, reports, gray literature, and journal-specific variants."
    },
    "S6.2" => %{
      id: "S6.2",
      name: "Sentence-level citation gaps",
      c_code: "C6",
      category: :citations,
      instructions:
        "Classify manuscript sentences as own result, interpretation, external claim, or background fact and flag only external claims that lack nearby support. Account for citations that govern a multi-sentence passage and common knowledge."
    },
    "S6.3" => %{
      id: "S6.3",
      name: "Semantic citation and primary-source verification",
      c_code: "C6",
      category: :citations,
      instructions:
        "Resolve each cited claim; retrieve the cited work's own abstract or results across PubMed, OpenAlex, Semantic Scholar, and open full text; test entailment and whether the result originated there. Distinguish legitimate review citations from citation laundering. Cascade sources before saying unsupported and never invent a primary DOI."
    },
    "S6.4" => %{
      id: "S6.4",
      name: "Wrong and irrelevant citation removal",
      c_code: "C6",
      category: :citations,
      instructions:
        "Identify citations that mismatch topic, direction, or claim; retracted sources; padding; and materially superseded sources. Recognize intentionally contrasting citations and relevant self-citation. When author identity and prior-work sources are available, check material undisclosed text recycling or self-plagiarism as a separate desk-reject risk."
    },
    "S7.1" => %{
      id: "S7.1",
      name: "Missing prior work and positioning",
      c_code: "C7",
      category: :literature,
      instructions:
        "Research important missed prior work, competing methods, larger or newer studies, contradictions, and seminal primary sources. Never claim that literature is missing unless an available search tool returns verified metadata and you confirm that work is absent from the bibliography. Ground every suggestion in a retrieved URL or DOI, explain relevance and placement, avoid recency bias, and deduplicate existing references."
    },
    "S8.1" => %{
      id: "S8.1",
      name: "Internal logical consistency",
      c_code: "C8",
      category: :argument,
      instructions:
        "Build a premise-to-conclusion map across aims, hypotheses, methods, results, discussion, and abstract. Find contradictions, unsupported leaps, unaddressed hypotheses, or mechanisms inconsistent with data while respecting hedged speculation."
    },
    "S8.2" => %{
      id: "S8.2",
      name: "Logical-fallacy detection",
      c_code: "C8",
      category: :argument,
      instructions:
        "Test for correlation-to-causation, post hoc reasoning, affirming the consequent, hasty generalization, authority, cherry-picking, base-rate neglect, survivorship bias, and moving goalposts. Name a fallacy only when the exact argument supports it."
    },
    "S8.3" => %{
      id: "S8.3",
      name: "Methodology and study design",
      c_code: "C8",
      category: :argument,
      instructions:
        "Judge design against the actual question and routed reporting guideline: sampling, eligibility, exposure/outcome validity, allocation/blinding, measurement, missingness, sensitivity analysis, protocol, ethics, and power. Apply discipline-appropriate standards."
    },
    "S8.4" => %{
      id: "S8.4",
      name: "Survey and instrument design",
      c_code: "C8",
      category: :argument,
      instructions:
        "When applicable, check instrument validation and reliability, question construction, scales, piloting, recall, response rates, mode effects, translation, missing items, and weights. Recognize validated instruments and non-survey designs."
    },
    "S8.5" => %{
      id: "S8.5",
      name: "Statistical models and regression",
      c_code: "C8",
      category: :argument,
      instructions:
        "Assess model-to-outcome fit, assumptions, functional form, interactions, multiplicity, missing-data method, selection, clustering, repeated measures, and instrumental-variable relevance and exclusion restriction. Recompute only what the manuscript makes identifiable; never inverse-solve hidden data."
    },
    "S8.6" => %{
      id: "S8.6",
      name: "Causal inference and confounding",
      c_code: "C8",
      category: :argument,
      instructions:
        "Check confounder rationale, colliders, mediators, selection, misclassification, E-values for estimate and nearest-null CI, negative controls, family designs, dose-response, exposure change, immortal time, and Table 2 interpretation. Do not assert a specific unmeasured confounder or bias magnitude beyond justified bounds."
    },
    "S8.7" => %{
      id: "S8.7",
      name: "Conclusion validity versus evidence",
      c_code: "C8",
      category: :argument,
      instructions:
        "Compare every conclusion and recommendation with design and result strength. Flag population or range extrapolation, causal wording from association, ignored limitations, unsupported policy claims, and spin while preserving appropriately hedged implications."
    },
    "S9.1" => %{
      id: "S9.1",
      name: "Journal fit and alternatives",
      c_code: "C9",
      category: :submission,
      instructions:
        "Research target-journal fit and grounded alternatives using current aims, scope, article types, audience, and recent issues. Date and source volatile impact, acceptance, fee, and turnaround facts; exclude predatory venues."
    },
    "S9.2" => %{
      id: "S9.2",
      name: "Submission requirements",
      c_code: "C9",
      category: :submission,
      instructions:
        "Extract current, sourced author requirements for structure, word/figure/table/reference limits, reporting guidelines, citation style, access options and fees, declarations, and portal. Record source URL and access date; never infer unstated requirements."
    },
    "S9.3" => %{
      id: "S9.3",
      name: "Cover-letter drafting",
      c_code: "C9",
      category: :submission,
      instructions:
        "Draft a restrained journal-specific cover letter from verified requirements and author metadata. Do not fabricate an editor, novelty claim, author detail, reviewer, exclusivity statement, or journal name; leave unknowns as explicit placeholders."
    }
  }

  @doc "All 30 specialties, keyed by id."
  def all, do: @specialties

  @doc "Fetch one specialty; raises on an unknown id."
  def fetch!(id), do: Map.fetch!(@specialties, id)

  @doc "The author-facing finding category for a specialty id."
  def category(id), do: fetch!(id).category

  @doc "Specialty count sanity check — must be 30."
  def count, do: map_size(@specialties)
end
