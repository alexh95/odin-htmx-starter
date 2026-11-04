import crypto from 'node:crypto';
import http from 'node:http';
import net from 'node:net';
import { expect, has, test } from '../../fixtures';
import { startServer, stopServer, TWO_HOSTS } from '../../helpers/server';
import { closeTopic, epochOf, get, HOST, post, publish, say, seqOf, sleep, sse, stats, uid, wsRaw } from './streams';

// 03's contract checks that speak the protocols from Node (03 §10.2; spike S0.3), numbered as 03
// numbers them, and what PLAN §8.2 and §9 add, against the lab's endpoints on platform/stream and
// platform/hub. The checks a browser engine must run are in engine.spec.ts.

const T = { tag: '@lab' };

test.describe('SSE', T, () => {
  test('03#01 sse/tick: 200, text/event-stream, chunked', async ({ server }) => {
    const r = await get(server.port, '/lab/sse/tick?n=5&ms=200');
    expect(r.status).toBe(200);
    expect(r.headers['content-type']).toBe('text/event-stream');
    expect(r.headers['transfer-encoding']).toBe('chunked');
  });

  test('03#02 sse/tick: 5 events spread over ~1 s (streamed, not buffered)', async ({ server }) => {
    const r = await get(server.port, '/lab/sse/tick?n=5&ms=200');
    expect((r.body.match(/^id: /gm) || []).length).toBe(5);
    expect(r.times.at(-1)!).toBeGreaterThanOrEqual(900);
    test.info().annotations.push({ type: 'chunk times ms', description: r.times.join(',') });
  });

  test('03#03 keep-alive: the next request reuses the socket after a stream ends', async ({ server }) => {
    const agent = new http.Agent({ keepAlive: true, maxSockets: 1 });
    await get(server.port, '/lab/sse/tick?n=2&ms=50', { agent });
    const r = await get(server.port, '/healthz', { agent });
    agent.destroy();
    expect(r.body).toBe('ok');
    expect(r.reused).toBe(true);
  });

  // F-18: a keep-alive client sends its next request the moment the last chunk lands, while
  // the stream's read (kept to notice the peer leaving) may still be in flight. Those bytes
  // are the next request's: lost, the server reads it from the middle (a 501, or a hang).
  test('keep-alive: a request sent the moment a stream ends is read whole, every time', async ({ server }) => {
    const s = net.connect(server.port, HOST);
    s.setNoDelay(true);
    let buf = '';
    let wake: (() => void) | null = null;
    s.on('data', (d) => { buf += d.toString('latin1'); wake?.(); });
    await new Promise<void>((r) => s.once('connect', () => r()));
    const until = async (what: string, done: () => boolean) => {
      const end = Date.now() + 5000;
      while (!done()) {
        if (Date.now() > end) throw new Error(`${what}: timed out; got ${JSON.stringify(buf.slice(0, 200))}`);
        await new Promise<void>((r) => { wake = r; setTimeout(r, 50); });
      }
    };
    const statuses: string[] = [];
    for (let i = 0; i < 300; i++) {
      buf = '';
      s.write(`GET /lab/sse/tick?n=1&ms=0 HTTP/1.1\r\nHost: ${HOST}\r\n\r\n`);
      await until(`round ${i}: the stream`, () => buf.endsWith('\r\n0\r\n\r\n'));
      buf = '';
      s.write(`GET /healthz HTTP/1.1\r\nHost: ${HOST}\r\n\r\n`); // at once, on the same socket
      await until(`round ${i}: the request after it`, () => /\r\n\r\n/.test(buf) && (buf.endsWith('ok') || !buf.startsWith('HTTP/1.1 200')));
      statuses.push(buf.slice(0, 12));
    }
    s.destroy();
    expect(statuses.filter((x) => x !== 'HTTP/1.1 200')).toEqual([]);
  });

  test('03#04 the bus: beats from the producer job (no event loop) arrive', async ({ server }) => {
    const evs = await sse(server.port, '/events?t=lab.bus', { count: 3, ms: 4000 });
    expect(evs).toHaveLength(3);
    for (const e of evs) expect(e.data).toMatch(/beat \d+/);
  });

  test('03#05 the bus: Last-Event-ID resumes right after the given id', async ({ server }) => {
    const evs = await sse(server.port, '/events?t=lab.bus', { count: 3, ms: 4000 });
    expect(evs.length).toBeGreaterThan(0);
    const first = evs[0].id!;
    const replay = await sse(server.port, '/events?t=lab.bus', { count: 2, ms: 3000, headers: { 'Last-Event-ID': first } });
    expect(epochOf(replay[0]?.id)).toBe(epochOf(first));
    expect(seqOf(replay[0]?.id)).toBeGreaterThan(seqOf(first));
    expect(replay[0]?.data).not.toBe(evs[0].data); // the one after, not the one given
  });

  test.describe('publish to 8 subscribers', () => {
    let hits: ({ event?: string; data: string } | undefined)[] = [];
    let status = 0;
    const key = uid('post');
    test.beforeAll(async ({ server }) => {
      const subs = Array.from({ length: 8 }, () => sse(server.port, `/events?t=lab.feed:${key}`, { count: 50, ms: 2000 }));
      await sleep(400);
      status = await publish(server.port, key, 'cr', `${key}\r\nevent: injected`);
      hits = (await Promise.all(subs)).map((evs) => evs.find((e) => e.data.includes(key)));
    });

    test('03#06 publish: 204', async () => {
      expect(status).toBe(204);
    });
    test('03#07 publish: all 8 subscribers got it', async () => {
      expect(hits.every(Boolean)).toBe(true);
    });
    test('03#08 sse framing: a CR in the payload cannot inject a field', async () => {
      for (const e of hits) {
        expect(e?.event).toBeUndefined();
        expect(e?.data).toContain('event: injected');
      }
    });
  });

  test('every stream route sends X-Accel-Buffering: no and Cache-Control: no-cache, no-transform (PLAN §8.2)', async ({ server }) => {
    for (const p of ['/events?t=lab.feed:x', '/events?t=lab.bus', '/lab/sse/tick?n=1&ms=10', '/lab/multipart?n=1&ms=10', '/lab/mp/count?n=1&max=1']) {
      const h = await new Promise<http.IncomingHttpHeaders>((res, rej) => {
        const req = http.get({ host: HOST, port: server.port, path: p }, (r) => { res(r.headers); r.destroy(); });
        req.on('error', rej);
      });
      expect(h['x-accel-buffering'], p).toBe('no');
      expect(h['cache-control'], p).toBe('no-cache, no-transform');
      expect(h['transfer-encoding'], p).toBe('chunked');
    }
  });

  test('a HEAD to a stream route gets 405 and Allow: GET, never a body that doesn\'t end (M2-14)', async ({ server }) => {
    for (const p of ['/events?t=lab.bus', '/lab/sse/tick?n=1&ms=10', '/lab/mp/count?n=1&max=1']) {
      const r = await new Promise<http.IncomingMessage>((res, rej) => {
        const req = http.request({ host: HOST, port: server.port, path: p, method: 'HEAD' }, res);
        req.on('error', rej);
        req.end();
      });
      expect(r.statusCode, p).toBe(405);
      expect(r.headers['allow'], p).toBe('GET');
      r.destroy();
    }
  });

  test('/events refuses a topic its host does not mount (400) and a malformed one (400)', async ({ server }) => {
    // chat.room where this host doesn't mount it (a selection with chat on its one host does: 403).
    const elsewhere = has('chat') && !TWO_HOSTS ? 'nothing.here:1' : 'chat.room:1';
    for (const t of [elsewhere, 'lab.feed:BAD', 'lab.feed:a@x', '', 'lab.bus@5']) {
      expect((await get(server.port, `/events?t=${encodeURIComponent(t)}`)).status, t).toBe(400);
    }
  });
});

