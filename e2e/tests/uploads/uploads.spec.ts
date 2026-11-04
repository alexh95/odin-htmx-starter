import { randomBytes } from 'node:crypto';
import { cpSync, mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { test, expect } from '../../fixtures';
import type { Page } from '@playwright/test';
import { signIn } from '../../helpers/accounts';
import { leave, member, uid } from '../../helpers/members';
import { startServer, stopServer, mainOrigin, type Server } from '../../helpers/server';

// Uploads (PLAN §14.2, §17.6): an image goes up in chunks through the shim, each chunk at the
// offset the server is at, and finishing it checks what the bytes are, whatever they were called.
// A finished one is a blob, named by its content, and chat's messages carry it.
const T = { tag: ['@uploads', '@chat'] };

// 1×1, white. Anything after IEND is ignored by every reader, so it pads a file past one chunk.
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC', 'base64');
const CHUNK = 4 << 20;

const made = async (page: any, size: number) => {
  const r = await page.request.post(`/uploads?size=${size}`);
  expect(r.status()).toBe(201);
  return (await r.json()).id as number;
};
const put = (page: any, id: number, off: number, data: Buffer) => page.request.put(`/uploads/${id}?off=${off}`, { data });

async function room(page: any, transport: string): Promise<string> {
  await page.goto('/chat');
  await page.locator('#room-name').fill(uid('pics '));
  await page.getByRole('button', { name: 'Create' }).click();
  await page.waitForURL(/\/chat\/r\//);
  const slug = new URL(page.url()).pathname.split('/').pop()!;
  await page.goto(`/chat/r/${slug}?transport=${transport}`);
  await expect(page.locator('.chat-room')).toBeVisible();
  return slug;
}

test.describe('uploads', T, () => {
  for (const transport of ['ws', 'sse'] as const) {
    test(`an image goes up in chunks and shows in the room, over ${transport}`, async ({ browser, baseURL }) => {
      test.slow();
      const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
      const slug = await room(ann.page, transport);
      await bob.page.goto(`/chat/r/${slug}?transport=sse`);
      await expect(bob.page.locator('.chat-room')).toBeVisible();
      if (transport === 'ws') await expect.poll(() => ann.page.locator('.chat-pane').evaluate((el: any) => el._htmx?.ws?.connection?.socket?.readyState)).toBe(1);

      // Two chunks, and a caption is optional: the text box stops being required once attached.
      const big = Buffer.concat([PNG, Buffer.alloc(CHUNK + 1024)]);
      await ann.page.locator('.chat-attach input').setInputFiles({ name: 'dot.png', mimeType: 'image/png', buffer: big });
      await expect(ann.page.locator('.chat-attach-say')).toHaveText('Attached: dot.png', { timeout: 20_000 });
      await ann.page.getByRole('button', { name: 'Send' }).click();

      const img = bob.page.locator('.chat-log .chat-img img');
      await expect(img).toHaveCount(1);
      await expect.poll(() => img.evaluate((el: HTMLImageElement) => el.naturalWidth)).toBe(1);
      await expect(img).toHaveAttribute('alt', `An image from ${ann.name}`);
      await expect(ann.page.locator('.chat-attach-say')).toHaveText(''); // the form forgot it
      await expect(ann.page.locator('.chat-composer textarea')).toHaveAttribute('required', '');

      await leave(ann, bob);
    });
  }

  test('a dropped chunk resumes from where the server got to', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/chat');
    const id = await made(ann.page, PNG.length);
    const half = PNG.length >> 1;
    expect((await put(ann.page, id, 0, PNG.subarray(0, half))).status()).toBe(200);

    // Its answer "lost": the same chunk again is told where to go on from, and a stale offset too.
    const again = await put(ann.page, id, 0, PNG.subarray(0, half));
    expect(again.status()).toBe(409);
    expect((await again.json()).received).toBe(half);
    expect((await (await ann.page.request.get(`/uploads/${id}`)).json())).toEqual({ received: half, size: PNG.length });
    expect((await ann.page.request.post(`/uploads/${id}/finish`)).status()).toBe(409); // not all here

    expect((await put(ann.page, id, half, PNG.subarray(half))).status()).toBe(200);
    const done = await ann.page.request.post(`/uploads/${id}/finish`);
    expect(done.status()).toBe(200);
    const { sha256 } = await done.json();
    expect(sha256).toMatch(/^[0-9a-f]{64}$/);

    // Served as what it is, from its address, for good.
    const blob = await ann.page.request.get(`/uploads/blob/${sha256}`);
    expect(blob.status()).toBe(200);
    expect(blob.headers()['content-type']).toContain('image/png');
    expect(blob.headers()['x-content-type-options']).toBe('nosniff');
    expect(blob.headers()['content-disposition']).toBe('inline');
    expect(blob.headers()['cache-control']).toContain('immutable');
    expect(Buffer.compare(await blob.body(), PNG)).toBe(0);
    expect((await ann.page.request.post(`/uploads/${id}/finish`)).status()).toBe(404); // it's closed
    await leave(ann);
  });

  test('what the bytes are decides, not what they are called', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/chat');
    for (const [bytes, why] of [
      ['<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>', 'Only PNG and JPEG images.'],
      ['<!doctype html><script>alert(1)</script>', 'Only PNG and JPEG images.'],
      [Buffer.concat([PNG.subarray(0, 8), Buffer.from('not a png at all, whatever it starts with')]), "That image can't be read."],
    ] as const) {
      const data = Buffer.from(bytes as any);
      const id = await made(ann.page, data.length);
      expect((await put(ann.page, id, 0, data)).status()).toBe(200);
      const r = await ann.page.request.post(`/uploads/${id}/finish`);
      expect(r.status()).toBe(422);
      expect((await r.json()).error).toBe(why);
    }
    await leave(ann);
  });

  test('an image past the pixel cap is refused by its header', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/chat');
    const bomb = Buffer.from(PNG);
    bomb.writeUInt32BE(60_000, 16); // width × height, in IHDR
    bomb.writeUInt32BE(60_000, 20);
    const id = await made(ann.page, bomb.length);
    await put(ann.page, id, 0, bomb);
    const r = await ann.page.request.post(`/uploads/${id}/finish`);
    expect(r.status()).toBe(422);
    expect((await r.json()).error).toContain('too large');
    await leave(ann);
  });

  // Nothing here decodes: what its header vouches for is kept, and the viewer's browser shows it
  // broken, as it would any bad file. `nosniff` and the type from its row are what make that safe.
  test('an image corrupt past its header is stored, and shows as broken', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const slug = await room(ann.page, 'sse');
    const data = Buffer.concat([PNG.subarray(0, 33), randomBytes(16)]);
    const id = await made(ann.page, data.length);
    expect((await put(ann.page, id, 0, data)).status()).toBe(200);
    const done = await ann.page.request.post(`/uploads/${id}/finish`);
    expect(done.status()).toBe(200);
    const sha = (await done.json()).sha256;
    expect((await ann.page.request.post(`/chat/r/${slug}`, { form: { body: 'broken', attachment: sha } })).status()).toBe(200);
    const img = ann.page.locator('.chat-log .chat-img img');
    await expect(img).toHaveCount(1);
    await expect.poll(() => img.evaluate((el: HTMLImageElement) => el.complete && el.naturalWidth)).toBe(0);
    await leave(ann);
  });

  test('sizes, overruns, two at a time, and only your own', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
    await ann.page.goto('/chat');
    await bob.page.goto('/chat');
    expect((await ann.page.request.post(`/uploads?size=${(10 << 20) + 1}`)).status()).toBe(422);
    expect((await ann.page.request.post('/uploads?size=0')).status()).toBe(422);
    const a = await made(ann.page, 4), b = await made(ann.page, 4);
    const third = await ann.page.request.post('/uploads?size=4');
    expect(third.status()).toBe(422);
    expect((await third.json()).error).toContain('Two uploads at a time');

    expect((await put(ann.page, a, 0, Buffer.alloc(5))).status()).toBe(422); // past what it said
    expect((await put(bob.page, b, 0, Buffer.alloc(4))).status()).toBe(404); // not Bob's
    expect((await bob.page.request.get(`/uploads/${b}`)).status()).toBe(404);
    expect((await bob.page.request.post(`/uploads/${b}/finish`)).status()).toBe(404);
    expect((await ann.page.request.get(`/uploads/blob/${'0'.repeat(64)}`)).status()).toBe(404);
    expect((await ann.page.request.get('/uploads/blob/..%2f..%2fdata.db')).status()).toBe(404);
    await leave(ann, bob);
  });

  test('a post can only name a blob that exists', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/chat/r/lobby?transport=sse');
    const r = await ann.page.request.post('/chat/r/lobby', { form: { body: 'look', attachment: 'a'.repeat(64) } });
    expect(r.status()).toBe(422);
    expect(await r.text()).toContain('there any more');
    await leave(ann);
  });

  test('a guest has no way in', async ({ browser, baseURL }) => {
    const context = await browser.newContext({ baseURL });
    expect((await context.request.post('/uploads?size=4', { maxRedirects: 0 })).status()).toBeGreaterThanOrEqual(300);
    expect((await context.request.get(`/uploads/blob/${'0'.repeat(64)}`, { maxRedirects: 0 })).status()).toBeGreaterThanOrEqual(300);
    await context.close();
  });
});

