# platform/web

The request path's L3 package: the prefix router (one map per host), `Req_Ctx`, the `respond_*` helpers, body caps,
the trusted-proxy client address, deferred responses, the embedded assets, and the platform's two route tables:
`web.ROUTES` for a site's main host and `web.PUBLIC_ROUTES` for every host (PLAN §5.2, §8.4). It is the only
package that imports odin-http; it re-exports `web.Request` and `web.Response`, and F-1's streams for
`platform/stream` (`stream.odin`).

## Prefixes

The platform's rows, mounted as `"platform"` by every profile (D9, PLAN §6.3):

| Prefix | Why |
|---|---|
| `/healthz` | the health check Fly and the CI smoke test compare verbatim |
| `/csp-report` | browsers' CSP violation reports, from a profile on `Header_Set.Reporting` (`web.REPORT_ROUTES`; PLAN §12.2) |
| `/events` | the page's one SSE stream: `hub.ROUTES`, mounted as `"platform"` by a profile with topics (PLAN §9.1) |
| `/livez` | liveness: every loop ticked in the last 5 s |
| `/readyz` | readiness: every critical module up, not draining |
| `/metrics` | Prometheus text, to an admin or the `METRICS_TOKEN_FILE` bearer |
| `/sitemap.xml` | crawlers look for it at the root |
| `/BingSiteAuth.xml` | Bing's ownership proof, at the path Bing fetches |
| `/([%x]+)%.txt` | IndexNow's key file: its path is the key |
| `/static` | the embedded, fingerprinted assets |
| `/robots.txt` | crawlers look for it at the root |
| `/favicon.ico` | crawlers look for it at the root |
| `/licenses` | the notices of what the binary contains |
| `/__test` | the crash drills and `/__test/shutdown`, in a `-define:TEST_ROUTES=true` build only (PLAN §19.1.10); a release build answers 404 |

Audited: cf7f42b 2026-10-31 docs/audit/M5.md (its M5 diff); d136601 2026-10-30 docs/audit/M4.md (its M4 diff); 5c5ebf2 2026-10-27 docs/audit/M2.md; 4f81819 2026-11-05 docs/audit/M8.md (`scan.odin` and its M8 diff)
