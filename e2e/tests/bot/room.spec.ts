import { test, expect, BUILD } from '../../fixtures';
import type { Page } from '@playwright/test';
import { startFake, stopFake, fakeStats, type Fake } from '../../helpers/fakellama';
import { leave, member, uid, type Member } from '../../helpers/members';
import { mainOrigin, startServer, stopServer, type Server } from '../../helpers/server';

// Room mode (PLAN §6.2, §14.3, X37): `@bot` in a room, over two static topic rows. The answer comes as
// a bubble to everyone in the room on any transport, then is a stored message from the bot.
const T = { tag: ['@bot', '@chat'] };
const TRANSPORTS = ['ws', 'sse', 'poll', 'multipart'] as const;

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
  if (transport === 'ws') {
    await expect.poll(() => m.page.locator('.chat-pane').evaluate((el: any) => el._htmx?.ws?.connection?.socket?.readyState)).toBe(1);
  }
}

async function say(m: Member, text: string) {
  const box = m.page.locator('.chat-composer textarea');
  await box.fill(text);
  await box.press('Enter');
  await expect(box).toHaveValue('');
}

// What the room's bubble last said, kept by the page past the bubble's own removal.
async function watchBubble(m: Member) {
  await m.page.evaluate(() => {
    new MutationObserver(() => {
      const b = document.querySelector('.bot-live .chat-body');
      if (b) (window as any).__bubble = (b as HTMLElement).innerText;
    }).observe(document.body, { subtree: true, childList: true, characterData: true });
  });
}
const lastBubble = (m: Member) => m.page.evaluate(() => (window as any).__bubble as string);

const fromBot = (m: Member) => m.page.locator('.chat-log > article.chat-msg', { has: m.page.locator('.chat-name', { hasText: 'Capcom' }) });

test.describe('room mode', T, () => {
  for (const t of TRANSPORTS) {
    test(`the answer reaches a reader over ${t}, is stored, and a reload keeps it`, async ({ browser, baseURL }) => {
      const ann = await member(browser, baseURL!);
      const bob = await member(browser, baseURL!);
      const slug = await newRoom(ann.page);
      await open(ann, slug, 'sse');
      await open(bob, slug, t);
      await say(ann, '@bot what are you?');
      await expect(fromBot(bob)).toHaveCount(1);
      await expect(fromBot(ann)).toHaveCount(1);
      await expect(bob.page.locator('.bot-live')).toHaveCount(0); // the bubble gave way to the message
      const said = await fromBot(bob).locator('.chat-body').innerText();
      expect(said.length).toBeGreaterThan(3);
      await bob.page.reload();
      await expect(fromBot(bob).locator('.chat-body')).toHaveText(said);
      await expect(fromBot(bob)).toHaveAttribute('data-author', '0');
      await leave(ann, bob);
    });
  }

  test('only `@bot` asks, the bot never asks itself, and no one is mentioned by it', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const slug = await newRoom(ann.page);
    await open(ann, slug, 'sse');
    await say(ann, 'a plain line, me@bot.example');
    await say(ann, '@bot hello');
    await expect(fromBot(ann)).toHaveCount(1);
    await ann.page.waitForTimeout(500);
    await expect(fromBot(ann)).toHaveCount(1);
    await leave(ann);
  });

  test('a DM doesn\'t ask the bot', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const bob = await member(browser, baseURL!);
    const slug = await newRoom(ann.page);
    await open(ann, slug, 'sse');
    await say(ann, 'hello bob');
    await open(bob, slug, 'sse');
    await bob.page.locator('.chat-more').first().click();
    await bob.page.getByRole('button', { name: `Message ${ann.name}` }).click();
    await bob.page.waitForURL(/\/chat\/r\//);
    await expect(bob.page.locator('.chat-room')).toBeVisible();
    await say(bob, '@bot are you there?');
    await bob.page.waitForTimeout(500);
    await expect(fromBot(bob)).toHaveCount(0);
    await leave(ann, bob);
  });

  test("a question can't be read off the topic", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    for (const family of ['bot.ask', 'chat.reply']) {
      expect((await ann.page.request.get(`/events?t=${family}:1`)).status()).toBe(400);
    }
    await leave(ann);
  });

  test('the asker\'s limits hold in a room, and are said to them alone', async ({ browser }) => {
    const config = test.info().config;
    const s = await startServer(config, { BOT_MEMBER_PER_HOUR: '1' });
    try {
      const ann = await member(browser, mainOrigin(s.port));
      const slug = await newRoom(ann.page);
      await open(ann, slug, 'sse');
      await say(ann, '@bot first');
      await expect(fromBot(ann)).toHaveCount(1);
      await say(ann, '@bot second');
      await expect(ann.page.locator('#toasts .toast')).toContainText('1 questions this hour');
      await expect(fromBot(ann)).toHaveCount(1);
      await leave(ann);
    } finally {
      await stopServer(s);
    }
  });
});

