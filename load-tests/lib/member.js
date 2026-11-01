import http from 'k6/http';
import { MAIN } from './config.js';

// A member, kept in the VU's cookie jar (PLAN §17.1): on a nick build a nickname picked at
// /login; on an accounts build (full, M6) an account registered at /register, which run.sh keeps
// open with its limits lifted. run.sh passes the build's identity; k6 is loopback, which its
// server counts as the LAN. Chat and the Inbox are the main host's (MAIN: a one-host build's
// only one).

export const FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };

const ACCOUNTS = __ENV.IDENTITY === 'accounts';

export function signIn(name) {
  if (ACCOUNTS) {
    // A username is letters, digits, `_`, `-` and `.`: a VU's name with a space isn't one.
    const username = name.replace(/[^A-Za-z0-9_.-]/g, '-');
    return http.post(`${MAIN}/register`, { username, password: 'a-long-enough-password', again: 'a-long-enough-password' },
      { headers: FORM, redirects: 0, tags: { name: 'POST /register' } });
  }
  return http.post(`${MAIN}/login`, { nick: name, next: '/' }, { headers: FORM, redirects: 0, tags: { name: 'POST /login' } });
}

// The jar's cookies as a Cookie header: a WebSocket's handshake carries no jar of its own.
export function cookieHeader() {
  const jar = http.cookieJar().cookiesForURL(MAIN);
  return Object.keys(jar).map((k) => `${k}=${jar[k][0]}`).join('; ');
}
