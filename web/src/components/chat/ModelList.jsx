import { cn, formatNumber } from "../../lib/utils"
import { Brain, ImageIcon, Mic, Video, Check, Settings } from "lucide-react"

const TYPE_ICONS = { text: Brain, image: ImageIcon, audio: Mic, video: Video }
const TYPE_COLORS = { text: "bg-blue-100 text-blue-700", image: "bg-purple-100 text-purple-700", audio: "bg-orange-100 text-orange-700", video: "bg-pink-100 text-pink-700" }

function TypeBadge({ type }) {
  const Icon = TYPE_ICONS[type] || Settings
  return (
    <span className={cn("inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-xs font-medium", TYPE_COLORS[type] || "bg-gray-100 text-gray-700")}>
      <Icon className="w-3 h-3" />
      {type}
    </span>
  )
}

/**
 * ModelList — unified model display component.
 *
 * Used by ProvidersPage (with enable/disable toggles) and ModelSelector (single-select).
 *
 * Props:
 *   models: { [modelName]: ModelInfo } — the provider's models map
 *   providerName: string — the provider name
 *   selected?: string — currently selected model name (for single-select)
 *   onSelect?: (modelName: string) => void
 *   showToggle?: boolean — show enable/disable checkboxes
 *   onToggle?: (modelName: string, enabled: boolean) => void
 */
export default function ModelList({ models, providerName, selected, onSelect, showToggle, onToggle }) {
  const entries = Object.entries(models || {})
  if (entries.length === 0) return null

  return (
    <div className="space-y-1">
      {entries.map(([name, meta]) => {
        const isSelected = selected === name
        const types = meta.types || [meta.type || "text"]
        const ctx = meta.context_window
        const maxOut = meta.max_output_tokens

        return (
          <button
            key={name}
            type="button"
            onClick={() => onSelect?.(name)}
            className={cn(
              "w-full text-left px-3 py-2 rounded-lg border transition-colors",
              isSelected
                ? "border-accent/50 bg-accent/5 ring-1 ring-accent/20"
                : "border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600",
              onSelect ? "cursor-pointer" : "cursor-default"
            )}
          >
            <div className="flex items-center justify-between gap-2">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-sm font-medium text-text-primary truncate">{name}</span>
                  {types.map(t => <TypeBadge key={t} type={t} />)}
                </div>
                <div className="flex items-center gap-3 mt-1 text-xs text-text-muted">
                  {ctx != null && <span>context: {formatNumber(ctx)}</span>}
                  {maxOut != null && <span>output: {formatNumber(maxOut)}</span>}
                  {meta.description && meta.description !== name && (
                    <span className="truncate">{meta.description}</span>
                  )}
                </div>
              </div>
              {showToggle && (
                <button
                  type="button"
                  onClick={e => { e.stopPropagation(); onToggle?.(name, !meta.enabled) }}
                  className={cn(
                    "shrink-0 w-5 h-5 rounded border-2 flex items-center justify-center transition-colors",
                    meta.enabled
                      ? "bg-accent border-accent text-white"
                      : "border-gray-300 dark:border-gray-600"
                  )}
                >
                  {meta.enabled && <Check className="w-3 h-3" />}
                </button>
              )}
            </div>
          </button>
        )
      })}
    </div>
  )
}