test.describe('room mode on llama', T, () => {
  let fake: Fake;
  let s: Server;

  test.beforeEach(async () => {
    fake = await startFake();
    s = await startServer(test.info().config, { BOT_BACKEND: 'llama', BOT_LLAMA_URL: fake.url, BOT_LLAMA_PROBE: '100ms', BOT_CONCURRENCY: '1', BOT_LLAMA_FIRST_TOKEN: '1s' });
  });

  test.afterEach(async () => {
    await stopServer(s);
    stopFake(fake);
  });

  test('a bubble grows for everyone, and what the model sends stays text', async ({ browser }) => {
    const ann = await member(browser, mainOrigin(s.port));
    const bob = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=llama');
    const slug = await newRoom(ann.page);
    await open(ann, slug, 'sse');
    await open(bob, slug, 'poll');
    await say(ann, '@bot fake:long a story');
    await expect(bob.page.locator('.bot-live .chat-body')).toContainText('word1');
    await expect(fromBot(bob)).toHaveCount(1, { timeout: 15000 });
    await expect(bob.page.locator('.bot-live')).toHaveCount(0);
    await say(ann, '@bot <img src=x onerror=alert(1)><script>alert(2)</script>');
    await expect(fromBot(bob).last().locator('.chat-body')).toContainText('<img src=x onerror=alert(1)>');
    await expect(bob.page.locator('.chat-log img[src="x"]')).toHaveCount(0);
    expect(bob.errors).toEqual([]);
    await leave(ann, bob);
  });

  test('an answer past a message is cut to one', async ({ browser }) => {
    const ann = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=llama');
    const slug = await newRoom(ann.page);
    await open(ann, slug, 'sse');
    await watchBubble(ann);
    await say(ann, '@bot fake:wall');
    await expect(fromBot(ann)).toHaveCount(1);
    const body = await fromBot(ann).locator('.chat-body').innerText();
    expect([...body].length).toBe(2000);
    expect(body.endsWith('…')).toBe(true);
    expect(await lastBubble(ann)).toBe(body); // it doesn't shrink as it lands
    await expect.poll(async () => (await fakeStats(fake)).closed).toBe(1); // the model was stopped there
    await leave(ann);
  });

  test('a failed ask stores nothing, and tells its asker alone', async ({ browser }) => {
    const ann = await member(browser, mainOrigin(s.port));
    const bob = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=llama');
    const slug = await newRoom(ann.page);
    await open(ann, slug, 'sse');
    await open(bob, slug, 'sse');
    await say(ann, '@bot fake:stall x');
    await expect(ann.page.locator('#toasts .toast')).toContainText("didn't start answering");
    await expect(ann.page.locator('.bot-live')).toHaveCount(0);
    await expect(bob.page.locator('.bot-live')).toHaveCount(0);
    await expect(bob.page.locator('#toasts .toast')).toHaveCount(0);
    await bob.page.reload();
    await expect(fromBot(bob)).toHaveCount(0);
    await leave(ann, bob);
  });

  test("an answer can't ping a member or ask the bot", async ({ browser }) => {
    const ann = await member(browser, mainOrigin(s.port));
    const bob = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=llama');
    const slug = await newRoom(ann.page);
    await open(bob, slug, 'sse'); // chat knows Bob's name
    await open(ann, slug, 'sse');
    await say(ann, `@bot @${bob.name} ping @bot again`);
    await expect(fromBot(ann)).toHaveCount(1);
    await expect(fromBot(ann).locator('.chat-body')).toContainText(`@${bob.name}`);
    await expect(fromBot(ann).locator('.chat-body')).toContainText('@bot');
    await ann.page.waitForTimeout(600);
    await expect(fromBot(ann)).toHaveCount(1);
    expect((await fakeStats(fake)).requests).toBe(1);
    // Ann's own line named Bob, once; the answer named him again, and that adds nothing.
    await bob.page.goto('/notify');
    await expect(bob.page.locator('#notify-list > *')).toHaveCount(1);
    await leave(ann, bob);
  });
});
