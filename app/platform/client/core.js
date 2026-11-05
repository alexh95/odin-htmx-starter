// The client's shared part, ahead of the client member's own in every profile's
// app.js (tools/bundle concatenates them; PLAN §12.4). HTMX drives every
// interaction; this covers what the server can't and what isn't a behaviour:
// the theme picker and its persistence (the head's pre-paint script restores the
// choice before first paint), the dashboard count-up, and Escape closing the
// overlay. Behaviours (tabs, toasts, form resets …) are the member's: vanilla's
// twins behind data-behave, or hyperscript's behaviours._hs.
//
// No inline handlers anywhere: the Content-Security-Policy forbids them. Markup
// names what a click means with a data-* attribute, and one delegated listener
// routes it, which also covers content htmx swaps in later.

// A revoke (PLAN §17.2.3): the hub's `kicked` on a member's #live (data-revoke) means the
// session ended or its role changed, so the page goes to sign in again rather than letting
// hx-sse reconnect as a guest. A page's own kick (the lab's #live) reconnects as before.
// A sign-out kicks its own session's streams, this page's among them (M4-09), as its answer
// (an HX-Redirect) arrives: going to sign in at once aborted that navigation. So the kick waits
// a moment, and a page that has started leaving meanwhile goes where it was going.
// Leaving is a moment, not a state: a beforeunload with no unload after it (an attachment, a
// page back from the bfcache) mustn't leave the page deaf to a later kick (M5-21).
// A snapshot of a public page still holds the member's header, so it goes with their session (§12).
function dropSnapshots() {
  try {
    Object.keys(sessionStorage).forEach(function (k) {
      if (k.indexOf("htmx-history-") === 0) sessionStorage.removeItem(k);
    });
  } catch (_) { /* no storage here */ }
}
document.addEventListener("submit", function (e) {
  if (e.target.matches && e.target.matches('[hx-post="/logout"]')) dropSnapshots();
});
var leftAt = 0;
addEventListener("beforeunload", function () { leftAt = Date.now(); });
addEventListener("pageshow", function () { leftAt = 0; });
document.addEventListener("kicked", function (e) {
  var live = e.target && e.target.closest ? e.target.closest("[data-revoke]") : null;
  if (live) dropSnapshots();
  if (live) setTimeout(function () { if (Date.now() - leftAt > 2000) location.assign(live.dataset.revoke); }, 500);
});
// `gone`: a member out of one room (a kick, a leave) keeps their session, so the page goes where the
// server names, a path on this site, rather than to sign in.
document.addEventListener("gone", function (e) {
  var to = e.detail && e.detail.data;
  if (typeof to !== "string" || to.charAt(0) !== "/" || to.charAt(1) === "/") return;
  setTimeout(function () { if (Date.now() - leftAt > 2000) location.assign(to); }, 500);
});
// A stream the server refuses (401, 403, 404: the viewer may not have its topics any more) is
// settled, not retried: hx-sse would back off and reconnect forever (PLAN §17.2.3 measured 5 in
// 30 s). The element is marked, and its next connection is cancelled.
document.addEventListener("htmx:sse:error", function (e) {
  var s = e.detail && e.detail.status;
  if (s === 401 || s === 403 || s === 404) e.target.dataset.sseRefused = "1";
});
document.addEventListener("htmx:sse:before:connection", function (e) {
  if (e.target.dataset && e.target.dataset.sseRefused) {
    if (e.detail && e.detail.connection) e.detail.connection.cancelled = true;
    e.preventDefault();
  }
});

