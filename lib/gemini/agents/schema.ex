defmodule Gemini.Agents.Schema do
  @moduledoc """
  The finding output schema, mirroring `Core.ReviewAgents.Finding.schema/1`.

  The `agent` enum is restricted to the specialty ids the execution owns, and
  the `category` enum to the author-facing categories those ids derive to —
  identity is enforced at generation time, not just checked afterward.
  Verification specs additionally carry the `overview` property.
  """

  alias Gemini.Agents.Specialties

  @severities ["major", "minor", "suggestion"]

  def findings_schema(specialty_ids, opts \\ []) do
    base = %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["findings"],
      "properties" => %{
        "findings" => %{
          "type" => "array",
          "items" => finding_item(specialty_ids)
        }
      }
    }

    if Keyword.get(opts, :overview, false) do
      put_in(base, ["properties", "overview"], %{
        "type" => "string",
        "description" =>
          "An editorial abstract of the whole review for the author: what it " <>
            "found overall, the dominant themes, and the most consequential " <>
            "verified issues. Three to five sentences, measured and scholarly."
      })
    else
      base
    end
  end

  defp finding_item(specialty_ids) do
    categories =
      specialty_ids
      |> Enum.map(&(&1 |> Specialties.category() |> Atom.to_string()))
      |> Enum.uniq()

    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => [
        "agent",
        "category",
        "subcategory",
        "title",
        "severity",
        "priority",
        "confidence",
        "anchor",
        "evidence",
        "explanation",
        "suggestion",
        "reporting_guideline_ref"
      ],
      "properties" => %{
        "agent" => %{"type" => "string", "enum" => specialty_ids},
        "category" => %{"type" => "string", "enum" => categories},
        "subcategory" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "severity" => %{"type" => "string", "enum" => @severities},
        "priority" => %{
          "type" => "string",
          "nullable" => true,
          "enum" => ["high", "medium", "low"]
        },
        "confidence" => %{"type" => "number", "minimum" => 0, "maximum" => 1},
        "anchor" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["block_id", "quote", "prefix", "suffix", "section"],
          "properties" => %{
            "block_id" => %{"type" => "string"},
            "quote" => %{"type" => "string"},
            "prefix" => %{"type" => "string"},
            "suffix" => %{"type" => "string"},
            "section" => %{"type" => "string"}
          }
        },
        "evidence" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["source", "id", "quote", "url"],
            "properties" => %{
              "source" => %{"type" => "string"},
              "id" => %{"type" => "string"},
              "quote" => %{"type" => "string"},
              "url" => %{"type" => "string"}
            }
          }
        },
        "explanation" => %{"type" => "string"},
        "suggestion" => %{"type" => "string", "nullable" => true},
        "reporting_guideline_ref" => %{"type" => "string", "nullable" => true}
      }
    }
  end
end
