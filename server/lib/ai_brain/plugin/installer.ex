defmodule AIBrain.Plugin.Installer do
  @moduledoc """
  Install, update, and uninstall plugins from remote URLs or GitHub releases.

  Plugins are distributed as tarballs (.tar.gz) containing:
    * `plugin.json` — manifest
    * `lib/` — tool modules (optional)

  ## Usage

      AIBrain.Plugin.Installer.install("https://github.com/aibrain/plugin-tts/releases/latest/download/plugin.tar.gz")
      AIBrain.Plugin.Installer.uninstall("tts")
  """

  require Logger

  alias AIBrain.Plugin.Registry

  @doc """
  Install a plugin from a URL.

  Downloads the tarball, extracts it, validates the manifest,
  and registers with the Plugin Registry.

  ## Examples

      {:ok, spec} = AIBrain.Plugin.Installer.install("https://github.com/.../plugin.tar.gz")
      {:error, reason} = AIBrain.Plugin.Installer.install("invalid-url")
  """
  def install(url) when is_binary(url) do
    with {:ok, tmp_dir} <- download_and_extract(url),
         manifest_path = Path.join(tmp_dir, "plugin.json"),
         true <- File.exists?(manifest_path),
         {:ok, spec} <- Registry.install(manifest_path) do
      cleanup(tmp_dir)
      {:ok, spec}
    else
      false -> {:error, "plugin.json not found in package"}
      {:error, reason} -> {:error, reason}
      other -> {:error, inspect(other)}
    end
  end

  @doc """
  Install a plugin from a local directory path.
  Useful for development or bundled plugins.
  """
  def install_local(path) when is_binary(path) do
    manifest_path = Path.join(path, "plugin.json")

    if File.exists?(manifest_path) do
      Registry.install(manifest_path)
    else
      {:error, "plugin.json not found at #{path}"}
    end
  end

  @doc """
  Uninstall a plugin by name.
  """
  def uninstall(name) when is_binary(name) do
    Registry.uninstall(Registry, name)
  end

  @doc """
  Re-pull a plugin from its repository URL and re-install.
  """
  def update(name) when is_binary(name) do
    case Registry.get(Registry, name) do
      {:ok, %{repository: url}} when is_binary(url) ->
        Registry.uninstall(Registry, name)
        install(url)

      {:ok, _} ->
        {:error, "Plugin has no repository URL configured"}

      {:error, :not_found} ->
        {:error, "Plugin not found: #{name}"}
    end
  end

  @doc """
  Register a built-in plugin that ships with the application.
  These live in `priv/plugins/<name>/` and are auto-registered at startup.
  """
  def register_builtin(name) when is_binary(name) do
    builtin_path = builtin_plugins_path()
    plugin_path = Path.join(builtin_path, name)

    if File.exists?(Path.join(plugin_path, "plugin.json")) do
      install_local(plugin_path)
    else
      {:error, "builtin plugin not found: #{name}"}
    end
  end

  @doc """
  Register all built-in plugins that haven't been installed yet.
  """
  def register_all_builtin do
    builtin_path = builtin_plugins_path()
    plugins_dir = plugins_dir()

    if File.dir?(builtin_path) do
      builtin_path
      |> File.ls!()
      |> Enum.each(fn name ->
        # Skip if already installed from a previous startup
        existing_path = Path.join(plugins_dir, name)

        if File.exists?(Path.join(existing_path, "plugin.json")) do
          :skip
        else
          case register_builtin(name) do
            {:ok, spec} ->
              Logger.info("Registered builtin plugin: #{spec.name} v#{spec.version}")

            {:error, reason} ->
              Logger.warning("Failed to register builtin plugin #{name}: #{reason}")
          end
        end
      end)
    end
  end

  # ── Private ──

  defp builtin_plugins_path do
    Application.app_dir(:ai_brain, "priv/plugins")
  end

  defp plugins_dir do
    data_dir =
      Application.get_env(:ai_brain, :data_dir, Path.join(System.user_home!(), ".aibrain"))

    Path.join(data_dir, "plugins")
  end

  defp download_and_extract(url) do
    tmp_dir = Path.join(System.tmp_dir!(), "plugin_#{:erlang.unique_integer([:positive])}")
    archive_path = tmp_dir <> ".tar.gz"

    try do
      with {:ok, body} <- download(url),
           :ok <- File.write(archive_path, body),
           {:ok, _} <- extract_tar(archive_path, tmp_dir) do
        {:ok, tmp_dir}
      end
    after
      File.rm(archive_path)
    end
  end

  defp download(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, "download failed: #{inspect(reason)}"}
    end
  end

  defp extract_tar(archive, dest) do
    case :erl_tar.extract(String.to_charlist(archive), [
           :compressed,
           {:cwd, String.to_charlist(dest)}
         ]) do
      :ok -> {:ok, dest}
      {:error, reason} -> {:error, "extraction failed: #{inspect(reason)}"}
    end
  end

  defp cleanup(tmp_dir) do
    File.rm_rf(tmp_dir)
  end
end
