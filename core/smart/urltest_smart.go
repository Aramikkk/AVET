package group

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/log"
	N "github.com/sagernet/sing/common/network"
)

// The "smart" choice of an automatic group (AVET): instead of the last single measurement of each server, a window of
// the last measurements is scored (median, spread, losses), and the group changes server only when another is
// clearly better, has been better in two rounds running, the time on the server has passed, and (for another country)
// by a wider margin. A server that stops answering is left at once. Every change is written to the log with its
// reason: lines starting with "smart[".

type smartOptions struct {
	dwell      time.Duration
	gainMs     int
	gainPct    int
	countryPct int
	window     int
	selects    bool          // the group chooses by the scored window (else it only keeps the windows)
	active     int           // servers kept awake and tested every round (0: all are tested)
	explore    int           // others woken each round, the longest unmeasured first
	fullEvery  time.Duration // all servers are tested together this often
	warm       time.Duration // after a start, and after every forced test, all servers are tested for this long

	// the points: a server is given points (speed, steadiness, the habit for its country, the real connections) instead of
	// a cost in ms, and the group changes server when another is ahead by [gainPts] (more for another country)
	points     bool
	gainPts    int
	countryPts int
	habit      int    // the most points the habit for a country can give (0: no learning)
	memory     string // the file the habits are kept in
	pins       string // the file the pinned servers are kept in (a list of tags the app writes): they are always awake
}

// priorityOptions: the servers of the main subscription are preferred: any other server has to be faster by [margin] ms
// to be chosen over them (the penalty is added to its delay).
type priorityOptions struct {
	tags   map[string]bool
	margin int
}

func (p *priorityOptions) penalty(tag string) int {
	if p == nil || p.margin <= 0 || p.tags[tag] {
		return 0
	}
	return p.margin
}

type smartState struct {
	priority   *priorityOptions
	mu         sync.Mutex
	logger     log.Logger
	name       string
	opt        smartOptions
	samples    map[string][]int // by tag: ms, 0 = lost; the newest last
	seen       map[string]time.Time
	badUntil   map[string]time.Time
	pick       map[string]string // by network: the tag in use
	lastSwitch map[string]time.Time
	cand       map[string]string
	candRounds map[string]int
	tested     map[string]bool // the servers tested in the round that has just run (nil: all)
	lastFull   time.Time
	warmUntil  time.Time

	fails      map[string][]time.Time // by tag: when real connections through it failed (the last hour)
	lastAccrue time.Time
	book       *habitBook

	pinned     map[string]bool // the servers the user pinned, read from [smartOptions.pins] when it changes
	pinnedMod  time.Time
}

func newSmartState(logger log.Logger, name string, opt smartOptions) *smartState {
	if opt.window <= 0 {
		opt.window = 7
	}
	if opt.dwell <= 0 {
		opt.dwell = 3 * time.Minute
	}
	if opt.gainMs <= 0 {
		opt.gainMs = 30
	}
	if opt.gainPct <= 0 {
		opt.gainPct = 25
	}
	if opt.countryPct <= 0 {
		opt.countryPct = 40
	}
	if opt.active > 0 && opt.fullEvery <= 0 {
		opt.fullEvery = 30 * time.Minute
	}
	if opt.active > 0 && opt.warm <= 0 {
		opt.warm = 5 * time.Minute
	}
	s := &smartState{
		warmUntil:  time.Now().Add(opt.warm),
		logger:     logger,
		name:       name,
		opt:        opt,
		samples:    map[string][]int{},
		seen:       map[string]time.Time{},
		badUntil:   map[string]time.Time{},
		pick:       map[string]string{},
		lastSwitch: map[string]time.Time{},
		cand:       map[string]string{},
		candRounds: map[string]int{},
		fails:      map[string][]time.Time{},
	}
	if opt.points {
		if opt.gainPts <= 0 {
			s.opt.gainPts = 6
		}
		if opt.countryPts <= 0 {
			s.opt.countryPts = 4
		}
		if opt.memory != "" {
			s.book = openBook(opt.memory)
		}
	}
	return s
}

// countryOf is the two-letter code from the flag in a server's name ("" when there is none).
func countryOf(tag string) string {
	var codes []rune
	for _, r := range tag {
		if r >= 0x1F1E6 && r <= 0x1F1FF {
			codes = append(codes, 'A'+(r-0x1F1E6))
			if len(codes) == 2 {
				return string(codes)
			}
		} else if len(codes) > 0 {
			codes = codes[:0]
		}
	}
	return ""
}

