defmodule AIBrain.Automation.Browser do
  require Logger

  @moduledoc """
  Browser automation using Puppeteer via Node.js.

  ## Capability detection

  Checks at runtime whether Puppeteer is available. If not, returns a clear error
  guiding the user to install it (`npm install puppeteer`).
  """

  @script_path Application.app_dir(:ai_brain, "priv/automation/puppeteer.mjs")

  @doc "Take a screenshot of a URL."
  def screenshot(url, opts \\ []) do
    selector = Keyword.get(opts, :selector)
    args = [if(selector, do: ["screenshot", url, selector], else: ["screenshot", url])]

    with :ok <- check_available(),
         {:ok, result} <- run_node(args) do
      {:ok, result}
    end
  end

  @doc "Extract text content from a page."
  def extract_text(url, opts \\ []) do
    selector = Keyword.get(opts, :selector)
    args = [if(selector, do: ["extract", url, selector], else: ["extract", url])]

    with :ok <- check_available(),
         {:ok, result} <- run_node(args) do
      {:ok, result}
    end
  end

  @doc "Fill form fields on a page."
  def fill_form(url, fields) when is_map(fields) do
    with :ok <- check_available(),
         {:ok, result} <- run_node(["fill", url, Jason.encode!(fields)]) do
      {:ok, result}
    end
  end

  @doc "Click an element on a page."
  def click(url, selector) do
    with :ok <- check_available(),
         {:ok, result} <- run_node(["click", url, selector]) do
      {:ok, result}
    end
  end

  @doc "Check if Puppeteer is available."
  def available? do
    System.find_executable("node") != nil and script_exists?()
  rescue
    e ->
      Logger.warning("Browser available? check error: #{Exception.message(e)}")
      false
  end

  @doc "Check if the Puppeteer npm package is installed."
  def puppeteer_installed? do
    case System.cmd("node", ["-e", "require('puppeteer'); console.log('ok')"]) do
      {"ok\n", 0} -> true
      _ -> false
    end
  rescue
    e ->
      Logger.warning("Puppeteer installed? check error: #{Exception.message(e)}")
      false
  end

  defp check_available do
    cond do
      System.find_executable("node") == nil ->
        {:error, "Node.js not found. Install Node.js to use browser automation."}

      not script_exists?() ->
        {:error, "Puppeteer script not found at #{@script_path}"}

      not puppeteer_installed?() ->
        {:error,
         "Puppeteer not installed. Run: cd #{Path.dirname(@script_path)} && npm install puppeteer"}

      true ->
        :ok
    end
  end

  defp run_node(args) do
    case System.cmd("node", [@script_path | args], stderr_to_stdout: true, timeout: 60_000) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, %{"ok" => true} = data} ->
            {:ok, Map.delete(data, "ok")}

          {:ok, %{"ok" => false, "error" => error}} ->
            {:error, error}

          {:ok, other} ->
            {:ok, other}

          {:error, reason} ->
            {:error, "Failed to parse automation output: #{inspect(reason)}"}
        end

      {output, _} ->
        {:error, "Node.js script failed: #{String.trim(output)}"}
    end
  rescue
    ArgumentError ->
      {:error, "Browser automation timed out after 60s"}

    e ->
      {:error, "Browser automation error: #{inspect(e)}"}
  end

  defp script_exists? do
    File.exists?(@script_path)
  end
end
