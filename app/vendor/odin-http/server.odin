package http

import "base:runtime"

import "core:bufio"
import "core:bytes"
import "core:c/libc"
import "core:container/queue"
import "core:fmt"
import "core:log"
import "core:mem"
@(require) import "core:mem/virtual" // used only outside -sanitize:thread (F-22)
import "core:nbio"
import "core:net"
import "core:os"
import "core:slice"
import "core:sync"
import "core:thread"
import "core:time"

Server_Opts :: struct {
	// Whether the server should accept every request that sends a "Expect: 100-continue" header automatically.
	// Defaults to true.
	auto_expect_continue:    bool,
	// When this is true, any HEAD request is automatically redirected to the handler as a GET request.
	// Then, when the response is sent, the body is removed from the response.
	// Defaults to true.
	redirect_head_to_get:    bool,
	// Limit the maximum number of bytes to read for the request line (first line of request containing the URI).
	// The HTTP spec does not specify any limits but in practice it is safer.
	// RFC 7230 3.1.1 says:
	// Various ad hoc limitations on request-line length are found in
	// practice.  It is RECOMMENDED that all HTTP senders and recipients
	// support, at a minimum, request-line lengths of 8000 octets.
	// defaults to 8000.
	limit_request_line:      int,
	// Limit the length of the headers.
	// The HTTP spec does not specify any limits but in practice it is safer.
	// defaults to 8000.
	limit_headers:           int,
	// The thread count to use, defaults to your core count - 1.
	thread_count:            int,

	// F-4: called on each server thread once its event loop runs (index 0 is the thread that
	// called `serve`), and again when that thread starts shutting down. Use it to register
	// per-loop state and timers, and to cancel those timers, so shutdown doesn't wait on them.
	on_thread_init:          proc(s: ^Server, thread_index: int),
	on_thread_shutdown:      proc(s: ^Server, thread_index: int),
	// M1-05: on each thread at the end of its shutdown, just before it releases its event loop
	// (nbio zeroes it): the application stops other threads posting to it here.
	on_thread_release:       proc(s: ^Server, thread_index: int),

	// F-5: when set, every completion callback the server owns (accept, the request scanner's
	// reads, the handler dispatch inside them, response sends, stream operations and the server's
	// timers) runs through this. A crash guard installed here returns false when the callback did
	// not return normally; the server then answers 500 if nothing was sent yet and closes that
	// connection (a stream gets its `on_crash`). nil calls the callbacks directly.
	invoke:                  Invoke_Proc,

	// F-7: how long a peer may take. 0 means no limit (upstream's behaviour).
	// From a request's first byte to the end of its headers. Default 10 s.
	header_timeout:          time.Duration,
	// Waiting for a new connection's first request, or a kept-alive connection's next one. Default 75 s.
	idle_timeout:            time.Duration,
	// Reading a request body, by the handler or by the server draining it. Default 30 s.
	body_timeout:            time.Duration,
	// One send waiting on a peer that doesn't read: a response's, or a stream's queued bytes. Past
	// it the connection is cut, so a client that never reads can't hold its descriptor and a copy of
	// its response forever (M1-02). Default 30 s.
	send_timeout:            time.Duration,

	// F-8: connections past this get a 503 and are closed. 0 derives it: the open-file soft limit
	// minus 64 where there is one (Linux, macOS), else no limit. -1 means no limit.
	max_connections:         int,

	// F-9: at shutdown, how long requests that are still being handled get before their
	// connections are cut. Idle connections close at once and streams get `STREAM_SHUTDOWN_GRACE`.
	// Default 5 s.
	drain_deadline:          time.Duration,

	// F-12: how long `listen` retries a bind that fails with Address_In_Use (a restart right after
	// a kill can find the old socket still held). Default 3 s; 0 tries once.
	bind_retry:              time.Duration,

	// // The initial size of the temp_allocator for each connection, defaults to 256KiB and doubles
	// // each time it needs to grow.
	// // NOTE: this value is assigned globally, running multiple servers with a different value will
	// // not work.
	// initial_temp_block_cap:  uint,
	// // The amount of free blocks each thread is allowed to hold on to before deallocating excess.
	// // Defaults to 64.
	// max_free_blocks_queued:  uint,
}

Default_Server_Opts := Server_Opts {
	auto_expect_continue    = true,
	redirect_head_to_get    = true,
	limit_request_line      = 8000,
	limit_headers           = 8000,
	header_timeout          = 10 * time.Second,
	idle_timeout            = 75 * time.Second,
	body_timeout            = 30 * time.Second,
	send_timeout            = 30 * time.Second,
	drain_deadline          = 5 * time.Second,
	bind_retry              = 3 * time.Second,
	// initial_temp_block_cap  = 256 * mem.Kilobyte,
	// max_free_blocks_queued  = 64,
}