func shortName(tag string) string {
	t := strings.TrimSpace(tag)
	if i := strings.Index(t, "§"); i >= 0 {
		t = strings.TrimSpace(t[:i])
	}
	return t
}

func (s *smartState) push(tag string, ms int) {
	xs := append(s.samples[tag], ms)
	if len(xs) > s.opt.window {
		xs = xs[len(xs)-s.opt.window:]
	}
	s.samples[tag] = xs
}

// score is the cost of a server in ms (lower is better); false when nothing is known of it yet.
func (s *smartState) score(tag string, now time.Time) (float64, bool) {
	xs := s.samples[tag]
	if len(xs) == 0 {
		return 0, false
	}
	var ok []int
	lost := 0
	for _, v := range xs {
		if v <= 0 {
			lost++
		} else {
			ok = append(ok, v)
		}
	}
	var sc float64
	if len(ok) == 0 {
		sc = 5000
	} else {
		sorted := append([]int(nil), ok...)
		sort.Ints(sorted)
		median := float64(sorted[len(sorted)/2])
		jitter := 0.0
		if len(sorted) >= 3 {
			jitter = float64(sorted[len(sorted)-1]-sorted[0]) / 2
		}
		sc = median + 0.6*jitter + 600*float64(lost)/float64(len(xs))
	}
	if len(xs) < 3 {
		sc += 60 // little is known of it
	}
	if until, bad := s.badUntil[tag]; bad && until.After(now) {
		sc += 300
	}
	sc += float64(s.priority.penalty(tag))
	return sc, true
}

func (s *smartState) dead(tag string) bool {
	xs := s.samples[tag]
	if len(xs) < 3 {
		return false
	}
	for _, v := range xs[len(xs)-3:] {
		if v > 0 {
			return false
		}
	}
	return true
}

// deadRetry is how long a server that has not answered for three tests in a row is left alone by the rotation of the
// sleepers (the full rounds and the warm time still test it): a dead server is not worth a test in every round.
const deadRetry = 15 * time.Minute

// restsDead reports a server the rotation passes by: it has not answered for a while, and was looked at not long ago.
func (s *smartState) restsDead(tag string, now time.Time) bool {
	return s.dead(tag) && now.Sub(s.seen[tag]) < deadRetry
}

