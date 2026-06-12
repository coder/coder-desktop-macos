//go:build ios

package main

import (
	"runtime"
	"runtime/debug"
)

func init() {
	// iOS kills Network Extension processes that exceed ~50 MiB resident
	// memory (jetsam). Keep the Go runtime well below that: a soft heap
	// limit leaves headroom for the Swift side and non-heap Go memory,
	// aggressive GC keeps the steady-state heap small, and a single P
	// avoids per-thread allocator overhead.
	runtime.GOMAXPROCS(1)
	debug.SetGCPercent(10)
	debug.SetMemoryLimit(32 << 20)
}