// A PNG of its own: bytes after IEND are ignored, and they give it its own address.
const unique = () => Buffer.concat([PNG, randomBytes(16)]);

async function uploaded(page: Page, data: Buffer): Promise<string> {
  const id = await made(page, data.length);
  expect((await put(page, id, 0, data)).status()).toBe(200);
  const done = await page.request.post(`/uploads/${id}/finish`);
  expect(done.status()).toBe(200);
  return (await done.json()).sha256;
}

const blob = (page: Page, sha: string) => page.request.get(`/uploads/blob/${sha}`);
const message = (page: Page, text: string) => page.locator('.chat-log > article.chat-msg').filter({ hasText: text });

async function menuOf(page: Page, text: string) {
  const msg = message(page, text);
  await msg.hover();
  await msg.getByRole('button', { name: 'Message actions' }).click();
  return msg;
}

async function post(page: Page, slug: string, body: string, attachment: string) {
  expect((await page.request.post(`/chat/r/${slug}`, { form: { body, attachment } })).status()).toBe(200);
}

test.describe('a blob lives while something holds it', T, () => {
  test("a member's delete takes it at once, unless another message holds it", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const slug = await room(ann.page, 'sse');
    const sha = await uploaded(ann.page, unique());
    await post(ann.page, slug, 'one', sha);
    await post(ann.page, slug, 'two', sha);
    await ann.page.goto(`/chat/r/${slug}?transport=sse`);

    let msg = await menuOf(ann.page, 'one');
    await msg.getByRole('button', { name: 'Delete' }).click();
    await expect(ann.page.locator('.chat-log').filter({ hasText: 'Message deleted.' })).toHaveCount(1);
    expect((await blob(ann.page, sha)).status()).toBe(200); // the other still holds it

    msg = await menuOf(ann.page, 'two');
    await msg.getByRole('button', { name: 'Delete' }).click();
    await expect.poll(async () => (await blob(ann.page, sha)).status()).toBe(404);
    await leave(ann);
  });
});

