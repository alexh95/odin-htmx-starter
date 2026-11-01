import { test, expect } from '../../fixtures';
import { leave, member, uid } from '../../helpers/members';
import { mainOrigin, startServer, stopServer, type Server } from '../../helpers/server';

// Retention (PLAN §14.1, Q19, D16): a room keeps its kind's newest CHAT_ROOM_CAP messages, and
// once it has let older ones go its page says so, with the room's own limits (the marker). Both
// stores: the memory store's ring takes the cap, SQLite's writer trims in the post's own batch.
test('a room keeps its newest CHAT_ROOM_CAP, and says it let older go', { tag: '@chat' }, async ({ browser }) => {
  let s: Server | undefined;
  try {
    s = await startServer(test.info().config, { CHAT_ROOM_CAP: '5', CHAT_ROOM_MAX_AGE: '2d' });
    const ann = await member(browser, mainOrigin(s.port)), bob = await member(browser, mainOrigin(s.port));
    await ann.page.goto('/chat');
    await ann.page.locator('#room-name').fill(uid('room '));
    await ann.page.getByRole('button', { name: 'Create' }).click();
    await ann.page.waitForURL(/\/chat\/r\//);
    const room = new URL(ann.page.url()).pathname;
    await ann.page.goto(`${room}?transport=sse`);
    await bob.page.goto(`${room}?transport=sse`);
    await expect(ann.page.locator('.chat-marker')).toHaveCount(0); // nothing let go yet
    // Taking turns: a member posts 5 in 10 s at most.
    for (let i = 1; i <= 7; i++) {
      const box = (i % 2 ? ann : bob).page.locator('.chat-composer textarea');
      await box.fill(`message ${i}`);
      await box.press('Enter');
      await expect(box).toHaveValue('');
    }
    await ann.page.goto(`${room}?transport=sse`);
    const log = ann.page.locator('.chat-log > article.chat-msg .chat-body');
    await expect(log).toHaveText(['message 3', 'message 4', 'message 5', 'message 6', 'message 7']);
    await expect(ann.page.locator('.chat-marker')).toHaveText('Older messages were removed (this room keeps the last 5 messages or 2 days).');
    await leave(ann, bob);
  } finally {
    if (s) await stopServer(s);
  }
});
