defmodule AIBrain.Web.Handlers.FilesHandler do
  @moduledoc """
  Handles file upload and retrieval for multimodal (image) support.

  Files are stored at ~/.aibrain/uploads/<uuid>_<original_filename>.
  """

  import Plug.Conn

  @upload_dir Path.join(System.user_home!(), ".aibrain/uploads")

  def handle_upload(conn, params) do
    upload = params["file"]

    unless upload do
      json(conn, 400, %{error: "No file provided. Use 'file' field in multipart form."})
    else
      # Ensure upload directory exists
      File.mkdir_p!(@upload_dir)

      id = UUID.uuid4()
      ext = Path.extname(upload.filename)
      safe_name = "#{id}#{ext}"
      dest = Path.join(@upload_dir, safe_name)

      # Copy the temp upload to our storage
      case File.cp(upload.path, dest) do
        :ok ->
          content_type = upload.content_type || "application/octet-stream"
          size = File.stat!(dest).size

          json(conn, 200, %{
            id: id,
            url: "/api/v1/files/#{id}",
            filename: upload.filename,
            content_type: content_type,
            size: size
          })

        {:error, reason} ->
          json(conn, 500, %{error: "Failed to save file: #{reason}"})
      end
    end
  end

  def handle_get(conn, id) do
    # Sanitize to prevent path traversal
    safe_id = Path.basename(id)

    case find_upload(safe_id) do
      {:ok, path, content_type} ->
        case File.read(path) do
          {:ok, data} ->
            conn
            |> put_resp_content_type(content_type)
            |> put_resp_header("content-disposition", "inline")
            |> send_resp(200, data)

          {:error, _} ->
            json(conn, 404, %{error: "File not found"})
        end

      :error ->
        json(conn, 404, %{error: "File not found"})
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp find_upload(id) do
    case File.ls(@upload_dir) do
      {:ok, files} ->
        case Enum.find(files, &String.starts_with?(&1, id)) do
          nil ->
            :error

          name ->
            path = Path.join(@upload_dir, name)
            content_type = infer_content_type(name)
            {:ok, path, content_type}
        end

      {:error, _} ->
        :error
    end
  end

  defp infer_content_type(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".bmp" -> "image/bmp"
      ".pdf" -> "application/pdf"
      ".mp4" -> "video/mp4"
      ".mp3" -> "audio/mpeg"
      ".wav" -> "audio/wav"
      ".json" -> "application/json"
      ".txt" -> "text/plain"
      ".md" -> "text/markdown"
      ".csv" -> "text/csv"
      ".html" -> "text/html"
      ".js" -> "application/javascript"
      ".css" -> "text/css"
      ".zip" -> "application/zip"
      _other -> "application/octet-stream"
    end
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
