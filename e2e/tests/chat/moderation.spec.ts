import { test, expect } from '../../fixtures';
import type { Page } from '@playwright/test';
import { signIn } from '../../helpers/accounts';
import { leave, member, uid } from '../../helpers/members';

// Moderation (PLAN §14.1, planning 2026-11-01): in a public room a moderator removes a message to
// a tombstone, mutes and kicks a member, locks the room and sets slow mode, each with a reason
// (hx-prompt) that lands in the audit log, never the message's body. Private rooms and DMs aren't
// theirs to read: a member reports a message there, the report carries a copy, and the moderator
// removes it from the reports page. Moderators are accounts' admins, so most of it runs on full.
const T = { tag: ['@chat'] };
const MOD = { tag: ['@chat', '@accounts-accounts', '@audit'] };

// hx-prompt asks with window.prompt: every dialog on the page answers `reason`.
const answers = (page: Page, reason: string) => page.on('dialog', (d) => d.accept(reason));

async function newRoom(page: Page, kind = 'public'): Promise<string> {
  await page.goto('/chat');
  await page.locator('#room-name').fill(uid('room '));
  await page.locator('#room-kind').selectOption(kind);
  await page.getByRole('button', { name: 'Create' }).click();
  await page.waitForURL(/\/chat\/r\//);
  return new URL(page.url()).pathname.split('/').pop()!;
}

async function open(page: Page, slug: string) {
  await page.goto(`/chat/r/${slug}?transport=sse`);
  await expect(page.locator('.chat-room')).toBeVisible();
}

async function say(page: Page, text: string) {
  const box = page.locator('.chat-composer textarea');
  await box.fill(text);
  await box.press('Enter');
  await expect(box).toHaveValue('');
}

const message = (page: Page, text: string) => page.locator('.chat-log > article.chat-msg').filter({ hasText: text });

async function menuOf(page: Page, text: string) {
  const msg = message(page, text);
  await msg.hover();
  await msg.getByRole('button', { name: 'Message actions' }).click();
  return msg;
}

test.describe('chat moderation', MOD, () => {
  test('a moderator removes, mutes, kicks, locks and slows, each audited', async ({ browser, baseURL }) => {
    const mod = await signIn(browser, baseURL!, '/chat');
    answers(mod.page, 'e2e reason');
    const bob = await member(browser, baseURL!), cat = await member(browser, baseURL!);
    const slug = await newRoom(mod.page);
    await open(bob.page, slug);
    await say(bob.page, 'rude words');
    await say(bob.page, 'more of it');

    // Remove: a tombstone for everyone, the body nowhere in the log.
    await open(mod.page, slug);
    let msg = await menuOf(mod.page, 'rude words');
    await expect(msg.getByRole('button', { name: 'Edit' })).toHaveCount(0); // not theirs to edit
    await msg.getByRole('button', { name: 'Remove' }).click();
    await expect(bob.page.locator('.chat-log > article.chat-msg').filter({ hasText: 'Message deleted.' })).toHaveCount(1);
    await expect(message(bob.page, 'rude words')).toHaveCount(0);

    // Mute: the composer says why, and a post is refused.
    msg = await menuOf(mod.page, 'more of it');
    await msg.getByRole('button', { name: 'Mute for an hour' }).click();
    await expect(mod.page.locator('#toasts .toast').last()).toContainText('Muted for 60 minutes.');
    await open(bob.page, slug);
    await expect(bob.page.locator('.chat-composer')).toHaveCount(0);
    await expect(bob.page.locator('.chat-readonly')).toContainText('A moderator muted you here until');
    expect((await bob.page.request.post(`/chat/r/${slug}`, { form: { body: 'still here' } })).status()).toBe(403);

    // Slow mode: one message every 30 s; the moderator isn't held to it.
    await mod.page.locator('.chat-mod select[name="seconds"]').selectOption('30');
    await mod.page.locator('.chat-mod').getByRole('button', { name: 'Set' }).click();
    await mod.page.waitForLoadState();
    await open(cat.page, slug);
    await say(cat.page, 'first');
    expect((await cat.page.request.post(`/chat/r/${slug}`, { form: { body: 'second' } })).status()).toBe(429);
    await open(mod.page, slug);
    await say(mod.page, 'a moderator one');
    await say(mod.page, 'and another');

    // Lock: only moderators post.
    await mod.page.locator('.chat-mod').getByRole('button', { name: 'Lock' }).click();
    await expect(mod.page.locator('.chat-mod').getByRole('button', { name: 'Unlock' })).toBeVisible();
    await open(cat.page, slug);
    await expect(cat.page.locator('.chat-readonly')).toHaveText('A moderator locked this room: only moderators post for now.');

    // Kick: the room is a missing one to him for the hour.
    await open(mod.page, slug);
    msg = await menuOf(mod.page, 'first');
    await msg.getByRole('button', { name: 'Kick for an hour' }).click();
    await expect(mod.page.locator('#toasts .toast').last()).toContainText('Kicked for 60 minutes.');
    expect((await cat.page.goto(`/chat/r/${slug}`))!.status()).toBe(404);

    // Each act in the audit log, with its reason; never a message's body.
    const csv = await (await mod.context.request.get('/admin/audit/export?action=chat.')).text();
    for (const action of ['chat.remove', 'chat.mute', 'chat.slow', 'chat.lock', 'chat.kick']) expect(csv).toContain(action);
    expect(csv).toContain('e2e reason');
    expect(csv).not.toContain('rude words');
    await mod.context.close();
    await leave(bob, cat);
  });

  test("a private room's message is moderated through its report, from a copy", async ({ browser, baseURL }) => {
    const mod = await signIn(browser, baseURL!, '/chat');
    answers(mod.page, 'removed after a report');
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
    answers(bob.page, 'it is spam');
    const slug = await newRoom(ann.page, 'private');
    expect((await mod.page.goto(`/chat/r/${slug}`))!.status()).toBe(404); // not theirs to read
    await ann.page.getByRole('button', { name: 'Invite link' }).click();
    const href = (await ann.page.locator('.chat-invite-link').getAttribute('href'))!;
    await bob.page.goto(href);
    await bob.page.getByRole('button', { name: 'Join the room' }).click();
    await bob.page.waitForURL(`**/chat/r/${slug}`);
    await open(ann.page, slug);
    const body = uid('buy now ');
    await say(ann.page, body);
    await open(bob.page, slug);
    const msg = await menuOf(bob.page, body);
    await expect(msg.getByRole('button', { name: 'Remove' })).toHaveCount(0); // a member's menu
    await msg.getByRole('button', { name: 'Report' }).click();
    await expect(bob.page.locator('#toasts .toast').last()).toContainText('Reported: a moderator will look at it.');

    await mod.page.goto('/chat/reports');
    const report = mod.page.locator('.chat-report').filter({ hasText: body });
    await expect(report).toContainText('it is spam');
    await report.getByRole('button', { name: 'Remove the message' }).click();
    await expect(mod.page.locator('.chat-report').filter({ hasText: body })).toHaveCount(0);
    await open(ann.page, slug);
    await expect(message(ann.page, body)).toHaveCount(0);
    await expect(ann.page.locator('.chat-log > article.chat-msg').filter({ hasText: 'Message deleted.' })).toHaveCount(1);
    const csv = await (await mod.context.request.get('/admin/audit/export?action=chat.')).text();
    expect(csv).toContain('chat.report_removed');
    expect(csv).not.toContain(body);
    await mod.context.close();
    await leave(ann, bob);
  });
});

test.describe('chat reports', T, () => {
  test("a member reports someone else's message, not their own, and nothing without a reason", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
    answers(bob.page, 'off topic');
    const slug = await newRoom(ann.page);
    await open(ann.page, slug);
    await say(ann.page, 'mine');
    const own = await menuOf(ann.page, 'mine');
    await expect(own.getByRole('button', { name: 'Report' })).toHaveCount(0);
    await open(bob.page, slug);
    const hers = await menuOf(bob.page, 'mine');
    await expect(hers.getByRole('button', { name: 'Remove' })).toHaveCount(0); // no moderator here
    await hers.getByRole('button', { name: 'Report' }).click();
    await expect(bob.page.locator('#toasts .toast').last()).toContainText('Reported');
    const id = (await message(bob.page, 'mine').getAttribute('id'))!.slice(2);
    expect((await bob.page.request.post(`/chat/m/${id}/report`)).status()).toBe(422); // a reason, always
    expect((await bob.page.request.get('/chat/reports', { maxRedirects: 0 })).status()).toBe(403);
    await leave(ann, bob);
  });
});
