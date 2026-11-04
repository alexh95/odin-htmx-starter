#+private
package http

import "base:intrinsics"

import "core:bufio"
import "core:nbio"
import "core:net"
import "core:time"

Scan_Callback :: #type proc(user_data: rawptr, token: string, err: bufio.Scanner_Error)
Split_Proc    :: #type proc(split_data: rawptr, data: []byte, at_eof: bool) -> (advance: int, token: []byte, err: bufio.Scanner_Error, final_token: bool)

scan_lines :: proc(split_data: rawptr, data: []byte, at_eof: bool) -> (advance: int, token: []byte, err: bufio.Scanner_Error, final_token: bool) {
	return bufio.scan_lines(data, at_eof)
}

scan_num_bytes :: proc(split_data: rawptr, data: []byte, at_eof: bool) -> (advance: int, token: []byte, err: bufio.Scanner_Error, final_token: bool) {
	assert(split_data != nil)
	n := int(uintptr(split_data))
	assert(n >= 0)

	if at_eof && len(data) < n {
		return
	}

	if len(data) < n {
		return
	}

	return n, data[:n], nil, false
}

// A callback based scanner over the connection based on nbio.
Scanner :: struct /* #no_copy */ {
	connection:                   ^Connection,
	split:                        Split_Proc,
	split_data:                   rawptr,
	buf:                          [dynamic]byte,
	max_token_size:               int,
	start:                        int,
	end:                          int,
	token:                        []byte,
	_err:                         bufio.Scanner_Error,
	consecutive_empty_reads:      int,
	max_consecutive_empty_reads:  int,
	successive_empty_token_count: int,
	done:                         bool,
	could_be_too_short:           bool,
	user_data:                    rawptr,
	callback:                     Scan_Callback,

	// F-7: the read in flight (so shutdown and a crash can cancel it), what the connection is
	// waiting for, and when that wait ends (zero: never).
	recv_op:                      ^nbio.Operation,
	phase:                        Scan_Phase,
	deadline:                     time.Time,

	// F-16: the scan a callback asked for, run by the outermost scanner_scan once the callback
	// returns (`dispatching`: such a call is on the stack).
	dispatching:                  bool,
	next_user_data:               rawptr,
	next_callback:                Scan_Callback,
}

// F-7: which of the server's timeouts applies to the scanner's reads.
Scan_Phase :: enum u8 {
	Idle,    // waiting for a request: Server_Opts.idle_timeout
	Headers, // the request line and headers: header_timeout, from the request's first byte
	Body,    // the body: body_timeout, from the end of the headers
}

scanner_set_phase :: proc(s: ^Scanner, phase: Scan_Phase) {
	s.phase = phase
	timeout: time.Duration
	opts := &s.connection.server.opts
	switch phase {
	case .Idle:    timeout = opts.idle_timeout
	case .Headers: timeout = opts.header_timeout
	case .Body:    timeout = opts.body_timeout
	}
	s.deadline = time.time_add(nbio.now(), timeout) if timeout > 0 else {}
}

// Cancels the read in flight, if any; its callback won't run.
scanner_cancel :: proc(s: ^Scanner) {
	if s.recv_op != nil {
		nbio.remove(s.recv_op)
		s.recv_op = nil
	}
}

INIT_BUF_SIZE :: 1024
SHRINK_BUF_SIZE :: 64 * 1024
DEFAULT_MAX_CONSECUTIVE_EMPTY_READS :: 128

scanner_init :: proc(s: ^Scanner, c: ^Connection, buf_allocator := context.allocator) {
	s.connection     = c
	s.split          = scan_lines
	s.max_token_size = bufio.DEFAULT_MAX_SCAN_TOKEN_SIZE
	s.buf.allocator  = buf_allocator
}

scanner_destroy :: proc(s: ^Scanner) {
	delete(s.buf)
}