// smartTargets is the servers to test in this round. With a limit of awake servers (smart_active), most are left
// asleep: the best ones by their windows are tested, the server in use, and a few of the others in turn (the longest
// unmeasured first), so the memory of the rest does not go stale; all of them are tested together at the start, now
// and then, and at once when the server in use stops answering. Everything else costs no battery.
func (g *URLTestGroup) smartTargets() []adapter.Outbound {
	s := g.smart
	if s == nil || s.opt.active <= 0 || len(g.outbounds) <= s.opt.active+s.opt.explore {
		return g.outbounds
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	// the warm time: every server is tested, so the windows are filled and the best ones are really known before the others sleep
	if now.Before(s.warmUntil) {
		s.tested = nil
		return g.outbounds
	}
	cur := s.pick[N.NetworkTCP]
	full := s.lastFull.IsZero() || now.Sub(s.lastFull) >= s.opt.fullEvery || (cur != "" && s.dead(cur))
	if len(s.samples) < len(g.outbounds)/2 {
		full = true // too little is known yet to tell the best ones
	}
	if full {
		s.lastFull = now
		s.tested = nil
		return g.outbounds
	}
	type ranked struct {
		o  adapter.Outbound
		sc float64
	}
	var all []ranked
	for _, o := range g.outbounds {
		sc, ok := s.score(o.Tag(), now)
		if !ok {
			sc = 1e9
		}
		all = append(all, ranked{o, sc})
	}
	sort.SliceStable(all, func(i, j int) bool { return all[i].sc < all[j].sc })
	chosen := map[string]bool{}
	var out []adapter.Outbound
	add := func(o adapter.Outbound) {
		if !chosen[o.Tag()] {
			chosen[o.Tag()] = true
			out = append(out, o)
		}
	}
	for i := 0; i < len(all) && i < s.opt.active; i++ {
		add(all[i].o)
	}
	for _, o := range g.outbounds {
		if o.Tag() == cur {
			add(o)
		}
	}
	// the pinned ones never sleep
	pins := s.pins()
	for _, o := range g.outbounds {
		if pins[o.Tag()] {
			add(o)
		}
	}
	// the sleepers woken in turn: the ones measured longest ago
	var rest []adapter.Outbound
	for _, r := range all[min(len(all), s.opt.active):] {
		if !chosen[r.o.Tag()] && !s.restsDead(r.o.Tag(), now) {
			rest = append(rest, r.o)
		}
	}
	sort.SliceStable(rest, func(i, j int) bool { return s.seen[rest[i].Tag()].Before(s.seen[rest[j].Tag()]) })
	for i := 0; i < len(rest) && i < s.opt.explore; i++ {
		add(rest[i])
	}
	s.tested = chosen
	return out
}

// pins are the servers the user pinned (long press in the list): the file is read again only when it has changed.
func (s *smartState) pins() map[string]bool {
	if s.opt.pins == "" {
		return nil
	}
	info, err := os.Stat(s.opt.pins)
	if err != nil {
		s.pinned, s.pinnedMod = nil, time.Time{}
		return nil
	}
	if info.ModTime().Equal(s.pinnedMod) {
		return s.pinned
	}
	s.pinnedMod = info.ModTime()
	s.pinned = nil
	data, err := os.ReadFile(s.opt.pins)
	if err != nil {
		return nil
	}
	var tags []string
	if json.Unmarshal(data, &tags) != nil {
		return nil
	}
	s.pinned = make(map[string]bool, len(tags))
	for _, t := range tags {
		s.pinned[t] = true
	}
	return s.pinned
}

// smartWarmUp starts the warm time again (a forced test: the app was opened, the network changed, the bolt was pressed):
// all servers are tested for a while before the sleeping begins.
func (g *URLTestGroup) smartWarmUp() {
	s := g.smart
	if s == nil || s.opt.active <= 0 {
		return
	}
	s.mu.Lock()
	s.warmUntil = time.Now().Add(s.opt.warm)
	s.tested = nil
	s.mu.Unlock()
}

// smartLost records a failed connection through [tag] (the group calls it when a dial fails).
func (g *URLTestGroup) smartLost(tag string) {
	if g.smart == nil {
		return
	}
	g.smart.mu.Lock()
	g.smart.push(tag, 0)
	g.smart.fails[tag] = append(g.smart.fails[tag], time.Now())
	g.smart.mu.Unlock()
}

// smartRound is called after each round of tests: it takes the new measurements into the windows and decides the pick.
func (g *URLTestGroup) smartRound() {
	s := g.smart
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	for _, detour := range g.outbounds {
		tag := detour.Tag()
		if s.tested != nil && !s.tested[tag] {
			continue // asleep this round: its window stays as it was
		}
		h := g.history.LoadURLTestHistory(RealTag(detour, N.NetworkTCP))
		switch {
		case h == nil:
			s.push(tag, 0)
		case h.Time.After(s.seen[tag]):
			s.seen[tag] = h.Time
			s.push(tag, int(h.Delay))
		}
	}
	if s.opt.selects {
		if s.opt.points {
			s.decidePoints(g, N.NetworkTCP, now)
			s.accrue(now)
		} else {
			s.decide(g, N.NetworkTCP, now)
		}
		// the same server for UDP (the servers carry both)
		s.pick[N.NetworkUDP] = s.pick[N.NetworkTCP]
	} else if s.pick[N.NetworkTCP] == "" {
		s.pick[N.NetworkTCP] = ""
	}
}

func (s *smartState) decide(g *URLTestGroup, network string, now time.Time) {
	var best adapter.Outbound
	bestScore := 0.0
	scores := map[string]float64{}
	for _, detour := range g.outbounds {
		if !containsNetwork(detour, network) {
			continue
		}
		sc, ok := s.score(detour.Tag(), now)
		if !ok {
			continue
		}
		scores[detour.Tag()] = sc
		if best == nil || sc < bestScore {
			best, bestScore = detour, sc
		}
	}
	if best == nil {
		return
	}
	cur := s.pick[network]
	curScore, curKnown := scores[cur]
	if cur == "" || !curKnown {
		s.pick[network] = best.Tag()
		s.lastSwitch[network] = now
		s.logger.Warn(fmt.Sprintf("smart[%s]: first choice %s (%.0f ms)", s.name, shortName(best.Tag()), bestScore))
		return
	}
	if best.Tag() == cur {
		s.cand[network] = ""
		s.candRounds[network] = 0
		return
	}
	switchNow := false
	reason := ""
	if s.dead(cur) {
		switchNow = true
		reason = "the server stopped answering"
		s.badUntil[cur] = now.Add(20 * time.Minute)
	} else {
		need := float64(s.opt.gainMs)
		if p := curScore * float64(s.opt.gainPct) / 100; p > need {
			need = p
		}
		cc, bc := countryOf(cur), countryOf(best.Tag())
		if cc != "" && bc != "" && cc != bc {
			if p := curScore * float64(s.opt.countryPct) / 100; p > need {
				need = p
			}
		}
		if curScore-bestScore >= need {
			if s.cand[network] == best.Tag() {
				s.candRounds[network]++
			} else {
				s.cand[network] = best.Tag()
				s.candRounds[network] = 1
			}
			if s.candRounds[network] >= 2 && now.Sub(s.lastSwitch[network]) >= s.opt.dwell {
				switchNow = true
				reason = fmt.Sprintf("better by %.0f ms in two rounds, held %s", curScore-bestScore, now.Sub(s.lastSwitch[network]).Round(time.Second))
			}
		} else {
			s.cand[network] = ""
			s.candRounds[network] = 0
		}
	}
	if !switchNow {
		return
	}
	s.logger.Warn(fmt.Sprintf("smart[%s]: %s (%.0f ms, %s) -> %s (%.0f ms, %s): %s",
		s.name, shortName(cur), curScore, countryOf(cur), shortName(best.Tag()), bestScore, countryOf(best.Tag()), reason))
	s.pick[network] = best.Tag()
	s.lastSwitch[network] = now
	s.cand[network] = ""
	s.candRounds[network] = 0
}

func containsNetwork(o adapter.Outbound, network string) bool {
	for _, n := range o.Network() {
		if n == network {
			return true
		}
	}
	return false
}

// smartSelect is the pick for [network]; until there is one, the first server that carries the network.
func (g *URLTestGroup) smartSelect(network string) (adapter.Outbound, bool) {
	s := g.smart
	s.mu.Lock()
	tag := s.pick[network]
	s.mu.Unlock()
	if tag != "" {
		for _, detour := range g.outbounds {
			if detour.Tag() == tag && containsNetwork(detour, network) {
				return detour, true
			}
		}
	}
	for _, detour := range g.outbounds {
		if containsNetwork(detour, network) {
			return detour, false
		}
	}
	return nil, false
}

// ---- the points and the habits --------------------------------------------------------------------------------

const (
	habitHalfLife = 14 * 24 * time.Hour
	// a few hours are learned before the habit counts for anything
	habitLearned = 1.0
	// the habit gives nothing to a server this much slower than the fastest: a habit must not hold a bad server
	habitSlowGuard = 150.0
	// a country picked by hand counts as this many hours on it
	manualHours = 5.0
)

type habitEntry struct {
	W float64 `json:"w"` // hours, as of T
	T int64   `json:"t"` // unix seconds
}

// habitBook is what the groups have learned of the countries: by group, a weight (hours of use, fading with a half-life
// of two weeks) for each country. Kept in a file, so it outlives the core; the app writes its events (a server picked by
// hand, a reset) into a second file beside it and the core takes them up.
type habitBook struct {
	mu        sync.Mutex
	path      string
	Groups    map[string]map[string]habitEntry `json:"groups"`
	LastEvent int64                            `json:"last_event"`
	dirty     bool
	saved     time.Time
	eventsMod time.Time
}

var (
	booksMu sync.Mutex
	books   = map[string]*habitBook{}
)

func openBook(path string) *habitBook {
	booksMu.Lock()
	defer booksMu.Unlock()
	if b, ok := books[path]; ok {
		return b
	}
	b := &habitBook{path: path, Groups: map[string]map[string]habitEntry{}, saved: time.Now()}
	if raw, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(raw, b)
		if b.Groups == nil {
			b.Groups = map[string]map[string]habitEntry{}
		}
	}
	books[path] = b
	return b
}

