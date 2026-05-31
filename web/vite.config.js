/* global process */
/// <reference types="vitest" />
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const apiProxyTarget = process.env.VITE_API_PROXY_TARGET || process.env.VITE_API_URL || 'http://localhost:4100'
const wsUrl = process.env.VITE_WS_URL || 'ws://localhost:4100'

// https://vite.dev/config/
export default defineConfig({
  base: './',
  plugins: [react()],
  define: {
    'import.meta.env.VITE_WS_URL': JSON.stringify(wsUrl),
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.js'],
  },
  server: {
    port: 5200,
    proxy: {
      '/api': {
        target: apiProxyTarget,
        ws: true,
        changeOrigin: true,
      },
    },
  },
  build: {
    chunkSizeWarningLimit: 1100,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules/@uiw/react-md-editor')) {
            return 'codemirror-mdeditor'
          }
          if (id.includes('node_modules/@uiw/react-codemirror')) {
            return 'codemirror-uiw'
          }
          if (id.includes('node_modules/@codemirror/view')) {
            return 'codemirror-view'
          }
          if (id.includes('node_modules/@codemirror/')) {
            return 'codemirror-core'
          }
          if (id.includes('node_modules/react-markdown') ||
              id.includes('node_modules/remark-') ||
              id.includes('node_modules/rehype-') ||
              id.includes('node_modules/katex') ||
              id.includes('node_modules/highlight.js') ||
              id.includes('node_modules/mdast-') ||
              id.includes('node_modules/unist-') ||
              id.includes('node_modules/unified') ||
              id.includes('node_modules/vfile') ||
              id.includes('node_modules/micromark') ||
              id.includes('node_modules/hast-') ||
              id.includes('node_modules/trim-lines') ||
              id.includes('node_modules/decode-named-character-reference') ||
              id.includes('node_modules/character-entities') ||
              id.includes('node_modules/ccount') ||
              id.includes('node_modules/comma-separated-tokens') ||
              id.includes('node_modules/property-information') ||
              id.includes('node_modules/space-separated-tokens') ||
              id.includes('node_modules/html-void-elements')) {
            return 'markdown'
          }
        },
      },
    },
  },
})
