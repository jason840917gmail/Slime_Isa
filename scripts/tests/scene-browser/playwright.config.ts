import { existsSync } from 'node:fs';

import { defineConfig } from '@playwright/test';

const systemChrome = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH
  ?? (existsSync(systemChrome) ? systemChrome : undefined);

export default defineConfig({
  testDir: '.',
  testMatch: ['*.spec.ts'],
  workers: 1,
  retries: 0,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  outputDir: 'test-results',
  reporter: [['list']],
  use: {
    baseURL: 'http://127.0.0.1:3101/scripts/tests/scene-browser/fixtures/',
    browserName: 'chromium',
    trace: 'retain-on-failure',
    launchOptions: executablePath ? { executablePath } : undefined,
  },
  webServer: {
    command: 'node ../../../node_modules/vite/bin/vite.js --config vite.config.ts',
    url: 'http://127.0.0.1:3101/scripts/tests/scene-browser/fixtures/',
    reuseExistingServer: process.env.SCENE_BROWSER_REUSE_SERVER === '1',
    timeout: 120_000,
  },
});