func (e habitEntry) at(now time.Time) float64 {
	age := now.Sub(time.Unix(e.T, 0))
	if age <= 0 {
		return e.W
	}
	return e.W * math.Pow(.5, float64(age)/float64(habitHalfLife))
}

func (b *habitBook) add(group, country string, hours float64, now time.Time) {
	if country == "" || hours <= 0 {
		return
	}
	m := b.Groups[group]
	if m == nil {
		m = map[string]habitEntry{}
		b.Groups[group] = m
	}
	e := m[country]
	m[country] = habitEntry{W: e.at(now) + hours, T: now.Unix()}
	b.dirty = true
}

// pref is how much the country is a habit of the group: 1 for the most used, less for the others, 0 when nothing is
// learned yet.
func (b *habitBook) pref(group, country string, now time.Time) float64 {
	m := b.Groups[group]
	if m == nil || country == "" {
		return 0
	}
	top := 0.0
	for _, e := range m {
		if w := e.at(now); w > top {
			top = w
		}
	}
	if top < habitLearned {
		return 0
	}
	return m[country].at(now) / top
}

func (b *habitBook) save(now time.Time, force bool) {
	if !b.dirty || (!force && now.Sub(b.saved) < 3*time.Minute) {
		return
	}
	raw, err := json.Marshal(b)
	if err != nil {
		return
	}
	tmp := b.path + ".tmp"
	if os.WriteFile(tmp, raw, 0o600) == nil && os.Rename(tmp, b.path) == nil {
		b.dirty = false
		b.saved = now
	}
}

