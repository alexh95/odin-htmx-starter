#!/usr/bin/env sh
# Load-test driver. Builds the profile `-o:speed`, then for each scenario and each
# VU level launches a FRESH server on a dedicated port (clean in-memory store — see
# load-tests/PLAN.md, "The write path needs care"), waits for /healthz, runs k6
# for a warmup + measured window, scrapes the server's per-route counters, and
# collects the result. At the end it stitches every run into results/summary.md
# and prints the table.
#
# Scenarios live per feature, scenarios/<f>/<name>.js, each with a `// tags:` line
# naming every feature it touches (@<f>, or @<f>-<member> for one family member),
# as the e2e specs are tagged. A run takes the scenarios whose features the build
# has, by its own `--features --json`.
#
# Usage:
#   ./run.sh                       # default sweep (10,50,100 VUs) over the profile's scenarios
#   ./run.sh --quick               # fast sanity: 20 VUs, short window
#   ./run.sh --sweep               # full curve: 1,10,50,100,200,500 VUs
#   ./run.sh --vus 1,100,500       # explicit VU levels
#   ./run.sh static api            # only these scenarios
#   ./run.sh --base https://host   # hit a remote target; skips build + local server
#   ./run.sh --strict              # exit 1 if any run breaches its thresholds
#   ./run.sh --parity [scenario …] # the parity gate (PLAN §18.2): lib/parity.sh
#
# Env: K6 (k6 binary), DURATION (30s), WARMUP (5s), PORT_BASE (8090), PROFILE (skeleton),
# BUILD_FLAGS (extra odin flags).
set -eu
cd "$(dirname "$0")"

[ "${1:-}" = "--parity" ] && { shift; exec sh lib/parity.sh "$@"; }

# ---- config / arg parsing -----------------------------------------------
SCENARIOS=""
VUS="10,50,100"
DURATION="${DURATION:-30s}"
WARMUP="${WARMUP:-5s}"
PORT_BASE="${PORT_BASE:-8090}"
BASE=""              # set => external target, no local build/launch
STRICT=""            # set => a breached threshold fails the whole run (exit 1)
P95="${P95:-50}"; P99="${P99:-100}"

while [ $# -gt 0 ]; do
  case "$1" in
    --quick)  VUS="20"; DURATION="6s"; WARMUP="2s" ;;
    --sweep)  VUS="1,10,50,100,200,500" ;;
    --vus)    shift; VUS="$1" ;;
    --duration) shift; DURATION="$1" ;;
    --base)   shift; BASE="$1" ;;
    --strict) STRICT=1 ;;
    --*)      echo "unknown flag: $1" >&2; exit 2 ;;
    *)        SCENARIOS="$SCENARIOS $1" ;;
  esac
  shift
done

