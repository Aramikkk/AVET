// Package v2rayxhttp is the client side of XHTTP (Xray's "splithttp"): a stream carried by ordinary HTTP requests.
//
// Three ways of carrying it, as in Xray:
//   - packet-up: the download is one long GET (/path/<session>); the upload is a series of POSTs
//     (/path/<session>/<seq>), each a piece of the stream with its number (the server puts them in order). Works over
//     HTTP/1.1, HTTP/2 and HTTP/3.
//   - stream-up: the download is a GET as above, the upload one POST (/path/<session>) whose body is the stream.
//     HTTP/2 and HTTP/3 only.
//   - stream-one: one POST (/path/) whose body is the upload and whose response is the download. HTTP/2 and HTTP/3 only.
//
// The download may come by another way than the upload (another address, TLS settings, host or path: "downloadSettings"),
// and the connections may be rotated by the xmux policy (how many streams one connection carries, how many requests,
// how long it lives). Every request carries "padding" (x_padding, both in the query and in the Referer) of a random
// length in the range the server expects.
package v2rayxhttp

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"io"
	mathrand "math/rand"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/common/tls"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing-box/transport/v2rayhttp"
	E "github.com/sagernet/sing/common/exceptions"
	"github.com/sagernet/sing/common/logger"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"

	"golang.org/x/net/http2"
)

const (
	modePacketUp  = "packet-up"
	modeStreamUp  = "stream-up"
	modeStreamOne = "stream-one"

	defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)

// endpoint is one way to the server: its address, its connections and the request's look.
type endpoint struct {
	serverAddr M.Socksaddr
	pool       *pool
	stream     bool // HTTP/2 or HTTP/3: a request's body can be streamed
	scheme     string
	hostHeader string
	basePath   string
	headers    http.Header
}

type Client struct {
	ctx         context.Context
	up, down    *endpoint
	mode        string
	noGRPC      bool
	padMin      int
	padMax      int
	maxPost     int
	minInterval time.Duration
}

func normalPath(path string) string {
	if i := strings.Index(path, "?"); i >= 0 {
		path = path[:i]
	}
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	if !strings.HasSuffix(path, "/") {
		path += "/"
	}
	return path
}

func newEndpoint(ctx context.Context, dialer N.Dialer, serverAddr M.Socksaddr, host, path string, headers http.Header, tlsConfig tls.Config, mux muxPolicy) (*endpoint, error) {
	e := &endpoint{
		serverAddr: serverAddr,
		scheme:     "http",
		basePath:   normalPath(path),
		hostHeader: host,
		headers:    headers,
	}
	if e.hostHeader == "" {
		e.hostHeader = serverAddr.String()
	}
	var make func() (http.RoundTripper, error)
	if tlsConfig == nil {
		make = func() (http.RoundTripper, error) {
			return &http.Transport{
				DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
					return dialer.DialContext(ctx, network, M.ParseSocksaddr(addr))
				},
				MaxIdleConnsPerHost: 64,
				DisableCompression:  true,
			}, nil
		}
	} else {
		e.scheme = "https"
		if len(tlsConfig.NextProtos()) == 0 {
			tlsConfig.SetNextProtos([]string{http2.NextProtoTLS})
		}
		h2, h3 := false, false
		for _, p := range tlsConfig.NextProtos() {
			switch p {
			case http2.NextProtoTLS:
				h2 = true
			case "h3":
				h3 = true
			}
		}
		switch {
		case h3 && !h2:
			e.stream = true
			make = func() (http.RoundTripper, error) { return newHTTP3Transport(dialer, tlsConfig) }
		case h2:
			e.stream = true
			tlsDialer := tls.NewDialer(dialer, tlsConfig)
			make = func() (http.RoundTripper, error) {
				return &http2.Transport{
					DialTLSContext: func(ctx context.Context, network, addr string, cfg *tls.STDConfig) (net.Conn, error) {
						return tlsDialer.DialTLSContext(adapter.ContextForMultiplexSession(ctx), M.ParseSocksaddr(addr))
					},
				}, nil
			}
		default:
			tlsDialer := tls.NewDialer(dialer, tlsConfig)
			make = func() (http.RoundTripper, error) {
				return &http.Transport{
					DialTLSContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
						return tlsDialer.DialTLSContext(ctx, M.ParseSocksaddr(addr))
					},
					MaxIdleConnsPerHost: 64,
					DisableCompression:  true,
				}, nil
			}
		}
	}
	// HTTP/1.1 keeps its own pool of connections; the multiplexed ones are rotated by the policy
	e.pool = newPool(make, mux, e.stream)
	return e, nil
}