scanner_reset :: proc(s: ^Scanner) {
	remove_range(&s.buf, 0, s.start)
	s.end   -= s.start
	s.start  = 0

	// F-25: a large body's buffer goes back with its request, not with its connection.
	if len(s.buf) > SHRINK_BUF_SIZE && s.end <= SHRINK_BUF_SIZE {
		resize(&s.buf, SHRINK_BUF_SIZE)
		shrink(&s.buf)
	}

	s.split                        = scan_lines
	s.split_data                   = nil
	s.max_token_size               = bufio.DEFAULT_MAX_SCAN_TOKEN_SIZE
	s.token                        = nil
	s._err                         = nil
	s.consecutive_empty_reads      = 0
	s.max_consecutive_empty_reads  = DEFAULT_MAX_CONSECUTIVE_EMPTY_READS
	s.successive_empty_token_count = 0
	s.done                         = false
	s.could_be_too_short           = false
	s.user_data                    = nil
	s.callback                     = nil
}

// F-16: a callback that scans again (the chunked decoder, the request and header lines) only
// queues that scan, and this loop runs it once the callback has returned. Upstream called it
// from inside the callback, one level deeper per token already in the buffer: a body of one-byte
// chunks went ~100k frames deep in one read and overflowed a loop's stack (M1-17), a pure crash
// that 101 times a minute exits the process.
scanner_scan :: proc(
	s: ^Scanner,
	user_data: rawptr,
	callback: proc(user_data: rawptr, token: string, err: bufio.Scanner_Error),
) {
	if s.dispatching {
		assert(s.next_callback == nil, "a scan callback asked for two scans")
		s.next_user_data, s.next_callback = user_data, callback
		return
	}
	s.dispatching = true
	user_data, callback := user_data, callback
	for {
		scan_once(s, user_data, callback)
		if s.next_callback == nil { break }
		user_data, callback = s.next_user_data, s.next_callback
		s.next_user_data, s.next_callback = nil, nil
	}
	s.dispatching = false
}

// A trap in a callback leaves the trampoline mid-run; the crash path clears it.
scanner_clear_dispatch :: proc(s: ^Scanner) {
	s.dispatching = false
	s.next_user_data, s.next_callback = nil, nil
}

@(private="file")
scan_once :: proc(s: ^Scanner, user_data: rawptr, callback: Scan_Callback) {
	set_err :: proc(s: ^Scanner, err: bufio.Scanner_Error) {
		switch s._err {
		case nil, .EOF:
			s._err = err
		}
	}

	if s.done {
		callback(user_data, "", .EOF)
		return
	}

	// Check if a token is possible with what is available
	// Allow the split procedure to recover if it fails
	if s.start < s.end || s._err != nil {
		advance, token, err, final_token := s.split(s.split_data, s.buf[s.start:s.end], s._err != nil)
		if final_token {
			s.token = token
			s.done = true
			callback(user_data, "", .EOF)
			return
		}
		if err != nil {
			set_err(s, err)
			callback(user_data, "", s._err)
			return
		}

		// Do advance
		if advance < 0 {
			set_err(s, .Negative_Advance)
			callback(user_data, "", s._err)
			return
		}
		if advance > s.end - s.start {
			set_err(s, .Advanced_Too_Far)
			callback(user_data, "", s._err)
			return
		}
		s.start += advance

		s.token = token
		if s.token != nil {
			if s._err == nil || advance > 0 {
				s.successive_empty_token_count = 0
			} else {
				s.successive_empty_token_count += 1

				if s.successive_empty_token_count > s.max_consecutive_empty_reads {
					set_err(s, .No_Progress)
					callback(user_data, "", s._err)
					return
				}
			}

			s.consecutive_empty_reads = 0
			s.callback = nil
			s.user_data = nil
			callback(user_data, string(token), s._err)
			return
		}
	}

	// If an error is hit, no token can be created
	if s._err != nil {
		s.start = 0
		s.end = 0
		callback(user_data, "", s._err)
		return
	}

	could_be_too_short := false

	// Resize the buffer if full
	if s.end == len(s.buf) {
		if s.max_token_size <= 0 {
			s.max_token_size = bufio.DEFAULT_MAX_SCAN_TOKEN_SIZE
		}

		if s.end - s.start >= s.max_token_size {
			set_err(s, .Too_Long)
			callback(user_data, "", s._err)
			return
		}

		// TODO: write over the part of the buffer already used

		// overflow check
		new_size := INIT_BUF_SIZE
		if len(s.buf) > 0 {
			overflowed: bool
			if new_size, overflowed = intrinsics.overflow_mul(len(s.buf), 2); overflowed {
				set_err(s, .Too_Long)
				callback(user_data, "", s._err)
				return
			}
		}

		old_size := len(s.buf)
		resize(&s.buf, new_size)

		could_be_too_short = old_size >= len(s.buf)

	}

	// Read data into the buffer
	s.consecutive_empty_reads += 1
	s.user_data = user_data
	s.callback = callback
	s.could_be_too_short = could_be_too_short

	assert_has_td()
	// F-7: the phase's deadline is enforced by the thread's 1 s sweep (_sweep_timeouts), not by a
	// timeout on each read: on io_uring a per-read timeout is a linked operation, an extra submission
	// and completion per request, and cost 2-4 % on the lightest routes (S0.2).
	s.recv_op = nbio.recv_poly(s.connection.socket, {s.buf[s.end:len(s.buf)]}, s, scanner_on_read)
}

