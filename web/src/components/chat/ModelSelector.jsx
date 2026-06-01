import { useState, useEffect, useRef } from "react"
import { ChevronDown, Brain } from "lucide-react"
import { formatNumber, cn } from "../../lib/utils"

function groupByProvider(models) {
  const groups = {}
  for (const m of models) {
    const p = m.provider || "unknown"
    if (!groups[p]) groups[p] = []
    groups[p].push(m)
  }
  return groups
}

/**
 * ModelSelector — compact dropdown to pick which model to use.
 * Uses ReqLLM model spec format: "provider:model"
 *
 * Props:
 *   models: { provider, name, context_window, max_output_tokens, ... }[]
 *   selectedModelSpec?: string — "provider:model" format
 *   onSelect: (modelSpec: string) => void
 */
export default function ModelSelector({ models = [], selectedModelSpec, onSelect }) {
  const [open, setOpen] = useState(false)
  const ref = useRef(null)

  useEffect(() => {
    function handleClick(e) {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false)
    }
    document.addEventListener("mousedown", handleClick)
    return () => document.removeEventListener("mousedown", handleClick)
  }, [])

  const enabled = models.filter(m => m.enabled !== false)
  const grouped = groupByProvider(enabled)

  // Extract model name from spec for display
  const currentLabel = selectedModelSpec
    ? selectedModelSpec.includes(":") ? selectedModelSpec.split(":")[1] : selectedModelSpec
    : "Auto"

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        onClick={() => setOpen(v => !v)}
        className={cn(
          "flex items-center gap-1 px-2 py-1 rounded-full text-[10px] font-medium transition-colors border",
          selectedModelSpec
            ? "bg-accent/10 text-accent border-accent/30"
            : "bg-gray-100 dark:bg-gray-800 text-text-muted border-gray-200 dark:border-gray-700 hover:border-accent/30"
        )}
      >
        <Brain className="w-3 h-3" />
        <span className="truncate max-w-[100px]">{currentLabel}</span>
        <ChevronDown className={cn("w-2.5 h-2.5 transition-transform", open && "rotate-180")} />
      </button>

      {open && (
        <div className="absolute bottom-full mb-1 left-0 w-72 max-h-80 overflow-y-auto rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 shadow-xl z-50">
          {Object.entries(grouped).length === 0 && (
            <div className="px-3 py-4 text-xs text-text-muted text-center">No models enabled</div>
          )}
          {Object.entries(grouped).map(([provider, providerModels]) => (
            <div key={provider}>
              <div className="px-3 py-1.5 text-[10px] font-semibold uppercase tracking-wider text-text-muted bg-gray-50 dark:bg-gray-800/50 sticky top-0">
                {provider}
              </div>
              {providerModels.map(m => {
                const modelSpec = `${provider}:${m.id}`
                const isSelected = modelSpec === selectedModelSpec
                return (
                  <button
                    key={modelSpec}
                    type="button"
                    onClick={() => { onSelect(modelSpec); setOpen(false) }}
                    className={cn(
                      "w-full text-left px-3 py-2 text-xs hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors",
                      isSelected && "bg-accent/5"
                    )}
                  >
                    <div className="flex items-center justify-between">
                      <span className={cn("font-medium", isSelected ? "text-accent" : "text-text-primary")}>
                        {m.name}
                      </span>
                      {isSelected && (
                        <span className="text-[10px] text-accent font-medium">on</span>
                      )}
                    </div>
                    <div className="flex items-center gap-2 mt-0.5 text-[11px] text-text-muted">
                      {m.context_window != null && <span>ctx: {formatNumber(m.context_window)}</span>}
                      {m.max_output_tokens != null && <span>out: {formatNumber(m.max_output_tokens)}</span>}
                    </div>
                  </button>
                )
              })}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
