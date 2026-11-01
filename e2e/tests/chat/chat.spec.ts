import { test, expect } from '../../fixtures';
import type { Page, WebSocketRoute } from '@playwright/test';
import { startServer, stopServer, type Server } from '../../helpers/server';
import { leave, member, uid, type Member } from '../../helpers/members';

// Chat (PLAN §14.1) over each of its four transports, chosen per page by ?transport=:
// a message reaches every member once, escaped, edits and tombstones follow it, and a
// restart costs a page nothing it had and duplicates nothing it gets next (D37).
const T = { tag: ['@chat', '@accounts-nick'] };
const TRANSPORTS = ['ws', 'sse', 'poll', 'multipart'] as const;

// A room of its own per test: the worker's server is shared by its tests.
async function newRoom(page: Page): Promise<string> {
  await page.goto('/chat');
  await page.locator('#room-name').fill(uid('room '));
  await page.getByRole('button', { name: 'Create' }).click();
  await page.waitForURL(/\/chat\/r\//);
  return new URL(page.url()).pathname.split('/').pop()!;
}

async function open(m: Member, slug: string, transport: string) {
  await m.page.goto(`/chat/r/${slug}?transport=${transport}`);
  await expect(m.page.locator('.chat-room')).toBeVisible();
  // A socket's composer sends on the socket: wait until it is open (the other three POST).
  if (transport === 'ws') {
    await expect.poll(() => m.page.locator('.chat-pane').evaluate((el: any) => el._htmx?.ws?.connection?.socket?.readyState)).toBe(1);
  }
}

async function say(m: Member, text: string) {
  const box = m.page.locator('.chat-composer textarea');
  await box.fill(text);
  await box.press('Enter');
  await expect(box).toHaveValue(''); // Composer cleared it once sent
}

// /events' resync on the body, which asks /since with the page's version.
const RESYNC = () => document.body.dispatchEvent(new CustomEvent('resync'));

// A socket that really reconnects: the page's sockets go through a route, and closing one with 1012
// (one of hx-ws's reconnect codes) makes it connect again, sending the page's version on the new
// socket. Call before the page opens its socket; the returned proc waits for the next connection.
async function routed(m: Member) {
  const live: { page: WebSocketRoute; server: WebSocketRoute }[] = [];
  await m.page.routeWebSocket(/\/ws$/, ws => { live.push({ page: ws, server: ws.connectToServer() }); });
  return async () => {
    const n = live.length;
    await live[n - 1].server.close();
    await live[n - 1].page.close({ code: 1012 });
    await expect.poll(() => live.length).toBe(n + 1);
    await expect.poll(() => m.page.locator('.chat-pane').evaluate((el: any) => el._htmx?.ws?.connection?.socket?.readyState)).toBe(1);
  };
}

const messages = (m: Member) => m.page.locator('.chat-log > article.chat-msg');
const message = (m: Member, text: string) => messages(m).filter({ hasText: text });

for (const t of TRANSPORTS) {
  test.describe(`chat over ${t}`, T, () => {
    test('a message reaches the other member once, escaped, and the author once', async ({ browser, baseURL }) => {
      const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
      const slug = await newRoom(ann.page);
      await open(ann, slug, t);
      await open(bob, slug, t);
      const text = `<b>hi</b> ${uid('x')}`;
      await say(ann, text);
      for (const m of [ann, bob]) {
        await expect(message(m, text)).toHaveCount(1);
        await expect(message(m, text).locator('.chat-body b')).toHaveCount(0); // text, not markup
        await expect(message(m, text).locator('.chat-name')).toHaveText(ann.name);
      }
      await expect(message(ann, text)).toHaveClass(/\bmine\b/);
      await expect(message(bob, text)).not.toHaveClass(/\bmine\b/);
      // Bob's answer goes the other way.
      await say(bob, 'and back');
      await expect(message(ann, 'and back')).toHaveCount(1);
      await expect(messages(ann)).toHaveCount(2);
      await expect(messages(bob)).toHaveCount(2);
      expect([...ann.errors, ...bob.errors]).toEqual([]);
      await leave(ann, bob);
    });

    test('an edit and a delete reach the other member', async ({ browser, baseURL }) => {
      const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
      const slug = await newRoom(ann.page);
      await open(ann, slug, t);
      await open(bob, slug, t);
      await say(ann, 'first take');
      const mine = message(ann, 'first take');
      await mine.hover();
      await mine.getByRole('button', { name: 'Message actions' }).click();
      await mine.getByRole('button', { name: 'Edit' }).click();
      await mine.locator('.chat-edit textarea').fill('second take');
      await mine.getByRole('button', { name: 'Save' }).click();
      await expect(message(bob, 'second take')).toContainText('(edited)');
      await expect(message(bob, 'first take')).toHaveCount(0);

      // Bob may not change Ann's: his menu has no Edit.
      const hers = message(bob, 'second take');
      await hers.hover();
      await hers.getByRole('button', { name: 'Message actions' }).click();
      await expect(hers.getByRole('link', { name: 'Link' })).toBeVisible();
      await expect(hers.getByRole('button', { name: 'Edit' })).toHaveCount(0);

      const again = message(ann, 'second take');
      await again.hover();
      await again.getByRole('button', { name: 'Message actions' }).click();
      await again.getByRole('button', { name: 'Delete' }).click();
      await expect(messages(bob).filter({ hasText: 'Message deleted.' })).toHaveCount(1);
      await expect(messages(bob)).toHaveCount(1); // a tombstone keeps its place
      await expect(messages(bob).locator('.chat-actions')).toHaveCount(0); // and drops the menu Bob had open
      await leave(ann, bob);
    });

    // A message rendered again while its edit form is open (here an edit from Ann's other tab; also its echo, or
    // a poll's) keeps the form and what was typed in it, and Save still closes it.
    test('an open edit form outlives its message being rendered again', async ({ browser, baseURL }) => {
      const ann = await member(browser, baseURL!);
      const slug = await newRoom(ann.page);
      await open(ann, slug, t);
      await say(ann, 'draft one');
      const id = await message(ann, 'draft one').getAttribute('id');
      const mine = ann.page.locator(`#${id}`);
      await mine.hover();
      await mine.getByRole('button', { name: 'Message actions' }).click();
      await mine.getByRole('button', { name: 'Edit' }).click();
      await mine.locator('.chat-edit textarea').fill('half typed');

      const tab: Member = { ...ann, page: await ann.context.newPage() };
      await open(tab, slug, t);
      const there = tab.page.locator(`#${id}`);
      await there.hover();
      await there.getByRole('button', { name: 'Message actions' }).click();
      await there.getByRole('button', { name: 'Edit' }).click();
      await there.locator('.chat-edit textarea').fill('from the other tab');
      await there.getByRole('button', { name: 'Save' }).click();

      await expect(mine.locator('.chat-body')).toHaveText('from the other tab');
      await expect(mine).toContainText('(edited)');
      await expect(mine.locator('.chat-edit textarea')).toHaveValue('half typed');
      await mine.getByRole('button', { name: 'Save' }).click();
      await expect(mine.locator('.chat-body')).toHaveText('half typed');
      await expect(mine.locator('.chat-edit')).toHaveCount(0);
      await expect(there.locator('.chat-body')).toHaveText('half typed');
      expect(ann.errors).toEqual([]);
      await leave(ann);
    });

    // Playwright's offline emulation fails new requests (the poll's) and closes Chromium's socket, but leaves an
    // open SSE or multipart response, and WebKit's socket, delivering: for those this only holds that nothing
    // doubles, and the restart below is what cuts them.
    test('offline a while: the page gets what it missed, once', async ({ browser, baseURL }) => {
      const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
      const slug = await newRoom(ann.page);
      await open(ann, slug, t);
      await open(bob, slug, t);
      await say(ann, 'while online');
      await expect(message(bob, 'while online')).toHaveCount(1);

      await bob.context.setOffline(true);
      await say(ann, 'while away 1');
      await say(ann, 'while away 2');
      await bob.page.waitForTimeout(1500);
      await bob.context.setOffline(false);

      for (const text of ['while online', 'while away 1', 'while away 2']) {
        await expect(message(bob, text)).toHaveCount(1, { timeout: 30_000 });
      }
      await expect(messages(bob)).toHaveCount(3);
      await leave(ann, bob);
    });

    test('a restart: the page keeps what it had and gets what comes next, once', async ({ browser }) => {
      test.slow();
      const config = test.info().config;
      const s1 = await startServer(config);
      let s2: Server | undefined;
      const base = `http://127.0.0.1:${s1.port}`;
      const ann = await member(browser, base), bob = await member(browser, base);
      try {
        await open(ann, 'lobby', t);
        await open(bob, 'lobby', t);
        await say(ann, 'before the restart');
        await expect(message(bob, 'before the restart')).toHaveCount(1);

        await stopServer(s1);
        s2 = await startServer(config, {}, s1.port);

        // Ann's composer works again once her page has its connection back; a socket
        // needs it to send, so she retries until Bob has it.
        await expect(async () => {
          await say(ann, 'after the restart');
          await expect(message(bob, 'after the restart')).not.toHaveCount(0, { timeout: 3000 });
        }).toPass({ timeout: 30_000 });
        await expect(message(bob, 'before the restart')).toHaveCount(1); // kept, not doubled
        const ids = await messages(bob).evaluateAll((els) => els.map((e) => e.id));
        expect(new Set(ids).size).toBe(ids.length);
      } finally {
        await leave(ann, bob);
        if (s2) await stopServer(s2);
        if (s1.proc.exitCode === null) s1.proc.kill();
      }
    });
  });
}

test.describe('chat', T, () => {
  test('presence and typing ride the page, whatever the transport', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
    const slug = await newRoom(ann.page);
    await open(bob, slug, 'poll');
    await open(ann, slug, 'ws');
    await expect(bob.page.locator('.chat-who .who-online', { hasText: ann.name })).toBeVisible();
    await ann.page.locator('.chat-composer textarea').pressSequentially('typ');
    await expect(bob.page.locator('.chat-typing')).toContainText(`${ann.name} is typing`);
    await expect(ann.page.locator('.chat-typing .typing-who')).toBeHidden(); // her own, marked and hidden
    await leave(ann, bob);
  });

  test('a refused message stays as typed, with the reason; past the rate a toast says to slow down', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const slug = await newRoom(ann.page);
    for (const t of ['sse', 'ws']) {
      await open(ann, slug, t);
      const box = ann.page.locator('.chat-composer textarea');
      await box.fill('   ');
      await box.evaluate((el: HTMLTextAreaElement) => el.removeAttribute('required'));
      await box.press('Enter');
      await expect(ann.page.locator('.chat-composer .form-error')).toHaveText('Write something first.');
    }
    // Five in ten seconds, the sixth refused (a window may open mid-burst: then the
    // eleventh is). Each post waits for its answer: htmx queues a form's next request
    // behind the one in flight.
    await open(ann, slug, 'sse');
    const box = ann.page.locator('.chat-composer textarea');
    let refused: import('@playwright/test').Response | undefined;
    for (let i = 0; i < 11 && !refused; i++) {
      await box.fill(`burst ${i}`);
      const [res] = await Promise.all([
        ann.page.waitForResponse((r) => r.request().method() === 'POST' && new URL(r.url()).pathname === `/chat/r/${slug}`),
        box.press('Enter'),
      ]);
      if (res.status() === 429) refused = res;
    }
    expect(refused, 'a post past the rate').toBeDefined();
    expect(Number(refused!.headers()['retry-after'])).toBeGreaterThan(0);
    await expect(ann.page.locator('#toasts .toast')).toContainText('Slow down');
    await expect(box).not.toHaveValue(''); // kept for when the window opens
    await leave(ann);
  });

  // 4 messages of 2,000 `&` render to ~42 KB, past a 32 KiB queue: the snapshot a socket or a
  // multipart feed opens with sent them all at once, and every connect was cut as too slow.
  for (const t of ['ws', 'multipart'] as const) {
    test(`a room of long messages over ${t}: the snapshot fits the stream, and live messages follow (M2-03)`, async ({ browser }) => {
      const s = await startServer(test.info().config, { STREAM_MAX_QUEUED: '32KiB' });
      const base = `http://127.0.0.1:${s.port}`;
      const ann = await member(browser, base), bob = await member(browser, base);
      try {
        const slug = await newRoom(ann.page);
        await open(ann, slug, 'sse');
        for (let i = 0; i < 4; i++) await say(ann, `long ${i} ${'&'.repeat(1990)}`);
        const reconnect = t === 'ws' ? await routed(bob) : null;
        await open(bob, slug, t);
        if (reconnect) {
          // A socket's page asks only for what changed since it rendered: from a version of 0, all of it.
          await bob.page.locator('input[name="ver"]').evaluate((el: HTMLInputElement) => { el.value = '0'; });
          await reconnect();
        }
        await expect(message(bob, 'long 3')).toHaveCount(1);
        // What didn't fit is gone from the log, not left behind a gap (M2-26).
        await expect(message(bob, 'long 0')).toHaveCount(0);
        await say(ann, 'short, after');
        await expect(message(bob, 'short, after')).toHaveCount(1);
      } finally {
        await leave(ann, bob);
        await stopServer(s);
      }
    });
  }

  // A poll whose tag predates what the room let go gets the snapshot, which replaces the log
  // (M2-35): upserted, it kept what the page had with a silent gap before the newest. A tag the
  // room still covers upserts as before, and so does a refetch with no tag (SSE's resync), which
  // after a restart must keep what the page had (D37).
  test('a poll from before what the room let go replaces the log (M2-35)', async ({ browser }) => {
    const s = await startServer(test.info().config, { CHAT_RING_BYTES: '3KiB' });
    const base = `http://127.0.0.1:${s.port}`;
    const ann = await member(browser, base);
    try {
      const slug = await newRoom(ann.page);
      await open(ann, slug, 'sse');
      await say(ann, 'first');
      const since = (tag?: string) => ann.context.request.get(`${base}/chat/r/${slug}/since`, { headers: tag ? { 'HX-PTag': tag } : {} });
      const resync = await since();
      expect(await resync.text()).toContain('hx-swap="upsert sort"');
      const before = resync.headers()['hx-ptag'];
      for (let i = 0; i < 4; i++) await say(ann, `long ${i} ${'x'.repeat(1000)}`);
      const gap = await since(before);
      expect(gap.status()).toBe(200);
      const body = await gap.text();
      expect(body).toContain('hx-swap="innerHTML"');
      expect(body).not.toContain('first'); // let go: the snapshot is what the room still holds
      const now = BigInt(gap.headers()['hx-ptag']); // past 2^53: a Number would round it
      const near = await since(String(now - 1n));
      expect(await near.text()).toContain('hx-swap="upsert sort"');
    } finally {
      await leave(ann);
      await stopServer(s);
    }
  });

  // A reconnect sends the page's version (#ver-<room>): past what the room still holds, the log is
  // replaced, where an upsert kept the page's old messages with a silent gap before the newest (M2-31's
  // socket, M2-35's SSE). The page is put back to its version from before the gap, then the socket
  // reconnects (routed) or /events asks a resync. A socket answers its version once: sent again on the
  // same socket it buys nothing (M3-02). A restart's reconnect is the restart specs' (above): the page
  // keeps its log.
  for (const t of ['ws', 'sse'] as const) {
    test(`over ${t}, a reconnect past what the room let go replaces the log (M2-31, M2-35)`, async ({ browser }) => {
      const s = await startServer(test.info().config, { CHAT_RING_BYTES: '3KiB' });
      const base = `http://127.0.0.1:${s.port}`;
      const ann = await member(browser, base), bob = await member(browser, base);
      try {
        const slug = await newRoom(ann.page);
        await open(ann, slug, 'sse');
        const reconnect = t === 'ws' ? await routed(bob) : () => bob.page.evaluate(RESYNC);
        await open(bob, slug, t);
        await say(ann, 'before the gap');
        await expect(message(bob, 'before the gap')).toHaveCount(1);
        const ver = bob.page.locator('input[name="ver"]');
        const before = await ver.inputValue();

        for (let i = 0; i < 4; i++) await say(ann, `long ${i} ${'x'.repeat(1000)}`);
        await expect(message(bob, 'long 3')).toHaveCount(1);
        expect(BigInt(await ver.inputValue())).toBeGreaterThan(BigInt(before)); // the live messages moved it

        await ver.evaluate((el: HTMLInputElement, v) => { el.value = v; }, before);
        if (t === 'ws') {
          // The version again on the open socket: answered once already, so the log stays as it is.
          await bob.page.locator('.chat-pane').evaluate(pane => pane.dispatchEvent(new CustomEvent('htmx:ws:after:connection')));
          await bob.page.waitForTimeout(500);
          await expect(message(bob, 'before the gap')).toHaveCount(1);
        }
        await reconnect();
        await expect(message(bob, 'before the gap')).toHaveCount(0); // let go by the room: replaced
        await expect(message(bob, 'long 0')).toHaveCount(0);
        await expect(message(bob, 'long 3')).toHaveCount(1);

        // A reconnect the room still reaches upserts what changed, here nothing: the log stays.
        const kept = await messages(bob).count();
        await reconnect();
        await bob.page.waitForTimeout(500);
        await expect(messages(bob)).toHaveCount(kept);
        await expect(message(bob, 'long 3')).toHaveCount(1);
      } finally {
        await leave(ann, bob);
        await stopServer(s);
      }
    });
  }

  // Brackets in a message are text: over the socket they once counted against its nesting bound,
  // and the message was refused after the composer had cleared it (M2-36).
  test('over ws, a message full of brackets posts, as it does on the other transports (M2-36)', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const slug = await newRoom(ann.page);
    await open(ann, slug, 'ws');
    const box = ann.page.locator('.chat-composer textarea');
    const text = '{"a":' + '['.repeat(300) + '}';
    await box.fill(text);
    await box.press('Enter');
    await expect(message(ann, text)).toHaveCount(1);
    await expect(ann.page.locator('#toasts .toast')).toHaveCount(0);
    await say(ann, 'still here');
    await expect(message(ann, 'still here')).toHaveCount(1);
    await leave(ann);
  });

  test('the connection setting sticks to the member', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/chat');
    await ann.page.locator('#transport').selectOption('poll');
    // The form posts from /chat back to /chat: wait for the page it lands on, not the URL.
    const landed = ann.page.waitForResponse((r) => new URL(r.url()).pathname === '/chat' && r.request().method() === 'GET');
    await ann.page.getByRole('button', { name: 'Use' }).click();
    await landed;
    await ann.page.waitForLoadState();
    await expect(ann.page.locator('#transport')).toHaveValue('poll');
    const res = await ann.page.goto('/chat/r/lobby');
    expect(res!.headers()['x-impl']).toContain('chat.transport=poll');
    await expect(ann.page.locator('.chat-pane')).toHaveAttribute('hx-ptag', /^\d+$/);
    await leave(ann);
  });
});
