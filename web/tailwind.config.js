/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        // Base colors - new design style
        'main-bg': '#f8f9fa',
        'card-bg': '#ffffff',
        'card-border': '#e2e5ea',
        'border-light': '#e8ebf0',
        'text-primary': '#0a0a0a',
        'text-secondary': '#4b5263',
        'text-muted': '#9aa0ab',
        'text-light': '#c8ccd4',
        // Brand accent palette - new design style
        accent: '#2f7bff', // blue   — primary actions, active, focus
        'accent-hover': '#5a82ff',
        'accent-light': '#c8d4ff',
        'accent-gold': '#f59e0b', // gold   — warnings, pending, scheduler
        'accent-pink': '#F9A8D4', // pink   — commitments, promises
        'accent-orange': '#FB923C', // orange — killed, delegation
        'accent-green': '#22c55e', // green  — success, healthy, completed
        'accent-green-dark': '#15803d',
        'accent-purple': '#a855f7', // purple — system, integrations
        'accent-red': '#ef4444', // red    — errors, failed
        // Dark colors for buttons and accents
        'dark-primary': '#0e1117',
        'dark-secondary': '#1a1a1a',
      },
      boxShadow: {
        card: '0 1px 2px 0 rgb(0 0 0 / 0.05)',
        'card-md': '0 1px 3px 0 rgb(0 0 0 / 0.06), 0 1px 2px -1px rgb(0 0 0 / 0.06)',
        'card-lg': '0 4px 12px -4px rgb(0 0 0 / 0.08)',
        'card-xl': '0 -8px 24px -12px rgb(0 0 0 / 0.12)',
        'glow': '0 8px 24px -8px rgba(90, 130, 255, 0.4)',
      },
      borderRadius: {
        'xl': '10px',
        '2xl': '14px',
        '3xl': '18px',
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
        mono: ['JetBrains Mono', 'monospace'],
      },
    },
  },
  plugins: [],
}