# A scenario by name, wherever its feature keeps it: one file per name.
script_of() {
  set -- scenarios/*/"$1".js
  [ -f "$1" ] || { echo "no such scenario: $(basename "$1" .js)" >&2; return 1; }
  [ $# -eq 1 ] || { echo "two scenarios named $(basename "$1" .js): $*" >&2; return 1; }
  echo "$1"
}

# ---- locate k6 ----------------------------------------------------------
K6="${K6:-}"
if [ -z "$K6" ]; then
  if command -v k6 >/dev/null 2>&1; then K6="k6"
  elif [ -x "/c/Program Files/k6/k6.exe" ]; then K6="/c/Program Files/k6/k6.exe"
  else echo "k6 not found. Install it (winget install GrafanaLabs.k6) or set K6=path." >&2; exit 1
  fi
fi
echo "k6: $("$K6" version | head -1)"

# bombardier is an optional fast baseline; used only if present.
BOMBARDIER="${BOMBARDIER:-}"
[ -z "$BOMBARDIER" ] && command -v bombardier >/dev/null 2>&1 && BOMBARDIER="bombardier"

# ---- build the app (skipped for an external --base target) ---------------
# PROFILE picks the build (build.sh <profile>): skeleton, the parity witness, by default.
APP="../app"
PROFILE="${PROFILE:-skeleton}"
BIN="$APP/bin/$PROFILE"
case "$(uname -s)" in *MINGW*|*MSYS*|*CYGWIN*) BIN="$APP/bin/$PROFILE.exe" ;; esac

# BUILD_FLAGS adds odin flags: the nightly's `-sanitize:address -debug`.
if [ -z "$BASE" ]; then
  echo "building $PROFILE -o:speed ${BUILD_FLAGS:-}..."
  # shellcheck disable=SC2086 # one flag per word
  sh ../build.sh "$PROFILE" -o:speed ${BUILD_FLAGS:-}
fi

# ---- the build's features, and the scenarios that need only those ------------
# `--features --json` flattened onto one line: no jq, so plain sed.
FEATURES=""; MEMBERS=""
if [ -x "$BIN" ]; then
  info="$("$BIN" --features --json | tr -d ' \t\r\n')"
  FEATURES="$(echo "$info" | sed 's/.*"features":\[\([^]]*\)\].*/\1/' | tr -d '"' | tr ',' ' ')"
  for k in store identity client theme; do
    MEMBERS="$MEMBERS $(echo "$info" | sed "s/.*\"$k\":\"\([^\"]*\)\".*/\1/")"
  done
  # A lab host (full, PLAN §7.3): its origin is 127.0.0.1, the main host's any other name.
  case "$info" in *'"hosts":{'*'"lab":['*) TWO_HOSTS=1 ;; esac