test.describe('the hub\'s cursors (PLAN §9.3)', T, () => {
  test('ids are `<epoch>-<seq>`; a foreign epoch gets `event: resync` whose id moves the cursor to now', async ({ server }) => {
    const key = uid('t');
    const evs = await sse(server.port, `/events?t=lab.feed:${key}&after=1-1`, { count: 1, ms: 2000 });
    const s = await stats(server.port);
    expect(evs[0]).toEqual({ id: `${epochOf(s.cursor)}-${seqOf(evs[0].id)}`, event: 'resync', data: `lab.feed:${key}` });
    // The resync's id is a cursor of this epoch: resuming from it replays from the ring.
    await publish(server.port, key, 'after', 'after the resync');
    const again = await sse(server.port, `/events?t=lab.feed:${key}`, { count: 1, ms: 2000, headers: { 'Last-Event-ID': evs[0].id! } });
    expect(again.map((e) => e.data)).toEqual([`<div hx-swap-oob="beforeend:#feed"><article id="m-after">after the resync</article></div>`]);
  });

  test('a page\'s `after` is one URL component: it can\'t add a topic to the page\'s stream (M2-16)', async ({ server }) => {
    const r = await get(server.port, '/lab/streams/live?after=1-1%26t%3Dlab.room%3Ax');
    expect(r.body).toContain('&amp;after=1-1%26t%3Dlab.room%3Ax"');
  });

  test('a gap older than the topic\'s ring gets `event: resync`, not a partial replay', async ({ server }) => {
    const key = uid('t');
    const old = (await stats(server.port)).cursor;
    for (let i = 0; i < 260; i++) await publish(server.port, key, `m${i}`); // HUB_RING is 256
    const evs = await sse(server.port, `/events?t=lab.feed:${key}`, { count: 1, ms: 2000, headers: { 'Last-Event-ID': old } });
    expect(evs[0]?.event).toBe('resync');
  });

  test('a replay past a stream\'s backlog budget gets `event: resync`, not a cut as too slow (M2-03)', async ({ server }) => {
    const key = uid('t');
    const old = (await stats(server.port)).cursor;
    for (let i = 0; i < 30; i++) await publish(server.port, key, `m${i}`, 'x'.repeat(10_000)); // 300 KB, past the 256 KiB queue
    const evs = await sse(server.port, `/events?t=lab.feed:${key}`, { count: 1, ms: 3000, headers: { 'Last-Event-ID': old } });
    expect(evs[0]?.event).toBe('resync');
  });

  test('a topic\'s ring replays only that topic: another topic\'s traffic doesn\'t push it out', async ({ server }) => {
    const quiet = uid('q'), busy = uid('b');
    const old = (await stats(server.port)).cursor;
    await publish(server.port, quiet, 'one');
    for (let i = 0; i < 300; i++) await publish(server.port, busy, `m${i}`);
    const evs = await sse(server.port, `/events?t=lab.feed:${quiet}`, { count: 1, ms: 2000, headers: { 'Last-Event-ID': old } });
    expect(evs[0]?.event).toBeUndefined();
    expect(evs[0]?.data).toContain('id="m-one"');
  });
});

