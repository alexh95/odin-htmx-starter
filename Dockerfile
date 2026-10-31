# syntax=docker/dockerfile:1
#
# Three stages: build one profile's self-contained binary (PROFILE, skeleton by
# default), list the runtime base's Debian packages, then ship the binary alone as
# /app/bin on distroless (PLAN §20.2). Every static asset is embedded in it, so the
# runtime image carries no toolchain, no shell and no asset files.
#
# Running it needs Linux io_uring, which Docker's default seccomp profile blocks
# (since 25.0): start it with docker/seccomp-io-uring.json, as compose.yaml does,
# or the server aborts at startup. containerd's default (since 2.0) blocks it too,
# so on Kubernetes RuntimeDefault isn't enough: load the same profile (Localhost).

# Debian 13 (trixie) on both sides, so the glibc the binary links against is the
# glibc it runs on. Pinned by digest; a bump moves both lines together.
ARG BUILD_BASE=debian:trixie-slim@sha256:89c1ea91e897f0fe0a3731595330bc45b8bdef4047464a07116f891a94054b31
ARG RUN_BASE=gcr.io/distroless/base-nossl-debian13@sha256:ca1c7e6a875e59345ae6ff182a1e0930f0ca1ffef23a9b830f8823ab348ad5dd

# ---- build: fetch the pinned Odin for this arch, build the profile -------
FROM ${BUILD_BASE} AS build

# Pin the toolchain so image builds are reproducible. Bump deliberately: each
# SHA-256 is the release's published digest of that arch's tarball, the same ones
# ci.yml and .github/actions/setup-odin pin (.github/scripts/check-pins.sh fails CI
# if they drift apart). The release workflow builds each arch on its own runner,
# so TARGETARCH is the runner's. It is declared bare: BuildKit fills it, and a default
# here won over BuildKit's value (an arm64 build fetched amd64's Odin); a builder that
# sets none gets amd64 below.
ARG ODIN_VERSION=dev-2026-10
ARG ODIN_SHA256=c3c8b095621fd0c75f7f73e3a0829f1b4d45324225f20ba11ed8dc4da310a8ab
ARG ODIN_SHA256_ARM64=99c43e9670a285901d6cfee5f56197b74c7d6f7c537b35ecba0c1b44ac2e4df8
ARG TARGETARCH

