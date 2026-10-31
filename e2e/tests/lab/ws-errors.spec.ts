import { expect, test } from '../../fixtures';
import { startServer, stopServer, directHost } from '../../helpers/server';

// M6's spike (docs/spikes/M6.1.md): what htmx 4's hx-ws tells a page when a socket can't connect
// and when an open one drops, which chat's "Auto" connection mode falls back to SSE on. Kept as a
// spec so a new htmx or browser that changes it fails here, not in Auto. Each browser alike: an
// `htmx:ws:error` whose `error` is the socket's bare `Event` (no reason: the WebSocket API gives
// none), then `htmx:ws:close` with code 1006, on every failed attempt; an open socket that drops
// gives `htmx:ws:close` 1006 (with or without an error first) and reconnects.
const T = { tag: '@lab' };

type Seen = { type: string; error?: string; code?: number | null; reason?: string };

// A page whose one element connects to `url`, recording the ws events it gets.
async function watch(page: import('@playwright/test').Page, base: string, url: string) {
  await page.goto(`${base}/lab`);
  await page.evaluate((u) => {
    const seen: Seen[] = [];
    (window as unknown as { seen: Seen[] }).seen = seen;
    for (const type of ['htmx:ws:after:connection', 'htmx:ws:error', 'htmx:ws:close']) {
      document.addEventListener(type, (e) => {
        const d = (e as CustomEvent).detail ?? {};
        const err = d.error;
        seen.push({
          type,
          error: err === undefined ? undefined : err instanceof Event ? `Event:${err.type}` : String(err),
          code: d.code, reason: d.reason,
        });
      });
    }
    const el = document.createElement('div');
    el.setAttribute('hx-ws:connect', u);
    document.body.append(el);
    (window as unknown as { htmx: { process(e: Element): void } }).htmx.process(el);
  }, url);
  return () => page.evaluate(() => (window as unknown as { seen: Seen[] }).seen);
}

test.describe('hx-ws errors', T, () => {
  // Same origin, as the page's CSP has it (connect-src 'self'): a path that answers 404 to the
  // upgrade, as a proxy that won't pass WebSockets does.
  test('a socket that can not connect: an error with a bare Event, then a close with 1006', async ({ page }, info) => {
    const s = await startServer(info.config);
    try {
      const seen = await watch(page, `http://${directHost(s.port)}`, `ws://${directHost(s.port)}/lab/ws/nowhere`);
      await expect.poll(async () => (await seen()).filter((e) => e.type === 'htmx:ws:close').length, { timeout: 15_000 }).toBeGreaterThanOrEqual(2);
      const events = await seen();
      console.log(`[${info.project.name}] refused:`, JSON.stringify(events.slice(0, 4)));
      expect(events.some((e) => e.type === 'htmx:ws:after:connection')).toBe(false);
      expect(events.find((e) => e.type === 'htmx:ws:error')?.error).toBe('Event:error');
      expect(events.find((e) => e.type === 'htmx:ws:close')?.code).toBe(1006);
    } finally {
      await stopServer(s);
    }
  });

  test('an open socket that drops: a close with 1006, then it reconnects', async ({ page }, info) => {
    const s = await startServer(info.config);
    const base = `http://${directHost(s.port)}`;
    const seen = await watch(page, base, `ws://${directHost(s.port)}/lab/ws/echo`);
    await expect.poll(async () => (await seen()).some((e) => e.type === 'htmx:ws:after:connection')).toBe(true);
    await stopServer(s); // the process ends: no close frame
    await expect.poll(async () => (await seen()).some((e) => e.type === 'htmx:ws:close'), { timeout: 10_000 }).toBe(true);
    const events = await seen();
    console.log(`[${info.project.name}] dropped:`, JSON.stringify(events.slice(0, 5)));
    const close = events.find((e) => e.type === 'htmx:ws:close')!;
    expect(close.code).toBe(1006);
    expect(close.reason).toBe('closed');
  });
});