// F-5: runs `fn(a, b)`. Returns false when `fn` did not return normally, which only a crash guard
// can make happen (a longjmp back into this frame).
Invoke_Proc :: #type proc(fn: proc(a, b: rawptr), a, b: rawptr) -> (returned: bool)

Server_State :: enum {
	Uninitialized,
	Idle,
	Listening,
	Serving,
	Running,
	Closing,
	Cleaning,
	Closed,
}

Server :: struct {
	opts:           Server_Opts,
	tcp_sock:       net.TCP_Socket,
	conn_allocator: mem.Allocator,
	handler:        Handler,

	threads:        []Server_Thread,
	// Once the server starts closing/shutdown this is set to true, all threads will check it
	// and start their thread local shutdown procedure.
	//
	// NOTE: This is only ever set from false to true, and checked repeatedly,
	// so it doesn't have to be atomic, this is purely to keep the thread sanitizer happy.
	closing:        Atomic(bool),
	// Threads will decrement the wait group when they have fully closed/shutdown.
	// The main thread waits on this to clean up global data and return.
	threads_closed: sync.Wait_Group,

	// F-8: open connections across all threads, and the cap derived from the options.
	conn_count:     int,
	max_conns:      int,

	// F-21: server_shutdown wakes every loop from another thread, maybe a signal handler, so not under
	// a lock: `shutdowns` (atomic) counts the calls in progress, and a loop about to be released
	// (Server_Thread.released) or serve about to free the threads (`freeing`, atomic) waits them out.
	// Upstream woke loops that had already been released, and read `threads` while serve freed it.
	shutdowns:      int,
	freeing:        bool,
}

Server_Thread :: struct {
	thread:     ^thread.Thread,
	event_loop: ^nbio.Event_Loop,
	conns:      map[net.TCP_Socket]^Connection,
	state:      Server_State,
	accept:     ^nbio.Operation,
	index:      int,

	// F-11: the date header, per thread. Upstream shared one buffer that a timer rewrote every
	// second while other threads read it (torn reads put NUL bytes in about 2 in 800k headers).
	date:       Server_Date,

	// F-7: the thread's 1 s timeout sweep.
	sweep:      ^nbio.Operation,

	// F-13: the last request generation handed out on this thread, and the refs to deferred
	// responses not yet resumed (shutdown waits for them).
	next_gen:   u64,
	deferred:   int,

	// F-21: set (atomic) just before the loop is released; `event_loop` is stored atomically too.
	released:   bool,

	// free_temp_blocks:       map[int]queue.Queue(^Block),
	// free_temp_blocks_count: int,
}

@(private, disabled = ODIN_DISABLE_ASSERT)
assert_has_td :: #force_inline proc(loc := #caller_location) {
	assert(td.state != .Uninitialized, "The thread you are calling from is not a server/handler thread", loc)
}

@(thread_local)
td: ^Server_Thread

Default_Endpoint := net.Endpoint {
	address = net.IP4_Any,
	port    = 8080,
}

listen :: proc(
	s: ^Server,
	endpoint: net.Endpoint = Default_Endpoint,
	opts: Server_Opts = Default_Server_Opts,
) -> (err: net.Network_Error) {
	s.opts = opts
	s.conn_allocator = context.allocator
	// initial_block_cap = int(s.opts.initial_temp_block_cap)
	// max_free_blocks_queued = int(s.opts.max_free_blocks_queued)

	if acquire_err := nbio.acquire_thread_event_loop(); acquire_err != nil {
		_log_event_loop_error(acquire_err)
		return net.Listen_Error.Unsupported_Socket
	}

	// F-12: a restart right after a kill can find the address still held; retry for a while.
	start := time.tick_now()
	for {
		s.tcp_sock, err = nbio.listen_tcp(endpoint)
		if !_is_address_in_use(err) || time.tick_since(start) >= s.opts.bind_retry { break }
		time.sleep(100 * time.Millisecond)
	}
	if err != nil {
		log.errorf("http: could not listen on %v: %v", net.endpoint_to_string(endpoint, context.temp_allocator), err)
		nbio.run()
		nbio.release_thread_event_loop()
		server_shutdown(s)
	}
	return
}

@(private)
_is_address_in_use :: proc(err: net.Network_Error) -> bool {
	#partial switch e in err {
	case net.Bind_Error:   return e == .Address_In_Use
	case net.Listen_Error: return e == .Address_In_Use
	}
	return false
}

