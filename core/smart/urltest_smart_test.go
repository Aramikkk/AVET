package group

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

const (
	tagDE = "\U0001F1E9\U0001F1EA Germany"
	tagNL = "\U0001F1F3\U0001F1F1 Netherlands"
)

func windowOf(ms, n int) []int {
	xs := make([]int, n)
	for i := range xs {
		xs[i] = ms
	}
	return xs
}

func newPointsState(t *testing.T, habit int) *smartState {
	dir := t.TempDir()
	return newSmartState(nil, "auto-wifi", smartOptions{
		points: true,
		habit:  habit,
		memory: filepath.Join(dir, "habits.json"),
	})
}

func TestPointsSpeedIsTheMainThing(t *testing.T) {
	s := newPointsState(t, 12)
	s.samples[tagDE] = windowOf(40, 6)
	s.samples[tagNL] = windowOf(200, 6)
	now := time.Now()
	a, _ := s.points(tagDE, now, 40)
	b, _ := s.points(tagNL, now, 40)
	if a.total-b.total < 25 {
		t.Fatalf("40 ms should lead 200 ms by 25 points or more: %v vs %v", a, b)
	}
}

func TestHabitTipsASmallGapButNotABigOne(t *testing.T) {
	s := newPointsState(t, 12)
	now := time.Now()
	s.book.add("auto-wifi", "DE", 10, now)
	s.book.add("auto-wifi", "NL", 1, now)
	// a small gap: 120 ms against 80 ms, the habit for DE leads, but by less than the gain needed to leave
	s.samples[tagDE] = windowOf(120, 6)
	s.samples[tagNL] = windowOf(80, 6)
	de, _ := s.points(tagDE, now, 80)
	nl, _ := s.points(tagNL, now, 80)
	if !(de.total > nl.total) {
		t.Fatalf("the habit should tip a small gap: %v vs %v", de, nl)
	}
	if de.total-nl.total >= float64(6) {
		t.Fatalf("but not by more than the gain: %v vs %v", de, nl)
	}
	// a big gap: 300 ms against 80 ms, no habit holds it
	s.samples[tagDE] = windowOf(300, 6)
	de, _ = s.points(tagDE, now, 80)
	if de.habit != 0 || de.total >= nl.total {
		t.Fatalf("a slow server must not be held by the habit: %v vs %v", de, nl)
	}
}

func TestNothingLearnedGivesNoHabit(t *testing.T) {
	s := newPointsState(t, 12)
	now := time.Now()
	s.book.add("auto-wifi", "DE", 0.3, now)
	s.samples[tagDE] = windowOf(80, 6)
	p, _ := s.points(tagDE, now, 80)
	if p.habit != 0 {
		t.Fatalf("a few minutes are not a habit: %v", p)
	}
}

func TestHabitFades(t *testing.T) {
	e := habitEntry{W: 8, T: time.Now().Add(-habitHalfLife).Unix()}
	got := e.at(time.Now())
	if got < 3.9 || got > 4.1 {
		t.Fatalf("a half-life should halve the weight, got %v", got)
	}
}

func TestEventsFromTheApp(t *testing.T) {
	s := newPointsState(t, 12)
	dir := filepath.Dir(s.opt.memory)
	write := func(events []habitEvent) {
		raw, _ := json.Marshal(map[string]any{"events": events})
		if err := os.WriteFile(filepath.Join(dir, "habit_events.json"), raw, 0o600); err != nil {
			t.Fatal(err)
		}
		// the file's time must move on for the book to look again
		future := time.Now().Add(time.Duration(len(events)) * time.Second)
		_ = os.Chtimes(filepath.Join(dir, "habit_events.json"), future, future)
	}
	now := time.Now()
	write([]habitEvent{{ID: 1, Group: "auto-wifi", Country: "NL"}})
	s.book.events(now)
	if p := s.book.pref("auto-wifi", "NL", now); p != 1 {
		t.Fatalf("a country picked by hand should count at once, got %v", p)
	}
	// the same event is not taken twice
	s.book.events(now.Add(time.Hour))
	if w := s.book.Groups["auto-wifi"]["NL"].W; w > manualHours+0.01 {
		t.Fatalf("an event must be taken once, weight %v", w)
	}
	write([]habitEvent{{ID: 1, Group: "auto-wifi", Country: "NL"}, {ID: 2, Reset: true}})
	s.book.events(now.Add(2 * time.Hour))
	if p := s.book.pref("auto-wifi", "NL", now); p != 0 {
		t.Fatalf("a reset should clear what was learned, got %v", p)
	}
}

func TestBookSurvivesARestart(t *testing.T) {
	s := newPointsState(t, 12)
	now := time.Now()
	s.book.add("auto-wifi", "DE", 6, now)
	s.book.save(now, true)
	path := s.opt.memory
	booksMu.Lock()
	delete(books, path)
	booksMu.Unlock()
	again := openBook(path)
	if p := again.pref("auto-wifi", "DE", now); p != 1 {
		t.Fatalf("the book should be read back, got %v", p)
	}
}

func TestPinnedServersAreRead(t *testing.T) {
	dir := t.TempDir()
	s := &smartState{opt: smartOptions{pins: filepath.Join(dir, "pinned.json")}}
	if got := s.pins(); len(got) != 0 {
		t.Fatalf("no file, no pins: %v", got)
	}
	if err := os.WriteFile(s.opt.pins, []byte(`["a","b"]`), 0o644); err != nil {
		t.Fatal(err)
	}
	got := s.pins()
	if !got["a"] || !got["b"] || got["c"] {
		t.Fatalf("pins read wrong: %v", got)
	}
	// a changed file is read again
	time.Sleep(20 * time.Millisecond)
	if err := os.WriteFile(s.opt.pins, []byte(`["c"]`), 0o644); err != nil {
		t.Fatal(err)
	}
	future := time.Now().Add(time.Second)
	_ = os.Chtimes(s.opt.pins, future, future)
	got = s.pins()
	if got["a"] || !got["c"] {
		t.Fatalf("a changed file not read again: %v", got)
	}
}

func TestDeadServersRestBetweenRetries(t *testing.T) {
	s := &smartState{
		samples: map[string][]int{"dead": {0, 0, 0}, "alive": {80, 0, 90}, "new": {0}},
		seen:    map[string]time.Time{},
	}
	now := time.Now()
	s.seen["dead"] = now.Add(-2 * time.Minute)
	if !s.restsDead("dead", now) {
		t.Fatal("a server dead for three tests, looked at two minutes ago, should rest")
	}
	s.seen["dead"] = now.Add(-20 * time.Minute)
	if s.restsDead("dead", now) {
		t.Fatal("after the retry time it takes its turn again")
	}
	if s.restsDead("alive", now) || s.restsDead("new", now) {
		t.Fatal("a server that answered, or one with too little known, does not rest")
	}
}
