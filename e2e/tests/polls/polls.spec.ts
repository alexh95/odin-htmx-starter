import { test, expect } from '../../fixtures';
import type { Browser, Page } from '@playwright/test';
import { signIn } from '../../helpers/accounts';
import { leave, member, uid, type Member } from '../../helpers/members';

// Go/No-go (PLAN §15.1, Q36): the bars move live; a named vote shows its name and can change; an anonymous
// one is final, is never shown to anyone, the voter included, and leaves nothing that joins a person to a choice.
const T = { tag: ['@polls', '@accounts-accounts', '@notify'] };

async function ask(page: Page, opts: { options?: string[]; multiple?: boolean; anonymous?: boolean } = {}) {
  const question = uid('Lunch ');
  await page.goto('/polls');
  await page.locator('#poll-question').fill(question);
  if (opts.options) {
    await page.locator('#poll-kind').selectOption('options');
    await page.locator('#poll-options').fill(opts.options.join(String.fromCharCode(10)));
  }
  if (opts.multiple) await page.locator('#poll-multiple').check();
  if (opts.anonymous) await page.locator('#poll-anonymous').check();
  await page.getByRole('button', { name: 'Ask' }).click();
  await page.waitForURL(/\/polls\/\d+$/);
  return { question, href: new URL(page.url()).pathname };
}

const choose = async (page: Page, label: string) => {
  await page.locator('.poll-vote').getByLabel(label, { exact: true }).check();
  await page.locator('.poll-vote button[type="submit"]').click();
};
const count = (page: Page, label: string) => page.locator('.poll-row', { hasText: label }).locator('.poll-n');
const live = async (m: Member, href: string) => {
  await m.page.goto(href);
  await expect(m.page.locator('#live')).toBeAttached();
};

async function guest(browser: Browser, baseURL: string) {
  const context = await browser.newContext({ baseURL });
  return { context, page: await context.newPage() };
}

test.describe('polls', T, () => {
  test('a vote reaches another member live, and a named vote shows its name and can change', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const bob = await member(browser, baseURL!);
    const { href } = await ask(ann.page);
    await live(bob, href);
    await choose(ann.page, 'Go');
    await expect(count(ann.page, 'No-go')).toHaveText('0');
    await expect(bob.page.locator('.poll-row').first().locator('.poll-n')).toHaveText('1');
    await expect(bob.page.locator('.poll-row').first().locator('.poll-names')).toHaveText(ann.name);
    expect(await bob.page.locator('.poll-row').first().locator('.poll-bar').getAttribute('style')).toBe('--p:100%');
    await expect(ann.page.locator('.poll-act')).toContainText('You voted');
    await choose(ann.page, 'No-go');
    await expect(bob.page.locator('.poll-row').nth(1).locator('.poll-names')).toHaveText(ann.name);
    await expect(bob.page.locator('.poll-row').first().locator('.poll-n')).toHaveText('0');
    await ann.page.reload();
    await expect(ann.page.locator('.poll-vote').getByLabel('No-go', { exact: true })).toBeChecked();
    await leave(ann, bob);
  });

  test('an anonymous poll says what it is, takes one final vote, and shows nobody what it was', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const bob = await member(browser, baseURL!);
    const { href } = await ask(ann.page, { anonymous: true, options: ['Pizza', 'Soup', 'Salad'], multiple: true });
    await expect(ann.page.locator('.poll-note')).toContainText("aren't stored with names");
    await expect(ann.page.locator('.poll-note')).toContainText("can't be changed");
    await expect(ann.page.locator('.poll-note')).toContainText('Whoever changes this server');
    await live(bob, href);
    await ann.page.locator('.poll-vote').getByLabel('Pizza', { exact: true }).check();
    await ann.page.locator('.poll-vote').getByLabel('Salad', { exact: true }).check();
    await ann.page.locator('.poll-vote button[type="submit"]').click();
    await expect(ann.page.locator('.poll-act')).toContainText('You voted.');
    await expect(ann.page.locator('.poll-vote')).toHaveCount(0);
    await expect(count(bob.page, 'Pizza')).toHaveText('1');
    await expect(bob.page.locator('.poll-count')).toHaveText('1 voted'); // two choices, one voter

    for (const m of [ann, bob]) {
      await m.page.goto(href);
      const main = (await m.page.locator('main').innerHTML());
      expect(main).not.toContain(m === ann ? bob.name : ann.name);
      await expect(m.page.locator('.poll-names')).toHaveCount(0);
      await expect(m.page.locator('input[name="option"]:checked')).toHaveCount(0);
    }
    await expect(ann.page.locator('main')).not.toContainText(ann.name.toUpperCase());

    // Final: a second try, with the form gone, is refused and moves nothing.
    const option = await bob.page.locator('.poll-row').nth(1).getAttribute('data-option');
    const again = await ann.page.request.post(`${href}/vote`, { form: { option: option! } });
    expect(again.status()).toBe(409);
    await bob.page.reload();
    await expect(count(bob.page, 'Soup')).toHaveText('0');
    await leave(ann, bob);
  });

  test('a repeated choice counts once, and one choice is all a single-choice poll takes', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const { href } = await ask(ann.page, { anonymous: true, options: ['A', 'B'], multiple: true });
    const a = await ann.page.locator('.poll-row').first().getAttribute('data-option');
    const url = new URL(href, baseURL).href;
    const cookies = (await ann.context.cookies()).map((c) => `${c.name}=${c.value}`).join('; ');
    const sent = await fetch(url + '/vote', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', cookie: cookies }, body: `option=${a}&option=${a}` });
    expect(sent.status).toBe(200);
    await ann.page.reload();
    await expect(count(ann.page, 'A')).toHaveText('1');

    const single = await ask(ann.page);
    const options = await ann.page.locator('.poll-row').evaluateAll((rows) => rows.map((r) => r.getAttribute('data-option')));
    const two = await fetch(new URL(single.href, baseURL).href + '/vote', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', cookie: cookies }, body: `option=${options[0]}&option=${options[1]}` });
    expect(two.status).toBe(404);
    await leave(ann);
  });

  test('closing tells whoever voted, ends the voting, and only its maker can', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const bob = await member(browser, baseURL!);
    const { href, question } = await ask(ann.page, { anonymous: true });
    await live(bob, href);
    await choose(bob.page, 'Go');
    await expect(bob.page.locator('.poll-act')).toContainText('You voted.');
    await expect(bob.page.getByRole('button', { name: 'Close now' })).toHaveCount(0);
    expect((await bob.page.request.post(`${href}/close`)).status()).toBe(404);
    await ann.page.getByRole('button', { name: 'Close now' }).click();
    await expect(ann.page.locator('.poll-act')).toContainText('This poll has closed.');
    await expect(bob.page.locator('.poll-act')).toContainText('This poll has closed.');
    const option = await ann.page.locator('.poll-row').first().getAttribute('data-option');
    expect((await ann.page.request.post(`${href}/vote`, { form: { option: option! } })).status()).toBe(409);
    await bob.page.goto('/notify');
    await expect(bob.page.locator('main')).toContainText(question);
    await ann.page.goto('/notify');
    await expect(ann.page.locator('main')).not.toContainText(question);
    await leave(ann, bob);
  });

  test('a poll keeps text as text, and a bad one is refused', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    await ask(ann.page, { options: ['<img src=x data-xss onerror=window.__xss=1>', 'other'] });
    await expect(ann.page.locator('[data-xss]')).toHaveCount(0);
    await ann.page.goto('/polls');
    await ann.page.locator('#poll-question').fill('Only one?');
    await ann.page.locator('#poll-kind').selectOption('options');
    await ann.page.locator('#poll-options').fill('just this');
    await ann.page.getByRole('button', { name: 'Ask' }).click();
    await expect(ann.page.locator('#poll-error')).toContainText('at least two');
    expect(await ann.page.evaluate(() => (window as any).__xss)).toBeUndefined();
    await leave(ann);
  });

  test('a guest has none of it', async ({ browser, baseURL }) => {
    const ann = await member(browser, baseURL!);
    const { href } = await ask(ann.page);
    const g = await guest(browser, baseURL!);
    expect([302, 303, 401]).toContain((await g.page.request.get(href, { maxRedirects: 0 })).status());
    expect((await g.page.request.post(`${href}/vote`, { form: { option: '1' }, maxRedirects: 0 })).status()).not.toBe(200);
    const events = await g.page.request.get(`/events?t=polls.poll:${href.split('/').pop()}`, { maxRedirects: 0 });
    expect(events.status()).toBeGreaterThanOrEqual(300);
    await g.context.close();
    await leave(ann);
  });
});