@(private)
_log_event_loop_error :: proc(err: nbio.General_Error) {
	when ODIN_OS == .Linux {
		log.errorf(
			"http: the event loop could not start (%v). core:nbio needs io_uring on Linux; a container's " +
			"seccomp profile can block io_uring_setup (Docker's default one does): run it under a profile " +
			"that allows io_uring.", err,
		)
	} else {
		log.errorf("http: the event loop could not start: %v", err)
	}
}

serve :: proc(s: ^Server, h: Handler) -> (err: net.Network_Error) {
	if atomic_load(&s.closing) { return }
	s.handler = h

	if s.opts.thread_count == 0 {
		s.opts.thread_count = os.get_processor_core_count()
	}

	s.max_conns = s.opts.max_connections
	if s.max_conns == 0 { s.max_conns = _default_max_connections() }

	thread_count := max(1, s.opts.thread_count)
	sync.wait_group_add(&s.threads_closed, thread_count)
	s.threads = make([]Server_Thread, thread_count, s.conn_allocator)
	for &td, i in s.threads {
		td.index = i
	}
	for &td in s.threads[1:] {
		td.thread = thread.create_and_start_with_poly_data2(s, &td, _server_thread_init, context)
	}

	_server_thread_init(s, &s.threads[0])

	sync.wait(&s.threads_closed)

	log.debug("server threads are done, shutting down")

	net.shutdown(s.tcp_sock, .Both)
	net.close(s.tcp_sock)
	sync.atomic_store(&s.freeing, true)
	for sync.atomic_load(&s.shutdowns) > 0 { sync.cpu_relax() }
	for t in s.threads[1:] { thread.destroy(t.thread) }
	delete(s.threads)

	return nil
}

listen_and_serve :: proc(
	s: ^Server,
	h: Handler,
	endpoint: net.Endpoint = Default_Endpoint,
	opts: Server_Opts = Default_Server_Opts,
) -> (err: net.Network_Error) {
	listen(s, endpoint, opts) or_return
	return serve(s, h)
}

_server_thread_init :: proc(s: ^Server, ttd: ^Server_Thread) {
	td = ttd

	td.conns = make(map[net.TCP_Socket]^Connection)
	// td.free_temp_blocks = make(map[int]queue.Queue(^Block))

	if td != &s.threads[0] {
		err := nbio.acquire_thread_event_loop()
		// TODO: error handling.
		assert(err == nil)
	}

	sync.atomic_store(&td.event_loop, nbio.current_thread_event_loop())

	if s.opts.on_thread_init != nil { s.opts.on_thread_init(s, td.index) }

	log.debug("accepting connections")

	td.accept = nbio.accept_poly(s.tcp_sock, s, on_accept)

	// F-7: one timer per thread checks every connection's deadline once a second.
	if s.opts.header_timeout > 0 || s.opts.idle_timeout > 0 || s.opts.body_timeout > 0 || s.opts.send_timeout > 0 {
		td.sweep = nbio.timeout_poly(SWEEP_INTERVAL, s, _sweep_timeouts)
	}

	log.debug("starting event loop")
	td.state = .Serving
	for {
		if atomic_load(&s.closing) { _server_thread_shutdown(s) }
		if td.state == .Closed { break }
		if td.state == .Cleaning { continue }

		err := _server_tick()
		if err != nil {
			log.errorf("non-blocking io tick error: %v", err)
			break
		}
	}

	log.debug("event loop end")

	if td != &s.threads[0] {
		runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data)
	}
	sync.wait_group_done(&s.threads_closed)
}

// F-23: one turn of a serving loop. core:nbio's Linux tick runs the callbacks queued before it
// began, then waits on the kernel even when they queued more (a next_tick, a 0 ms timeout), so
// that work waited for some unrelated event, on a quiet loop the next 1 s timer. Its Windows and
// posix ticks don't wait while work is queued, and neither does this one. Work another thread
// posted counts: the tick takes it from `l.queue` and runs it, and whatever that queues (the hub's
// drain, from the writer's answer on a socket's post) would wait the same way, with no response
// in flight to wake the loop.
_server_tick :: proc() -> nbio.General_Error {
	l := nbio.current_thread_event_loop()
	busy := queue.len(l.completed) > 0 || sync.atomic_load(&l.queue.count) > 0
	return nbio.tick(0 if busy else nbio.NO_TIMEOUT)
}


// The time between checks and closes of connections in a graceful shutdown.
@(private)
SHUTDOWN_INTERVAL :: time.Millisecond * 100

