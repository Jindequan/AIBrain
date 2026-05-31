defmodule AIBrain.LLM.SimpleChat do
  @moduledoc """
  Simple non-streaming LLM chat for background tasks (episodic distillation, reflections).

  Uses the default provider and collects a streaming response synchronously.
  """

  require Logger

  @timeout 60_000

  @doc """
  Send a prompt to the default LLM and return the full text response.

  Returns `{:ok, text}` on success, `{:error, reason}` on failure.
  """
  def call(prompt, opts \\ []) when is_binary(prompt) do
    case resolve_provider() do
      {:error, reason} ->
        {:error, reason}

      {:ok, provider} ->
        messages = [
          %{role: "system", content: Keyword.get(opts, :system, "You are a helpful assistant.")},
          %{role: "user", content: prompt}
        ]

        system = Keyword.get(opts, :system, "You are a helpful assistant.")

        case AIBrain.LLM.Client.stream(provider, messages, [],
               system: system,
               protocol: "openai",
               on_event: fn _ -> :ok end
             ) do
          {:ok, :streaming_complete} ->
            response = collect_response()
            {:ok, response}

          {:error, reason} ->
            Logger.error("SimpleChat: LLM stream failed: #{inspect(reason)}")
            {:error, reason}

          other ->
            Logger.error("SimpleChat: unexpected LLM response: #{inspect(other)}")
            {:error, :unexpected_response}
        end
    end
  rescue
    e ->
      Logger.error("SimpleChat: error: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp collect_response(acc \\ "") do
    receive do
      {:sse_event, {:text_delta, text}} -> collect_response(acc <> text)
      {:sse_event, {:stop, _reason}} -> acc
      {:sse_done} -> acc
    after
      @timeout -> acc
    end
  end

  defp resolve_provider do
    cheap_model = Application.get_env(:ai_brain, :smart_router, %{})[:cheap] || "default"

    try do
      case AIBrain.Provider.Router.select("openai", cheap_model) do
        {:ok, provider} ->
          {:ok, provider}

        {:error, _} ->
          case AIBrain.Provider.Router.all_providers() do
            [p | _] ->
              {:ok, p}

            _ ->
              Logger.warning("SimpleChat: no providers available")
              {:error, :no_providers}
          end
      end
    rescue
      e ->
        Logger.warning("SimpleChat: provider resolution failed: #{Exception.message(e)}")
        {:error, :provider_resolution_failed}
    end
  end
end
