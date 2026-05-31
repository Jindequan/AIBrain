export function ChatStatusBar({ status }) {
  if (!status || status.type === 'error') return null

  return (
    <div className={`px-4 py-2 text-xs flex items-center gap-2 border-t border-card-border ${
      status.type === 'connecting'
        ? 'bg-accent/5 text-accent'
        : 'text-text-secondary'
    }`}>
      {status.type === 'connecting' && (
        <svg className="animate-spin h-3 w-3" viewBox="0 0 24 24">
          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none" />
          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
        </svg>
      )}
      <span>{status.text}</span>
    </div>
  )
}
