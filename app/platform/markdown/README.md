# platform/markdown

Markdown, a safe subset: domains render at write time and store the HTML. Everything is escaped through
`platform/escape`, raw HTML shows as text, links go only to http(s), mailto or this site, images only from the
prefix the caller names. A pure zone (D15 rule 7): no lock, no I/O, no SQLite. Layer L2 (PLAN §5.1).

Audited: bf831da 2026-10-26 docs/audit/M1.md; 88f9222 2026-11-05 docs/audit/M7.md
