# Data — the stores, and when each is right

A feature keeps its data in a **store**, one package per family: `app/stores/memory/<f>/` and
`app/stores/sqlite/<f>/`. A profile picks the family on its `build.sh` line (`store=memory` or
`store=sqlite`), the feature's domain imports `store:<f>`, and the compiler resolves it to that
family's package. The domain, the views and the HTTP surface don't change when the family does:
each store states the feature's contract (the `Store_*` proc types in its `models`) in its
`contract.odin`, so a store that drifts fails to build. `minimal` runs on memory and links no SQLite
at all; `skeleton` runs on SQLite. (PLAN §11 is the design; the M0 spikes S0.4 and S0.11 measured it.)

## When memory is genuinely fine

Don't add a database to look serious. The memory family is the *correct* choice when:

- the data is a fixed seed or a demo fixture, or is rebuilt from an authoritative source on boot;
- it fits comfortably in RAM and the working set is small;
- one process owns it, and losing it on restart is acceptable (or it's reseeded);
- you want zero operational surface.

The honesty rule (PHILOSOPHY → "the 90%") is to *call it ephemeral*, not to pretend it's durable.

## SQLite: the default for anything that must last

When you need persistence, the answer that keeps the philosophy intact is **SQLite**: the
amalgamation, pinned by SHA-256, compiled by `prepare` with the starter's flags (no double-quoted
strings, foreign keys on, multi-thread mode, no global memory statistics, FTS5) and linked into the
binary. No server, one file, `DB_PATH` names it; `:memory:` gives a fresh, seeded store per process.

**How a request uses it (store v3).** Each event loop reads through its own read-only connection,
with a statement cache, so reads on different loops run in parallel. Writes are `store.Op`s queued to
one **writer task**, which commits whatever is queued, up to 100, in one transaction, then hands each
op's `done` back to the loop that queued it; the handler answers through a deferred response once its
batch is durable. WAL mode, `synchronous=NORMAL` (a process crash loses nothing; a power loss can lose
the last commits). `:memory:` is served from an unsynced temporary file (`MEMMODE=ephemeral`, on
`/dev/shm` on Linux), so it gets the same concurrency.

**Migrations** are SQL files per store, `app/stores/sqlite/<f>/migrations/NNNN_<name>.sql`, listed
in its `MIGRATIONS` and run by `store_sqlite.migrate("<f>", …)` in the profile's `main.odin`, in one
transaction each. Each is recorded with its hash: an edited migration that has shipped stops the boot
with a message, so add the next one instead. A database written by the 1.x skeleton (709bc94 or
v1.1.1) is adopted without re-running anything; one written by another app is refused.

**Seeding** happens only in a store nobody owns yet: `:memory:`, or `SEED=1` on an empty file.

## Backup and restore (SQLite)

The binary backs itself up: `DB_PATH=<live db> <bin> --backup <new file>` writes a consistent,
compacted snapshot with `VACUUM INTO` and exits. It opens its own connection, so it runs beside the
live server, and it refuses to overwrite an existing file. `/healthz` stays green throughout.

**Back up** (from wherever the database lives; use a dated name, so each run makes a new file):

```sh
# Fly (the Dockerfile puts the binary at /app/bin; the volume at /data):
fly ssh console -C "/app/bin --backup /data/backup-$(date +%F).db"   # DB_PATH is already set
fly ssh sftp get /data/backup-$(date +%F).db                                     # take it off the volume
# Docker host:
docker exec <container> /app/bin --backup /data/backup-$(date +%F).db
docker cp <container>:/data/backup-$(date +%F).db .
```

Run it on a schedule (a cron job or systemd timer on the host; on Fly, a scheduled GitHub Action or
machine running the same `fly ssh console` line), keep several, and copy them **off the machine**: a
backup on the same volume dies with it. A Fly volume lives on one host, so its snapshots are a
second line, not the first.

**Restore**:

1. Stop the app (`fly scale count 0`, or `docker compose stop`).
2. Replace `data.db` with the backup, and **delete `data.db-wal` and `data.db-shm`**: a stale WAL
   would be replayed onto the restored file.
3. Start the app. The boot log names the migrations it applied (none, if the backup is current), and
   a backup from an older release is migrated forward like any database; one written by a different
   app is refused with a message rather than opened.
4. Check `/healthz` and a page you know the data for.

Rehearse it once before you need it: `e2e/tests/platform/backup.spec.ts` does exactly this.

**Houston's own** (M5's `store.backup` job): nightly into `BACKUP_DIR`, the newest 7 kept. In
`deploy/compose.yaml` that is `/backups`, a mount of its own outside the database's volume: a volume
of its own by default, or the host directory `FULL_BACKUPS` names in the stack's `.env` (one line;
the backup disk's directory, chowned to `10001:10001` once), from where a nightly pull takes them off
the machine.

**TOTP secrets at rest** (M4-12): with `ACCOUNTS_TOTP_KEY_FILE` set, each member's TOTP secret is
stored sealed (XChaCha20-Poly1305, bound to the row), so a backup or a stolen database file gives no
one a second factor. The key is 32 bytes in a file, raw or as 64 hex digits:

```sh
head -c 32 /dev/urandom > totp-key && chown 10001:10001 totp-key && chmod 400 totp-key
```

In the stack, `FULL_TOTP_KEY=./totp-key` in `.env` mounts it (beside compose.yaml, as admin-hash).
The first boot with the key seals every plaintext secret, zeroes the old bytes and empties the WAL;
backups taken before it still hold them in plaintext. Keep the key apart from the backups: a
database whose secrets are sealed refuses to boot without it, and with it lost every member's
two-step sign-in must be turned off by an admin and enrolled again.

**One machine, one database.** With `DB_PATH` on a volume, `fly scale count 2` gives two machines
two separate databases that drift apart. Persistent SQLite here means one machine; past that is the
Postgres row of the table below.

## Summary

| | memory | SQLite | Postgres (scale) |
|---|---|---|---|
| persistence | none | one file | networked server |
| ops surface | none | a volume | a database to run |
| concurrency | a lock per store | a reader per loop, one batching writer | full MVCC |
| in-process | yes | yes | no (network hop) |
| fits the philosophy | for ephemeral data | **yes** | when justified |

The store seam means you can sit at any row of that table and move right exactly when a real
constraint — not a vibe — makes you: a new family is a package per feature behind the same contract.
