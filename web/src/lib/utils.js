import { clsx } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs) {
  return twMerge(clsx(inputs))
}

export function formatDuration(ms) {
  if (!ms) return '—'
  if (ms < 1000) return `${ms}ms`
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`
  return `${Math.floor(ms / 60000)}m ${Math.floor((ms % 60000) / 1000)}s`
}

/**
 * Parse error message from backend API responses.
 * Handles various error formats:
 * - "inspect(changeset.errors)" format: `"title: {\"can't be blank\", []}"`
 * - Simple string: `"Session not found"`
 * - Object: `{ error: "message" }`
 * - Fallback: status code text
 */
export function parseApiError(error) {
  if (!error) return 'Unknown error'

  // Extract from Error object
  const message = typeof error === 'string' ? error : error?.message || error?.error || String(error)

  // Try to parse inspect format
  const inspectMatch = message.match(/^(\w+):\s*\{.*"(.+)".*\}$/)
  if (inspectMatch) {
    return `${inspectMatch[1]}: ${inspectMatch[2]}`
  }

  // Try to extract JSON error field
  if (typeof message === 'string' && message.startsWith('{')) {
    try {
      const parsed = JSON.parse(message)
      if (parsed.error) return parsed.error
    } catch { /* not JSON */ }
  }

  // Clean up common patterns
  return message
    .replace(/^Error:\s*/i, '')
    .replace(/^\d{3}\s+/, '')
    .trim()
}

/**
 * Extract field-level errors from inspect format
 * Returns { field: "error message" } or null
 */
export function parseFieldErrors(error) {
  if (!error) return null

  const message = typeof error === 'string' ? error : error?.message || error?.error
  if (!message) return null

  // Match patterns like: title: {"can't be blank", []} or multiple fields
  const fieldPattern = /(\w+):\s*\{.*?"([^"]+)".*?\}/g
  const fields = {}
  let match
  while ((match = fieldPattern.exec(message)) !== null) {
    fields[match[1]] = match[2]
  }

  return Object.keys(fields).length > 0 ? fields : null
}

/**
 * Format context window tokens to human-readable format (K/M/B)
 * Examples: 128000 -> "128K", 1048576 -> "1M", 2000000 -> "2M"
 */
export function formatNumber(tokens) {
  if (!tokens || tokens === 0) return '—'

  const abs = Math.abs(tokens)

  if (abs >= 1_000_000_000) {
    return (tokens / 1_000_000_000).toFixed(1).replace(/\.0$/, '') + 'B'
  }

  if (abs >= 1_000_000) {
    return (tokens / 1_000_000).toFixed(2).replace(/\.00$/, '').replace(/\.0$/, '') + 'M'
  }

  if (abs >= 1_000) {
    return (tokens / 1_000).toFixed(0) + 'K'
  }

  return tokens.toString()
}

/**
 * Format context window tokens to human-readable format (K/M/B)
 * @deprecated Use formatNumber instead
 */
export const formatContextWindow = formatNumber