// Theme picker — two axes on <html>: data-style (treatment) and data-scheme
// (palette). Pure presentation; persisted so the head pre-paint script can
// restore the choice before first paint. A signed-in member's identity may keep
// it too (data-theme-href on <html>), so every device of theirs renders it.
function persistPref() {
  var r = document.documentElement;
  try {
    localStorage.setItem("style", r.dataset.style || "");
    localStorage.setItem("scheme", r.dataset.scheme || "");
  } catch (e) {}
  if (r.dataset.themeHref) {
    fetch(r.dataset.themeHref, {
      method: "POST",
      body: new URLSearchParams({ style: r.dataset.style || "", scheme: r.dataset.scheme || "" }),
    }).catch(function () {});
  }
  markPicker();
}
function pickStyle(name) {
  var r = document.documentElement;
  r.dataset.style = name;
  // Keep the scheme valid for the new style; fall back to its first swatch.
  var swatches = document.querySelectorAll('.picker-schemes[data-for="' + name + '"] [data-pick-scheme]');
  var ids = Array.prototype.map.call(swatches, function (b) { return b.dataset.pickScheme; });
  if (ids.indexOf(r.dataset.scheme) < 0 && swatches[0]) r.dataset.scheme = swatches[0].dataset.pickScheme;
  persistPref();
}
function pickScheme(name) {
  document.documentElement.dataset.scheme = name;
  persistPref();
}
// Set both axes at once — the /components showroom swatches jump straight to a
// given style + scheme.
function setTheme(style, scheme) {
  var r = document.documentElement;
  r.dataset.style = style;
  r.dataset.scheme = scheme;
  persistPref();
}
function markPicker() {
  var r = document.documentElement;
  document.querySelectorAll("[data-pick-style]").forEach(function (b) {
    b.setAttribute("aria-pressed", String(b.dataset.pickStyle === r.dataset.style));
  });
  document.querySelectorAll("[data-pick-scheme]").forEach(function (b) {
    b.setAttribute("aria-pressed", String(b.dataset.pickScheme === r.dataset.scheme));
  });
  document.querySelectorAll(".showroom-swatches .swatch[data-sw-style]").forEach(function (b) {
    b.setAttribute("aria-pressed", String(b.dataset.swStyle === r.dataset.style && b.dataset.swScheme === r.dataset.scheme));
  });
}

// Count the dashboard stat values up from zero — cheap, and it makes the
// numbers feel alive on first paint.
function countUp() {
  document.querySelectorAll(".stat-value[data-count]").forEach(function (el) {
    if (el.dataset.counted) return; // animate each card once — idempotent so it's
    el.dataset.counted = "1";       // safe to re-run after a boosted nav swap.
    var target = parseInt(el.dataset.count, 10) || 0;
    if (target === 0) return;
    var start = performance.now(), dur = 600;
    function step(now) {
      var t = Math.min(1, (now - start) / dur);
      el.textContent = Math.round(target * (1 - Math.pow(1 - t, 3)));
      if (t < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  });
}

// htmx 4 fires htmx:after:process when it wires up new content (initial load and
// every swap, boosted navigation included): restore the chrome a boosted
// body-swap re-renders, the picker's pressed state and the count-up. Both are
// idempotent, so small in-page fragment swaps are cheap no-ops.
document.addEventListener("htmx:after:process", function () {
  markPicker();
  countUp();
}, true);

// The picker and showroom buttons, by what they carry; an outside click closes
// the picker.
document.addEventListener("click", function (e) {
  var t = e.target.closest ? e.target : e.target.parentElement;
  var b;
  if ((b = t.closest("[data-pick-style]"))) pickStyle(b.dataset.pickStyle);
  else if ((b = t.closest("[data-pick-scheme]"))) pickScheme(b.dataset.pickScheme);
  else if ((b = t.closest("[data-sw-style]"))) setTheme(b.dataset.swStyle, b.dataset.swScheme);
  var picker = document.querySelector(".picker[open]");
  if (picker && !picker.contains(e.target)) picker.removeAttribute("open");
});

// Escape closes the overlay (a modal or the drawer). The modal's backdrop never
// does: an outside click must not discard a half-typed field.
document.addEventListener("keydown", function (e) {
  if (e.key !== "Escape") return;
  var overlay = document.getElementById("overlay");
  if (overlay) overlay.replaceChildren(); // not innerHTML: a Trusted Types page refuses it
});

countUp();
markPicker();