type habitEvent struct {
	ID      int64   `json:"id"`
	Group   string  `json:"g"`
	Country string  `json:"c"`
	Hours   float64 `json:"h"`
	Reset   bool    `json:"reset"`
}

// events takes up what the app wrote: the countries picked by hand and the resets.
func (b *habitBook) events(now time.Time) {
	path := filepath.Join(filepath.Dir(b.path), "habit_events.json")
	info, err := os.Stat(path)
	if err != nil || !info.ModTime().After(b.eventsMod) {
		return
	}
	b.eventsMod = info.ModTime()
	raw, err := os.ReadFile(path)
	if err != nil {
		return
	}
	var file struct {
		Events []habitEvent `json:"events"`
	}
	if json.Unmarshal(raw, &file) != nil {
		return
	}
	for _, ev := range file.Events {
		if ev.ID <= b.LastEvent {
			continue
		}
		b.LastEvent = ev.ID
		b.dirty = true
		if ev.Reset {
			b.Groups = map[string]map[string]habitEntry{}
			continue
		}
		h := ev.Hours
		if h <= 0 {
			h = manualHours
		}
		b.add(ev.Group, ev.Country, h, now)
	}
}

// accrue adds the time since the last round to the country the group is on (when the server answers).
func (s *smartState) accrue(now time.Time) {
	last := s.lastAccrue
	s.lastAccrue = now
	if s.book == nil || s.opt.habit <= 0 || last.IsZero() {
		return
	}
	cur := s.pick[N.NetworkTCP]
	if cur == "" || s.dead(cur) {
		return
	}
	dt := now.Sub(last)
	if dt > 10*time.Minute {
		dt = 10 * time.Minute
	}
	s.book.mu.Lock()
	s.book.events(now)
	s.book.add(s.name, countryOf(cur), dt.Hours(), now)
	s.book.save(now, false)
	s.book.mu.Unlock()
}

// pointsOf is what a server has earned (0..100, higher is better), and where the points came from.
type pointsOf struct {
	speed, steady, habit, real, misc, total float64
	median                                  float64
}

func (p pointsOf) String() string {
	return fmt.Sprintf("%.0f pts (speed %.0f, steady %.0f, habit %.0f, real %.0f, other %+.0f; %.0f ms)", p.total, p.speed, p.steady, p.habit, p.real, p.misc, p.median)
}

// medianOf is the median of the answers in a window, the share of losses and the spread; ok false when no answer came.
func medianOf(xs []int) (median, lossShare, jitter float64, ok bool) {
	var good []int
	lost := 0
	for _, v := range xs {
		if v <= 0 {
			lost++
		} else {
			good = append(good, v)
		}
	}
	if len(xs) > 0 {
		lossShare = float64(lost) / float64(len(xs))
	}
	if len(good) == 0 {
		return 5000, lossShare, 0, false
	}
	sorted := append([]int(nil), good...)
	sort.Ints(sorted)
	median = float64(sorted[len(sorted)/2])
	if len(sorted) >= 3 {
		jitter = float64(sorted[len(sorted)-1]-sorted[0]) / 2
	}
	return median, lossShare, jitter, true
}

