import { test, expect } from '../../fixtures';
import { leave, member, uid } from '../../helpers/members';

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

  test('a decode bomb goes before a pixel is allocated', async ({ browser, baseURL }) => {
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
