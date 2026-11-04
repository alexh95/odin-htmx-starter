import { readFileSync } from 'node:fs';
import path from 'node:path';
import { test, expect } from '../../fixtures';
import type { Page } from '@playwright/test';
import { leave, member } from '../../helpers/members';

// The server reads a JPEG's header and nothing else (PLAN §17.6), so the pixel cap holds only if a
// browser draws the frame the walk found. Files built to part them, in each engine: a real 32×32 image
// hidden from the walk behind a real 1×1 one. What the walk passes must show as the walk read it,
// or fail to show. A browser drawing the hidden frame would be a way past the cap.
const T = { tag: ['@uploads', '@chat'] };

const data = (name: string) => readFileSync(path.join(__dirname, '../../../app/features/uploads/testdata', name));
const SMALL = data('tiny.jpg'), HIDDEN = data('gradient.jpg');
const SOI = Buffer.from([0xff, 0xd8]);
const noSoi = (b: Buffer) => b.subarray(2);

const segment = (marker: number, body: Buffer) => {
  const head = Buffer.from([0xff, marker, 0, 0]);
  head.writeUInt16BE(body.length + 2, 2);
  return Buffer.concat([head, body]);
};

// Each passes the walk, and its header says 1×1.
const PASSING: [string, Buffer][] = [
  ['a whole image in a comment', Buffer.concat([SOI, segment(0xfe, noSoi(HIDDEN)), noSoi(SMALL)])],
  ['a whole image in an APP1', Buffer.concat([SOI, segment(0xe1, HIDDEN), noSoi(SMALL)])],
  ['a whole image after the end', Buffer.concat([SMALL, HIDDEN])],
  ['fill bytes before the frame', Buffer.concat([SOI, Buffer.from([0xff, 0xff, 0xff]), noSoi(SMALL)])],
];

// Each is refused: the walk can't tell what a decoder would do with it.
const REFUSED: [string, Buffer][] = [
  ['stuffing where a marker belongs', Buffer.concat([SOI, Buffer.from([0xff, 0x00, 0, 4, 0, 0]), noSoi(HIDDEN), noSoi(SMALL)])],
  ['a reserved marker', Buffer.concat([SOI, Buffer.from([0xff, 0x02, 0, 4, 0, 0]), noSoi(HIDDEN), noSoi(SMALL)])],
  ['a hierarchical marker', Buffer.concat([SOI, Buffer.from([0xff, 0xde, 0, 4, 0, 0]), noSoi(HIDDEN), noSoi(SMALL)])],
  ['a second frame', Buffer.concat([SMALL.subarray(0, SMALL.length - 2), noSoi(HIDDEN)])],
];

async function finish(page: Page, bytes: Buffer) {
  const made = await (await page.request.post(`/uploads?size=${bytes.length}`)).json();
  expect((await page.request.put(`/uploads/${made.id}?off=0`, { data: bytes })).status()).toBe(200);
  return page.request.post(`/uploads/${made.id}/finish`);
}

// What this engine makes of it: its width, or 0 for a broken image.
const drawn = (page: Page, bytes: Buffer) => page.evaluate((b64) => new Promise<number>((done) => {
  const img = new Image();
  img.onload = () => done(img.naturalWidth);
  img.onerror = () => done(0);
  img.src = `data:image/jpeg;base64,${b64}`;
}), bytes.toString('base64'));

test.describe('a browser draws the frame the walk read', T, () => {
  for (const [name, bytes] of PASSING) {
    test(`${name}: passes, and shows as its header says`, async ({ browser, baseURL }) => {
      const ann = await member(browser, baseURL!);
      await ann.page.goto('/chat');
      expect((await finish(ann.page, bytes)).status()).toBe(200);
      expect([0, 1]).toContain(await drawn(ann.page, bytes));
      await leave(ann);
    });
  }

  for (const [name, bytes] of REFUSED) {
    test(`${name}: refused`, async ({ browser, baseURL }) => {
      const ann = await member(browser, baseURL!);
      await ann.page.goto('/chat');
      expect((await finish(ann.page, bytes)).status()).toBe(422);
      // For the record, not the verdict: what this engine would have drawn had it got through.
      test.info().annotations.push({ type: 'drawn', description: `${name}: ${await drawn(ann.page, bytes)}` });
      await leave(ann);
    });
  }
});