// F-9: how long a thread waits for operations still pending once its connections are gone.
@(private)
SHUTDOWN_FINAL_WAIT :: time.Millisecond * 500

// Starts a graceful shutdown.
//
// Some error logs will be generated but all active connections are finished
// before closing them and all connections and threads are freed.
//
// 1. Stops 'server_start' from accepting new connections.
// 2. Close and free non-active connections.
// 3. Repeat 2 every SHUTDOWN_INTERVAL until no more connections are open.
// 4. Close the main socket.
// 5. Signal 'server_start' it can return.
server_shutdown :: proc(s: ^Server) {
	sync.atomic_add(&s.shutdowns, 1)
	defer sync.atomic_sub(&s.shutdowns, 1)
	atomic_store(&s.closing, true)
	if sync.atomic_load(&s.freeing) { return }
	for &t in s.threads {
		l := sync.atomic_load(&t.event_loop)
		if l != nil && !sync.atomic_load(&t.released) { nbio.wake_up(l) }
	}
}

_server_thread_shutdown :: proc(s: ^Server, loc := #caller_location) {
	assert_has_td(loc)

	td.state = .Closing
	defer delete(td.conns)

	// F-9: stop accepting at once, so the listen backlog stops feeding this thread.
	if td.accept != nil {
		nbio.remove(td.accept)
		td.accept = nil
	}
	if td.sweep != nil {
		nbio.remove(td.sweep)
		td.sweep = nil
	}

	// F-4: the application cancels its per-loop timers and tells its streams.
	if s.opts.on_thread_shutdown != nil { s.opts.on_thread_shutdown(s, td.index) }

	// F-9: every wait is bounded. Idle connections are closed now (their pending read cancelled),
	// streams end within STREAM_SHUTDOWN_GRACE, and requests still being handled get
	// `drain_deadline`, after which their sockets are shut down and left for the process exit.
	start := time.tick_now()
	for {
		past_deadline := s.opts.drain_deadline > 0 && time.tick_since(start) >= s.opts.drain_deadline
		waiting := 0
		for sock, conn in td.conns {
			#partial switch conn.state {
			case .Active, .Will_Close:
				if conn.state == .Active && conn.scanner.phase != .Body {
					// Still reading the request line or headers (a slowloris looks like this):
					// no handler runs yet, so it closes like an idle connection.
					scanner_cancel(&conn.scanner)
					connection_close(conn)
					waiting += 1
				} else if past_deadline {
					log.infof("shutdown: connection %i still active at the drain deadline, cutting it", sock)
					net.shutdown(conn.socket, .Both)
				} else {
					waiting += 1
				}
			case .Streaming:
				stream_shutdown(conn.stream)
				waiting += 1
			case .New, .Idle, .Pending:
				log.debugf("shutdown: closing connection %i", sock)
				scanner_cancel(&conn.scanner)
				connection_close(conn)
				waiting += 1
			case .Closing:
				// Waits out Conn_Close_Delay so the peer can read what was sent; not past the deadline.
				log.debugf("shutdown: connection %i is closing", sock)
				if !past_deadline { waiting += 1 }
			case .Closed:
				log.warn("closed connection in connections map, maybe a race or logic error")
			}
		}

		// F-13: a reply still owed to this loop keeps it alive until the deadline.
		if !past_deadline { waiting += td.deferred }

		if waiting == 0 { break }

		err := nbio.tick(SHUTDOWN_INTERVAL)
		fmt.assertf(err == nil, "IO tick error during shutdown: %v", err)
	}

	td.state = .Cleaning

	// Whatever is still pending (an application timer nobody cancelled, a send to a peer that stopped
	// reading) gets a short while, not forever.
	final := time.tick_now()
	for nbio.num_waiting() > 0 && time.tick_since(final) < SHUTDOWN_FINAL_WAIT {
		nbio.tick(SHUTDOWN_INTERVAL)
	}
	if s.opts.on_thread_release != nil { s.opts.on_thread_release(s, td.index) }
	sync.atomic_store(&td.released, true)
	for sync.atomic_load(&s.shutdowns) > 0 { sync.cpu_relax() }
	nbio.release_thread_event_loop()

	td.state = .Closed

	log.info("shutdown: done")
}

@(private)
on_interrupt_server: ^Server
@(private)
on_interrupt_context: runtime.Context
@(private)
on_interrupt_seen: Atomic(bool)

