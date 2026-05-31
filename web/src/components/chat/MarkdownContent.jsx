import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import remarkMath from 'remark-math'
import remarkBreaks from 'remark-breaks'
import rehypeKatex from 'rehype-katex'
import { useState, memo, useCallback } from 'react'
import { LazyCodeBlock } from './LazyCodeBlock'
import 'katex/dist/katex.min.css'

// ─── Inline Code ──────────────────────────────────────────────

function InlineCode({ children }) {
  return (
    <code className="px-1.5 py-0.5 rounded-md bg-gray-100 text-[#7c3aed] font-mono text-[0.85em] border border-gray-200 break-words">
      {children}
    </code>
  )
}

// ─── Copy Button ──────────────────────────────────────────────

function CopyButton({ text }) {
  const [copied, setCopied] = useState(false)
  const copy = useCallback(() => {
    navigator.clipboard.writeText(text).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }, [text])
  return (
    <button
      onClick={copy}
      aria-label="Copy code"
      className="px-2 py-0.5 rounded-lg text-[10px] font-medium bg-white/10 hover:bg-white/20 text-gray-300 hover:text-white transition-colors"
    >
      {copied ? 'Copied!' : 'Copy'}
    </button>
  )
}

// ─── Helpers ──────────────────────────────────────────────────

function extractText(node) {
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (node == null) return ''
  if (Array.isArray(node)) return node.map(extractText).join('')
  // React element
  if (node.props) return extractText(node.props.children)
  return ''
}

function countLines(text) {
  if (!text) return 0
  return text.split('\n').length
}

// ─── Code Block ───────────────────────────────────────────────

function CodeBlock({ className, children }) {
  const [wrapLines, setWrapLines] = useState(false)
  const lang = (className || '').replace('language-', '') || ''
  const rawText = extractText(children).replace(/\n$/, '')
  const lineCount = countLines(rawText)

  const codeBlock = (
    <div className="relative my-2 rounded-2xl overflow-hidden border border-gray-200 shadow-card">
      <div className="flex items-center justify-between px-3 py-1.5 bg-gray-800 border-b border-gray-700">
        <div className="flex items-center gap-2 text-[10px]">
          <span className="font-mono font-medium text-gray-300">{lang || 'code'}</span>
          {lineCount > 1 && <span className="text-gray-500">{lineCount} lines</span>}
          {rawText.length > 10000 && (
            <span className="text-amber-400/80">{(rawText.length / 1024).toFixed(1)} KB</span>
          )}
        </div>
        <div className="flex items-center gap-1.5">
          <button
            onClick={() => setWrapLines(v => !v)}
            className="px-1.5 py-0.5 rounded text-[10px] text-gray-400 hover:text-white hover:bg-white/10 transition-colors"
            title={wrapLines ? 'Disable word wrap' : 'Enable word wrap'}
          >
            {wrapLines ? 'No wrap' : 'Wrap'}
          </button>
          <CopyButton text={rawText} />
        </div>
      </div>
      <div className={`bg-gray-900 text-gray-100 text-xs leading-relaxed font-mono ${wrapLines ? '' : 'overflow-x-auto'}`}>
        <pre className={`p-3 m-0 ${wrapLines ? 'whitespace-pre-wrap break-all' : ''}`}>
          <code className={className}>{children}</code>
        </pre>
      </div>
    </div>
  )

  if (rawText.length > 2000) {
    return <LazyCodeBlock lang={lang} rawText={rawText}>{codeBlock}</LazyCodeBlock>
  }
  return codeBlock
}

// ─── Table ────────────────────────────────────────────────────

function Table({ children }) {
  return (
    <div className="my-2 overflow-x-auto rounded-xl border border-card-border shadow-card">
      <table className="w-full text-sm border-collapse">{children}</table>
    </div>
  )
}

// ─── Image ────────────────────────────────────────────────────

function LazyImage({ src, alt }) {
  const [loaded, setLoaded] = useState(false)
  const [error, setError] = useState(false)
  if (error) {
    return (
      <div className="my-2 rounded-xl border border-red-200 bg-red-50 p-4 text-center text-xs text-red-500">
        Failed to load image: {alt || src}
      </div>
    )
  }
  return (
    <div className="relative my-2">
      {!loaded && (
        <div className="rounded-xl border border-card-border bg-gray-50 animate-pulse" style={{ aspectRatio: '16/9', maxHeight: 400 }} />
      )}
      <img
        src={src}
        alt={alt}
        loading="lazy"
        onLoad={() => setLoaded(true)}
        onError={() => setError(true)}
        className={`max-w-full rounded-xl border border-card-border transition-opacity duration-200 ${loaded ? 'opacity-100' : 'opacity-0 absolute inset-0'}`}
      />
    </div>
  )
}

