// Send to another member's DOM (PLAN §18, D38: p95 ≤ 50 ms on the LAN through NPM). A real browser:
// one reader on a room's page over WebSocket, and senders in contexts of their own, since a member
// may post 5 messages in 10 s. A sender stamps the moment Enter submits, in the page; a
// MutationObserver on the reader's log stamps the moment the message lands. One browser, so one clock.
//
//   node tools/drills/chat-latency.mjs <base URL> [--senders 12] [--each 5] [--transport ws]
//
// On an accounts build members register, which needs registration open; a nick build's need the
// LAN. Run from the repo root with e2e's dependencies installed.

import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const { chromium } = createRequire(path.join(here, '../../e2e/package.json'))('@playwright/test');

const argv = process.argv.slice(2);
const flag = (name, def) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : def; };
const BASE = argv[0];
const SENDERS = Number(flag('--senders', '12'));
const EACH = Number(flag('--each', '5'));
const TRANSPORT = flag('--transport', 'ws');
const PASSWORD = 'a-long-enough-password';
if (!BASE?.startsWith('http')) { console.error('usage: chat-latency.mjs <base URL> [--senders N] [--each N] [--transport ws]'); process.exit(2); }

const browser = await chromium.launch();

async function member(name) {
  const context = await browser.newContext({ baseURL: BASE });
  const page = await context.newPage();
  await page.goto('/login');
  if (await page.locator('#nick').count()) {
    await page.locator('#nick').fill(name);
    await page.getByRole('button', { name: 'Use this nickname' }).click();
  } else {
    await page.goto('/register');
    await page.locator('#username').fill(name);
    await page.locator('#password').fill(PASSWORD);
    await page.locator('#again').fill(PASSWORD);
    await page.getByRole('button', { name: 'Join' }).click();
  }
  await page.waitForURL((u) => !/\/(login|register)$/.test(u.pathname));
  return page;
}

async function inRoom(page) {
  await page.goto(`/chat/r/lobby?transport=${TRANSPORT}`);
  await page.locator('.chat-room').waitFor();
  if (TRANSPORT === 'ws') {
    await page.waitForFunction(() => document.querySelector('.chat-pane')?._htmx?.ws?.connection?.socket?.readyState === 1);
  }
}

const run = Date.now().toString(36);
const reader = await member(`reader-${run}`);
await inRoom(reader);
await reader.evaluate(() => {
  window.landed = {};
  new MutationObserver((list) => {
    const at = performance.timeOrigin + performance.now();
    for (const m of list) {
      for (const n of m.addedNodes) {
        const stamp = n.textContent?.match(/lat-[a-z0-9]+-\d+/);
        if (stamp && !window.landed[stamp[0]]) window.landed[stamp[0]] = at;
      }
    }
  }).observe(document.querySelector('.chat-log'), { childList: true, subtree: true });
});

const sent = {};
for (let s = 0; s < SENDERS; s++) {
  const page = await member(`sender-${run}-${s}`);
  await inRoom(page);
  for (let i = 0; i < EACH; i++) {
    const id = `lat-${run}-${s * 100 + i}`;
    sent[id] = await page.evaluate((text) => {
      const box = document.querySelector('.chat-composer textarea');
      box.value = text;
      const at = performance.timeOrigin + performance.now();
      box.form.requestSubmit();
      return at;
    }, id);
    await page.waitForTimeout(150);
  }
  await page.context().close();
}
await reader.waitForTimeout(1000);
const landed = await reader.evaluate(() => window.landed);
await browser.close();

const lat = Object.entries(sent).filter(([id]) => landed[id]).map(([id, at]) => landed[id] - at).sort((a, b) => a - b);
const pct = (p) => lat[Math.min(lat.length - 1, Math.floor(lat.length * p / 100))];
console.log(`${lat.length} of ${Object.keys(sent).length} landed over ${TRANSPORT}; ms p50 ${pct(50).toFixed(1)} p95 ${pct(95).toFixed(1)} max ${lat[lat.length - 1].toFixed(1)} (budget p95 ≤ 50)`);
process.exit(lat.length === Object.keys(sent).length && pct(95) <= 50 ? 0 : 1);