// F-7: ends the read in flight as if the peer had left (EOF): the scanner's callback runs as it would
// for a closed connection, so a handler reading a body gets an error, and a request line or headers
// that never finish close the connection.
scanner_timed_out :: proc(s: ^Scanner) {
	if s.recv_op == nil { return }
	scanner_cancel(s)
	// A body cut off part way leaves its rest unread on the wire, so the connection must close after
	// the answer: `_body_length` marks the body read before scanning it, so the response path alone
	// would keep it alive and read the rest as the next request.
	if s.phase == .Body { connection_set_state(s.connection, .Will_Close) }
	context.temp_allocator = conn_arena_allocator(&s.connection.temp_allocator)
	s._err = .EOF
	scanner_scan(s, s.user_data, s.callback)
}

scanner_on_read :: proc(op: ^nbio.Operation, s: ^Scanner) {
	s.recv_op = nil
	c := s.connection
	if !_invoke(c.server, proc(a, b: rawptr) { _scanner_on_read((^nbio.Operation)(a), (^Scanner)(b)) }, op, s) {
		connection_crashed(c)
	}
}

_scanner_on_read :: proc(op: ^nbio.Operation, s: ^Scanner) {
	context.temp_allocator = conn_arena_allocator(&s.connection.temp_allocator)

	defer scanner_scan(s, s.user_data, s.callback)

	if op.recv.err != nil {
		#partial switch op.recv.err.(net.TCP_Recv_Error) {
		case .Connection_Closed, .Invalid_Argument:
			// EBADF (bad file descriptor) happens when OS closes socket.
			s._err = .EOF
			return
		case .Timeout:
			// F-7: a peer that took too long reads as one that left.
			s._err = .EOF
			return
		}

		s._err = .Unknown
		return
	}

	// When n == 0, connection is closed or buffer is of length 0.
	if op.recv.received == 0 {
		s._err = .EOF
		return
	}

	if op.recv.received < 0 || len(s.buf) - s.end < op.recv.received {
		s._err = .Bad_Read_Count
		return
	}

	// F-7: the first byte of a request starts its header deadline.
	if s.phase == .Idle {
		scanner_set_phase(s, .Headers)
	}

	s.end += op.recv.received
	if op.recv.received > 0 {
		s.successive_empty_token_count = 0
		return
	}
}
