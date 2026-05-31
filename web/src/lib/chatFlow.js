export function normalizeRouteSessionId(routeSessionId) {
  return routeSessionId && routeSessionId !== 'new' ? routeSessionId : null
}

export function resolveSendSessionId(routeSessionId, activeSessionId) {
  const routeSessionIdNormalized = normalizeRouteSessionId(routeSessionId)
  if (routeSessionId === undefined || routeSessionId === null || routeSessionId === 'new') {
    return null
  }
  const activeSessionIdNormalized = activeSessionId && activeSessionId !== 'new' ? activeSessionId : null
  return routeSessionIdNormalized || activeSessionIdNormalized
}