// Registers a signal handler to shutdown the server gracefully on SIGINT or SIGTERM (F-10: a
// container runtime stops PID 1 with SIGTERM). A second signal exits at once.
// Can only be called once in the lifetime of the program because of a hacky interaction with libc.
server_shutdown_on_interrupt :: proc(s: ^Server) {
	on_interrupt_server = s
	on_interrupt_context = context

	on_signal :: proc "cdecl" (_: i32) {
		context = on_interrupt_context

		// Force close on second signal. The signal can land on any thread, so this is a
		// process-wide flag, not the thread's state (upstream read `td`, which is nil off the
		// server's threads).
		if sync.atomic_exchange(&on_interrupt_seen.raw, true) {
			os.exit(1)
		}

		server_shutdown(on_interrupt_server)
	}

	libc.signal(libc.SIGINT, on_signal)
	libc.signal(libc.SIGTERM, on_signal)
}

// True once a shutdown has started, e.g. for a readiness probe to answer 503 while draining.
server_is_closing :: proc(s: ^Server) -> bool {
	return atomic_load(&s.closing)
}

// The maximum amount of bytes we will read (if handler did not)
// in order to get the connection ready for the next request. F-25: past this the connection closes.
// Go's is 256 KiB, which a GET with a stalled body holds uncounted and with no account: a guest's
// thousand sockets would be a small server's memory (M6-S1).
@(private)
Max_Post_Handler_Discard_Bytes :: 4 << 10

// How long to wait before actually closing a connection.
// This is to make sure the client can fully receive the response.
@(private)
Conn_Close_Delay :: time.Millisecond * 500

Connection_State :: enum {
	Pending, // Pending a client to attach.
	New, // Got client, waiting to service first request.
	Active, // Servicing request.
	Streaming, // F-1: a Stream owns the connection (stream.odin): SSE, chunked, or upgraded.
	Idle, // Waiting for next request.
	Will_Close, // Closing after the current response is sent.
	Closing, // Going to close, cleaning up.
	Closed, // Fully closed.
}

@(private)
connection_set_state :: proc(c: ^Connection, s: Connection_State) -> bool {
	if s < .Closing && c.state >= .Closing {
		return false
	}

	if s == .Closing && c.state == .Closed {
		return false
	}

	c.state = s
	return true
}

// F-22: under -sanitize:thread a connection's arena is the runtime's, on the heap. ThreadSanitizer
// doesn't see core:mem/virtual's raw mmap and munmap, so pages one loop unmapped and another mapped
// again read as a race on every reuse (about a hundred reports a run); malloc and free it sees.
when .Thread in ODIN_SANITIZER_FLAGS {
	Conn_Arena :: runtime.Arena

	conn_arena_allocator :: runtime.arena_allocator

	// The runtime arena's first block is otherwise 4 MiB; a connection's request needs a few KiB.
	@(private)
	conn_arena_init :: proc(a: ^Conn_Arena) {
		a^ = {minimum_block_size = 16 * mem.Kilobyte}
	}

	@(private)
	conn_arena_destroy :: proc(a: ^Conn_Arena) {
		runtime.arena_destroy(a)
		conn_arena_init(a)
	}
} else {
	Conn_Arena :: virtual.Arena

	conn_arena_allocator :: virtual.arena_allocator

	@(private)
	conn_arena_init :: proc(a: ^Conn_Arena) {
		err := virtual.arena_init_growing(a)
		assert(err == nil)
	}

	// A zero arena is a growing one that maps its first block on first use (F-17).
	@(private)
	conn_arena_destroy :: proc(a: ^Conn_Arena) {
		virtual.arena_destroy(a)
		a^ = {}
	}
}

// TODO/PERF: pool the connections, saves having to allocate scanner buf and temp_allocator every time.
Connection :: struct {
	server:         ^Server,
	socket:         net.TCP_Socket,
	state:          Connection_State,
	scanner:        Scanner,
	temp_allocator: Conn_Arena,
	loop:           Loop,
	stream:         ^Stream,
	// F-13: this request's generation (unique per thread), and its deferred response, if any.
	gen:            u64,
	deferred:       Deferred,
	// M1-02: when the send in flight (a response's or a stream's) must have finished; zero: none.
	send_deadline:  time.Time,
	// M2-12: connection_crashed queued its 500; the send's completion closes the connection.
	crashed:        bool,
}

// M1-02: a send posted now must finish by this; zero when sends have no limit.
@(private)
_send_deadline :: proc(c: ^Connection) -> time.Time {
	if c.server.opts.send_timeout <= 0 { return {} }
	return time.time_add(nbio.now(), c.server.opts.send_timeout)
}

// Loop/request cycle state.
@(private)
Loop :: struct {
	conn: ^Connection,
	req:  Request,
	res:  Response,
}

