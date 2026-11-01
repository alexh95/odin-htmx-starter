import { test, expect } from '../../fixtures';
import type { Page } from '@playwright/test';
import { signIn } from '../../helpers/accounts';
import { leave, member, uid, type Member } from '../../helpers/members';

// Rooms beyond public (PLAN §14.1, D30): a private room is its members' alone (anyone else gets
// the 404 a missing room gets, and doesn't see it listed) and grows by its owner's invite link; a
// DM is two members' room, started from a message's menu; announcements are posted by their owner.
// On SSE throughout: the transport is chat.spec's subject.
const T = { tag: ['@chat'] };

async function newRoom(page: Page, kind: 'public' | 'private' | 'announce'): Promise<string> {
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

test.describe('chat rooms', T, () => {
  test('a private room: hidden from others, joined by its invite link, and left', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
    const slug = await newRoom(ann.page, 'private');
    await expect(ann.page.locator('.chat-head .chat-kind')).toHaveText('private');
    await expect(ann.page.locator('.chat-members li')).toHaveText([`${ann.name} owner`]);

    // Not Bob's: not listed, and every way in answers as a missing room does.
    await bob.page.goto('/chat');
    await expect(bob.page.locator(`a[href="/chat/r/${slug}"]`)).toHaveCount(0);
    expect((await bob.page.goto(`/chat/r/${slug}`))!.status()).toBe(404);
    for (const path of [`/chat/r/${slug}`, `/chat/r/${slug}/invite`]) {
      expect((await bob.page.request.post(path, { form: { body: 'let me in' } })).status()).toBe(404);
    }

    // The owner's invite link lets him in.
    await open(ann.page, slug);
    await ann.page.getByRole('button', { name: 'Invite link' }).click();
    const link = ann.page.locator('.chat-invite-link');
    await expect(link).toBeVisible();
    const href = (await link.getAttribute('href'))!;
    expect((await bob.page.request.post(`${href}x`)).status()).toBe(404); // a forged token
    await bob.page.goto(href);
    await bob.page.getByRole('button', { name: 'Join the room' }).click();
    await bob.page.waitForURL(`**/chat/r/${slug}`);
    await expect(bob.page.locator('.chat-members li')).toHaveText([`${ann.name} owner`, bob.name]);
    await expect(bob.page.getByRole('button', { name: 'Invite link' })).toHaveCount(0); // the owner's

    // Members talk; then Bob leaves, and the room is closed to him again.
    await open(bob.page, slug);
    await say(ann.page, 'only us');
    await expect(message(bob.page, 'only us')).toHaveCount(1);
    await bob.page.getByRole('button', { name: 'Leave the room' }).click();
    await bob.page.waitForURL('**/chat');
    await expect(bob.page.locator(`a[href="/chat/r/${slug}"]`)).toHaveCount(0);
    expect((await bob.page.goto(`/chat/r/${slug}`))!.status()).toBe(404);
    expect(ann.errors).toEqual([]);
    expect(bob.errors).toEqual([]);
    await leave(ann, bob);
  });

  test("a DM, from a message's menu: the two members' alone", async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!), cat = await member(browser, baseURL!);
    const slug = await newRoom(ann.page, 'public');
    await open(bob.page, slug);
    await say(bob.page, 'hello from bob');
    await open(ann.page, slug);
    const his = message(ann.page, 'hello from bob');
    await his.hover();
    await his.getByRole('button', { name: 'Message actions' }).click();
    await his.getByRole('button', { name: `Message ${bob.name}` }).click();
    await ann.page.waitForURL(/\/chat\/r\/dm-[0-9a-f]{16}$/);
    const dm = new URL(ann.page.url()).pathname;
    await expect(ann.page.locator('.chat-head h1')).toContainText(`${ann.name} and ${bob.name}`);
    await expect(ann.page.locator('.chat-head .chat-kind')).toHaveText('direct');

    // The same DM from Bob's side, listed for him; nothing for a third.
    await bob.page.goto('/chat');
    await expect(bob.page.locator(`a[href="${dm}"]`)).toHaveCount(1);
    await bob.page.goto(`${dm}?transport=sse`);
    await say(ann.page, 'just between us');
    await expect(message(bob.page, 'just between us')).toHaveCount(1);
    await cat.page.goto('/chat');
    await expect(cat.page.locator(`a[href="${dm}"]`)).toHaveCount(0);
    expect((await cat.page.goto(dm))!.status()).toBe(404);
    // Her own messages' menus offer no DM with herself.
    const mine = message(ann.page, 'just between us');
    await mine.hover();
    await mine.getByRole('button', { name: 'Message actions' }).click();
    await expect(mine.getByRole('link', { name: 'Link' })).toBeVisible();
    await expect(mine.getByRole('button', { name: `Message ${ann.name}` })).toHaveCount(0);
    await leave(ann, bob, cat);
  });

  // Announcements are a moderator's to make; on a nick build nobody is one.
  test('announcements: read by every member, posted by their owner', { tag: '@accounts-accounts' }, async ({ browser, baseURL }) => {
    const admin = await signIn(browser, baseURL!, '/chat');
    const bob = await member(browser, baseURL!);
    await bob.page.goto('/chat');
    await expect(bob.page.locator('#room-kind option[value="announce"]')).toHaveCount(0);
    expect((await bob.page.request.post('/chat/rooms', { form: { name: uid('news '), kind: 'announce' } })).status()).toBe(403);

    const slug = await newRoom(admin.page, 'announce');
    await expect(admin.page.locator('.chat-head .chat-kind')).toHaveText('announcements');
    await open(admin.page, slug);
    await open(bob.page, slug);
    await expect(bob.page.locator('.chat-composer')).toHaveCount(0);
    await expect(bob.page.locator('.chat-readonly')).toHaveText('Only its owner and the moderators post here.');
    expect((await bob.page.request.post(`/chat/r/${slug}`, { form: { body: 'me too' } })).status()).toBe(403);
    await say(admin.page, 'the news');
    await expect(message(bob.page, 'the news')).toHaveCount(1);
    await admin.context.close();
    await leave(bob);
  });
});
