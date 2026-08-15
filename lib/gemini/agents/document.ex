defmodule Gemini.Agents.Document do
  @moduledoc """
  The manuscript input every agent consumes, cached by default.

  `prepare/2` accepts raw text, a PDF path, or PDF bytes and returns a
  `%Document{}` that every agent's `run/2` / `start/2` takes directly. PDFs
  are uploaded to the Files API **once per unique content hash** and memoized
  process-wide (`:persistent_term`), so a review that fans out across all 16
  execution agents performs one upload, not sixteen.

  What this cache is and is not, measured:

    * It reuses **bytes** — upload time, bandwidth, request size. Every agent
      call still re-tokenizes the document at full input-token price
      (`cached: 0` on Interactions, always).
    * The token-discounting Context Cache is `generateContent`-only — the
      Interactions API silently drops `cached_content` — and a cache is bound
      to one model while these agents span four. It is therefore not wired
      here; if a single-model, many-question workload emerges, use
      `Gemini.APIs.ContextCache` with `Gemini.generate/2` directly.

  Uploads expire server-side after 48 hours; the memo re-uploads past a
  47-hour safety margin. A deleted or expired file surfaces as
  `403 permission_denied` on the next agent call — call `prepare/2` again.
  """

  alias Gemini.APIs.Files

  @enforce_keys [:sha]
  defstruct [:sha, :text, :file_uri, :file_name, :mime_type, :uploaded_at]

  @memo_prefix {__MODULE__, :memo}
  @reupload_after_s 47 * 3600

  @doc """
  Prepare a document for the agent fleet.

    * binary text → held inline (no upload; text is cheap and groundable)
    * `{:pdf, path}` → Files upload, memoized by content SHA-256
    * `{:pdf_binary, bytes, display_name}` → same, for already-loaded bytes
  """
  def prepare(source, opts \\ [])

  def prepare(text, _opts) when is_binary(text) do
    %__MODULE__{sha: sha(text), text: text}
  end

  def prepare({:pdf, path}, opts) do
    prepare({:pdf_binary, File.read!(path), Path.basename(path)}, opts)
  end

  def prepare({:pdf_binary, bytes, display_name}, opts) do
    key = sha(bytes)

    case lookup(key) do
      %__MODULE__{} = doc ->
        doc

      nil ->
        {:ok, file} =
          Files.upload_data(bytes,
            mime_type: "application/pdf",
            display_name: display_name,
            auth: Keyword.get(opts, :auth, :gemini)
          )

        doc = %__MODULE__{
          sha: key,
          file_uri: file.uri,
          file_name: file.name,
          mime_type: "application/pdf",
          uploaded_at: System.system_time(:second)
        }

        :persistent_term.put({@memo_prefix, key}, doc)
        doc
    end
  end

  @doc "The Interactions content blocks for this document."
  def to_input(%__MODULE__{text: text}) when is_binary(text) do
    [%{"type" => "text", "text" => "MANUSCRIPT:\n\n" <> text}]
  end

  def to_input(%__MODULE__{file_uri: uri, mime_type: mime}) when is_binary(uri) do
    [%{"type" => "document", "uri" => uri, "mime_type" => mime}]
  end

  @doc "Drop the memo entry and delete the upload server-side."
  def release(%__MODULE__{sha: key, file_name: name}) do
    :persistent_term.erase({@memo_prefix, key})
    if name, do: Files.delete(name, auth: :gemini), else: :ok
  end

  defp lookup(key) do
    case :persistent_term.get({@memo_prefix, key}, nil) do
      %__MODULE__{uploaded_at: at} = doc
      when is_integer(at) ->
        if System.system_time(:second) - at < @reupload_after_s do
          doc
        else
          :persistent_term.erase({@memo_prefix, key})
          nil
        end

      _ ->
        nil
    end
  end

  defp sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
