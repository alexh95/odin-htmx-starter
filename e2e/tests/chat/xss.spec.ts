import { test, expect } from '../../fixtures';
import type { Page } from '@playwright/test';
import { signIn } from '../../helpers/accounts';
import { leave, member, uid } from '../../helpers/members';

// Every place chat, notify and uploads render what a member wrote (PLAN §19.1.2, D22), against one
// injection set: script and handlers, attributes breaking out of their quotes, htmx and hyperscript
// attributes that would run if they ever became markup, an `hx-partial` that would swap the page, a
// double-encoded tag. Each lands as text: no element of ours, nothing run, the words as written. The
// members helper already fails a test on any page error or CSP refusal.
const T = { tag: ['@chat', '@notify'] };

const PAYLOADS = [
  `<img src=x data-xss onerror="window.__xss=1">`,
  `<script data-xss>window.__xss=1</script>`,
  `"><svg data-xss onload="window.__xss=1">`,
  `'><a data-xss href="javascript:window.__xss=1">x</a>`,
  `<div data-xss hx-post="/logout" hx-trigger="load">x</div>`,
  `<span data-xss _="on load set window.__xss to 1">x</span>`,
  `<hx-partial hx-target="body" hx-swap="innerHTML"><b data-xss>x</b></hx-partial>`,
  `<template data-xss><script>window.__xss=1</script></template>`,
  `&lt;img data-xss src=x onerror=window.__xss=1&gt;`,
  `<style data-xss>*{display:none}</style>`,
  `javascript:window.__xss=1`,
  `{{7*7}} \${7*7} <%= 7*7 %>`,
];
const ALL = PAYLOADS.join('\n');

async function clean(page: Page, where: string) {
  await expect(page.locator('[data-xss]'), `${where}: an element from a payload`).toHaveCount(0);
  expect(await page.evaluate(() => (window as any).__xss), `${where}: a payload ran`).toBeUndefined();
}

async function room(page: Page, name: string, kind = 'public'): Promise<string> {
  await page.goto('/chat');
  await page.locator('#room-name').fill(name);
  await page.locator('#room-kind').selectOption(kind);
  await page.getByRole('button', { name: 'Create' }).click();
  await page.waitForURL(/\/chat\/r\//);
  return new URL(page.url()).pathname.split('/').pop()!;
}

async function open(page: Page, slug: string, transport: string) {
  await page.goto(`/chat/r/${slug}?transport=${transport}`);
  await expect(page.locator('.chat-room')).toBeVisible();
  if (transport === 'ws') await expect.poll(() => page.locator('.chat-pane').evaluate((el: any) => el._htmx?.ws?.connection?.socket?.readyState)).toBe(1);
}

async function say(page: Page, text: string) {
  const box = page.locator('.chat-composer textarea');
  await box.fill(text);
  await box.press('Enter');
  await expect(box).toHaveValue('');
}

const message = (page: Page, text: string) => page.locator('.chat-log > article.chat-msg').filter({ hasText: text });

test.describe('what members write stays text', T, () => {
  for (const t of ['ws', 'sse', 'poll', 'multipart'] as const) {
    test(`a message, live and on a reload, over ${t}`, async ({ browser, baseURL }) => {
      const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
      const slug = await room(ann.page, uid('xss '));
      await open(ann.page, slug, t);
      await open(bob.page, slug, t);
      const mark = uid('m');
      await say(ann.page, `${mark}\n${ALL}`);
      await expect(message(bob.page, mark)).toHaveCount(1);
      await clean(bob.page, 'live');
      await clean(ann.page, "the author's own");
      for (const p of PAYLOADS) await expect(message(bob.page, mark).locator('.chat-body')).toContainText(p.split('\n')[0]);

      await open(bob.page, slug, t);
      await expect(message(bob.page, mark)).toHaveCount(1);
      await clean(bob.page, 'the snapshot');
      await leave(ann, bob);
    });
  }

  test('an edit, its form, and search', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const slug = await room(ann.page, uid('xss '));
    await open(ann.page, slug, 'sse');
    const mark = uid('m');
    await say(ann.page, `${mark} first`);
    const msg = message(ann.page, mark);
    await msg.hover();
    await msg.getByRole('button', { name: 'Message actions' }).click();
    await msg.getByRole('button', { name: 'Edit' }).click();
    const form = msg.locator('textarea');
    await form.fill(`${mark} ${ALL}`);
    await msg.getByRole('button', { name: 'Save' }).click();
    await expect(msg.locator('.chat-body')).toContainText('window.__xss=1');
    await clean(ann.page, 'an edit');
    await msg.hover();
    await msg.getByRole('button', { name: 'Message actions' }).click();
    await msg.getByRole('button', { name: 'Edit' }).click();
    await expect(msg.locator('textarea')).toHaveValue(new RegExp(mark));
    await clean(ann.page, 'the edit form, filled');

    await ann.page.goto(`/chat/search?q=${encodeURIComponent(mark)}`);
    await expect(ann.page.locator('main')).toContainText(mark);
    await clean(ann.page, 'a search result');
    await ann.page.goto(`/chat/search?q=${encodeURIComponent(ALL)}`);
    await clean(ann.page, 'a query echoed back');
    await leave(ann);
  });

  test("a room's name, wherever it shows", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const name = `<img src=x data-xss onerror=window.__xss=1>${uid('')}`;
    const slug = await room(ann.page, name);
    await clean(ann.page, 'its page');
    await expect(ann.page.locator('.chat-head h1')).toContainText('<img');
    await say(ann.page, 'a word in it');
    await ann.page.goto('/chat');
    await clean(ann.page, 'the rooms');
    await ann.page.goto('/chat/search?q=word');
    await clean(ann.page, 'a search hit');
    await ann.page.goto(`/chat/r/${slug}/nothing-here`);
    await clean(ann.page, 'its 404');
    await leave(ann);
  });

  test('the Inbox: a DM line, pushed live and listed', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
    await bob.page.goto('/chat/r/lobby?transport=sse');
    const id = await bob.page.locator('.chat-log').getAttribute('data-me');
    await ann.page.goto('/chat');
    const dm = await ann.page.request.post(`/chat/dm/${id}`);
    const path = dm.headers()['hx-redirect'];
    await bob.page.goto('/notify');
    await open(ann.page, path.split('/').pop()!, 'sse');
    const mark = uid('m');
    await say(ann.page, `${mark} ${PAYLOADS[0]} ${PAYLOADS[1]}`);
    await expect(bob.page.locator('#notify-list')).toContainText(mark); // the push
    await clean(bob.page, 'a pushed item');
    await bob.page.goto('/notify');
    await expect(bob.page.locator('#notify-list')).toContainText(mark);
    await clean(bob.page, 'the Inbox');
    await leave(ann, bob);
  });

  test("an upload's file name, and an image's alt", async ({ browser, baseURL }) => {
    const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC', 'base64');
    const ann = await member(browser, baseURL!);
    const slug = await room(ann.page, uid('xss '));
    await open(ann.page, slug, 'sse');
    const name = `<img src=x data-xss onerror=window.__xss=1>.png`;
    await ann.page.locator('.chat-attach input').setInputFiles({ name, mimeType: 'image/png', buffer: png });
    await expect(ann.page.locator('.chat-attach-say')).toHaveText(`Attached: ${name}`);
    await clean(ann.page, 'the composer says its name');
    await ann.page.getByRole('button', { name: 'Send' }).click();
    await expect(ann.page.locator('.chat-log .chat-img img')).toHaveCount(1);
    await clean(ann.page, 'the image');
    await leave(ann);
  });

  test('an upload that says it is an image and is a script is refused, and nothing serves it', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/chat');
    const svg = Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" onload="window.__xss=1"/>');
    const made = await (await ann.page.request.post(`/uploads?size=${svg.length}`)).json();
    await ann.page.request.put(`/uploads/${made.id}?off=0`, { data: svg, headers: { 'content-type': 'image/svg+xml' } });
    expect((await ann.page.request.post(`/uploads/${made.id}/finish`)).status()).toBe(422);
    await leave(ann);
  });
});

