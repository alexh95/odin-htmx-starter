import { defineConfig, devices } from '@playwright/test';

// Specs that never open a page: they talk HTTP to a server (their own, or the
// worker's), so a browser engine changes nothing. They run once, as the `api`
// project, instead of once per engine.
const API_ONLY =
  /[\\/](backup|canonical|cross-site|dashboard|demo|events|hosts|ids|limits|headers|ops|persistence|protocol|rbac|routing|seo|writes)\.spec\.ts$/;

// skeleton, lab and full run in the three engines (Firefox in CI only: it can't start
// on the dev PC), streams too (M6: chat had never met Firefox), every other profile in chromium
// (PLAN §19.1.2); the api project always. E2E_PROFILE picks the profile, as in
// global-setup.ts.
const PROFILE = process.env.E2E_PROFILE || 'skeleton';
const ENGINES = ['skeleton', 'lab', 'full'].includes(PROFILE) ? ['chromium', 'firefox', 'webkit']
  : PROFILE === 'streams' ? ['chromium', 'firefox', 'webkit'] : ['chromium'];
const DEVICE: Record<string, string> = { chromium: 'Desktop Chrome', firefox: 'Desktop Firefox', webkit: 'Desktop Safari' };

// Every response carries Cross-Origin-Opener-Policy: same-origin, so Firefox's first navigation
// of a page (from about:blank) swaps browsing-context groups, and Playwright's Firefox driver
// now and then loses that navigation: page.goto never resolves though the page has loaded and
// the server answered (one test in 25 in CI's image; Python's file server with the header
// added stalls the same way, and without it never). Real Firefox is unaffected. The pref turns
// off COOP's enforcement in the test browser only; the server still sends the header, and the
// header specs still hold it.
const FIREFOX = { launchOptions: { firefoxUserPrefs: { 'browser.tabs.remote.useCrossOriginOpenerPolicy': false } } };

// E2E_PROXY (CI's e2e-proxy job, PLAN §20.1): the pages go through a proxy in front of one server
// on a fixed port, so one worker, in chromium (or E2E_PROXY_BROWSER's engine); the browser-less specs
// need no proxy and don't run.
const PROXY = process.env.E2E_PROXY || '';
const PROXY_ENGINE = process.env.E2E_PROXY_BROWSER || 'chromium';

// global-setup builds the binary once; each worker spawns its own server on its
// own port (see fixtures.ts) with an isolated in-memory store — so the suite
// runs fully in parallel across workers and the three browser engines.
export default defineConfig({
  testDir: './tests',
  fullyParallel: !PROXY,
  // Playwright defaults to ~half the cores; on a small CI runner that's near-
  // serial. Use one worker per core there (CI shards the engines across runners,
  // so each runner handles a single engine). Locally, use the core-based default.
  workers: PROXY ? 1 : process.env.CI ? '100%' : undefined,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : [['list']],
  globalSetup: './global-setup.ts',
  use: {
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: PROXY ? [{ name: PROXY_ENGINE, testIgnore: API_ONLY, use: { ...devices[DEVICE[PROXY_ENGINE]], ...(PROXY_ENGINE === 'firefox' ? FIREFOX : {}) } }] : [
    ...ENGINES.map((name) => ({ name, testIgnore: API_ONLY, use: { ...devices[DEVICE[name]], ...(name === 'firefox' ? FIREFOX : {}) } })),
    { name: 'api', testMatch: API_ONLY },
  ],
});
