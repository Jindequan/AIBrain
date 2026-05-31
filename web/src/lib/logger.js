const isDev = import.meta.env.DEV

export const logger = {
  log: (...args) => {
    if (isDev) console.log(...args)
  },
  warn: (...args) => {
    if (isDev) console.warn(...args)
  },
  error: (...args) => {
    // Always log errors regardless of environment
    console.error(...args)
  },
  info: (...args) => {
    if (isDev) console.info(...args)
  },
}
