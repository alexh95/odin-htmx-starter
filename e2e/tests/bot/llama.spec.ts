import { test, expect, BUILD } from '../../fixtures';
import type { Page } from '@playwright/test';
import { startFake, stopFake, setState, fakeStats, type Fake } from '../../helpers/fakellama';
import { leave, member, type Member } from '../../helpers/members';
import { mainOrigin, startServer, stopServer, type Server } from '../../helpers/server';
import { signIn } from '../../helpers/accounts';

// The bot on llama.cpp's binding, in a real browser, against tools/fakellama (PLAN §14.3, D8): a
// member's answer and its x-impl, a guest's mock, Stop, the queue at one slot, each state of the
// badge with no reload, a member's choice, and the admin's default.
const T = { tag: ['@bot'] };
const LLAMA = { BOT_BACKEND: 'llama', BOT_LLAMA_PROBE: '100ms', BOT_CONCURRENCY: '1' };

async function conversation(m: Member): Promise<string> {
  await m.page.goto('/bot');
  await m.page.getByRole('button', { name: 'New conversation' }).click();
  await m.page.waitForURL(/\/bot\/c\/\d+$/);
  return new URL(m.page.url()).pathname;
}

async function ask(page: Page, q: string) {
  const box = page.locator('.bot-ask textarea');
  await box.fill(q);
  await box.press('Enter');
}

const answers = (page: Page) => page.locator('#c-log article.bot-a');

test.describe('the bot on llama', T, () => {
  let fake: Fake;
  let s: Server;

  test.beforeEach(async () => {
    const config = test.info().config;
    fake = await startFake();
    s = await startServer(config, { ...LLAMA, BOT_LLAMA_URL: fake.url });
  });

  test.afterEach(async () => {
    await stopServer(s);
    stopFake(fake);
  });

  test('a member gets the model, in the page and in x-impl; a guest the mock', async ({ browser }) => {
    const ann = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=llama');
    await conversation(ann);
    await expect(ann.page.locator('#bot-health')).toHaveText('Ready');
    await ask(ann.page, 'is it <b>you</b>?');
    await expect(answers(ann.page).locator('.bot-stats')).toContainText(/\d+ tokens/);
    await expect(answers(ann.page).locator('.bot-body')).toContainText('You asked: is it <b>you</b>?');
    await expect(answers(ann.page).locator('.bot-body b')).toHaveCount(0); // the model's text is escaped
    expect(ann.errors).toEqual([]);

    const context = await browser.newContext({ baseURL: mainOrigin(s.port) });
    const guest = await context.newPage();
    const res = await guest.goto('/bot');
    expect(res!.headers()['x-impl']).toBe('bot.backend=mock');
    await expect(guest.locator('#bot-health')).toHaveText('Mock');
    const before = (await fakeStats(fake)).requests;
    await ask(guest, 'a guest asks');
    await expect(answers(guest).locator('.bot-stats')).toBeVisible();
    expect((await fakeStats(fake)).requests).toBe(before);
    await context.close();
    await leave(ann);
  });

  test('Stop reaches the server as a close, and the words so far stand', async ({ browser }) => {
    const ann = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=llama');
    await conversation(ann);
    await ask(ann.page, 'fake:long story');
    await expect(answers(ann.page).locator('.bot-stream')).toContainText('word1');
    await answers(ann.page).locator('.bot-stop').click();
    await expect(answers(ann.page).locator('.bot-stats')).toContainText('Stopped');
    await expect(answers(ann.page).locator('.bot-body')).toContainText('word1');
    await expect.poll(async () => (await fakeStats(fake)).closed).toBe(1);
    await leave(ann);
  });

  test('a closed browser stops the generation', async ({ browser }) => {
    const ann = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=llama');
    await conversation(ann);
    await ask(ann.page, 'fake:long story');
    await expect(answers(ann.page).locator('.bot-stream')).toContainText('word1');
    await ann.page.close();
    await expect.poll(async () => (await fakeStats(fake)).closed).toBe(1);
    await ann.context.close();
  });

  test('with BOT_CONCURRENCY=1 the second waits, says so, and answers', async ({ browser }) => {
    const ann = await member(browser, mainOrigin(s.port));
    const bob = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=llama');
    await conversation(ann);
    await conversation(bob);
    await ask(ann.page, 'fake:long story');
    await expect(answers(ann.page).locator('.bot-stream')).toContainText('word1');
    await ask(bob.page, 'my turn');
    await expect(answers(bob.page).locator('.bot-queued')).toHaveText('Queued (#1)');
    await answers(ann.page).locator('.bot-stop').click();
    await expect(answers(bob.page).locator('.bot-body')).toContainText('You asked: my turn');
    await expect(answers(bob.page).locator('.bot-stats')).toBeVisible();
    expect((await fakeStats(fake)).peak).toBe(1);
    await leave(ann, bob);
  });

  test('a stall and a dropped socket end in words, and the next question works', async ({ browser }) => {
    const config = test.info().config;
    await stopServer(s);
    s = await startServer(config, { ...LLAMA, BOT_LLAMA_URL: fake.url, BOT_LLAMA_FIRST_TOKEN: '400ms', BOT_LLAMA_IDLE: '400ms' });
    const ann = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=llama');
    await conversation(ann);
    await ask(ann.page, 'fake:stall x');
    await expect(answers(ann.page).first()).toHaveText("The model didn't start answering in time.");
    await ask(ann.page, 'fake:drop x');
    await expect(answers(ann.page).nth(1).locator('.bot-stats')).toContainText('Cut off');
    await ask(ann.page, 'still there?');
    await expect(answers(ann.page).nth(2).locator('.bot-body')).toContainText('You asked: still there?');
    await leave(ann);
  });

  test('the badge follows the server with no reload, and the mock takes over meanwhile', async ({ browser }) => {
    const ann = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=llama');
    await conversation(ann);
    const badge = ann.page.locator('#bot-health');
    await expect(badge).toHaveText('Ready');
    await setState(fake, 'sleeping');
    await expect(badge).toHaveText('Sleeping');
    await setState(fake, 'loading');
    await expect(badge).toHaveText('Loading');
    await ask(ann.page, 'anyone?');
    await expect(answers(ann.page).locator('.bot-stats')).toBeVisible();
    expect((await fakeStats(fake)).requests).toBe(0); // answered by the mock
    await setState(fake, 'ready');
    await expect(badge).toHaveText('Ready');
    stopFake(fake);
    await expect(badge).toHaveText('Offline');
    // An optional backend: the site stays ready, and says so on /status.
    expect((await ann.page.request.get('/readyz')).status()).toBe(200);
    await expect.poll(async () => (await ann.page.request.get('/readyz?detail')).text()).toContain('bot degraded');
    fake = await startFake(); // for afterEach
    await leave(ann);
  });

  test('a member may choose while both are healthy', async ({ browser }) => {
    const ann = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=llama');
    await conversation(ann);
    await ann.page.locator('select[name="backend"]').selectOption('mock');
    await ask(ann.page, 'not the model');
    await expect(answers(ann.page).locator('.bot-stats')).toBeVisible();
    expect((await fakeStats(fake)).requests).toBe(0);
    await leave(ann);
  });
});