@(private)
connection_close :: proc(c: ^Connection, loc := #caller_location) {
	assert_has_td(loc)

	if c.state >= .Closing {
		log.debugf("connection %i already closing/closed", c.socket)
		return
	}

	log.debugf("closing connection: %i", c.socket)

	// F-13: a deferred response's watch ends here, and the application hears its peer is gone.
	_deferred_end(c, gone = true)

	c.state = .Closing

	// RFC 7230 6.6.

	// Close read side of the connection, then wait a little bit, allowing the client
	// to process the closing and receive any remaining data.
	net.shutdown(c.socket, net.Shutdown_Manner.Send)

	nbio.timeout_poly(Conn_Close_Delay, c, proc(_: ^nbio.Operation, c: ^Connection) {
		nbio.close_poly(c.socket, c, proc(_: ^nbio.Operation, c: ^Connection) {
			log.debugf("closed connection: %i", c.socket)

			c.state = .Closed

			conn_arena_destroy(&c.temp_allocator)

			scanner_destroy(&c.scanner)
			delete_key(&td.conns, c.socket)
			sync.atomic_sub(&c.server.conn_count, 1)
			free(c, c.server.conn_allocator)
		})
	})
}

@(private)
on_accept :: proc(op: ^nbio.Operation, server: ^Server) {
	_invoke(server, proc(a, b: rawptr) { _on_accept((^nbio.Operation)(a), (^Server)(b)) }, op, server)
}

@(private)
_on_accept :: proc(op: ^nbio.Operation, server: ^Server) {
	td.accept = nil

	if op.accept.err != nil {
		if td.state != .Serving { return }

		// F-8: never panic here; log and accept again. Out of descriptors, wait for some to free up.
		if op.accept.err == .Insufficient_Resources {
			log.error("Connection limit reached, trying again in a bit")
			nbio.timeout_poly(time.Second, server, _accept_again)
		} else {
			log.errorf("accept error: %v", op.accept.err)
			nbio.timeout_poly(10 * time.Millisecond, server, _accept_again)
		}
		return
	}

	// Accept next connection.
	td.accept = nbio.accept_poly(server.tcp_sock, server, on_accept)
	_accepted(server.tcp_sock, op.accept.client) // F-19

	// F-8: past the cap, answer 503 and close, without allocating a connection.
	if server.max_conns > 0 && sync.atomic_load(&server.conn_count) >= server.max_conns {
		nbio.send_poly(op.accept.client, {transmute([]byte)string(OVER_CAPACITY_RESPONSE)}, op.accept.client, proc(op: ^nbio.Operation, sock: net.TCP_Socket) {
			nbio.close(sock)
		})
		return
	}
	sync.atomic_add(&server.conn_count, 1)

	c := new(Connection, server.conn_allocator)
	c.state = .New
	c.server = server
	c.socket = op.accept.client
	c.loop.req.client = op.accept.client_endpoint

	td.conns[c.socket] = c

	log.debugf("new connection with thread, got %d conns", len(td.conns))
	conn_handle_reqs(c)
}

// F-7: how often a thread looks for connections past their deadline; a timeout fires up to this late.
@(private)
SWEEP_INTERVAL :: time.Second

// F-7: closes (or fails the body read of) every connection on this thread whose scanner is waiting
// past its phase's deadline. One pass over the thread's connections a second replaces a timeout on
// every read.
@(private)
_sweep_timeouts :: proc(_: ^nbio.Operation, s: ^Server) {
	td.sweep = nil
	if td.state != .Serving { return }
	now := nbio.now()
	for _, c in td.conns {
		// M1-02: a send past its deadline. Cut as the drain cuts a connection: the pending send
		// fails, and its own path closes the connection.
		if c.send_deadline != {} && time.diff(c.send_deadline, now) >= 0 && c.state < .Closing {
			log.infof("connection %i: a send waited past send_timeout, cutting it", c.socket)
			c.send_deadline = {}
			net.shutdown(c.socket, .Both)
			continue
		}
		sc := &c.scanner
		if sc.recv_op == nil || sc.deadline == {} || time.diff(sc.deadline, now) < 0 { continue }
		#partial switch c.state {
		case .New, .Idle, .Active:
			log.debugf("connection %i: %v phase timed out", c.socket, sc.phase)
			if !_invoke(s, proc(a, _: rawptr) { scanner_timed_out((^Scanner)(a)) }, sc, nil) {
				connection_crashed(c)
			}
		}
	}
	td.sweep = nbio.timeout_poly(SWEEP_INTERVAL, s, _sweep_timeouts)
}

