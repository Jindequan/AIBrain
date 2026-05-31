import { useState, memo } from 'react'
import { ChevronDown, ChevronRight, Brain } from 'lucide-react'

export const ThinkingBlock = memo(function ThinkingBlock({ text, streaming }) {
  const [open, setOpen] = useState(false)

  return (
    <div className="my-1 rounded-xl border border-card-border bg-amber-50/40 text-xs overflow-hidden">
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-2 w-full px-3 py-2 text-left text-text-muted hover:text-text-primary hover:bg-amber-50/60 transition-colors"
      >
        <Brain className="w-3.5 h-3.5 shrink-0 text-amber-500" />
        <span className="font-medium">
          {!text && streaming ? 'Thinking…' : open ? 'Thinking' : `Thought (${text.length} chars)`}
        </span>
        {open ? (
          <ChevronDown className="w-3 h-3 ml-auto" />
        ) : (
          <ChevronRight className="w-3 h-3 ml-auto" />
        )}
      </button>
      {open && text && (
        <div className="border-t border-card-border px-3 py-2">
          <div className="text-xs text-text-secondary leading-relaxed whitespace-pre-wrap">{text}</div>
        </div>
      )}
    </div>
  )
})