fi
TWO_HOSTS="${TWO_HOSTS:-}"
# Where the dashboard is: /dashboard where landing owns the root. Passed without its slash: Git
# Bash rewrites an argument like DASHBOARD=/dashboard into a Windows path on its way to k6.exe.
case " $FEATURES " in *" landing "*) DASHBOARD=dashboard ;; *) DASHBOARD= ;; esac
# Whether the build has every feature (and member) a scenario's tags name. With
# no binary to ask (--base, nothing built here), every scenario counts.
wanted() { # $1 = script; sh has no locals, hence the w_ names
  grep -q '^// tags: @' "$1" || { echo "$1 has no '// tags:' line" >&2; exit 2; }
  [ -n "$FEATURES" ] || return 0
  for w_tag in $(sed -n 's|^// tags: ||p' "$1"); do
    w_tag="${w_tag#@}"; w_f="${w_tag%%-*}"; w_m=""; [ "$w_f" = "$w_tag" ] || w_m="${w_tag#*-}"
    case " $FEATURES " in *" $w_f "*) ;; *) return 1 ;; esac
    [ -z "$w_m" ] && continue
    case " $MEMBERS " in *" $w_m "*) ;; *) return 1 ;; esac
  done
}
# Default: every scenario of the build's features, so a new one is just a file.
if [ -z "$SCENARIOS" ]; then
  for f in scenarios/*/*.js; do
    [ -f "$f" ] || continue
    wanted "$f" && SCENARIOS="$SCENARIOS $(basename "$f" .js)"
  done
  [ -n "$SCENARIOS" ] || { echo "no scenarios for $PROFILE in $(pwd)/scenarios" >&2; exit 2; }
fi
for s in $SCENARIOS; do script_of "$s" >/dev/null || exit 2; done

# ---- results dir --------------------------------------------------------
RAW="results/raw"
rm -rf results
mkdir -p "$RAW"

# Each run's per-route request counters, scraped from /metrics before its server
# stops, for `tools/check parity` (PLAN §19.1.11): every route the profile mounts
# needs a non-zero count from this suite and from e2e. The bearer is this run's.
ROUTES="$APP/build/coverage/load/$PROFILE"
TOKEN=""
if [ -z "$BASE" ]; then
  rm -rf "$ROUTES"; mkdir -p "$ROUTES"
  TOKEN="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  printf '%s' "$TOKEN" >"$ROUTES/.token"
fi

# ---- server lifecycle helpers -------------------------------------------
# free_port: the first port from $1 that nothing listens on (lib/ports.sh).
. lib/ports.sh

SRV_PID=""
# The suites' test admin: a test value, made with `bin --hash-password` from the password in
# scenarios/accounts/login.js (and e2e/helpers/accounts.ts).
TEST_ADMIN_HASH='$argon2id$v=19$m=19456,t=2,p=1$usNdKTDf754mp5KZr0QZOg$UmN+6Cr4ai7YMbp4f0SsrCtA/kmVO/w4cSHz7Fs8F8I'
start_server() { # $1 = port
  # PORT is set, not just passed: the server prefers an exported PORT over argv.
  # LOG_LEVEL=warn drops the access log (~9% of throughput) so numbers stay
  # comparable with runs before it existed; export LOG_LEVEL=info to keep it.
  # k6 is one client opening far more streams than a person would, so the
  # per-client stream caps are lifted (PLAN §9.4); the totals stand. k6 is loopback,
  # which a nick build counts as the LAN, so its VUs can pick nicknames, and as its admins,
  # so they can load /admin/ops. The bot's mock answers at once, and its hourly limits are
  # lifted: a run measures the work, not the cap. An accounts build boots the suites' test
  # admin with the sign-in and registration limits lifted, its TOTP optional and registration open,
  # for the same reason.
  PORT="$1" LOG_LEVEL="${LOG_LEVEL:-warn}" METRICS_TOKEN_FILE="$ROUTES/.token" \
    STREAM_CONNECTS="${STREAM_CONNECTS:-1000000}" STREAMS_PER_CLIENT="${STREAMS_PER_CLIENT:-4096}" \
    LAB_PUBLISH_PER_MINUTE="${LAB_PUBLISH_PER_MINUTE:-100000000}" \
    LAN_CIDRS="${LAN_CIDRS:-127.0.0.0/8}" ACCOUNTS_NICK_ADMIN_CIDRS="${ACCOUNTS_NICK_ADMIN_CIDRS:-127.0.0.1/32}" \
    BOT_DELAY_MS="${BOT_DELAY_MS:-0}" \
    BOT_MEMBER_PER_HOUR="${BOT_MEMBER_PER_HOUR:-100000000}" BOT_GUEST_PER_HOUR="${BOT_GUEST_PER_HOUR:-100000000}" \
    ACCOUNTS_ADMIN_HASH="${ACCOUNTS_ADMIN_HASH:-$TEST_ADMIN_HASH}" SITE_URL_LAB="${TWO_HOSTS:+https://127.0.0.1}" \
    ACCOUNTS_LOGIN_PER_CLIENT="${ACCOUNTS_LOGIN_PER_CLIENT:-100000000}" ACCOUNTS_LOGIN_PER_NET="${ACCOUNTS_LOGIN_PER_NET:-100000000}" ACCOUNTS_LOGIN_OVERALL="${ACCOUNTS_LOGIN_OVERALL:-100000000}" \
    ACCOUNTS_ADMIN_TOTP="${ACCOUNTS_ADMIN_TOTP:-optional}" ACCOUNTS_REGISTRATION="${ACCOUNTS_REGISTRATION:-open}" \
    CONTACTS_CAP="${CONTACTS_CAP:-0}" ACCOUNTS_STEP_UP_PER_MEMBER="${ACCOUNTS_STEP_UP_PER_MEMBER:-100000000}" \
    ACCOUNTS_REGISTER_PER_HOUR="${ACCOUNTS_REGISTER_PER_HOUR:-100000000}" ACCOUNTS_CODES_PER_HOUR="${ACCOUNTS_CODES_PER_HOUR:-100000000}" \
    "$BIN" "$1" >"$RAW/server_$1.log" 2>&1 &
  SRV_PID=$!
  # wait for /healthz (up to ~10s)
  i=0
  while [ $i -lt 100 ]; do
    if curl -fs "http://127.0.0.1:$1/healthz" >/dev/null 2>&1; then return 0; fi
    i=$((i + 1)); sleep 0.1
  done
  echo "server on :$1 never became healthy; log:" >&2; cat "$RAW/server_$1.log" >&2
  return 1
}
stop_server() { # $1 = port and $2 = the run's name, to scrape its counters first
  [ -n "$SRV_PID" ] || return 0
  if [ -n "${2:-}" ]; then
    curl -fs -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:$1/metrics" |
      grep '^app_http_requests_total{' >"$ROUTES/$2.prom" || true
  fi
  kill "$SRV_PID" 2>/dev/null || true
  wait "$SRV_PID" 2>/dev/null || true
  SRV_PID=""
}
trap stop_server EXIT INT TERM

# ---- run matrix ---------------------------------------------------------
port=$PORT_BASE
FAILED=""   # scenario@VUs of every run k6 failed (a breached threshold, or worse)
for s in $SCENARIOS; do
  script="$(script_of "$s")"

  for vus in $(echo "$VUS" | tr ',' ' '); do
    [ -n "$BASE" ] || port="$(free_port "$port")"
    target="${BASE:-http://127.0.0.1:$port}"
    if [ -z "$BASE" ]; then start_server "$port" || exit 1; fi

    echo "==> $s @ ${vus} VUs (${DURATION} window) -> $target"
    "$K6" run \
      --quiet \
      --env "BASE_URL=$target" \
      --env "MAIN_URL=${TWO_HOSTS:+http://localhost:$port}" --env "DASHBOARD=$DASHBOARD" \
      --env "VUS=$vus" \
      --env "DURATION=$DURATION" \
      --env "WARMUP=$WARMUP" \
      --env "P95=$P95" --env "P99=$P99" \
      --env "METRICS_TOKEN=$TOKEN" \
      --env "OUT=$RAW/${s}_${vus}.json" \
      --env "OUT_CSV=$RAW/${s}_${vus}.csv" \
      "$script" || {
        # Keep going either way: one breach shouldn't cost the rest of the table.
        rc=$?; FAILED="$FAILED ${s}@${vus}"
        echo "  (k6 exit $rc at ${vus} VUs: thresholds breached, or an error — recorded, continuing)"
      }

    if [ -z "$BASE" ]; then stop_server "$port" "${s}_${vus}"; port=$((port + 1)); fi
  done
done

# ---- bombardier baselines (optional) ------------------------------------
if [ -n "$BOMBARDIER" ] && [ -z "$BASE" ]; then
  echo "bombardier baselines (raw throughput, 10s @ 100 conns) ..."
  start_server "$port" || exit 1
  for path in /static/app.css /api/search?q=a /; do
    echo "--- $path ---" >>"$RAW/bombardier.txt"
    "$BOMBARDIER" -d 10s -c 100 -l "http://127.0.0.1:$port$path" >>"$RAW/bombardier.txt" 2>&1 || true
  done
  stop_server
fi

# ---- stitch the summary -------------------------------------------------
SUMMARY="results/summary.md"
{
  echo "# Load-test run — $(date -u '+%Y-%m-%d %H:%M UTC')"
  echo
  echo "Target: ${BASE:-local $PROFILE (-o:speed, fresh server per run)} · window: $DURATION · warmup: $WARMUP"
  echo "Machine: $(uname -s -m)"
  echo
  echo "| scenario | VUs | RPS | p50 ms | p90 ms | p95 ms | p99 ms | max ms | fail % | KB/s |"
  echo "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
  for f in $(ls "$RAW"/*.csv 2>/dev/null | sort); do
    # csv: scenario,vus,rps,p50,p90,p95,p99,max,fail_rate,bytes_per_s
    awk -F',' '{
      printf "| %s | %s | %s | %s | %s | %s | %s | %s | %.2f | %d |\n",
        $1, $2, $3, $4, $5, $6, $7, $8, $9*100, $10/1024
    }' "$f"
  done
} >"$SUMMARY"

echo
echo "================ summary ($SUMMARY) ================"
cat "$SUMMARY"
echo
echo "raw per-run JSON + server logs in $RAW/"
[ -z "$BASE" ] && echo "per-route counters in $ROUTES/"

# Without --strict a breach is information (finding the knee is what a sweep is
# for); with it, the run is a gate.
if [ -n "$FAILED" ]; then
  echo "failed runs:$FAILED"
  [ -z "$STRICT" ] || exit 1
fi
