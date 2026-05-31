defmodule AIBrain.Business.WebContent.UrlValidator do
  @moduledoc """
  URL validation with SSRF protection.

  Blocks private/internal IP addresses, non-HTTP schemes,
  and malformed URLs.
  """

  @doc """
  Validate a URL for safe fetching.

  Checks:
  1. Scheme is http or https
  2. Host is present
  3. Host is not a private/internal address

  Returns `:ok` or `{:error, reason}`.
  """
  def validate(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme not in ["http", "https"] ->
        {:error, "URL blocked: only http/https allowed"}

      %URI{host: nil} ->
        {:error, "URL blocked: missing host"}

      %URI{host: host} ->
        if private_host?(host) do
          {:error, "URL blocked: private/internal address not allowed (#{host})"}
        else
          :ok
        end
    end
  end

  def valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] ->
        host != nil and String.length(host) > 0

      _ ->
        false
    end
  end

  # -- Private Host Detection --

  defp private_host?(host) do
    host = String.downcase(host)

    cond do
      host in ~w(localhost 127.0.0.1 ::1 0.0.0.0) -> true
      String.starts_with?(host, "192.168.") -> true
      String.starts_with?(host, "10.") -> true
      String.starts_with?(host, "172.") -> in_172_range?(host)
      # Cloud metadata endpoints (AWS/GCP/Azure)
      String.starts_with?(host, "169.254.") -> true
      String.starts_with?(host, "100.64.") -> true
      # IPv6 private ranges
      String.starts_with?(host, "fc") -> true
      String.starts_with?(host, "fd") -> true
      String.starts_with?(host, "fe80:") -> true
      # Local TLDs
      String.ends_with?(host, ".local") -> true
      String.ends_with?(host, ".internal") -> true
      String.ends_with?(host, ".localhost") -> true
      # Numeric host with no dots (e.g. "0")
      Regex.match?(~r/^\d+$/, host) -> true
      true -> false
    end
  end

  defp in_172_range?(host) do
    case String.split(host, ".") do
      ["172", second | _] ->
        case Integer.parse(second) do
          {n, ""} -> n >= 16 and n <= 31
          _ -> false
        end

      _ ->
        false
    end
  end
end