func NewClient(ctx context.Context, dialer N.Dialer, serverAddr M.Socksaddr, options option.V2RayXHTTPOptions, tlsConfig tls.Config) (adapter.V2RayClientTransport, error) {
	c := &Client{ctx: ctx, noGRPC: options.NoGRPCHeader}
	c.padMin, c.padMax = parseRange(options.XPaddingBytes, 100, 1000)
	c.maxPost = options.ScMaxEachPostBytes
	if c.maxPost <= 0 {
		c.maxPost = 1000000
	}
	c.minInterval = 30 * time.Millisecond
	if options.ScMinPostsIntervalMs > 0 {
		c.minInterval = time.Duration(options.ScMinPostsIntervalMs) * time.Millisecond
	}
	mux := newMuxPolicy(options.XMux)
	var err error
	c.up, err = newEndpoint(ctx, dialer, serverAddr, options.Host, options.Path, options.Headers.Build(), tlsConfig, mux)
	if err != nil {
		return nil, err
	}
	c.down = c.up
	if d := options.Download; d != nil && d.Server != "" {
		downAddr := M.ParseSocksaddrHostPort(d.Server, d.ServerPort)
		if d.ServerPort == 0 {
			downAddr = M.ParseSocksaddrHostPort(d.Server, 443)
		}
		var downTLS tls.Config
		if d.TLS != nil && d.TLS.Enabled {
			downTLS, err = tls.NewClient(ctx, logger.NOP(), d.Server, *d.TLS)
			if err != nil {
				return nil, E.Cause(err, "xhttp download tls")
			}
		}
		path, host := d.Path, d.Host
		if path == "" {
			path = options.Path
		}
		headers := c.up.headers
		if len(d.Headers) > 0 {
			headers = d.Headers.Build()
		}
		c.down, err = newEndpoint(ctx, dialer, downAddr, host, path, headers, downTLS, mux)
		if err != nil {
			return nil, err
		}
	}
	// the way the stream is carried: the streaming ones need HTTP/2 (or 3); with the download on another way the
	// upload and the download are separate requests whatever the mode
	split := c.down != c.up
	switch strings.ToLower(options.Mode) {
	case modePacketUp:
		c.mode = modePacketUp
	case modeStreamUp:
		c.mode = modeStreamUp
	case modeStreamOne:
		c.mode = modeStreamOne
	default:
		if c.up.stream {
			c.mode = modeStreamOne
		} else {
			c.mode = modePacketUp
		}
	}
	if split && c.mode == modeStreamOne {
		c.mode = modeStreamUp
	}
	if !c.up.stream && c.mode != modePacketUp {
		c.mode = modePacketUp
	}
	if c.mode == modeStreamUp && !c.up.stream {
		c.mode = modePacketUp
	}
	return c, nil
}

func parseRange(s string, defMin, defMax int) (int, int) {
	s = strings.TrimSpace(s)
	if s == "" {
		return defMin, defMax
	}
	lo, hi := s, s
	if i := strings.Index(s, "-"); i > 0 {
		lo, hi = s[:i], s[i+1:]
	}
	a, err1 := strconv.Atoi(strings.TrimSpace(lo))
	b, err2 := strconv.Atoi(strings.TrimSpace(hi))
	if err1 != nil || err2 != nil || a < 0 || b < a {
		return defMin, defMax
	}
	return a, b
}

