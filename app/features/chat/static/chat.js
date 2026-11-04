// chat's Auto connection (PLAN §14.1, spike M6.1): a WebSocket until two closes come with no
// connection between them, which is all a browser says of a proxy that won't pass one. Then
// Streaming, for as long as the browser stays open: the next session tries the socket again.
(function () {
  var closes = 0;
  document.addEventListener("htmx:ws:after:connection", function () { closes = 0; }, true);
  document.addEventListener("htmx:ws:close", function (e) {
    if (!e.target.closest || !e.target.closest("[data-auto]")) return;
    closes += 1;
    if (closes < 2) return;
    document.cookie = "chat_fallback=sse; Path=/chat; SameSite=Lax" + (location.protocol === "https:" ? "; Secure" : "");
    location.reload();
  }, true);
})();