test.describe('WebSocket protocol edges', T, () => {
  test('03#13 handshake: 101 and the right Sec-WebSocket-Accept', async ({ server }) => {
    const w = await wsRaw(server.port, '/lab/ws/echo');
    expect(w.status).toBe(101);
    expect(w.acceptOk).toBe(true);
    w.s.destroy();
  });

  test.describe('a ping between fragments', () => {
    let f1: Awaited<ReturnType<Awaited<ReturnType<typeof wsRaw>>['next']>>;
    let f2: typeof f1;
    test.beforeAll(async ({ server }) => {
      const w = await wsRaw(server.port, '/lab/ws/echo');
      w.send(0x1, 'he', { fin: false }); w.send(0x9, 'p'); w.send(0x0, 'llo');
      f1 = await w.next(); f2 = await w.next();
      w.s.destroy();
    });
    test('03#14 ws: a ping between fragments gets a pong, then the reassembled message', async () => {
      expect(f1?.op).toBe(0xA);
      expect(f1?.payload.toString()).toBe('p');
      expect(f2?.op).toBe(0x1);
      expect(f2?.payload.toString()).toBe('hello');
    });
    test('03#15 ws: server frames are unmasked', async () => {
      expect(f1?.masked).toBe(false);
      expect(f2?.masked).toBe(false);
    });
  });

  const closes: [string, (w: Awaited<ReturnType<typeof wsRaw>>) => void, number][] = [
    ['03#16 ws: an unmasked client frame closes 1002', (w) => w.send(0x1, 'x', { mask: false }), 1002],
    ['03#17 ws: invalid UTF-8 in a text frame closes 1007', (w) => w.send(0x1, Buffer.from([0xff, 0xfe])), 1007],
    ['03#18 ws: RSV1 without an extension closes 1002', (w) => w.send(0x1, 'a', { rsv: 0x40 }), 1002],
    ['03#19 ws: a continuation with nothing to continue closes 1002', (w) => w.send(0x0, 'a'), 1002],
    ['03#20 ws: a close with the reserved code 1005 closes 1002', (w) => w.send(0x8, Buffer.from([0x03, 0xed])), 1002],
  ];
  for (const [name, act, code] of closes) {
    test(name, async ({ server }) => {
      const w = await wsRaw(server.port, '/lab/ws/echo');
      act(w);
      const f = await w.next();
      expect(f?.op).toBe(8);
      expect(f?.code).toBe(code);
      await w.closed;
    });
  }

  test('03#21 handshake: a foreign Origin gets 403', async ({ server }) => {
    const w = await wsRaw(server.port, '/lab/ws/echo', { Origin: 'http://evil.example' });
    expect(w.status).toBe(403);
    w.s.destroy();
  });

  test('03#22 handshake: the host\'s own origin gets 101', async ({ server }) => {
    // The e2e server runs with no SITE_URL, so its origin is the brand's placeholder, and the
    // page's own origin (the request's Host) is what passes.
    const w = await wsRaw(server.port, '/lab/ws/echo', { Origin: `http://${HOST}:${server.port}` });
    expect(w.status).toBe(101);
    w.s.destroy();
    const other = await wsRaw(server.port, '/lab/ws/echo', { Origin: `http://${HOST}:${server.port + 1}` });
    expect(other.status).toBe(403);
    other.s.destroy();
  });

  test('a handshake admission refuses is a plain 429: no Upgrade, no accept key (M2-15)', async () => {
    const s = await startServer(test.info().config, { STREAM_CONNECTS: '1' });
    try {
      const first = await wsRaw(s.port, '/lab/ws/echo');
      expect(first.status).toBe(101);
      const refused = await wsRaw(s.port, '/lab/ws/echo');
      expect(refused.status).toBe(429);
      expect(refused.head).not.toMatch(/^(upgrade|sec-websocket-accept):/im);
      expect(refused.head).not.toMatch(/^connection: upgrade/im);
      first.s.destroy();
      refused.s.destroy();
    } finally {
      await stopServer(s);
    }
  });

  test('03#23 handshake: version 8 gets 426 and Sec-WebSocket-Version: 13', async ({ server }) => {
    const w = await wsRaw(server.port, '/lab/ws/echo', { 'Sec-WebSocket-Version': '8' });
    expect(w.status).toBe(426);
    expect(w.head).toMatch(/sec-websocket-version: 13/i);
    w.s.destroy();
  });

  test('03#24 ws: frames pipelined in the handshake\'s packet are processed', async ({ server }) => {
    const key = crypto.randomBytes(16).toString('base64');
    const s = net.connect(server.port, HOST);
    const m = Buffer.from([1, 2, 3, 4]);
    const p = Buffer.from('early').map((x, i) => x ^ m[i & 3]);
    const frame = Buffer.concat([Buffer.from([0x81, 0x80 | 5]), m, p]);
    const reply = await new Promise((res) => {
      let data = Buffer.alloc(0);
      s.on('connect', () => s.write(Buffer.concat([Buffer.from(`GET /lab/ws/echo HTTP/1.1\r\nHost: ${HOST}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`), frame])));
      s.on('data', (d) => { data = Buffer.concat([data, d]); if (data.includes('early')) res(true); });
      setTimeout(() => res(false), 3000);
    });
    s.destroy();
    expect(reply).toBe(true);
  });
});

