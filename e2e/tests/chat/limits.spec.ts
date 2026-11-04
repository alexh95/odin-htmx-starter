import net from 'node:net';
import { test, expect } from '../../fixtures';
import type { Page } from '@playwright/test';
import { signIn } from '../../helpers/accounts';
import { leave, member, uid } from '../../helpers/members';
import { startServer, stopServer, mainOrigin, type Server } from '../../helpers/server';

// What one member may do to everyone else (docs/audit/M6.md): reports, rooms, edits, uploads' bytes and
// large bodies each stop at a limit. A server of its own, whose limits are the test's: the shared
// one lifts them, for the rest of the suite and for load.
const T = { tag: ['@chat'] };

const own = async (env: NodeJS.ProcessEnv, run: (s: Server, base: string) => Promise<void>) => {
  const s = await startServer(test.info().config, env);
  try {
    await run(s, mainOrigin(s.port));
  } finally {
    await stopServer(s);
  }
};

async function posted(page: Page, slug: string, body: string): Promise<string> {
  const r = await page.request.post(`/chat/r/${slug}`, { form: { body } });
  expect(r.status()).toBe(200);
  return (await r.text()).match(/id="m-(\d+)"/)![1];
}

const report = (page: Page, id: string) => page.request.post(`/chat/m/${id}/report`, { headers: { 'hx-prompt': 'why' } });

test.describe('limits', T, () => {
  test('a report: once a message, and only so many a minute', async ({ browser }) => {
    await own({ CHAT_REPORTS_PER_MINUTE: '3' }, async (_s, base) => {
      const ann = await member(browser, base), bob = await member(browser, base);
      await ann.page.goto('/chat');
      await bob.page.goto('/chat');
      const a = await posted(ann.page, 'lobby', 'one'), b = await posted(ann.page, 'lobby', 'two');
      expect((await report(bob.page, a)).status()).toBe(200);
      expect((await report(bob.page, a)).status()).toBe(200); // as the first answered: no second row
      expect((await report(bob.page, b)).status()).toBe(200);
      expect((await report(bob.page, b)).status()).toBe(429);
      await leave(ann, bob);
    });
  });

  test('a moderator sees one row for a report made twice', { tag: ['@chat', '@accounts-accounts'] }, async ({ browser, baseURL }) => {
    const mod = await signIn(browser, baseURL!, '/chat');
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
    await ann.page.goto('/chat');
    const mark = uid('twice ');
    const id = await posted(ann.page, 'lobby', mark);
    await bob.page.goto('/chat');
    await report(bob.page, id);
    await report(bob.page, id);
    await mod.page.goto('/chat/reports');
    await expect(mod.page.locator('.chat-report').filter({ hasText: mark })).toHaveCount(1);
    await mod.context.close();
    await leave(ann, bob);
  });

  test('a member owns so many rooms, and a DM is none of them', async ({ browser }) => {
    await own({ CHAT_ROOMS_PER_MEMBER: '2' }, async (_s, base) => {
      const ann = await member(browser, base), bob = await member(browser, base);
      await ann.page.goto('/chat');
      await bob.page.goto('/chat/r/lobby?transport=sse');
      const make = (name: string) => ann.page.request.post('/chat/rooms', { form: { name, kind: 'public' } });
      expect((await make(uid('a '))).status()).toBeLessThan(400);
      expect((await make(uid('b '))).status()).toBeLessThan(400);
      expect((await make(uid('c '))).status()).toBe(422);
      const id = await bob.page.locator('.chat-log').getAttribute('data-me');
      expect((await ann.page.request.post(`/chat/dm/${id}`)).status()).toBe(204);
      await leave(ann, bob);
    });
  });

  test('rooms, DMs and blocks share a rate', async ({ browser }) => {
    await own({ CHAT_WRITES_PER_MINUTE: '2' }, async (_s, base) => {
      const ann = await member(browser, base);
      await ann.page.goto('/chat');
      const make = (name: string) => ann.page.request.post('/chat/rooms', { form: { name, kind: 'public' } });
      expect((await make(uid('a '))).status()).toBeLessThan(400);
      expect((await make(uid('b '))).status()).toBeLessThan(400);
      expect((await make(uid('c '))).status()).toBe(429);
      expect((await ann.page.request.post('/chat/unblock/1')).status()).toBe(429);
      await leave(ann);
    });
  });

  test('an edit passes the rules a post does', { tag: ['@chat', '@accounts-accounts', '@audit'] }, async ({ browser, baseURL }) => {
    const mod = await signIn(browser, baseURL!, '/chat');
    mod.page.on('dialog', (d) => d.accept('quiet'));
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/chat');
    await mod.page.goto('/chat');
    const name = uid('room ');
    await mod.page.request.post('/chat/rooms', { form: { name, kind: 'public' } });
    const slug = (await mod.page.goto('/chat'), new URL(await mod.page.locator('.chat-rooms a, a[href^="/chat/r/"]').filter({ hasText: name }).first().evaluate((a: HTMLAnchorElement) => a.href)).pathname.split('/').pop()!);
    const id = await posted(ann.page, slug, 'said in time');
    const edit = () => ann.page.request.post(`/chat/m/${id}/edit`, { form: { body: 'and changed' } });
    expect((await edit()).status()).toBe(200);
    await mod.page.goto(`/chat/r/${slug}?transport=sse`);
    await mod.page.locator('.chat-mod').getByRole('button', { name: 'Lock' }).click();
    await expect(mod.page.locator('.chat-mod').getByRole('button', { name: 'Unlock' })).toBeVisible();
    const locked = await edit();
    expect(locked.status()).toBe(403);
    expect(await locked.text()).toContain('locked');
    expect((await ann.page.request.get(`/chat/m/${id}/edit`)).status()).toBe(403);
    await mod.context.close();
    await leave(ann);
  });

  test('a member uploads so many bytes a day', { tag: ['@chat', '@uploads'] }, async ({ browser }) => {
    await own({ UPLOADS_BYTES_PER_DAY: '1KiB' }, async (_s, base) => {
      const ann = await member(browser, base);
      await ann.page.goto('/chat');
      expect((await ann.page.request.post('/uploads?size=800')).status()).toBe(201);
      const r = await ann.page.request.post('/uploads?size=800');
      expect(r.status()).toBe(422);
      expect((await r.json()).error).toContain('as much as you can upload today');
      await leave(ann);
    });
  });

  // Each holds a socket mid-body, and front counts it before reading a byte. A body cut off gives
  // its count back: otherwise a client that leaves would close uploads for everyone.
  test('large bodies: two a member, and one cut off gives its place back', { tag: ['@chat', '@uploads'] }, async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/chat');
    const made = await (await ann.page.request.post('/uploads?size=2097152')).json();
    const cookie = (await ann.context.cookies()).map((c) => `${c.name}=${c.value}`).join('; ');
    const u = new URL(baseURL!);
    const open = () => new Promise<{ sock: net.Socket; head: Promise<string> }>((done) => {
      const sock = net.connect(Number(u.port), u.hostname, () => {
        sock.write(`PUT /uploads/${made.id}?off=0 HTTP/1.1\r\nHost: ${u.host}\r\nCookie: ${cookie}\r\nContent-Length: 2097152\r\n\r\n`);
        sock.write(Buffer.alloc(1024));
        done({ sock, head: new Promise((got) => { sock.once('data', (d) => got(d.toString())); sock.once('close', () => got('')); }) });
      });
    });
    const a = await open(), b = await open();
    await new Promise((r) => setTimeout(r, 300));
    const third = await open();
    expect(await third.head).toContain('503');
    a.sock.destroy();
    b.sock.destroy();
    await expect.poll(async () => {
      const c = await open();
      const got = await Promise.race([c.head, new Promise<string>((r) => setTimeout(() => r('held'), 300))]);
      c.sock.destroy();
      return got;
    }).toBe('held');
    third.sock.destroy();
    await leave(ann);
  });
});

