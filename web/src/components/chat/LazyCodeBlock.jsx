import { useState, useRef, useEffect, memo } from 'react'
import { Code, Loader2 } from 'lucide-react'

const LARGE_CODE_THRESHOLD = 2000 // chars

export const LazyCodeBlock = memo(function LazyCodeBlock({ children, lang = 'code', rawText }) {
  const [shouldRender, setShouldRender] = useState(rawText.length < LARGE_CODE_THRESHOLD)
  const [isLoading, setIsLoading] = useState(false)
  const placeholderRef = useRef(null)

  useEffect(() => {
    if (shouldRender || rawText.length < LARGE_CODE_THRESHOLD) return

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) {
          setIsLoading(true)
          // Defer rendering to next frame to avoid blocking UI
          requestAnimationFrame(() => {
            requestAnimationFrame(() => {
              setShouldRender(true)
              setIsLoading(false)
            })
          })
          observer.disconnect()
        }
      },
      { threshold: 0.1, rootMargin: '200px' }
    )

    if (placeholderRef.current) {
      observer.observe(placeholderRef.current)
    }

    return () => observer.disconnect()
  }, [rawText.length, shouldRender])

  if (!shouldRender) {
    return (
      <div ref={placeholderRef} className="relative my-3 rounded-2xl overflow-hidden border border-gray-200 shadow-card">
        <div className="flex items-center justify-between px-4 py-2 bg-gray-800 border-b border-gray-700">
          <span className="text-[11px] font-mono text-gray-400">{lang}</span>
          <button
            onClick={() => {
              setIsLoading(true)
              setShouldRender(true)
            }}
            className="px-2 py-0.5 rounded-lg text-[10px] font-medium bg-accent hover:bg-accent/90 text-white transition-colors flex items-center gap-1"
          >
            <Code className="w-3 h-3" />
            Show code ({(rawText.length / 1024).toFixed(1)} KB)
          </button>
        </div>
        <div className="p-4 bg-gray-900 text-gray-500 text-xs flex items-center justify-center min-h-[100px]">
          Code block hidden to improve performance
        </div>
      </div>
    )
  }

  if (isLoading) {
    return (
      <div className="relative my-3 rounded-2xl overflow-hidden border border-gray-200 shadow-card">
        <div className="flex items-center justify-between px-4 py-2 bg-gray-800 border-b border-gray-700">
          <span className="text-[11px] font-mono text-gray-400">{lang}</span>
        </div>
        <div className="p-4 bg-gray-900 flex items-center justify-center min-h-[100px]">
          <Loader2 className="w-5 h-5 text-gray-400 animate-spin" />
        </div>
      </div>
    )
  }

  return <>{children}</>
})
