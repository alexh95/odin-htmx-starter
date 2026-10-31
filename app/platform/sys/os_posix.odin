#+build linux, darwin, freebsd, openbsd, netbsd
package sys

import "core:c"
import "core:net"
import "core:strings"
import "core:sys/posix"
import "core:time"

// Soft to hard (PLAN §8.6 step 2): a container's soft limit is 1024 by default, and at
// that limit the server stopped accepting after 1,012 streams (13 §3.5). F-8's cap
// then derives from the raised limit.
raise_nofile :: proc() -> (soft: int) {
	lim: posix.rlimit
	if posix.getrlimit(.NOFILE, &lim) != .OK { return -1 }
	if lim.rlim_cur < lim.rlim_max {
		lim.rlim_cur = lim.rlim_max
		posix.setrlimit(.NOFILE, &lim)
		posix.getrlimit(.NOFILE, &lim)
	}
	return int(lim.rlim_cur)
}

// libc's clock_gettime goes through the vDSO: 19 ns, against 324-377 ns for the raw
// syscall core:time makes on Linux (13 §5.5). The logger reads these per line.
now_unix_ns :: proc "contextless" () -> i64 {
	ts: posix.timespec
	posix.clock_gettime(.REALTIME, &ts)
	return i64(ts.tv_sec) * 1e9 + i64(ts.tv_nsec)
}

mono_ns :: proc "contextless" () -> i64 {
	ts: posix.timespec
	posix.clock_gettime(.MONOTONIC, &ts)
	return i64(ts.tv_sec) * 1e9 + i64(ts.tv_nsec)
}

// Whether a process with this id still runs: kill(pid, 0) checks without
// signalling. One that exists but isn't ours (EPERM) counts as running.
process_alive :: proc(pid: int) -> bool {
	if posix.kill(posix.pid_t(pid), .NONE) == .OK { return true }
	return posix.errno() == .EPERM
}

// The process's resident memory, in bytes: /proc/self/statm's second field on Linux
// (ops's panel); 0 where there is no such file.
rss_bytes :: proc() -> int {
	when ODIN_OS != .Linux { return 0 } else {
		fd := posix.open("/proc/self/statm", {})
		if fd < 0 { return 0 }
		defer posix.close(fd)
		buf: [128]byte
		n := posix.read(fd, raw_data(buf[:]), len(buf))
		if n <= 0 { return 0 }
		fields := 0
		pages := 0
		for c in buf[:n] {
			switch {
			case c == ' ':
				fields += 1
				if fields == 2 { return pages * int(posix.sysconf(._PAGESIZE)) }
			case fields == 1 && c >= '0' && c <= '9':
				pages = pages * 10 + int(c - '0')
			}
		}
		return 0
	}
}

// The bytes free to this process and the total on the filesystem holding `path` (status's disk part).
disk_free :: proc(path: string) -> (free, total: i64, ok: bool) {
	st: posix.statvfs_t
	if posix.statvfs(strings.clone_to_cstring(path, context.temp_allocator), &st) != .OK { return }
	return i64(st.f_bavail) * i64(st.f_frsize), i64(st.f_blocks) * i64(st.f_frsize), true
}

// Connects `sock` to an IPv4 `ep`, giving up after `within` (status's probes, M5-09): a blocking
// connect to an address that drops packets waits out the kernel's SYN retries, about two minutes.
connect_within :: proc(sock: net.TCP_Socket, ep: net.Endpoint, within: time.Duration) -> (ok, timed_out: bool) {
	ip, is4 := ep.address.(net.IP4_Address)
	if !is4 || net.set_blocking(sock, false) != nil { return }
	defer net.set_blocking(sock, true)
	fd := posix.FD(sock)
	sa := posix.sockaddr_in{sin_family = .INET, sin_port = posix.in_port_t(ep.port), sin_addr = {transmute(posix.in_addr_t)ip}}
	if posix.connect(fd, (^posix.sockaddr)(&sa), size_of(sa)) == .OK { return true, false }
	if posix.errno() != .EINPROGRESS { return }
	p := posix.pollfd{fd = fd, events = {.OUT}}
	n := posix.poll(&p, 1, c.int(time.duration_milliseconds(within)))
	if n == 0 { return false, true }
	err: c.int
	size := posix.socklen_t(size_of(err))
	if n < 0 || posix.getsockopt(fd, posix.SOL_SOCKET, .ERROR, &err, &size) != .OK || err != 0 { return }
	return true, false
}
