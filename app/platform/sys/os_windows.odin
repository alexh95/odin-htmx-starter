#+build windows
package sys

import "core:net"
import win32 "core:sys/windows"
import "core:time"

// Windows has no per-process soft limit on sockets to raise.
raise_nofile :: proc() -> (soft: int) {
	return -1
}

// Both are fast here already: GetSystemTimePreciseAsFileTime and QueryPerformanceCounter.
now_unix_ns :: proc "contextless" () -> i64 {
	return time.now()._nsec
}

mono_ns :: proc "contextless" () -> i64 {
	return time.tick_now()._nsec
}

// Whether a process with this id still runs. One that exists but isn't ours to
// ask counts as running: its files aren't ours to delete either.
process_alive :: proc(pid: int) -> bool {
	h := win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, false, win32.DWORD(pid))
	if h == nil { return win32.GetLastError() == win32.ERROR_ACCESS_DENIED }
	defer win32.CloseHandle(h)
	STILL_ACTIVE :: 259
	code: win32.DWORD
	return bool(win32.GetExitCodeProcess(h, &code)) && code == STILL_ACTIVE
}

// The process's working set, in bytes (ops's panel).
rss_bytes :: proc() -> int {
	pmc: win32.PROCESS_MEMORY_COUNTERS
	if !win32.GetProcessMemoryInfo(win32.GetCurrentProcess(), &pmc, size_of(pmc)) { return 0 }
	return int(pmc.WorkingSetSize)
}

// The bytes free to this process and the total on the volume holding `path` (status's disk part).
disk_free :: proc(path: string) -> (free, total: i64, ok: bool) {
	w := win32.utf8_to_wstring(path, context.temp_allocator)
	avail, all: win32.ULARGE_INTEGER
	if !win32.GetDiskFreeSpaceExW(w, &avail, &all, nil) { return }
	return i64(avail), i64(all), true
}

// Connects `sock` to an IPv4 `ep`, giving up after `within` (status's probes, M5-09): a blocking
// connect to an address that drops packets waits out the SYN retries, about 21 s here.
connect_within :: proc(sock: net.TCP_Socket, ep: net.Endpoint, within: time.Duration) -> (ok, timed_out: bool) {
	ip, is4 := ep.address.(net.IP4_Address)
	if !is4 || net.set_blocking(sock, false) != nil { return }
	defer net.set_blocking(sock, true)
	s := win32.SOCKET(sock)
	sa := win32.sockaddr_in{sin_family = win32.ADDRESS_FAMILY(win32.AF_INET), sin_port = u16be(ep.port), sin_addr = {transmute(u32)ip}}
	if win32.connect(s, (^win32.SOCKADDR_STORAGE_LH)(&sa), size_of(sa)) == 0 { return true, false }
	if win32.WSAGetLastError() != win32.WSAEWOULDBLOCK { return }
	// A refused connect shows in the except set, not the write set.
	writable, failed: win32.fd_set
	writable.fd_count, writable.fd_array[0] = 1, s
	failed = writable
	ms := i64(time.duration_milliseconds(within))
	tv := win32.timeval{tv_sec = win32.c_long(ms / 1000), tv_usec = win32.c_long(ms % 1000 * 1000)}
	n := win32.select(0, nil, &writable, &failed, &tv)
	if n == 0 { return false, true }
	return n > 0 && failed.fd_count == 0, false
}