test.describe('multipart', T, () => {
  test('03#26 multipart: Content-Type multipart/mixed with a boundary', async ({ server }) => {
    const r = await get(server.port, '/lab/multipart?n=3');
    expect(r.headers['content-type']).toMatch(/^multipart\/mixed; boundary=[\x21-\x7e]{1,70}$/);
  });

  test('03#27 multipart: 3 parts with HX-Part-ID, then the closing boundary, spread over time', async ({ server }) => {
    const r = await get(server.port, '/lab/multipart?n=3');
    const boundary = /boundary=(\S+)/.exec(r.headers['content-type'] ?? '')![1];
    expect((r.body.match(/HX-Part-ID/g) || []).length).toBe(3);
    expect(r.body.startsWith(`\r\n--${boundary}\r\n`)).toBe(true); // a CRLF preamble, then the first part
    expect(r.body.endsWith(`\r\n--${boundary}--\r\n`)).toBe(true);
    expect(r.body).not.toMatch(/[^\r]\n/); // CRLF framing: no bare LF anywhere
    expect(r.times.at(-1)!).toBeGreaterThanOrEqual(250);
    test.info().annotations.push({ type: 'chunk times ms', description: r.times.join(',') });
  });
});

test.describe('fan-out, limits and slow consumers', T, () => {
  test('03#28 a slow SSE consumer is dropped as Too_Slow; the server keeps serving', async ({ server }) => {
    const key = uid('slow');
    const before = (await stats(server.port)).ended.Too_Slow;
    const slow = net.connect(server.port, HOST);
    await new Promise((r) => slow.on('connect', r));
    slow.write(`GET /events?t=lab.feed:${key} HTTP/1.1\r\nHost: ${HOST}\r\n\r\n`);
    slow.pause();
    await sleep(300);
    const chunk = 'x'.repeat(60000);
    for (let i = 0; i < 200; i += 50) await Promise.all(Array.from({ length: 50 }, (_, j) => publish(server.port, key, `m${i + j}`, chunk)));
    let after = before;
    for (let i = 0; i < 30 && after <= before; i++) { await sleep(100); after = (await stats(server.port)).ended.Too_Slow; }
    slow.destroy();
    expect(after).toBeGreaterThan(before);
    expect((await get(server.port, '/healthz')).body).toBe('ok');
  });

  test('03#29 fan-out spans more than one event loop', async ({ server }) => {
    const key = uid('fan');
    const subs = Array.from({ length: 8 }, () => sse(server.port, `/events?t=lab.feed:${key}`, { count: 50, ms: 1500 }));
    await sleep(400);
    const n = await stats(server.port);
    await publish(server.port, key, 'fan');
    const got = await Promise.all(subs);
    expect(got.every((evs) => evs.some((e) => e.data.includes('id="m-fan"')))).toBe(true);
    // The claim is the Linux leg's (R3): Windows IOCP may hand every connection to one loop
    // (03 §2.1, §10.4), and spreads them unevenly when it doesn't (12 §2), so there it is noted.
    if (n.os === 'windows') test.info().annotations.push({ type: 'loops with subscribers', description: String(n.loops_with_subs) });
    else expect(n.loops_with_subs).toBeGreaterThan(1);
  });

  // PLAN §9.4: a slow socket gets 1013 when the next frame would pass its cap, then 2 s to take
  // what's queued (F-1's stream_end deadline) before it is cut off as Too_Slow. The messages go
  // one at a time, as a slow consumer meets them: the kernel's buffers fill first, then the
  // queue. A burst of five 60 KB messages in one drain passes the 256 KiB cap on its own while
  // the kernel still has room, and the kernel then takes the rest inside the deadline.
  async function slowSocket(port: number, room: string) {
    const key = crypto.randomBytes(16).toString('base64');
    const s = net.connect(port, HOST);
    await new Promise((r) => s.on('connect', r));
    s.write(`GET /lab/ws/chat?room=${room} HTTP/1.1\r\nHost: ${HOST}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n\r\n`);
    await sleep(300);
    s.pause();
    const chunk = 'x'.repeat(60000);
    for (let i = 0; i < 200; i++) await say(port, room, chunk);
    return s;
  }

  test('a slow WebSocket consumer that reads again gets close 1013 (PLAN §9.4)', async ({ server }) => {
    const s = await slowSocket(server.port, uid('room'));
    await sleep(500);
    let buf = Buffer.alloc(0);
    s.on('data', (d) => { buf = Buffer.concat([buf, d]); });
    s.resume();
    await new Promise((r) => { s.on('close', r); setTimeout(r, 5000); });
    const tail = buf.subarray(Math.max(0, buf.length - 4));
    expect([...tail]).toEqual([0x88, 0x02, 1013 >> 8, 1013 & 255]);
  });

  test('a slow WebSocket consumer that never reads is cut off at the deadline (PLAN §9.4)', async ({ server }) => {
    const before = (await stats(server.port)).ended.Too_Slow;
    const s = await slowSocket(server.port, uid('room'));
    const closed = new Promise<number>((r) => { const t0 = Date.now(); s.on('close', () => r(Date.now() - t0)); });
    let after = before;
    for (let i = 0; i < 50 && after <= before; i++) { await sleep(100); after = (await stats(server.port)).ended.Too_Slow; }
    expect(after).toBeGreaterThan(before);
    s.resume();
    expect(await Promise.race([closed, sleep(3000).then(() => -1)])).toBeGreaterThanOrEqual(0);
  });

  test('close: a kick ends the topic\'s SSE streams with the named event `kicked`', async ({ server }) => {
    const key = uid('k');
    const evs = sse(server.port, `/events?t=lab.feed:${key}`, { count: 5, ms: 2000 });
    await sleep(300);
    expect(await closeTopic(server.port, `lab.feed:${key}`)).toBe(204);
    expect((await evs).map((e) => e.event)).toEqual(['kicked']);
  });

  test('publish and close refuse what isn\'t a lab feed or room with a plain key', async ({ server }) => {
    for (const t of ['lab.bus', 'chat.room:1', 'lab.feed:A', 'lab.feed:', 'lab.feed:a<b']) {
      expect(await post(server.port, `/lab/publish?t=${encodeURIComponent(t)}`, { id: 'x', text: 'y' }), t).toBe(400);
      expect(await closeTopic(server.port, t), t).toBe(400);
    }
  });
});
