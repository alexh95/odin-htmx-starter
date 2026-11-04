import { test, expect } from '../../fixtures';
import type { Browser, Page } from '@playwright/test';
import { signIn } from '../../helpers/accounts';
import { leave, member, uid, type Member } from '../../helpers/members';

// Blocking (planning 2026-11-04): a DM can't be left, so this is how one ends. A blocks B: the DM
// closes both ways, B can't start one, and B's DMs and mentions stop reaching A's Inbox. Public
// rooms don't change, moderation doesn't notice, nothing is audited.
const T = { tag: ['@chat', '@notify'] };

const idOf = async (m: Member): Promise<string> => {
  await m.page.goto('/chat/r/lobby?transport=sse');
  return (await m.page.locator('.chat-log').getAttribute('data-me'))!;
};

async function dmWith(m: Member, id: string): Promise<string> {
  const r = await m.page.request.post(`/chat/dm/${id}`);
  expect(r.status()).toBe(204);
  return r.headers()['hx-redirect'];
}

async function say(page: Page, text: string) {
  const box = page.locator('.chat-composer textarea');
  await box.fill(text);
  await box.press('Enter');
  await expect(box).toHaveValue('');
}

const pair = async (browser: Browser, baseURL: string) => [await member(browser, baseURL), await member(browser, baseURL)];
const inbox = async (m: Member) => (await m.page.request.get('/notify/list')).text();
const CANT = "You can't message this member.";

test.describe('blocking', T, () => {
  test('from a DM: it closes both ways, and neither can start one', async ({ browser, baseURL }) => {
    const [ann, bob] = await pair(browser, baseURL!);
    const annId = await idOf(ann), bobId = await idOf(bob);
    const path = await dmWith(ann, bobId);
    await ann.page.goto(`${path}?transport=sse`);
    await say(ann.page, 'hello');
    await expect.poll(() => inbox(bob)).toContain('hello');

    const slug = path.split('/').pop()!;
    await ann.page.goto(`${path}?transport=sse`);
    await ann.page.getByRole('button', { name: 'Block', exact: true }).click();
    await expect(ann.page.getByRole('button', { name: 'Unblock' })).toBeVisible();
    await expect(ann.page.locator('.chat-composer')).toHaveCount(0);
    await expect(ann.page.locator('.chat-readonly')).toHaveText(CANT);

    await bob.page.goto(`${path}?transport=sse`);
    await expect(bob.page.locator('.chat-readonly')).toHaveText(CANT);
    await expect(bob.page.locator('.chat-log')).toContainText('hello'); // what was said stays
    expect((await bob.page.request.post(`/chat/r/${slug}`, { form: { body: 'still here' } })).status()).toBe(403);
    expect((await bob.page.request.post(`/chat/dm/${annId}`)).status()).toBe(403);
    expect(await inbox(ann)).not.toContain('still here');

    // Unblocked, it opens again: only a block's own side undoes it.
    expect((await bob.page.request.post(`/chat/unblock/${annId}`)).status()).toBeLessThan(400); // no block of Bob's
    await bob.page.goto(`${path}?transport=sse`);
    await expect(bob.page.locator('.chat-readonly')).toHaveText(CANT);
    await ann.page.getByRole('button', { name: 'Unblock' }).click();
    await expect(ann.page.locator('.chat-composer')).toBeVisible();
    await bob.page.goto(`${path}?transport=sse`);
    await expect(bob.page.locator('.chat-composer')).toBeVisible();
    await leave(ann, bob);
  });

  test('over a socket too', async ({ browser, baseURL }) => {
    const [ann, bob] = await pair(browser, baseURL!);
    const path = await dmWith(ann, await idOf(bob));
    const slug = path.split('/').pop()!;
    await bob.page.goto(`${path}?transport=ws`);
    await expect.poll(() => bob.page.locator('.chat-pane').evaluate((el: any) => el._htmx?.ws?.connection?.socket?.readyState)).toBe(1);
    expect((await ann.page.request.post(`/chat/r/${slug}/block`)).status()).toBeLessThan(400);
    const box = bob.page.locator('.chat-composer textarea');
    await box.fill('through the open socket');
    await box.press('Enter');
    await expect(bob.page.locator('.chat-composer .form-error')).toHaveText(CANT);
    await ann.page.goto(`${path}?transport=sse`);
    await expect(ann.page.locator('.chat-log')).not.toContainText('through the open socket');
    await leave(ann, bob);
  });

  test("from a message's menu: their mentions stop reaching the Inbox, the room doesn't change", async ({ browser, baseURL }) => {
    const [ann, bob] = await pair(browser, baseURL!);
    await idOf(ann); // chat knows Ann's name once she's been here
    await ann.page.goto('/chat/r/lobby?transport=sse');
    await bob.page.goto('/chat/r/lobby?transport=sse');
    const first = uid('before ');
    await say(ann.page, 'hello everyone'); // so her mention resolves
    await say(bob.page, `${first} @${ann.name}`);
    await expect.poll(() => inbox(ann)).toContain(first);

    const msg = ann.page.locator('.chat-log > article.chat-msg').filter({ hasText: first });
    await msg.hover();
    await msg.getByRole('button', { name: 'Message actions' }).click();
    await msg.getByRole('button', { name: 'Block', exact: true }).click();
    await ann.page.waitForLoadState();

    const second = uid('after ');
    await say(bob.page, `${second} @${ann.name}`);
    await expect(ann.page.locator('.chat-log')).toContainText(second); // the room is everyone's
    expect(await inbox(ann)).not.toContain(second);
    await leave(ann, bob);
  });

  test('the list, and its Unblock', async ({ browser, baseURL }) => {
    const [ann, bob] = await pair(browser, baseURL!);
    const path = await dmWith(ann, await idOf(bob));
    const slug = path.split('/').pop()!;
    await ann.page.goto('/chat/blocks');
    await expect(ann.page.locator('.chat-blocks')).toContainText("You haven't blocked anyone.");
    await ann.page.request.post(`/chat/r/${slug}/block`);
    await ann.page.goto('/chat');
    await ann.page.getByRole('link', { name: 'Blocked members' }).click();
    const row = ann.page.locator('.chat-blocks li').filter({ hasText: bob.name });
    await expect(row).toHaveCount(1);
    await row.getByRole('button', { name: 'Unblock' }).click();
    await expect(ann.page.locator('.chat-blocks')).toContainText("You haven't blocked anyone.");
    await leave(ann, bob);
  });

  test("you can't block yourself, or a room that isn't a DM", async ({ browser, baseURL }) => {
    const [ann] = await pair(browser, baseURL!);
    await ann.page.goto('/chat/r/lobby?transport=sse');
    const box = ann.page.locator('.chat-composer textarea');
    await box.fill('mine');
    await box.press('Enter');
    const own = ann.page.locator('.chat-log > article.chat-msg').filter({ hasText: 'mine' }).last();
    const id = (await own.getAttribute('id'))!.slice(2);
    expect((await ann.page.request.post(`/chat/m/${id}/block`)).status()).toBe(422);
    expect((await ann.page.request.post('/chat/r/lobby/block')).status()).toBe(404);
    await leave(ann);
  });
});

