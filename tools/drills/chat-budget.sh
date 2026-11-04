#!/usr/bin/env sh
# M6's chat budgets (PLAN §18.4, D38; docs/perf/CHAT-BUDGETS.md). Linux only, the fan-out claims are
# that leg's. Three measurements, on `full` unless PROFILE says otherwise:
#
#   1. the writer task against one commit per write (tools/writerbench);
#   2. 1000 sockets in a room, 20 messages each to all, posted the way a composer posts them
#      (tools/streamload fanout --room);
#   3. send to another member's DOM, direct (tools/drills/chat-latency.mjs); the budget's own number
#      is through NPM, so run that script against the proxy or the site as well.
#
#   sh tools/drills/chat-budget.sh        (from the repo root, prepared)
#
# Env: PROFILE (full), PORT (8199), SOCKETS (1000), MESSAGES (20).
set -eu
cd "$(dirname "$0")/../.."
[ "$(uname -s)" = Linux ] || { echo "chat-budget: Linux only" >&2; exit 2; }
PROFILE="${PROFILE:-full}"
PORT="${PORT:-8199}"
SOCKETS="${SOCKETS:-1000}"
MESSAGES="${MESSAGES:-20}"
BASE="http://127.0.0.1:$PORT"
WORK="$(mktemp -d)"
trap 'kill "$SRV" 2>/dev/null || true; rm -rf "$WORK"' EXIT
mkdir -p app/bin

FAMILIES="-collection:store=app/stores/sqlite -collection:identity=app/platform/authz/anonymous -collection:client=app/platform/client/vanilla -collection:theme=app/platform/theme/lite"
# shellcheck disable=SC2086
odin build tools/writerbench -o:speed $FAMILIES -out:app/bin/writerbench
odin build tools/streamload -o:speed -out:app/bin/streamload
OUT="app/bin/$PROFILE-budget" sh build.sh "$PROFILE" -o:speed >/dev/null
ulimit -n 65536 2>/dev/null || ulimit -n 8192

echo "== the writer"
app/bin/writerbench --db "$WORK/writer.db"

echo "== $SOCKETS sockets × $MESSAGES messages"
ADMIN_HASH='$argon2id$v=19$m=19456,t=2,p=1$usNdKTDf754mp5KZr0QZOg$UmN+6Cr4ai7YMbp4f0SsrCtA/kmVO/w4cSHz7Fs8F8I' # the suites' test admin
THREADS=4 LOG_LEVEL=warn LAN_CIDRS=127.0.0.0/8 STREAM_CONNECTS=1000000 STREAMS_PER_CLIENT=100000 \
  DB_PATH="$WORK/data.db" UPLOADS_DIR="$WORK/uploads" ACCOUNTS_ADMIN_HASH="$ADMIN_HASH" ACCOUNTS_ADMIN_TOTP=optional \
  ACCOUNTS_REGISTRATION=open ACCOUNTS_REGISTER_PER_HOUR=100000000 ACCOUNTS_LOGIN_PER_CLIENT=100000000 \
  ACCOUNTS_LOGIN_PER_NET=100000000 ACCOUNTS_LOGIN_OVERALL=100000000 ACCOUNTS_NICK_KEY=budget-only-nickname-signing-key-0123456789 \
  "app/bin/$PROFILE-budget" "$PORT" >"$WORK/server.log" 2>&1 &
SRV=$!
i=0
until curl -fs "$BASE/livez" >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -lt 100 ] || { cat "$WORK/server.log"; exit 1; }
  sleep 0.1
done

# Members: the first holds the sockets; a post limit of 5 in 10 s needs MESSAGES/5 of them to post.
: >"$WORK/cookies"
n=$((MESSAGES / 5 + 2))
i=0
while [ "$i" -lt "$n" ]; do
  name="budget$i"
  if [ "$PROFILE" = streams ]; then
    url=/login; data="nick=$name&next=/"
  else
    url=/register; data="username=$name&password=a-long-enough-password&again=a-long-enough-password"
  fi
  curl -s -o /dev/null -c "$WORK/jar$i" -d "$data" "$BASE$url"
  awk 'NF >= 7 { printf "%s%s=%s", (c++ ? "; " : ""), $6, $7 } END { print "" }' "$WORK/jar$i" | sed 's/^#HttpOnly_//' >>"$WORK/cookies"
  i=$((i + 1))
done
app/bin/streamload fanout --base "$BASE" --ws "$SOCKETS" --publish "$MESSAGES" --every 0 --room lobby --cookies "$WORK/cookies"

echo "== send to another member's DOM, direct"
node tools/drills/chat-latency.mjs "$BASE" || true