test.describe('a moderator takes an image everywhere', { tag: ['@uploads', '@chat', '@accounts-accounts', '@audit'] }, () => {
  test('from a report, out of a private room too, keeping the copy past an author\'s delete', async ({ browser, baseURL }) => {
    const mod = await signIn(browser, baseURL!, '/chat');
    mod.page.on('dialog', (d) => d.accept('removed after a report'));
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
    bob.page.on('dialog', (d) => d.accept('this image'));
    const open = await room(ann.page, 'sse');
    const sha = await uploaded(ann.page, unique());
    await post(ann.page, open, 'reported one', sha);

    // The same image in a private room of Ann's, which no moderator reads.
    await ann.page.goto('/chat');
    await ann.page.locator('#room-name').fill(uid('den '));
    await ann.page.locator('#room-kind').selectOption('private');
    await ann.page.getByRole('button', { name: 'Create' }).click();
    await ann.page.waitForURL(/\/chat\/r\//);
    const den = new URL(ann.page.url()).pathname.split('/').pop()!;
    await post(ann.page, den, 'the same one, private', sha);

    await bob.page.goto(`/chat/r/${open}?transport=sse`);
    const msg = await menuOf(bob.page, 'reported one');
    await msg.getByRole('button', { name: 'Report' }).click();
    await expect(bob.page.locator('#toasts .toast').last()).toContainText('Reported');

    // An open report holds it: her delete leaves the moderator the image.
    await ann.page.goto(`/chat/r/${open}?transport=sse`);
    const hers = await menuOf(ann.page, 'reported one');
    await hers.getByRole('button', { name: 'Delete' }).click();
    await expect(message(ann.page, 'reported one')).toHaveCount(0);
    expect((await blob(ann.page, sha)).status()).toBe(200);

    await ann.page.goto(`/chat/r/${den}?transport=sse`);
    await expect(ann.page.locator('.chat-img img')).toHaveCount(1);

    await mod.page.goto('/chat/reports');
    const report = mod.page.locator('.chat-report').filter({ hasText: 'reported one' });
    await expect(report.locator('.chat-img img')).toHaveCount(1);
    await report.getByRole('button', { name: 'Remove the message' }).click();
    await expect(mod.page.locator('.chat-report').filter({ hasText: 'reported one' })).toHaveCount(0);

    await expect(ann.page.locator('.chat-img img')).toHaveCount(0); // live, on an open page
    await expect(message(ann.page, 'the same one, private')).toHaveCount(1); // her words stay
    expect((await blob(ann.page, sha)).status()).toBe(404);
    const csv = await (await mod.context.request.get('/admin/audit/export?action=chat.image_removed')).text();
    expect(csv).toContain(sha);
    await mod.context.close();
    await leave(ann, bob);
  });

  test('an image alone leaves a line saying so', async ({ browser, baseURL }) => {
    const mod = await signIn(browser, baseURL!, '/chat');
    mod.page.on('dialog', (d) => d.accept('off topic'));
    const ann = await member(browser, baseURL!);
    const open = await room(ann.page, 'sse');
    const sha = await uploaded(ann.page, unique());
    await post(ann.page, open, 'with words', sha);
    await post(ann.page, open, '', sha);
    await ann.page.goto(`/chat/r/${open}?transport=sse`);
    await mod.page.goto(`/chat/r/${open}?transport=sse`);
    const msg = await menuOf(mod.page, 'with words');
    await msg.getByRole('button', { name: 'Remove' }).click();
    await expect(ann.page.locator('.chat-log')).toContainText('Image removed.');
    await expect(ann.page.locator('.chat-img img')).toHaveCount(0);
    await mod.context.close();
    await leave(ann);
  });
});

// DATA.md's restore, for images: the database's backup and the blobs' copy, on a new disk.
test('a restore brings an image back, and a removal reaches the copy', { tag: ['@uploads', '@chat', '@jobs', '@accounts-accounts', '@platform-sqlite'] }, async ({ browser }) => {
  test.slow();
  const dir = mkdtempSync(path.join(os.tmpdir(), 'odin-blobs-'));
  const env = { DB_PATH: path.join(dir, 'data.db'), BACKUP_DIR: path.join(dir, 'backups'), UPLOADS_DIR: path.join(dir, 'uploads') };
  let s: Server | undefined;
  try {
    s = await startServer(test.info().config, env);
    const admin = await signIn(browser, mainOrigin(s.port), '/chat');
    admin.page.on('dialog', (d) => d.accept('the copy'));
    const slug = await room(admin.page, 'sse');
    const kept = await uploaded(admin.page, unique()), gone = await uploaded(admin.page, unique());
    await post(admin.page, slug, 'kept', kept);
    await post(admin.page, slug, 'gone', gone);

    const mirror = async () => {
      await admin.page.goto('/admin/jobs');
      const row = admin.page.locator('tr.job').filter({ has: admin.page.locator('code', { hasText: /^uploads\.mirror$/ }) });
      const before = await admin.page.locator('#jobs-runs tr.run').count();
      await row.getByRole('button', { name: 'Run now' }).click();
      await expect(admin.page.locator('#jobs-runs tr.run')).toHaveCount(before + 1);
      await expect(admin.page.locator('#jobs-runs tr.run').first().locator('.run-state')).toHaveText('done', { timeout: 10_000 });
    };
    const copy = path.join(env.BACKUP_DIR, 'blobs');
    const copied = () => { try { return execFileSync('ls', [copy], { encoding: 'utf8' }); } catch { return ''; } };
    await mirror();
    expect(copied()).toContain(kept);
    expect(copied()).toContain(gone);

    // A blob that's gone goes from the copy on the next run.
    await admin.page.goto(`/chat/r/${slug}?transport=sse`);
    const msg = await menuOf(admin.page, 'gone');
    await msg.getByRole('button', { name: 'Delete' }).click();
    await expect.poll(async () => (await blob(admin.page, gone)).status()).toBe(404);
    await mirror();
    expect(copied()).toContain(kept);
    expect(copied()).not.toContain(gone);

    const db = path.join(dir, 'restored.db');
    execFileSync(s.proc.spawnfile, ['--backup', db], { env: { ...process.env, DB_PATH: env.DB_PATH }, stdio: 'pipe' });
    const cookies = await admin.context.cookies();
    await admin.context.close();
    await stopServer(s);
    s = undefined;

    const fresh = path.join(dir, 'fresh-uploads');
    cpSync(copy, path.join(fresh, 'blobs'), { recursive: true });
    s = await startServer(test.info().config, { DB_PATH: db, BACKUP_DIR: path.join(dir, 'backups2'), UPLOADS_DIR: fresh });
    const back = await browser.newContext({ baseURL: mainOrigin(s.port) });
    await back.addCookies(cookies.map((c) => ({ ...c, domain: new URL(mainOrigin(s!.port)).hostname })));
    const page = await back.newPage();
    await page.goto(`/chat/r/${slug}?transport=sse`);
    const img = page.locator('.chat-log .chat-img img');
    await expect(img).toHaveCount(1);
    await expect.poll(() => img.evaluate((el: HTMLImageElement) => el.naturalWidth)).toBe(1);
    await back.close();
  } finally {
    if (s) await stopServer(s);
    try { rmSync(dir, { recursive: true, force: true }); } catch { /* best effort */ }
  }
});