test('joining, leaving and revoking an invite share that rate', { tag: ['@chat'] }, async ({ browser }) => {
  await own({ CHAT_WRITES_PER_MINUTE: '3' }, async (_s, base) => {
    const ann = await member(browser, base), bob = await member(browser, base);
    await ann.page.goto('/chat');
    await bob.page.goto('/chat');
    expect((await ann.page.request.post('/chat/rooms', { form: { name: uid('den '), kind: 'private' } })).status()).toBeLessThan(400);
    const slug = (await ann.page.goto('/chat'), new URL(await ann.page.locator('a[href^="/chat/r/"]').filter({ hasText: 'den ' }).first().evaluate((a: HTMLAnchorElement) => a.href)).pathname.split('/').pop()!);
    const invite = await ann.page.request.post(`/chat/r/${slug}/invite`, { form: { once: '0' } });
    expect(invite.status()).toBe(200);
    const [href, id] = (await invite.text()).match(/\/chat\/join\/(\d+)\.[^"]+/)!;
    expect((await ann.page.request.post(`/chat/r/${slug}/invites/${id}/revoke`)).status()).toBe(200); // the third
    expect((await ann.page.request.post(`/chat/r/${slug}/invites/${id}/revoke`)).status()).toBe(429);
    expect((await ann.page.request.post(href)).status()).toBe(429); // join
    expect((await ann.page.request.post(`/chat/r/${slug}/leave`)).status()).toBe(429);
    await leave(ann, bob);
  });
});

test.describe('what a delete takes back', { tag: ['@chat', '@notify'] }, () => {
  test("a DM's line leaves the Inbox with its message", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
    await bob.page.goto('/chat/r/lobby?transport=sse');
    const id = await bob.page.locator('.chat-log').getAttribute('data-me');
    await ann.page.goto('/chat');
    const path = (await ann.page.request.post(`/chat/dm/${id}`)).headers()['hx-redirect'];
    const slug = path.split('/').pop()!;
    const mark = uid('sent to the wrong person ');
    const m = await posted(ann.page, slug, mark);
    await expect.poll(async () => (await bob.page.request.get('/notify/list')).text()).toContain(mark);
    expect((await ann.page.request.post(`/chat/m/${m}/delete`)).status()).toBe(200);
    await expect.poll(async () => (await bob.page.request.get('/notify/list')).text()).not.toContain(mark);
    await leave(ann, bob);
  });
});

test("a search can't be made to fail by what's typed", T, async ({ browser, baseURL }) => {
  const ann = await member(browser, baseURL!);
  await ann.page.goto('/chat');
  expect((await ann.page.request.get('/chat/search?q=%00')).status()).toBe(200);
  expect((await ann.page.request.get(`/chat/search?q=${'x'.repeat(4000)}`)).status()).toBeLessThan(500);
  // Past the cap in a two-byte character: cut at its start, not through it.
  const long = await ann.page.request.get(`/chat/search?q=${encodeURIComponent('x' + 'é'.repeat(150))}`);
  expect(long.status()).toBe(200);
  expect(await long.text()).not.toContain('\ufffd');
  await leave(ann);
});
