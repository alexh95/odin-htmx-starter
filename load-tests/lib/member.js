import http from 'k6/http';
import { MAIN } from './config.js';

// A member, kept in the VU's cookie jar (PLAN §17.1): on a nick build a nickname picked at
// /login; on an accounts build (full, M6) an account registered at /register, which run.sh keeps
// open with its limits lifted. run.sh passes the build's identity; k6 is loopback, which its
// server counts as the LAN. Chat and the Inbox are the main host's (MAIN: a one-host build's
// only one).

export const FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };

const ACCOUNTS = __ENV.IDENTITY === 'accounts';

// `params` go with each request (a second member's own `jar`).
export function signIn(name, params = {}) {
  if (ACCOUNTS) {
    // A username is letters, digits, `_`, `-` and `.`: a VU's name with a space isn't one.
    const username = name.replace(/[^A-Za-z0-9_.-]/g, '-');
    const made = http.post(`${MAIN}/register`, { username, password: 'a-long-enough-password', again: 'a-long-enough-password' },
      { headers: FORM, redirects: 0, tags: { name: 'POST /register' }, responseCallback: http.expectedStatuses({ min: 200, max: 399 }, 422), ...params });
    if (made.status !== 422) return made;
    // The name is taken: by this VU's own earlier registration, made from a jar it no longer has
    // (k6 gives the measured window new VUs); sign in to it.
    return http.post(`${MAIN}/login`, { username, password: 'a-long-enough-password', next: '/' },
      { headers: FORM, redirects: 0, tags: { name: 'POST /login' }, ...params });
  }
  return http.post(`${MAIN}/login`, { nick: name, next: '/' }, { headers: FORM, redirects: 0, tags: { name: 'POST /login' }, ...params });
}

// The jar's cookies as a Cookie header: a WebSocket's handshake carries no jar of its own.
export function cookieHeader() {
  const jar = http.cookieJar().cookiesForURL(MAIN);
  return Object.keys(jar).map((k) => `${k}=${jar[k][0]}`).join('; ');
}