test.describe('blocking and moderation', { tag: ['@chat', '@notify', '@accounts-accounts', '@audit'] }, () => {
  test('a moderator acts on a member who blocked them, and a block writes no audit row', async ({ browser, baseURL }) => {
    const mod = await signIn(browser, baseURL!, '/chat');
    mod.page.on('dialog', (d) => d.accept('moderating'));
    await mod.page.goto('/chat/r/lobby?transport=sse');
    const ann = await member(browser, baseURL!);
    await ann.page.goto('/chat/r/lobby?transport=sse');
    const mark = uid('m');
    await say(ann.page, mark);
    const hers = mod.page.locator('.chat-log > article.chat-msg').filter({ hasText: mark });
    const id = (await hers.getAttribute('id'))!.slice(2);
    await say(mod.page, 'a word from the moderator');
    const his = ann.page.locator('.chat-log > article.chat-msg').filter({ hasText: 'a word from the moderator' });
    const hisId = (await his.getAttribute('id'))!.slice(2);
    expect((await ann.page.request.post(`/chat/m/${hisId}/block`)).status()).toBeLessThan(400);

    await hers.hover();
    await hers.getByRole('button', { name: 'Message actions' }).click();
    await hers.getByRole('button', { name: 'Remove' }).click();
    await expect(ann.page.locator(`#m-${id}`)).toContainText('Message deleted.');
    const csv = await (await mod.context.request.get('/admin/audit/export?action=chat.')).text();
    expect(csv).toContain('chat.remove');
    expect(csv).not.toContain('block');
    await mod.context.close();
    await leave(ann);
  });
});