func (c *Client) padding() string {
	n := c.padMin
	if c.padMax > c.padMin {
		n += mathrand.Intn(c.padMax - c.padMin + 1)
	}
	return strings.Repeat("X", n)
}

func newSessionID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	h := hex.EncodeToString(b)
	return h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:32]
}

func (c *Client) newRequest(ctx context.Context, e *endpoint, method, path string, body io.Reader) (*http.Request, error) {
	pad := c.padding()
	u := url.URL{Scheme: e.scheme, Host: e.serverAddr.String(), Path: path, RawQuery: "x_padding=" + pad}
	req, err := http.NewRequestWithContext(ctx, method, u.String(), body)
	if err != nil {
		return nil, err
	}
	req.Host = e.hostHeader
	req.Header = e.headers.Clone()
	if req.Header.Get("Referer") == "" {
		ref := url.URL{Scheme: e.scheme, Host: e.hostHeader, Path: path, RawQuery: "x_padding=" + pad}
		req.Header.Set("Referer", ref.String())
	}
	if req.Header.Get("User-Agent") == "" {
		req.Header.Set("User-Agent", defaultUserAgent)
	}
	return req, nil
}

func (c *Client) DialContext(ctx context.Context) (net.Conn, error) {
	switch c.mode {
	case modeStreamOne:
		return c.dialStreamOne(ctx)
	case modeStreamUp:
		return c.dialSplit(ctx, false)
	default:
		return c.dialSplit(ctx, true)
	}
}

// dialStreamOne: one POST, the upload in its body, the download in its response.
func (c *Client) dialStreamOne(ctx context.Context) (net.Conn, error) {
	pr, pw := io.Pipe()
	reqCtx, cancel := context.WithCancel(context.WithoutCancel(ctx))
	req, err := c.newRequest(reqCtx, c.up, http.MethodPost, c.up.basePath, pr)
	if err != nil {
		cancel()
		return nil, err
	}
	if !c.noGRPC {
		req.Header.Set("Content-Type", "application/grpc")
	}
	conn := v2rayhttp.NewLateHTTPConn(pw, cancel)
	go func() {
		resp, err := c.up.pool.roundTrip(req)
		if err != nil {
			conn.Setup(nil, err)
			return
		}
		if resp.StatusCode != http.StatusOK {
			resp.Body.Close()
			conn.Setup(nil, E.New("xhttp: unexpected status: ", resp.Status))
			return
		}
		conn.Setup(resp.Body, nil)
	}()
	return conn, nil
}

// dialSplit: the download is a GET of the session; the upload is POSTs of pieces (packetUp) or one POST streamed.
func (c *Client) dialSplit(ctx context.Context, packetUp bool) (net.Conn, error) {
	session := newSessionID()
	reqCtx, cancel := context.WithCancel(context.WithoutCancel(ctx))
	get, err := c.newRequest(reqCtx, c.down, http.MethodGet, c.down.basePath+session, nil)
	if err != nil {
		cancel()
		return nil, err
	}
	var writer io.WriteCloser
	if packetUp {
		writer = newPacketWriter(c, reqCtx, cancel, session)
	} else {
		pr, pw := io.Pipe()
		post, err := c.newRequest(reqCtx, c.up, http.MethodPost, c.up.basePath+session, pr)
		if err != nil {
			cancel()
			return nil, err
		}
		if !c.noGRPC {
			post.Header.Set("Content-Type", "application/grpc")
		}
		writer = pw
		go func() {
			resp, err := c.up.pool.roundTrip(post)
			if err != nil {
				pw.CloseWithError(err)
				cancel()
				return
			}
			// the response lasts as long as the upload does (the server may send keep-alive padding in it)
			_, _ = io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
		}()
	}
	conn := v2rayhttp.NewLateHTTPConn(writer, cancel)
	go func() {
		resp, err := c.down.pool.roundTrip(get)
		if err != nil {
			conn.Setup(nil, err)
			return
		}
		if resp.StatusCode != http.StatusOK {
			resp.Body.Close()
			conn.Setup(nil, E.New("xhttp: unexpected status: ", resp.Status))
			return
		}
		conn.Setup(resp.Body, nil)
	}()
	return conn, nil
}

