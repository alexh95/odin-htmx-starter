import { test, expect } from '../../fixtures';
import { startServer, stopServer, type Server } from '../../helpers/server';
import { leave, member, uid } from '../../helpers/members';

// The Inbox (PLAN §14.2): a producer's notification lands on the member's page as it
// happens, over the layout's one #live stream (notify.user:<id>), with every count;
// chat is the producer here (a mention), and its unread counts ride the same topic.
const T = { tag: ['@notify', '@chat', '@accounts-nick'] };

test.describe('notify', T, () => {
  test('a mention lands in the Inbox live, and marking all read zeroes the count', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!, uid('bob'));
    await bob.page.goto('/notify');
    await expect(bob.page.locator('#notify-list')).toContainText('Nothing yet.');
    await expect(bob.page.locator('.notify-count').first()).toHaveText('0');

    await ann.page.goto('/chat/r/lobby?transport=sse');
    // Mentions match the name a member last used in chat: Bob's, once he has been in a room.
    await bob.page.goto('/chat/r/lobby');
    await bob.page.goto('/notify');
    const box = ann.page.locator('.chat-composer textarea');
    await box.fill(`hey @${bob.name}, look`);
    await box.press('Enter');

    const item = bob.page.locator('#notify-list article.notify-item').first();
    await expect(item).toContainText(`${ann.name} mentioned you in #Lobby`);
    await expect(item.locator('a')).toHaveAttribute('href', /^\/chat\/r\/lobby#m-\d+$/);
    await expect(bob.page.locator('.notify-count').first()).toHaveText('1');
    await expect(bob.page.locator('.notify-empty')).toHaveCount(0);

    await bob.page.getByRole('button', { name: 'Mark all read' }).click();
    await expect(bob.page.locator('.notify-count').first()).toHaveText('0');
    await expect(bob.page.locator('#notify-list .notify-item.unread')).toHaveCount(0);
    expect([...ann.errors, ...bob.errors]).toEqual([]);
    await leave(ann, bob);
  });

  test('a room\'s unread count follows on the rooms page, and reading it clears it', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!), bob = await member(browser, baseURL!);
    await ann.page.goto('/chat');
    await ann.page.locator('#room-name').fill(uid('unread '));
    await ann.page.getByRole('button', { name: 'Create' }).click();
    await ann.page.waitForURL(/\/chat\/r\//);
    const slug = new URL(ann.page.url()).pathname.split('/').pop()!;
    const box = ann.page.locator('.chat-composer textarea');
    await box.fill('one');
    await box.press('Enter');
    await expect(box).toHaveValue('');

    // Bob reads the room: its newest message posts his receipt once it is in view.
    const read = bob.page.waitForResponse((r) => r.request().method() === 'POST' && r.url().includes(`/chat/r/${slug}/read?upto=`));
    await bob.page.goto(`/chat/r/${slug}`);
    await read;
    await bob.page.goto('/chat');
    const badge = bob.page.locator(`.unread-${slug}`);
    await expect(badge).toBeEmpty();

    for (const text of ['two', 'three']) {
      await box.fill(text);
      await box.press('Enter');
      await expect(box).toHaveValue('');
    }
    await expect(badge).toHaveText('2');

    const again = bob.page.waitForResponse((r) => r.request().method() === 'POST' && r.url().includes(`/chat/r/${slug}/read?upto=`));
    await bob.page.goto(`/chat/r/${slug}`);
    await again;
    await bob.page.goto('/chat');
    await expect(badge).toBeEmpty();
    await leave(ann, bob);
  });

  test('after a restart the Inbox refetches its log (resync), which the new process has empty', async ({ browser }) => {
    test.slow();
    const config = test.info().config;
    const s1 = await startServer(config);
    let s2: Server | undefined;
    const base = `http://127.0.0.1:${s1.port}`;
    const ann = await member(browser, base), bob = await member(browser, base, uid('bob'));
    try {
      await bob.page.goto('/chat/r/lobby'); // seen, so a mention finds him
      await bob.page.goto('/notify');
      await ann.page.goto('/chat/r/lobby?transport=sse');
      const box = ann.page.locator('.chat-composer textarea');
      await box.fill(`@${bob.name} before the restart`);
      await box.press('Enter');
      await expect(bob.page.locator('#notify-list .notify-item')).toHaveCount(1);

      const refetched = bob.page.waitForResponse((r) => new URL(r.url()).pathname === '/notify/list', { timeout: 30_000 });
      await stopServer(s1);
      s2 = await startServer(config, {}, s1.port);
      expect((await refetched).status()).toBe(200);
      await expect(bob.page.locator('#notify-list')).toContainText('Nothing yet.'); // memory: the old process's items went with it
    } finally {
      await leave(ann, bob);
      if (s2) await stopServer(s2);
      if (s1.proc.exitCode === null) s1.proc.kill();
    }
  });

  test('the Inbox is a member\'s: a guest is sent to pick a nickname', async ({ page }) => {
    await page.goto('/notify');
    await expect(page).toHaveURL(/\/login/);
  });
});
