package x

import "core:sync"

// A raw lock in a feature: a trap under it would recover with the lock held.
@(private)
counted: struct { mu: sync.Mutex, n: int }

@(private)
ready: sync.Once

bump :: proc() {
	sync.once_do(&ready, proc() {})
	sync.mutex_lock(&counted.mu)
	counted.n += 1
	sync.mutex_unlock(&counted.mu)
}
