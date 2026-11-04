// uploads: the chunked shim (PLAN §14.2). A file input with data-upload names the hidden field that
// gets the finished blob's address, and data-status the element that says how far it got. Fetch,
// not htmx: the chunks are binary, and each one's answer is the progress. A chunk that fails is
// tried again from where the server says it got to, so a dropped connection resumes.
(function () {
  var TRIES = 5;

  function say(input, text) {
    var at = document.querySelector(input.dataset.status);
    if (at) at.textContent = text;
  }

  function failed(r) {
    return r.json().catch(function () { return {}; }).then(function (j) {
      throw new Error(j.error || (r.status === 429 ? "Too many uploads: try again later." : "That upload failed."));
    });
  }

  function pause(tries) {
    return new Promise(function (done) { setTimeout(done, 250 * tries); });
  }

  // From `off` on; a 409 or a lost answer asks where it got to and goes on from there.
  function send(input, file, id, size, off, tries) {
    if (off >= file.size) return Promise.resolve();
    var part = file.slice(off, off + size);
    return fetch("/uploads/" + id + "?off=" + off, { method: "PUT", body: part }).then(function (r) {
      if (r.ok) return r.json();
      if (r.status === 422 || r.status === 404) return failed(r);
      throw new Error("retry");
    }).then(function (j) {
      say(input, "Uploading " + Math.floor(100 * j.received / file.size) + "%");
      return send(input, file, id, size, j.received, 0);
    }, function (e) {
      if (e.message !== "retry" && !(e instanceof TypeError)) throw e;
      if (tries >= TRIES) throw new Error("The connection dropped: that upload stopped.");
      return pause(tries + 1).then(function () {
        return fetch("/uploads/" + id);
      }).then(function (r) {
        return r.ok ? r.json() : failed(r);
      }).then(function (j) {
        return send(input, file, id, size, j.received, tries + 1);
      }, function (e2) {
        if (!(e2 instanceof TypeError)) throw e2;
        return send(input, file, id, size, off, tries + 1);
      });
    });
  }

  // A 503 is a full queue: the bytes are all there, so it only needs asking again.
  function finish(id, tries) {
    return fetch("/uploads/" + id + "/finish", { method: "POST" }).then(function (r) {
      if (r.status === 503 && tries < TRIES) return pause(tries + 1).then(function () { return finish(id, tries + 1); });
      return r.ok ? r.json() : failed(r);
    });
  }

  function upload(input, field) {
    var file = input.files[0];
    if (!file) return;
    field.value = "";
    say(input, "Uploading…");
    fetch("/uploads?size=" + file.size, { method: "POST" }).then(function (r) {
      return r.ok ? r.json() : failed(r);
    }).then(function (made) {
      return send(input, file, made.id, made.chunk, 0, 0).then(function () {
        return finish(made.id, 0);
      });
    }).then(function (j) {
      field.value = j.sha256;
      say(input, "Attached: " + file.name);
      var text = input.form && input.form.querySelector("textarea[required]");
      if (text) {
        text.required = false;
        text.dataset.optional = "1";
      }
    }).catch(function (e) {
      input.value = "";
      say(input, e.message);
    });
  }

  document.addEventListener("change", function (e) {
    var input = e.target;
    if (!input.matches || !input.matches("input[type=file][data-upload]")) return;
    var field = document.querySelector(input.dataset.upload);
    if (field) upload(input, field);
  });

  // A sent form forgets its attachment; reset() leaves a hidden field's value alone.
  document.addEventListener("reset", function (e) {
    var input = e.target.querySelector && e.target.querySelector("input[type=file][data-upload]");
    if (!input) return;
    var field = document.querySelector(input.dataset.upload);
    if (field) field.value = "";
    say(input, "");
    var text = e.target.querySelector("textarea[data-optional]");
    if (text) {
      text.required = true;
      delete text.dataset.optional;
    }
  }, true);
})();
