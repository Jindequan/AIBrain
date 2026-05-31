defmodule AIBrain.Web.Handlers.FsHandler do
  import Plug.Conn

  @sensitive_patterns [
    ~r"/\.ssh/",
    ~r"/\.gnupg/",
    ~r"/\.aws/",
    ~r"/\.config/gh/",
    ~r"/\.docker/",
    ~r"/etc/(shadow|passwd|sudoers|master\.passwd)",
    ~r"/var/root/",
    ~r"/private/etc/",
    ~r"/\.env$",
    ~r"/\.netrc$",
    ~r"/\.git-credentials$",
    ~r"/\.pgpass$"
  ]

  def handle_list(conn) do
    raw_path = conn.query_params["path"] || System.user_home!()
    path = Path.expand(raw_path)

    cond do
      has_parent_component?(raw_path) ->
        forbidden(conn, "Path traversal detected")

      sensitive_path?(path) ->
        forbidden(conn, "Access to this path is restricted")

      not allowed_root?(path) ->
        send_fallback_list(conn, raw_path)

      true ->
        case File.ls(path) do
          {:ok, _entries} ->
            result = %{
              path: path,
              parent:
                if(path == "/" or path == System.user_home!(),
                  do: nil,
                  else: Path.dirname(path)
                ),
              dirs: list_dirs(path),
              files: list_files(path)
            }

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(result))

          {:error, _reason} ->
            send_fallback_list(conn, raw_path)
        end
    end
  end

  defp send_fallback_list(conn, raw_path) do
    fallback = System.user_home!()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        path: fallback,
        parent: nil,
        dirs: list_dirs(fallback),
        files: list_files(fallback),
        fallback: true,
        original_path: raw_path
      })
    )
  end

  defp sensitive_path?(path) do
    Enum.any?(@sensitive_patterns, fn pattern ->
      String.match?(path, pattern)
    end)
  end

  defp allowed_root?(path) do
    normalized_path = if String.ends_with?(path, "/"), do: path, else: path <> "/"

    home = System.user_home!() <> "/"
    workspace = Application.get_env(:ai_brain, :workspace_path)
    workspace_root = if is_binary(workspace), do: workspace <> "/", else: nil

    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain")) <> "/"

    String.starts_with?(normalized_path, home) or
      (is_binary(workspace_root) and String.starts_with?(normalized_path, workspace_root)) or
      String.starts_with?(normalized_path, data_dir)
  end

  defp has_parent_component?(path) do
    path
    |> Path.split()
    |> Enum.any?(fn component ->
      component == ".."
    end)
  end

  defp list_dirs(path) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn e -> File.dir?(Path.join(path, e)) end)
        |> Enum.reject(fn e -> String.starts_with?(e, ".") end)
        |> Enum.sort()
        |> Enum.map(fn name -> %{name: name, path: Path.join(path, name)} end)

      _ ->
        []
    end
  end

  defp list_files(path) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn e -> not File.dir?(Path.join(path, e)) end)
        |> Enum.reject(fn e -> String.starts_with?(e, ".") end)
        |> Enum.sort()
        |> Enum.flat_map(fn name ->
          full = Path.join(path, name)

          case File.stat(full, time: :posix) do
            {:ok, stat} -> [%{name: name, path: full, size: stat.size}]
            {:error, _} -> []
          end
        end)

      _ ->
        []
    end
  end

  # 5 MB limit for file reads
  @max_read_size 5 * 1024 * 1024

  def handle_read(conn) do
    raw_path = conn.query_params["path"]

    cond do
      is_nil(raw_path) or raw_path == "" ->
        send_resp(conn, 400, Jason.encode!(%{error: "Missing path parameter"}))

      true ->
        path = Path.expand(raw_path)

        cond do
          has_parent_component?(raw_path) ->
            forbidden(conn, "Path traversal detected")

          sensitive_path?(path) ->
            forbidden(conn, "Access to this path is restricted")

          not allowed_root?(path) ->
            forbidden(conn, "Path is outside allowed directories")

          not File.exists?(path) ->
            send_resp(conn, 404, Jason.encode!(%{error: "File not found"}))

          File.dir?(path) ->
            send_resp(conn, 400, Jason.encode!(%{error: "Path is a directory"}))

          true ->
            stat = File.stat!(path, time: :posix)

            if stat.size > @max_read_size do
              send_resp(
                conn,
                413,
                Jason.encode!(%{
                  error: "File too large (max #{div(@max_read_size, 1024 * 1024)} MB)"
                })
              )
            else
              case File.read(path) do
                {:ok, content} ->
                  content_type = mime_type(path)

                  conn
                  |> put_resp_content_type(content_type)
                  |> send_resp(200, content)

                {:error, reason} ->
                  send_resp(conn, 500, Jason.encode!(%{error: to_string(reason)}))
              end
            end
        end
    end
  end

  defp mime_type(path) do
    case Path.extname(path) |> String.downcase() do
      ".md" -> "text/markdown; charset=utf-8"
      ".json" -> "application/json; charset=utf-8"
      ".pdf" -> "application/pdf"
      ".html" -> "text/html; charset=utf-8"
      ".css" -> "text/css; charset=utf-8"
      ".js" -> "text/javascript; charset=utf-8"
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".svg" -> "image/svg+xml"
      ".txt" -> "text/plain; charset=utf-8"
      ".yaml" -> "text/plain; charset=utf-8"
      ".yml" -> "text/plain; charset=utf-8"
      ".toml" -> "text/plain; charset=utf-8"
      ".ex" -> "text/plain; charset=utf-8"
      ".exs" -> "text/plain; charset=utf-8"
      _ -> "application/octet-stream"
    end
  end

  defp forbidden(conn, msg) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(403, Jason.encode!(%{error: msg}))
  end
end