func (c *Client) Close() error {
	c.up.pool.close()
	if c.down != c.up {
		c.down.pool.close()
	}
	return nil
}

// ---- the connections and their rotation (xmux)

// muxPolicy is Xray's xmux: a connection takes up to maxConcurrency streams at once and hMaxRequestTimes requests in
// all, and lives hMaxReusableSecs; with more than maxConnections of them the least busy is used. Zero is "no limit".
type muxPolicy struct {
	maxConcurrency   int
	maxConnections   int
	maxRequests      int
	maxReusableSecs  int
}

func newMuxPolicy(o *option.V2RayXHTTPMux) muxPolicy {
	var m muxPolicy
	if o == nil {
		return m
	}
	pick := func(s string) int {
		_, hi := parseRange(s, 0, 0)
		return hi
	}
	m.maxConcurrency = pick(o.MaxConcurrency)
	m.maxConnections = pick(o.MaxConnections)
	m.maxRequests = pick(o.HMaxRequestTimes)
	m.maxReusableSecs = pick(o.HMaxReusableSecs)
	return m
}

type conn struct {
	rt       http.RoundTripper
	created  time.Time
	requests atomic.Int64
	inflight atomic.Int64
}

type pool struct {
	make   func() (http.RoundTripper, error)
	policy muxPolicy
	multi  bool // a multiplexed transport (HTTP/2, HTTP/3): one connection carries many streams

	mu    sync.Mutex
	conns []*conn
}

func newPool(make func() (http.RoundTripper, error), policy muxPolicy, multi bool) *pool {
	return &pool{make: make, policy: policy, multi: multi}
}

func (p *pool) usable(c *conn) bool {
	if p.policy.maxRequests > 0 && c.requests.Load() >= int64(p.policy.maxRequests) {
		return false
	}
	if p.policy.maxReusableSecs > 0 && time.Since(c.created) > time.Duration(p.policy.maxReusableSecs)*time.Second {
		return false
	}
	return true
}

func (p *pool) pick() (*conn, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	// the ones that have run their course are dropped (they close when their streams are done)
	live := p.conns[:0]
	for _, c := range p.conns {
		if p.usable(c) || c.inflight.Load() > 0 {
			live = append(live, c)
		} else if closer, ok := c.rt.(interface{ CloseIdleConnections() }); ok {
			closer.CloseIdleConnections()
		}
	}
	p.conns = live
	var least, roomy *conn
	for _, c := range p.conns {
		if !p.usable(c) {
			continue
		}
		if least == nil || c.inflight.Load() < least.inflight.Load() {
			least = c
		}
		if p.policy.maxConcurrency > 0 && c.inflight.Load() >= int64(p.policy.maxConcurrency) {
			continue
		}
		if roomy == nil || c.inflight.Load() < roomy.inflight.Load() {
			roomy = c
		}
	}
	if roomy != nil {
		return roomy, nil
	}
	// no connection with room: a new one while the policy lets, else the least busy
	if least == nil || p.policy.maxConnections == 0 || len(p.conns) < p.policy.maxConnections {
		rt, err := p.make()
		if err != nil {
			return nil, err
		}
		c := &conn{rt: rt, created: time.Now()}
		p.conns = append(p.conns, c)
		return c, nil
	}
	return least, nil
}

func (p *pool) roundTrip(req *http.Request) (*http.Response, error) {
	c, err := p.pick()
	if err != nil {
		return nil, err
	}
	c.requests.Add(1)
	c.inflight.Add(1)
	resp, err := c.rt.RoundTrip(req)
	if err != nil {
		c.inflight.Add(-1)
		return nil, err
	}
	resp.Body = &countedBody{ReadCloser: resp.Body, done: func() { c.inflight.Add(-1) }}
	return resp, nil
}

