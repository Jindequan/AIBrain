import { useRef, useState, useCallback, useEffect } from 'react'

const SCROLL_NEAR_BOTTOM_THRESHOLD = 150
const USER_INTERACTION_RESET_DELAY = 2000
const SCROLL_DELTA_THRESHOLD = 10

export function useChatScroll(messages, streaming, sessionId) {
  const scrollRef = useRef(null)
  const bottomRef = useRef(null)
  const userScrolledUpRef = useRef(false)
  const [userScrolledUp, setUserScrolledUp] = useState(false)
  const loadedRef = useRef(false)
  const lastScrollTopRef = useRef(0)
  const prevSessionIdRef = useRef(null)
  const sessionChangedRef = useRef(false)
  const isUserInteractingRef = useRef(false)
  const userInteractionTimerRef = useRef(null)

  const isNearBottom = useCallback(() => {
    const el = scrollRef.current
    if (!el) return true
    return el.scrollHeight - el.scrollTop - el.clientHeight < SCROLL_NEAR_BOTTOM_THRESHOLD
  }, [])

  const scrollToBottom = useCallback((smooth) => {
    const el = scrollRef.current
    if (!el) return
    el.scrollTo({
      top: el.scrollHeight,
      behavior: smooth ? 'smooth' : 'instant',
    })
  }, [])

  const handleScroll = useCallback(() => {
    const el = scrollRef.current
    if (!el) return

    const currentScrollTop = el.scrollTop
    const scrollDelta = Math.abs(currentScrollTop - lastScrollTopRef.current)
    lastScrollTopRef.current = currentScrollTop

    if (userInteractionTimerRef.current) {
      clearTimeout(userInteractionTimerRef.current)
    }

    if (scrollDelta < SCROLL_DELTA_THRESHOLD && !isUserInteractingRef.current) {
      return
    }

    if (scrollDelta >= SCROLL_DELTA_THRESHOLD) {
      isUserInteractingRef.current = true
      userInteractionTimerRef.current = setTimeout(() => {
        isUserInteractingRef.current = false
      }, USER_INTERACTION_RESET_DELAY)
    }

    if (isNearBottom()) {
      if (userScrolledUpRef.current) {
        userScrolledUpRef.current = false
        setUserScrolledUp(false)
      }
      isUserInteractingRef.current = false
    } else {
      if (!userScrolledUpRef.current) {
        userScrolledUpRef.current = true
        setUserScrolledUp(true)
      }
    }
  }, [isNearBottom])

  // Auto-scroll on session change and new content
  useEffect(() => {
    // Detect session change and reset scroll state
    if (sessionId && sessionId !== prevSessionIdRef.current) {
      prevSessionIdRef.current = sessionId
      loadedRef.current = false
      sessionChangedRef.current = true
      userScrolledUpRef.current = false
      setUserScrolledUp(false)
    }

    if (messages.length === 0) {
      // Don't mark loaded if session just changed — we want to scroll
      // when the new session's messages arrive
      if (!sessionChangedRef.current) {
        loadedRef.current = true
      }
      sessionChangedRef.current = false
      return
    }

    sessionChangedRef.current = false

    if (streaming) {
      // Use refs (always current) to avoid stale closure state
      // Respect user scroll — once they scroll up, stop auto-scrolling
      if (!userScrolledUpRef.current && !isUserInteractingRef.current) {
        requestAnimationFrame(() => {
          // Double-check refs inside RAF — they may have changed since scheduling
          if (!userScrolledUpRef.current && !isUserInteractingRef.current) {
            scrollToBottom(false) // instant, not smooth — streaming needs fast updates
          }
        })
      }
    } else if (!loadedRef.current) {
      loadedRef.current = true
      requestAnimationFrame(() => scrollToBottom(false))
    }
  }, [messages, streaming, scrollToBottom, sessionId])

  // Cleanup timers on unmount
  useEffect(() => {
    return () => {
      if (userInteractionTimerRef.current) {
        clearTimeout(userInteractionTimerRef.current)
      }
    }
  }, [])

  return {
    scrollRef,
    bottomRef,
    userScrolledUp,
    userScrolledUpRef,
    isUserInteractingRef,
    isNearBottom,
    scrollToBottom,
    handleScroll,
  }
}