test.describe('what a moderator reads stays text', { tag: ['@chat', '@notify', '@accounts-accounts', '@audit'] }, () => {
  test("a report's copy and its reason, and the audit log's", async ({ browser, baseURL }) => {
    const mod = await signIn(browser, baseURL!, '/chat');
    mod.page.on('dialog', (d) => d.accept(`${PAYLOADS[0]} removed`));
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
    bob.page.on('dialog', (d) => d.accept(`${PAYLOADS[0]} ${PAYLOADS[1]}`));
    const slug = await room(ann.page, uid('xss '));
    await open(ann.page, slug, 'sse');
    const mark = uid('m');
    await say(ann.page, `${mark} ${ALL}`);
    await open(bob.page, slug, 'sse');
    const msg = message(bob.page, mark);
    await msg.hover();
    await msg.getByRole('button', { name: 'Message actions' }).click();
    await msg.getByRole('button', { name: 'Report' }).click();
    await expect(bob.page.locator('#toasts .toast').last()).toContainText('Reported');

    await mod.page.goto('/chat/reports');
    const report = mod.page.locator('.chat-report').filter({ hasText: mark });
    await expect(report).toContainText('window.__xss=1');
    await clean(mod.page, 'the reports');
    await report.getByRole('button', { name: 'Remove the message' }).click();
    await expect(mod.page.locator('.chat-report').filter({ hasText: mark })).toHaveCount(0);
    await mod.page.goto('/admin/audit?action=chat.');
    await clean(mod.page, 'the audit log');
    await mod.context.close();
    await leave(ann, bob);
  });
});

test('an invite page names its room as text', { tag: ['@chat', '@notify'] }, async ({ browser, baseURL }) => {
  const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
  const name = `<img src=x data-xss onerror=window.__xss=1>${uid('')}`;
  await room(ann.page, name, 'private');
  await ann.page.getByRole('button', { name: 'Invite link' }).click();
  const href = (await ann.page.locator('.chat-invite-link').getAttribute('href'))!;
  await clean(ann.page, 'the room with its link');
  await bob.page.goto(href);
  await expect(bob.page.locator('main')).toContainText('<img');
  await clean(bob.page, 'the invite page');
  await leave(ann, bob);
});
