# platform/jpeg

`core:image/jpeg` at Odin dev-2026-10 (BSD-3-Clause, as Odin's core), with what `features/uploads` needs of a decoder that
meets hostile files. The audit found them (`docs/audit/M6.md`, M6-01, M6-03), and `uploads_test.odin` holds each. Each
change is marked `PATCHED` in `jpeg.odin`; to report upstream (`TODO.md`), and to drop this copy for core's once fixed:

- APP0 is skipped by its length: JFXX's thumbnail sizes could walk the decoder somewhere a header read doesn't go.
- A Huffman table's counts are summed in an `int` and judged at every step: in a `u8` they wrapped past 256.
- One SOF. Each component once, Y among them: with no Y the scan's loops never step.
- No component samples finer than Y, which is what `blocks` is sized by; the scan needs a frame.
- The scan is bounds checked: it was `#no_bounds_check`, and the factors above made it a write past `blocks`.