@(private)
_accept_again :: proc(_: ^nbio.Operation, server: ^Server) {
	if td.state != .Serving || td.accept != nil { return }
	td.accept = nbio.accept_poly(server.tcp_sock, server, on_accept)
}

// F-8: what a connection past `max_connections` gets.
@(private)
OVER_CAPACITY_RESPONSE :: "HTTP/1.1 503 \r\nconnection: close\r\ncontent-length: 0\r\nretry-after: 1\r\n\r\n"

// F-5: runs `fn` through the server's `invoke`, when one is set.
@(private)
_invoke :: #force_inline proc(s: ^Server, fn: proc(a, b: rawptr), a, b: rawptr) -> (returned: bool) {
	if s.opts.invoke == nil {
		fn(a, b)
		return true
	}
	return s.opts.invoke(fn, a, b)
}

// F-5: a callback on this connection crashed and the guard recovered. Whatever the request had
// reached, the connection can't be trusted to continue: answer 500 if nothing was sent, then close.
@(private)
connection_crashed :: proc(c: ^Connection) {
	// A continuation that ran inside its handler crashes the connection twice: through
	// response_crashed, then through the handler's own invoke. The second closed it under
	// the queued 500 (M2-12).
	if c.crashed { return }
	scanner_cancel(&c.scanner)
	scanner_clear_dispatch(&c.scanner)
	_deferred_end(c, gone = true)

	if c.state == .Streaming && c.stream != nil {
		stream_crashed(c.stream)
		return
	}

	if c.state >= .Closing { return }

	if c.state == .Active && !c.loop.res.sent {
		c.loop.res.sent = true
		c.crashed = true
		c.send_deadline = _send_deadline(c) // M2-28: cut like any other send that stalls
		connection_set_state(c, .Will_Close)
		nbio.send_poly(c.socket, {transmute([]byte)string(CRASHED_RESPONSE)}, c, proc(_: ^nbio.Operation, c: ^Connection) {
			connection_close(c)
		})
		return
	}

	connection_close(c)
}

@(private)
CRASHED_RESPONSE :: "HTTP/1.1 500 \r\nconnection: close\r\ncontent-type: text/plain\r\ncontent-length: 15\r\n\r\nInternal error."

@(private)
conn_handle_reqs :: proc(c: ^Connection) {
	// TODO/PERF: not sure why this is allocated on the connections allocator, can't it use the arena?
	scanner_init(&c.scanner, c, c.server.conn_allocator)

	conn_arena_init(&c.temp_allocator)
	context.temp_allocator = conn_arena_allocator(&c.temp_allocator)

	conn_handle_req(c, context.temp_allocator)
}

