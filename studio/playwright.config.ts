import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './tests/browser',
  fullyParallel: false,
  workers: 1,
  use: {
    baseURL: 'http://127.0.0.1:4199',
    browserName: 'chromium',
    ...(process.env.CI ? {} : { channel: 'chrome' as const }),
    colorScheme: 'dark',
    reducedMotion: 'reduce',
    trace: 'retain-on-failure',
  },
  webServer: {
    command: 'npm run dev -- --port 4199 --strictPort',
    url: 'http://127.0.0.1:4199',
    reuseExistingServer: true,
    env: {
      ...process.env,
      VITE_SUPABASE_URL: 'http://127.0.0.1:4199/fake-supabase',
      VITE_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_browser_test',
    },
  },
})
