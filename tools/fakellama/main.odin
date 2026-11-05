package main

// ---- fakellama: a llama.cpp server with no model (PLAN §14.3) ---------------------------------
//
//   odin run tools/fakellama -- [--port 9931] [--key K] [--strict 1] [--slots 1] [--delay-ms 5]
//
// --strict wants the key on /health too. The routes, the faults and the control endpoints are in fake/fake.odin. It prints its port and
// serves until killed.

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:thread"
import "core:time"

import fake "fake"

main :: proc() {
	opt := fake.Options{slots = 1}
	port := 9931
	args := os.args[1:]
	for i := 0; i + 1 < len(args); i += 2 {
		v := args[i + 1]
		switch args[i] {
		case "--port":     port, _ = strconv.parse_int(v, 10)
		case "--key":      opt.key = v
		case "--strict":   opt.strict = v == "1"
		case "--slots":    opt.slots, _ = strconv.parse_int(v, 10)
		case "--delay-ms":
			ms, _ := strconv.parse_int(v, 10)
			opt.delay = time.Duration(ms) * time.Millisecond
		case:
			fmt.eprintfln("fakellama: unknown flag %s", args[i])
			os.exit(2)
		}
	}
	bound, err := fake.start(opt, port)
	if err != nil {
		fmt.eprintfln("fakellama: can't listen on %d: %v", port, err)
		os.exit(1)
	}
	fmt.printfln("fakellama on 127.0.0.1:%d", bound)
	for { thread.yield(); time.sleep(time.Hour) }
}