// points scores a server; [fastest] is the best median among the servers (the habit gives nothing to one far behind it).
func (s *smartState) points(tag string, now time.Time, fastest float64) (pointsOf, bool) {
	xs := s.samples[tag]
	if len(xs) == 0 {
		return pointsOf{}, false
	}
	var p pointsOf
	median, loss, jitter, ok := medianOf(xs)
	p.median = median
	if ok {
		// the speed: the main thing (55 of 100): 40 ms earns 52, 100 ms 38, 200 ms 24, 400 ms 7
		p.speed = 55 / (1 + math.Pow(median/150, 2))
	}
	// the steadiness (20): losses cost most, the spread a little
	p.steady = math.Max(0, 20*(1-math.Min(1, 2*loss))-math.Min(8, jitter/25))
	// the real connections (10): each failure through the server in the last hour takes three
	recent := s.fails[tag][:0]
	for _, t := range s.fails[tag] {
		if now.Sub(t) < time.Hour {
			recent = append(recent, t)
		}
	}
	s.fails[tag] = recent
	p.real = math.Max(0, 10-3*float64(len(recent)))
	// the habit for the country
	if s.book != nil && s.opt.habit > 0 && ok && median-fastest <= habitSlowGuard {
		s.book.mu.Lock()
		pref := s.book.pref(s.name, countryOf(tag), now)
		s.book.mu.Unlock()
		p.habit = float64(s.opt.habit) * pref
	}
	// the rest: a server of another subscription than the main one, little known of it, lately bad
	p.misc -= float64(s.priority.penalty(tag)) / 20
	if len(xs) < 3 {
		p.misc -= 5
	}
	if until, bad := s.badUntil[tag]; bad && until.After(now) {
		p.misc -= 15
	}
	p.total = p.speed + p.steady + p.habit + p.real + p.misc
	return p, true
}

func (s *smartState) decidePoints(g *URLTestGroup, network string, now time.Time) {
	fastest := math.MaxFloat64
	for _, detour := range g.outbounds {
		if !containsNetwork(detour, network) {
			continue
		}
		if m, _, _, ok := medianOf(s.samples[detour.Tag()]); ok && m < fastest {
			fastest = m
		}
	}
	var best adapter.Outbound
	var bestP pointsOf
	scores := map[string]pointsOf{}
	for _, detour := range g.outbounds {
		if !containsNetwork(detour, network) {
			continue
		}
		p, ok := s.points(detour.Tag(), now, fastest)
		if !ok {
			continue
		}
		scores[detour.Tag()] = p
		if best == nil || p.total > bestP.total {
			best, bestP = detour, p
		}
	}
	if best == nil {
		return
	}
	cur := s.pick[network]
	curP, curKnown := scores[cur]
	if cur == "" || !curKnown {
		s.pick[network] = best.Tag()
		s.lastSwitch[network] = now
		s.logger.Warn(fmt.Sprintf("smart[%s]: first choice %s: %s", s.name, shortName(best.Tag()), bestP))
		return
	}
	if best.Tag() == cur {
		s.cand[network] = ""
		s.candRounds[network] = 0
		return
	}
	switchNow := false
	reason := ""
	if s.dead(cur) {
		switchNow = true
		reason = "the server stopped answering"
		s.badUntil[cur] = now.Add(20 * time.Minute)
	} else {
		need := float64(s.opt.gainPts)
		cc, bc := countryOf(cur), countryOf(best.Tag())
		if cc != "" && bc != "" && cc != bc {
			need += float64(s.opt.countryPts)
		}
		if bestP.total-curP.total >= need {
			if s.cand[network] == best.Tag() {
				s.candRounds[network]++
			} else {
				s.cand[network] = best.Tag()
				s.candRounds[network] = 1
			}
			if s.candRounds[network] >= 2 && now.Sub(s.lastSwitch[network]) >= s.opt.dwell {
				switchNow = true
				reason = fmt.Sprintf("ahead by %.0f pts (needed %.0f) in two rounds, held %s", bestP.total-curP.total, need, now.Sub(s.lastSwitch[network]).Round(time.Second))
			}
		} else {
			s.cand[network] = ""
			s.candRounds[network] = 0
		}
	}
	if !switchNow {
		return
	}
	s.logger.Warn(fmt.Sprintf("smart[%s]: %s [%s] -> %s [%s]: %s",
		s.name, shortName(cur), curP, shortName(best.Tag()), bestP, reason))
	s.pick[network] = best.Tag()
	s.lastSwitch[network] = now
	s.cand[network] = ""
	s.candRounds[network] = 0
}
