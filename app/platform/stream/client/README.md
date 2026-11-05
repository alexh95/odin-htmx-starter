# platform/stream/client

The one non-blocking HTTP, SSE and WebSocket client (PLAN §8.2, D12): a `Conn` on the event loop of the thread that
opens it (core:nbio), reporting through callbacks: `on_open` after the response head, `on_sse` per event, `on_ws` per
message, `on_body` per decoded read of a plain response (chunked or not), `on_close` with why. Its parsers (the head, a
chunked body, SSE with CR, LF and CRLF line ends, the server's WebSocket frames) are incremental and unit-tested. An SSE
event can be capped (`c.sse.max`), past which the read ends as `.Bad_Response`. Plain HTTP only. Its users: `tools/streamload` (M2), the bot's llama binding (M7) and the Pi's terminal agent (M11). Layer L3
(PLAN §5.1); it imports core only.

Audited: 88f9222 2026-11-05 docs/audit/M7.md (the head, chunked and SSE parsers; the WebSocket side, for M11, has no frame cap yet)
