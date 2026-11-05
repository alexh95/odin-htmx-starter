package wiki

// ---- a line diff ---------------------------------------------------------------------------------
//
// Longest common subsequence over the lines between the common head and tail, which is what's left of
// a real edit. The table is n×m, so past MAX_DIFF_LINES on a side the middle is shown as replaced
// whole: 64 KiB can be 32k lines, and a cheap diff beats a clever one. Off the loop (§6).

import "core:strings"

MAX_DIFF_LINES :: 1000

Diff_Kind :: enum {
	Same,
	Drop,
	Add,
}

Diff_Line :: struct {
	kind: Diff_Kind,
	text: string,
}

// From `a` to `b`, in the temp allocator.
diff :: proc(a, b: string) -> []Diff_Line {
	x := strings.split_lines(a, context.temp_allocator)
	y := strings.split_lines(b, context.temp_allocator)
	out := make([dynamic]Diff_Line, 0, len(x) + len(y), context.temp_allocator)

	head := 0
	for head < len(x) && head < len(y) && x[head] == y[head] { head += 1 }
	tail := 0
	for tail < len(x) - head && tail < len(y) - head && x[len(x) - 1 - tail] == y[len(y) - 1 - tail] { tail += 1 }
	for line in x[:head] { append(&out, Diff_Line{.Same, line}) }

	p, q := x[head:len(x) - tail], y[head:len(y) - tail]
	n, m := len(p), len(q)
	if n > MAX_DIFF_LINES || m > MAX_DIFF_LINES {
		for line in p { append(&out, Diff_Line{.Drop, line}) }
		for line in q { append(&out, Diff_Line{.Add, line}) }
	} else {
		w := m + 1
		lcs := make([]u16, (n + 1) * w, context.temp_allocator)
		for i := n - 1; i >= 0; i -= 1 {
			for j := m - 1; j >= 0; j -= 1 {
				if p[i] == q[j] {
					lcs[i * w + j] = lcs[(i + 1) * w + j + 1] + 1
				} else {
					lcs[i * w + j] = max(lcs[(i + 1) * w + j], lcs[i * w + j + 1])
				}
			}
		}
		i, j := 0, 0
		for i < n || j < m {
			switch {
			case i < n && j < m && p[i] == q[j]:
				append(&out, Diff_Line{.Same, p[i]})
				i += 1
				j += 1
			case j == m || (i < n && lcs[(i + 1) * w + j] >= lcs[i * w + j + 1]):
				append(&out, Diff_Line{.Drop, p[i]})
				i += 1
			case:
				append(&out, Diff_Line{.Add, q[j]})
				j += 1
			}
		}
	}
	for line in x[len(x) - tail:] { append(&out, Diff_Line{.Same, line}) }
	return out[:]
}