// ─── Component map ────────────────────────────────────────────

const components = {
  // Headings
  h1: ({ children }) => <h1 className="text-xl font-bold text-text-primary mt-3 mb-2 pb-1 border-b border-card-border">{children}</h1>,
  h2: ({ children }) => <h2 className="text-lg font-bold text-text-primary mt-2 mb-1.5">{children}</h2>,
  h3: ({ children }) => <h3 className="text-base font-semibold text-text-primary mt-2 mb-1">{children}</h3>,
  h4: ({ children }) => <h4 className="text-sm font-semibold text-text-primary mt-1.5 mb-1">{children}</h4>,

  // Paragraph
  p: ({ children }) => <p className="text-text-primary leading-relaxed mb-2 last:mb-0">{children}</p>,

  // Bold / italic
  strong: ({ children }) => <strong className="font-semibold text-text-primary">{children}</strong>,
  em: ({ children }) => <em className="italic text-text-secondary">{children}</em>,

  // Links
  a: ({ href, children }) => (
    <a href={href} target="_blank" rel="noopener noreferrer" className="text-accent underline underline-offset-2 hover:text-accent/80 transition-colors">
      {children}
    </a>
  ),

  // Code
  code: ({ inline, className, children }) => {
    // rehype-highlight AST transforms can corrupt the inline flag.
    // Inline code never has a language- class — use that as reliable fallback.
    if (inline || !className?.startsWith('language-')) return <InlineCode>{children}</InlineCode>
    return <CodeBlock className={className} children={children} />
  },

  // Override pre — our CodeBlock handles the wrapper
  pre: ({ children }) => <>{children}</>,

  // Blockquote
  blockquote: ({ children }) => (
    <blockquote className="my-2 pl-3 border-l-4 border-accent-gold/60 bg-amber-50/50 rounded-r-lg py-1.5 pr-2 text-text-secondary italic">
      {children}
    </blockquote>
  ),

  // Lists
  ul: ({ children }) => <ul className="my-1.5 pl-4 space-y-0.5 list-disc marker:text-text-muted">{children}</ul>,
  ol: ({ children }) => <ol className="my-1.5 pl-4 space-y-0.5 list-decimal marker:text-text-muted">{children}</ol>,
  li: ({ children }) => <li className="text-text-primary leading-relaxed">{children}</li>,

  // Task list (GFM checkbox)
  // remark-gfm renders checked/unchecked items as <li className="task-list-item">
  // We cannot intercept task items separately, so we apply via CSS in markdown-body
  // See the style tag in the component

  // Horizontal rule
  hr: () => <hr className="my-3 border-card-border" />,

  // Tables
  table: ({ children }) => <Table>{children}</Table>,
  thead: ({ children }) => <thead className="bg-gray-50 border-b border-card-border">{children}</thead>,
  tbody: ({ children }) => <tbody className="divide-y divide-card-border">{children}</tbody>,
  tr: ({ children }) => <tr className="hover:bg-gray-50 transition-colors">{children}</tr>,
  th: ({ children }) => <th className="px-3 py-2 text-left text-xs font-semibold text-text-muted uppercase tracking-wide">{children}</th>,
  td: ({ children }) => <td className="px-3 py-2 text-text-primary text-xs">{children}</td>,

  // Images
  img: ({ src, alt }) => <LazyImage src={src} alt={alt} />,
}

// ─── Exported component ───────────────────────────────────────

export const MarkdownContent = memo(function MarkdownContent({ content, streaming }) {
  // During streaming, render as plain text — ReactMarkdown re-parsing on every
  // delta causes visual flicker and incorrect formatting with partial syntax.
  if (streaming) {
    return (
      <div className="markdown-body text-sm whitespace-pre-wrap break-words">
        {content}
      </div>
    )
  }

  return (
    <div className="markdown-body text-sm whitespace-pre-wrap break-words">
      {/* Task list styles */}
      <style>{`
        .markdown-body .task-list-item {
          list-style: none;
          margin-left: -1.5em;
        }
        .markdown-body .task-list-item input[type="checkbox"] {
          margin-right: 0.5em;
        }
      `}</style>
      <ReactMarkdown
        remarkPlugins={[remarkGfm, remarkMath, remarkBreaks]}
        rehypePlugins={[rehypeKatex]}
        components={components}
      >
        {content}
      </ReactMarkdown>
    </div>
  )
})
