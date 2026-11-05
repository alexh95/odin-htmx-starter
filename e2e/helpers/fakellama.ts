import { spawn, type ChildProcess } from 'node:child_process';
import { existsSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';

// tools/fakellama for a spec (PLAN §14.3): llama-server's routes with no model, built by global-setup. A
// spec drives its state over /__fake and picks a fault by a question's first word.

const REPO = path.resolve(__dirname, '../..');
const BIN = path.join(REPO, 'app', 'bin', process.platform === 'win32' ? 'fakellama.exe' : 'fakellama');

export type Fake = { url: string; port: number; proc: ChildProcess };

export async function startFake(opts: { key?: string; strict?: boolean; slots?: number; delayMs?: number } = {}): Promise<Fake> {
  if (!existsSync(BIN)) throw new Error('fakellama is not built: global-setup builds it for a build with the bot');
  const args = ['--port', '0', '--slots', String(opts.slots ?? 1), '--delay-ms', String(opts.delayMs ?? 5)];
  if (opts.key) args.push('--key', opts.key);
  if (opts.strict) args.push('--strict', '1');
  const proc = spawn(BIN, args, { stdio: ['ignore', 'pipe', 'inherit'] });
  const port = await new Promise<number>((done, fail) => {
    let out = '';
    proc.stdout!.on('data', (d) => {
      out += d;
      const m = out.match(/fakellama on 127\.0\.0\.1:(\d+)/);
      if (m) done(Number(m[1]));
    });
    proc.on('exit', (code) => fail(new Error(`fakellama exited ${code}`)));
  });
  return { url: `http://127.0.0.1:${port}`, port, proc };
}

export function stopFake(f: Fake) {
  f.proc.removeAllListeners('exit');
  f.proc.kill();
}

function call(f: Fake, method: string, route: string, body = ''): Promise<string> {
  return new Promise((done, fail) => {
    const req = http.request({ host: '127.0.0.1', port: f.port, path: route, method }, (res) => {
      let out = '';
      res.on('data', (d) => (out += d));
      res.on('end', () => done(out));
    });
    req.on('error', fail);
    req.end(body);
  });
}

export const setState = (f: Fake, state: 'ready' | 'loading' | 'sleeping') => call(f, 'POST', '/__fake/state', state);
export const fakeStats = async (f: Fake) =>
  JSON.parse(await call(f, 'GET', '/__fake/stats')) as { requests: number; closed: number; finished: number; refused: number; busy: number; peak: number };
