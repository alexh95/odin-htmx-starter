# platform/signed

`<body>.<MAC>` text the server hands out and reads back (PLAN §5.1, M4-13): a pending sign-in, envadmin's cookie.
`sign(body, key)` appends HMAC-SHA256 in base64url; `open(text, key)` gives the body back only when the MAC is the
key's, compared in constant time, so a caller parses only the server's own text. `signed_test` holds it, and fuzzes
`open` (`platform/fuzz`). L1: core and `platform/escape` only.