// countedBody tells the pool when a stream ends (its body is closed).
type countedBody struct {
	io.ReadCloser
	once sync.Once
	done func()
}

func (b *countedBody) Close() error {
	b.once.Do(b.done)
	return b.ReadCloser.Close()
}

func (p *pool) close() {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, c := range p.conns {
		if closer, ok := c.rt.(interface{ CloseIdleConnections() }); ok {
			closer.CloseIdleConnections()
		}
	}
	p.conns = nil
}

// ---- the upload of packet-up

// packetWriter sends what is written as numbered POSTs: what comes in while the last one is out (and for the least
// interval between two) is put together into the next, up to the largest piece.
type packetWriter struct {
	client  *Client
	ctx     context.Context
	cancel  context.CancelFunc
	session string

	mu     sync.Mutex
	cond   *sync.Cond
	buf    []byte
	closed bool
	err    error

	seq      uint64
	inflight chan struct{}
}

func newPacketWriter(c *Client, ctx context.Context, cancel context.CancelFunc, session string) *packetWriter {
	w := &packetWriter{client: c, ctx: ctx, cancel: cancel, session: session, inflight: make(chan struct{}, 4)}
	w.cond = sync.NewCond(&w.mu)
	go w.run()
	return w
}

func (w *packetWriter) Write(b []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	// the buffer is kept from growing without end: the writer waits while a lot is not yet sent
	for len(w.buf) > 4*w.client.maxPost && !w.closed && w.err == nil {
		w.cond.Wait()
	}
	if w.err != nil {
		return 0, w.err
	}
	if w.closed {
		return 0, io.ErrClosedPipe
	}
	w.buf = append(w.buf, b...)
	w.cond.Broadcast()
	return len(b), nil
}

func (w *packetWriter) Close() error {
	w.mu.Lock()
	w.closed = true
	w.cond.Broadcast()
	w.mu.Unlock()
	return nil
}

func (w *packetWriter) fail(err error) {
	w.mu.Lock()
	if w.err == nil {
		w.err = err
	}
	w.cond.Broadcast()
	w.mu.Unlock()
	w.cancel()
}

func (w *packetWriter) run() {
	var last time.Time
	for {
		w.mu.Lock()
		for len(w.buf) == 0 && !w.closed && w.err == nil {
			w.cond.Wait()
		}
		if w.err != nil || (w.closed && len(w.buf) == 0) {
			w.mu.Unlock()
			return
		}
		w.mu.Unlock()
		// pieces go no closer together than the interval: what is written meanwhile joins the next piece
		if wait := w.client.minInterval - time.Since(last); !last.IsZero() && wait > 0 {
			select {
			case <-time.After(wait):
			case <-w.ctx.Done():
				return
			}
		}
		w.mu.Lock()
		n := len(w.buf)
		if n > w.client.maxPost {
			n = w.client.maxPost
		}
		piece := make([]byte, n)
		copy(piece, w.buf[:n])
		w.buf = w.buf[n:]
		if len(w.buf) == 0 {
			w.buf = nil
		}
		seq := w.seq
		w.seq++
		w.cond.Broadcast()
		w.mu.Unlock()
		select {
		case w.inflight <- struct{}{}:
		case <-w.ctx.Done():
			return
		}
		last = time.Now()
		go func() {
			defer func() { <-w.inflight }()
			if err := w.post(seq, piece); err != nil {
				w.fail(err)
			}
		}()
	}
}

func (w *packetWriter) post(seq uint64, piece []byte) error {
	e := w.client.up
	req, err := w.client.newRequest(w.ctx, e, http.MethodPost, e.basePath+w.session+"/"+strconv.FormatUint(seq, 10), bytes.NewReader(piece))
	if err != nil {
		return err
	}
	req.ContentLength = int64(len(piece))
	resp, err := e.pool.roundTrip(req)
	if err != nil {
		return err
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return E.New("xhttp: upload refused: ", resp.Status)
	}
	return nil
}