# clang is the linker driver and also compiles the SQLite amalgamation (prepare.sh);
# unzip extracts it and binutils (ar) archives it into sqlite3.a; brotli compresses
# the bundled assets (tools/bundle). The Odin release statically bundles LLVM.
RUN apt-get update \
 && apt-get install -y --no-install-recommends clang binutils unzip brotli git curl ca-certificates tar \
 && rm -rf /var/lib/apt/lists/*

RUN arch="${TARGETARCH:-amd64}" \
 && case "${arch}" in \
      amd64) sha="${ODIN_SHA256}" ;; \
      arm64) sha="${ODIN_SHA256_ARM64}" ;; \
      *) echo "no Odin asset for ${arch}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL "https://github.com/odin-lang/Odin/releases/download/${ODIN_VERSION}/odin-linux-${arch}-${ODIN_VERSION}.tar.gz" -o /tmp/odin.tar.gz \
 && echo "${sha}  /tmp/odin.tar.gz" | sha256sum -c - \
 && mkdir -p /opt/odin \
 && tar -xzf /tmp/odin.tar.gz -C /opt/odin --strip-components=1 \
 && rm /tmp/odin.tar.gz
ENV PATH="/opt/odin:${PATH}"

# app/, build.sh (the one place a profile's flags live), tools/bundle and
# docs/catalog.json are what the build needs. odin-http is vendored in app/vendor/odin-http (already in the
# build context), so prepare only fetches htmx and SQLite (both pinned by
# SHA-256), compiles SQLite and bundles each profile's assets; THIRD_PARTY_NOTICES
# is embedded for /licenses.
COPY app /src/app
COPY tools/bundle /src/tools/bundle
COPY build.sh THIRD_PARTY_NOTICES /src/
# The lab's landing page embeds the generator's catalog.
COPY docs/catalog.json /src/docs/catalog.json
WORKDIR /src
# Invoke via `sh` (not ./) so the build doesn't depend on the exec bit, which a
# Windows-origin build context (e.g. local `flyctl deploy`) wouldn't carry.
RUN sh app/prepare.sh
# VERSION names the build in the x-version header and /healthz; the docker and
# release jobs pass the commit or the tag. Declared after prepare so a new commit doesn't re-run it.
ARG PROFILE=skeleton
ARG VERSION=dev
# /out/data and /out/backups are the empty /data and /backups the runtime stage copies (and
# chowns to the app's UID): distroless has no shell to create them there.
RUN VERSION="${VERSION}" sh build.sh "${PROFILE}" -o:speed \
 && mkdir -p /out/data /out/backups && cp "app/bin/${PROFILE}" /out/bin

# ---- sources: what the runtime base is made of ---------------------------
# Distroless records each package it carries in /var/lib/dpkg/status.d; SOURCES.md
# names their Debian source packages and versions, for the (L)GPL source duty of a
# published image (PLAN §20.2).
FROM ${RUN_BASE} AS runbase
FROM ${BUILD_BASE} AS sources
ARG RUN_BASE
COPY --from=runbase /var/lib/dpkg/status.d /status.d
RUN { echo "# Sources of the runtime base's Debian packages"; echo; \
      echo "From \`${RUN_BASE}\`. Each is at https://snapshot.debian.org/package/<source>/<version>/."; echo; \
      echo "| Package | Version | Source |"; echo "|---|---|---|"; \
      for f in /status.d/*; do \
        case "$f" in *.md5sums) continue ;; esac; \
        awk -F': ' '/^Package:/ {p=$2} /^Version:/ {v=$2} /^Source:/ {s=$2} \
          END {if (s == "") s = p; sub(/ .*/, "", s); print "| " p " | " v " | " s " |"}' "$f"; \
      done | sort; } > /SOURCES.md

# ---- runtime: the binary on distroless -----------------------------------
FROM ${RUN_BASE}

WORKDIR /app
COPY --from=build /out/bin /app/bin
COPY --from=sources /SOURCES.md /app/SOURCES.md
# /data is where DB_PATH points to persist (DB_PATH=/data/data.db) and the one
# directory it can write; a fresh named volume mounted there inherits its owner.
# A volume that already holds root-owned files, or that the platform mounts as
# root (a Fly volume), needs a one-time `chown -R 10001:10001` first.
COPY --from=build --chown=10001:10001 /out/data /data
# /backups is where a deploy's BACKUP_DIR points, a mount of its own outside /data (M4-12): a
# bind mount from the host is the host directory's, which wants `chown 10001:10001` once.
COPY --from=build --chown=10001:10001 /out/backups /backups
# A fixed numeric UID, so a volume can be chowned to it from outside and
# Kubernetes' runAsNonRoot can check it without reading /etc/passwd.
USER 10001:10001

# Bind 0.0.0.0 so the platform can route in; PORT is the platform's contract.
ENV PORT=8080 BIND_ALL=1
EXPOSE 8080

# The server drains on SIGTERM and SIGINT alike (F-10: in-flight requests finish,
# the store's last batch commits and SQLite checkpoints); a second signal exits at
# once. Fly sends its own kill_signal (SIGINT), which drains the same way.
STOPSIGNAL SIGTERM

# The binary probes its own /livez (distroless has no shell or curl). Fly ignores
# this (fly.toml has its own check); Docker and compose use it.
HEALTHCHECK --interval=10s --timeout=3s --retries=3 --start-period=10s --start-interval=1s \
  CMD ["/app/bin", "--healthcheck"]

ENTRYPOINT ["/app/bin"]
