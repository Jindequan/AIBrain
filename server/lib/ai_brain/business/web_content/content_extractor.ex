defmodule AIBrain.Business.WebContent.ContentExtractor do
  @moduledoc """
  HTML content extraction and format conversion.

  Supports three output formats:
  - `text` — plain text, cleaned and truncated
  - `markdown` — converted from HTML to simplified markdown
  - `html` — cleaned HTML (scripts/styles/clutter removed)
  """

  @max_length 50_000

  @doc """
  Extract the page title from HTML.
  """
  def extract_title(html) do
    patterns = [
      ~r/<title[^>]*>(.*?)<\/title>/is,
      ~r/<h1[^>]*>(.*?)<\/h1>/is,
      ~r/<meta[^>]*property="og:title"[^>]*content="([^"]*)"/is
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html, capture: :all_but_first) do
        [title] ->
          title |> HtmlEntities.decode() |> String.trim()

        _ ->
          nil
      end
    end) || "Untitled"
  end

  @doc """
  Extract content from HTML in the specified format.
  """
  def extract(html, "text") do
    html
    |> remove_script_style()
    |> remove_clutter()
    |> extract_main_content()
    |> clean_text()
    |> limit_length()
  end

  def extract(html, "markdown") do
    html
    |> remove_script_style()
    |> remove_clutter()
    |> html_to_markdown()
    |> clean_text()
    |> limit_length()
  end

  def extract(html, "html") do
    html
    |> remove_script_style()
    |> remove_clutter()
    |> limit_length()
  end

  # -- Cleaning --

  def remove_script_style(html) do
    html
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/is, "")
    |> String.replace(~r/<!--.*?-->/s, "")
  end

  def remove_clutter(html) do
    clutter_patterns = [
      ~r/<nav[^>]*>.*?<\/nav>/is,
      ~r/<header[^>]*>.*?<\/header>/is,
      ~r/<footer[^>]*>.*?<\/footer>/is,
      ~r/<aside[^>]*>.*?<\/aside>/is,
      ~r/<div[^>]*class="[^"]*sidebar[^"]*"[^>]*>.*?<\/div>/is,
      ~r/<div[^>]*class="[^"]*advertisement[^"]*"[^>]*>.*?<\/div>/is,
      ~r/<div[^>]*id="[^"]*sidebar[^"]*"[^>]*>.*?<\/div>/is
    ]

    Enum.reduce(clutter_patterns, html, fn pattern, acc ->
      String.replace(acc, pattern, "")
    end)
  end

  defp extract_main_content(html) do
    main_patterns = [
      ~r/<main[^>]*>(.*?)<\/main>/is,
      ~r/<article[^>]*>(.*?)<\/article>/is,
      ~r/<div[^>]*class="[^"]*content[^"]*"[^>]*>(.*?)<\/div>/is,
      ~r/<div[^>]*id="[^"]*content[^"]*"[^>]*>(.*?)<\/div>/is
    ]

    Enum.find_value(main_patterns, fn pattern ->
      case Regex.run(pattern, html, capture: :all_but_first) do
        [content] when byte_size(content) > 500 -> content
        _ -> nil
      end
    end) || html
  end

  # -- HTML → Markdown Conversion --

  defp html_to_markdown(html) do
    html
    |> convert_headers()
    |> convert_paragraphs()
    |> convert_links()
    |> convert_lists()
    |> convert_code_blocks()
    |> convert_bold_italic()
    |> strip_tags()
  end

  defp convert_headers(html) do
    html
    |> String.replace(~r/<h1[^>]*>(.*?)<\/h1>/is, "# \\1\n")
    |> String.replace(~r/<h2[^>]*>(.*?)<\/h2>/is, "## \\1\n")
    |> String.replace(~r/<h3[^>]*>(.*?)<\/h3>/is, "### \\1\n")
    |> String.replace(~r/<h4[^>]*>(.*?)<\/h4>/is, "#### \\1\n")
    |> String.replace(~r/<h5[^>]*>(.*?)<\/h5>/is, "##### \\1\n")
    |> String.replace(~r/<h6[^>]*>(.*?)<\/h6>/is, "###### \\1\n")
  end

  defp convert_paragraphs(html) do
    html
    |> String.replace(~r/<p[^>]*>(.*?)<\/p>/is, "\\1\n\n")
    |> String.replace(~r/<br[^>]*>/is, "\n")
  end

  defp convert_links(html) do
    String.replace(html, ~r/<a[^>]*href="([^"]*)"[^>]*>(.*?)<\/a>/is, "[\\2](\\1)")
  end

  defp convert_lists(html) do
    html
    |> String.replace(~r/<ul[^>]*>/is, "")
    |> String.replace(~r/<\/ul>/is, "\n")
    |> String.replace(~r/<ol[^>]*>/is, "")
    |> String.replace(~r/<\/ol>/is, "\n")
    |> String.replace(~r/<li[^>]*>(.*?)<\/li>/is, "- \\1\n")
  end

  defp convert_code_blocks(html) do
    html
    |> String.replace(~r/<pre[^>]*><code[^>]*>(.*?)<\/code><\/pre>/is, "```\n\\1\n```\n")
    |> String.replace(~r/<code[^>]*>(.*?)<\/code>/is, "`\\1`")
  end

  defp convert_bold_italic(html) do
    html
    |> String.replace(~r/<strong[^>]*>(.*?)<\/strong>/is, "**\\1**")
    |> String.replace(~r/<b[^>]*>(.*?)<\/b>/is, "**\\1**")
    |> String.replace(~r/<em[^>]*>(.*?)<\/em>/is, "*\\1*")
    |> String.replace(~r/<i[^>]*>(.*?)<\/i>/is, "*\\1*")
  end

  defp strip_tags(html) do
    String.replace(html, ~r/<[^>]*>/, "")
  end

  # -- Shared --

  defp clean_text(text) do
    text
    |> HtmlEntities.decode()
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  defp limit_length(text, max_length \\ @max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length) <> "\n\n[Content truncated...]"
    else
      text
    end
  end
end
