package middleware

import (
	"testing"
	"time"
)

func TestLimiterWindow(t *testing.T) {
	l := NewLimiter(3, time.Minute)
	t0 := time.Unix(1_800_000_000, 0) // start of a minute
	for i := 0; i < 3; i++ {
		if ok, _ := l.Allow("ip", t0); !ok {
			t.Fatalf("hit %d should pass", i+1)
		}
	}
	ok, wait := l.Allow("ip", t0.Add(10*time.Second))
	if ok || wait != 50 {
		t.Fatalf("4th hit should be refused with 50s wait, got %v %d", ok, wait)
	}
	if ok, _ := l.Allow("other", t0); !ok {
		t.Fatal("keys are independent")
	}
	if ok, _ := l.Allow("ip", t0.Add(time.Minute)); !ok {
		t.Fatal("a new window starts fresh")
	}
}

func TestLimiterPeekDoesNotCount(t *testing.T) {
	l := NewLimiter(2, 15*time.Minute)
	now := time.Unix(1_800_000_000, 0)
	for i := 0; i < 5; i++ {
		if ok, _ := l.Peek("user", now); !ok {
			t.Fatal("peek must not count hits")
		}
	}
	l.Allow("user", now)
	l.Allow("user", now)
	if ok, wait := l.Peek("user", now); ok || wait <= 0 {
		t.Fatal("after max hits peek should report blocked")
	}
}

func TestLimiterDisabled(t *testing.T) {
	l := NewLimiter(0, time.Minute)
	for i := 0; i < 100; i++ {
		if ok, _ := l.Allow("x", time.Now()); !ok {
			t.Fatal("max <= 0 disables the limiter")
		}
	}
}
