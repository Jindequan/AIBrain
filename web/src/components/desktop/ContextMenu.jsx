import { useState, useEffect, useRef, useCallback } from 'react'
import { cn } from '../../lib/utils'

/**
 * Desktop-style context menu.
 * Usage: wrap any element with `onContextMenu` prop.
 *
 * <ContextMenu items={[...]}>
 *   <div>Right-click me</div>
 * </ContextMenu>
 */
export default function ContextMenu({ items, children, className }) {
  const [open, setOpen] = useState(false)
  const [pos, setPos] = useState({ x: 0, y: 0 })
  const menuRef = useRef(null)

  const handleContextMenu = useCallback((e) => {
    e.preventDefault()
    e.stopPropagation()
    setPos({ x: e.clientX, y: e.clientY })
    setOpen(true)
  }, [])

  useEffect(() => {
    if (!open) return
    const handle = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) {
        setOpen(false)
      }
    }
    const handleKeyDown = (e) => { if (e.key === 'Escape') setOpen(false) }
    document.addEventListener('mousedown', handle)
    document.addEventListener('keydown', handleKeyDown)
    return () => {
      document.removeEventListener('mousedown', handle)
      document.removeEventListener('keydown', handleKeyDown)
    }
  }, [open])

  return (
    <>
      <div onContextMenu={handleContextMenu} className={className}>
        {children}
      </div>

      {open && (
        <div
          ref={menuRef}
          className="fixed z-[200] min-w-[180px] py-1 bg-white rounded-xl shadow-2xl border border-gray-200 text-sm"
          style={{ left: pos.x, top: pos.y }}
        >
          {items.map((item, i) => {
            if (item.separator) {
              return <div key={i} className="h-px bg-gray-200 my-1 mx-2" />
            }
            return (
              <button
                key={i}
                disabled={item.disabled}
                onClick={() => {
                  setOpen(false)
                  item.onClick?.()
                }}
                className={cn(
                  'w-full flex items-center gap-3 px-3 py-1.5 text-left transition-colors',
                  item.danger
                    ? 'text-red-600 hover:bg-red-50'
                    : 'text-gray-700 hover:bg-gray-100',
                  item.disabled && 'opacity-40 cursor-default'
                )}
              >
                {item.icon && <span className="w-4 h-4 shrink-0">{item.icon}</span>}
                <span className="flex-1">{item.label}</span>
                {item.shortcut && (
                  <span className="text-xs text-gray-400">{item.shortcut}</span>
                )}
              </button>
            )
          })}
        </div>
      )}
    </>
  )
}