test('a key: sent as a bearer, and one the server refuses is said in words', T, async ({ browser }) => {
  const config = test.info().config;
  const fake = await startFake({ key: 'right' });
  let s = await startServer(config, { ...LLAMA, BOT_LLAMA_URL: fake.url, BOT_LLAMA_KEY: 'right' });
  try {
    const ann = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=llama');
    await conversation(ann);
    await ask(ann.page, 'hello');
    await expect(answers(ann.page).locator('.bot-body')).toContainText('You asked: hello');
    expect((await fakeStats(fake)).refused).toBe(0);
    await leave(ann);
    await stopServer(s);
    s = await startServer(config, { ...LLAMA, BOT_LLAMA_URL: fake.url, BOT_LLAMA_KEY: 'wrong' });
    const bob = await member(browser, mainOrigin(s.port));
    await bob.page.goto('/bot');
    await expect(bob.page.locator('#bot-health')).toHaveText('Offline'); // a key it refuses is no server
    await leave(bob);
  } finally {
    await stopServer(s);
    stopFake(fake);
  }
});

test("the admin's default: audited, shown on /admin/modules, and gone at a restart", { tag: ['@bot', '@accounts'] }, async ({ browser }) => {
  test.skip(!BUILD.features.includes('bot') || BUILD.identity !== 'accounts', 'an admin needs accounts');
  const config = test.info().config;
  const fake = await startFake();
  const env = { BOT_LLAMA_URL: fake.url, BOT_LLAMA_PROBE: '100ms', BOT_CONCURRENCY: '1' };
  let s = await startServer(config, env);
  try {
    const ann = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=mock'); // BOT_BACKEND's default
    expect((await ann.page.request.get('/admin/bot')).status()).toBe(403);

    const admin = await signIn(browser, mainOrigin(s.port), '/admin/bot');
    await admin.page.goto('/admin/bot');
    await expect(admin.page.locator('#bot-default')).toHaveText('mock');
    await expect(admin.page.locator('#bot-admin #bot-health')).toHaveText('Ready');
    await admin.page.getByRole('button', { name: 'Make llama the default' }).click();
    await expect(admin.page.locator('#bot-default')).toHaveText('llama');
    await expect.poll(async () => (await ann.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=llama');

    await admin.page.goto('/admin/audit');
    await expect(admin.page.getByText('bot.default').first()).toBeVisible();
    await admin.page.goto('/admin/modules');
    await expect(admin.page.locator('#modules-health, section').getByRole('link', { name: 'Change' })).toHaveAttribute('href', '/admin/bot');
    await expect(admin.page.getByText(/default llama/)).toBeVisible();
    await admin.context.close();
    await leave(ann);

    await stopServer(s);
    s = await startServer(config, env);
    const bob = await member(browser, mainOrigin(s.port));
    await expect.poll(async () => (await bob.page.goto('/bot'))!.headers()['x-impl']).toBe('bot.backend=mock');
    await leave(bob);
  } finally {
    await stopServer(s);
    stopFake(fake);
  }
});

test('a boot asking for llama with no URL is refused', T, async () => {
  const config = test.info().config;
  await expect(startServer(config, { BOT_BACKEND: 'llama' })).rejects.toThrow();
});