test.describe('what an anonymous vote leaves', { tag: ['@polls', '@dbview', '@audit', '@accounts-accounts'] }, () => {
  test('the database, the audit log and the server log hold no link', async ({ browser, baseURL, server }) => {
    const ann = await member(browser, baseURL!);
    const { href } = await ask(ann.page, { anonymous: true, options: ['Marker one', 'Marker two'] });
    const option = await ann.page.locator('.poll-row').nth(1).getAttribute('data-option');
    await choose(ann.page, 'Marker two');
    await expect(ann.page.locator('.poll-act')).toContainText('You voted.');
    const id = href.split('/').pop();

    const admin = await signIn(browser, baseURL!, '/admin/dbview');
    try {
      const run = async (sql: string) => {
        await admin.page.locator('#dbview-sql').fill(sql);
        await Promise.all([
          admin.page.waitForResponse((r) => r.request().method() === 'POST' && r.url().includes('/admin/dbview')),
          admin.page.getByRole('button', { name: 'Run' }).click(),
        ]);
        return admin.page.locator('#dbview-result');
      };
      const heads = (r: ReturnType<Page['locator']>) => r.locator('.dbview-table th');
      await expect(heads(await run(`SELECT * FROM poll_voters WHERE poll = ${id}`))).toHaveText(['poll', 'who']);
      await expect(heads(await run(`SELECT * FROM poll_tally WHERE poll = ${id}`))).toHaveText(['poll', 'option', 'n']);
      await expect((await run(`SELECT count(*) FROM poll_votes WHERE poll = ${id}`)).locator('.dbview-table td')).toHaveText('0');
      await expect((await run('SELECT rowid FROM poll_voters')).locator('.dbview-problem')).toContainText('rowid');
      await expect((await run('SELECT rowid FROM poll_tally')).locator('.dbview-problem')).toContainText('rowid');
      await expect((await run("SELECT count(*) FROM audit_log WHERE action LIKE 'poll%'")).locator('.dbview-table td')).toHaveText('0');
    } finally {
      await admin.context.close();
    }

    // The access line names the route, and the option is nowhere near it.
    const lines = server.output().split(String.fromCharCode(10)).filter((l) => l.includes(`/polls/`) && l.includes('/vote'));
    expect(lines.length).toBeGreaterThan(0);
    for (const l of lines) {
      expect(l).not.toContain('option');
      expect(l).not.toContain('Marker');
      expect(l).not.toMatch(new RegExp(`\\b${option}\\b`));
    }
    await leave(ann);
  });
});