@(private)
conn_handle_req :: proc(c: ^Connection, allocator := context.temp_allocator) {
	td.next_gen += 1
	c.gen = td.next_gen

	// F-7: waiting for the next request is the idle phase; the first byte of it starts the header
	// deadline (scanner_on_read), and the end of the headers starts the body deadline.
	scanner_set_phase(&c.scanner, .Idle)

	on_rline1 :: proc(loop: rawptr, token: string, err: bufio.Scanner_Error) {
		l := cast(^Loop)loop

		if !connection_set_state(l.conn, .Active) { return }

		if err != nil {
			if err == .EOF {
				log.debugf("client disconnected (EOF)")
			} else {
				log.infof("request scanner error: %v", err) // F-16: client-caused, info (M1-22)
			}

			clean_request_loop(l.conn, close = true)
			return
		}

		// In the interest of robustness, a server that is expecting to receive
		// and parse a request-line SHOULD ignore at least one empty line (CRLF)
		// received prior to the request-line.
		if len(token) == 0 {
			log.debug("first request line empty, skipping in interest of robustness")
			scanner_scan(&l.conn.scanner, loop, on_rline2)
			return
		}

		on_rline2(loop, token, err)
	}

	on_rline2 :: proc(loop: rawptr, token: string, err: bufio.Scanner_Error) {
		l := cast(^Loop)loop

		if err != nil {
			log.infof("request scanning error: %v", err)
			clean_request_loop(l.conn, close = true)
			return
		}

		rline, err := requestline_parse(token, context.temp_allocator)
		switch err {
		case .Method_Not_Implemented:
			log.infof("request-line %q invalid method", token)
			headers_set_close(&l.res.headers)
			l.res.status = .Not_Implemented
			respond(&l.res)
			return
		case .Invalid_Version_Format, .Not_Enough_Fields:
			log.infof("request-line %q invalid: %s", token, err)
			clean_request_loop(l.conn, close = true)
			return
		case .None:
			l.req.line = rline
		}

		// Might need to support more versions later.
		if rline.version.major != 1 || rline.version.minor > 1 {
			log.infof("request http version not supported %v", rline.version)
			headers_set_close(&l.res.headers)
			l.res.status = .HTTP_Version_Not_Supported
			respond(&l.res)
			return
		}

		l.req.url = url_parse(rline.target.(string))

		l.conn.scanner.max_token_size = l.conn.server.opts.limit_headers
		scanner_scan(&l.conn.scanner, loop, on_header_line)
	}

	on_header_line :: proc(loop: rawptr, token: string, err: bufio.Scanner_Error) {
		l := cast(^Loop)loop

		if err != nil {
			log.infof("request scanning error: %v", err)
			clean_request_loop(l.conn, close = true)
			return
		}

		// The first empty line denotes the end of the headers section.
		if len(token) == 0 {
			on_headers_end(l)
			return
		}

		if _, ok := header_parse(&l.req.headers, token); !ok {
			log.infof("header-line %q is invalid", token)
			headers_set_close(&l.res.headers)
			l.res.status = .Bad_Request
			respond(&l.res)
			return
		}

		l.conn.scanner.max_token_size -= len(token)
		if l.conn.scanner.max_token_size <= 0 {
			log.info("request headers too large")
			headers_set_close(&l.res.headers)
			l.res.status = .Request_Header_Fields_Too_Large
			respond(&l.res)
			return
		}

		scanner_scan(&l.conn.scanner, loop, on_header_line)
	}

	on_headers_end :: proc(l: ^Loop) {
		scanner_set_phase(&l.conn.scanner, .Body)

		if !headers_validate_for_server(&l.req.headers) {
			log.info("request headers are invalid")
			headers_set_close(&l.res.headers)
			l.res.status = .Bad_Request
			respond(&l.res)
			return
		}

		l.req.headers.readonly = true

		l.conn.scanner.max_token_size = bufio.DEFAULT_MAX_SCAN_TOKEN_SIZE

		// Automatically respond with a continue status when the client has the Expect: 100-continue header.
		if expect, ok := headers_get_unsafe(l.req.headers, "expect");
		   ok && expect == "100-continue" && l.conn.server.opts.auto_expect_continue {

			l.res.status = .Continue

			respond(&l.res)
			return
		}

		rline := &l.req.line.(Requestline)
		// An options request with the "*" is a no-op/ping request to
		// check for server capabilities and should not be sent to handlers.
		if rline.method == .Options && rline.target.(string) == "*" {
			l.res.status = .OK
			respond(&l.res)
		} else {
			// Give the handler this request as a GET, since the HTTP spec
			// says a HEAD is identical to a GET but just without writing the body,
			// handlers shouldn't have to worry about it.
			is_head := rline.method == .Head
			if is_head && l.conn.server.opts.redirect_head_to_get {
				l.req.is_head = true
				rline.method = .Get
			}

			l.conn.server.handler.handle(&l.conn.server.handler, &l.req, &l.res)
			// F-17: the handler began a stream and has returned, so nothing reads this request
			// again: its arena's pages go back. The destroyed arena maps its first block on first
			// use (re-initialising it would touch a page now), so a chunked stream that ends serves
			// the next request from it (clean_request_loop).
			if l.conn.stream != nil { conn_arena_destroy(&l.conn.temp_allocator) }
		}
	}

	c.loop.conn = c
	c.loop.res._conn = c
	c.loop.req._scanner = &c.scanner
	request_init(&c.loop.req, allocator)
	response_init(&c.loop.res, allocator)

	c.scanner.max_token_size = c.server.opts.limit_request_line
	scanner_scan(&c.scanner, &c.loop, on_rline1)
}

// A buffer that will contain the date header for the current second.
@(private)
Server_Date :: struct {
	buf_backing: [DATE_LENGTH]byte,
	second:      i64,
}

// F-11: each thread formats its own date header, at most once per second of its event loop's clock
// (nbio's time, cached per tick), so no thread reads a buffer another one is writing.
@(private)
server_date :: proc(s: ^Server) -> string {
	now := nbio.now()
	second := time.to_unix_seconds(now)
	if second != td.date.second || td.date.buf_backing[0] == 0 {
		buf: bytes.Buffer
		buf.buf = slice.into_dynamic(td.date.buf_backing[:])
		date_write(bytes.buffer_to_stream(&buf), now)
		td.date.second = second
	}
	return string(td.date.buf_backing[:])
}
