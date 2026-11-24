# The URL test timeout of a group as an option (`test_timeout`): how long one server's test may take before the server counts as
# unreachable. Stock sing-box has 15 s for every group and a client timeout of its own; on a slow mobile network (a car's
# modem) that is too short. Run by patch-singbox.sh from core/ (after smart/apply.py).
import io


def read(p):
    return io.open(p, encoding="utf8").read()


def write(p, s):
    io.open(p, "w", encoding="utf8", newline="\n").write(s)


def rep(s, a, b):
    assert a in s, a[:80]
    return s.replace(a, b, 1)


root = "patched/sing-box/"

p = root + "option/group.go"
s = read(p)
s = rep(s, '\tSmartWarm                 badoption.Duration `json:"smart_warm,omitempty"`\n', '\tSmartWarm                 badoption.Duration `json:"smart_warm,omitempty"`\n\tTestTimeout               badoption.Duration `json:"test_timeout,omitempty"`\n')
write(p, s)

p = root + "protocol/group/urltest.go"
s = read(p)
# the option reaches the group
s = rep(s, "\tinterruptExternalConnections bool\n\tsmart                        *smartOptions\n\tpriority                     *priorityOptions\n}\n\nfunc NewURLTest(", "\tinterruptExternalConnections bool\n\tsmart                        *smartOptions\n\tpriority                     *priorityOptions\n\ttestTimeout                  time.Duration\n}\n\nfunc NewURLTest(")
s = rep(s, "\t\tinterruptExternalConnections: options.InterruptExistConnections,\n\t}\n\tif options.Smart || options.SmartActive > 0 {", "\t\tinterruptExternalConnections: options.InterruptExistConnections,\n\t\ttestTimeout:                  time.Duration(options.TestTimeout),\n\t}\n\tif options.Smart || options.SmartActive > 0 {")
s = rep(s, "\t\ts.group = group\n\t\tgroup.priority = s.priority\n", "\t\ts.group = group\n\t\tgroup.priority = s.priority\n\t\tgroup.testTimeout = s.testTimeout\n")
s = rep(s, "\tsmart                        *smartState\n\tpriority                     *priorityOptions\n}\n\nfunc NewURLTestGroup(", "\tsmart                        *smartState\n\tpriority                     *priorityOptions\n\ttestTimeout                  time.Duration\n}\n\n// timeout is how long one test of one server may take.\nfunc (g *URLTestGroup) timeout() time.Duration {\n\tif g.testTimeout > 0 {\n\t\treturn g.testTimeout\n\t}\n\treturn C.TCPTimeout\n}\n\nfunc NewURLTestGroup(")
s = rep(s, "testCtx, cancel := context.WithTimeout(b.ctx, C.TCPTimeout)", "testCtx, cancel := context.WithTimeout(b.ctx, b.testTimeout)")
# the timeout of the group travels to the batch in the context
s = rep(s, "\taccess   sync.Mutex\n\tresult   map[string]uint16\n}\n", "\taccess   sync.Mutex\n\tresult   map[string]uint16\n\ttestTimeout time.Duration\n}\n\ntype testTimeoutKey struct{}\n")
s = rep(s, "\tb, _ := batch.New(ctx, batch.WithConcurrencyNum[any](10))\n\ttestBatch := &urlTestBatch{\n", "\tb, _ := batch.New(ctx, batch.WithConcurrencyNum[any](10))\n\ttimeout := C.TCPTimeout\n\tif d, ok := ctx.Value(testTimeoutKey{}).(time.Duration); ok && d > 0 {\n\t\ttimeout = d\n\t}\n\ttestBatch := &urlTestBatch{\n\t\ttestTimeout: timeout,\n")
s = rep(s, "result := URLTestOutbounds(ctx, g.outbound, g.history, g.logger, targets, g.link, g.interval, force)", "result := URLTestOutbounds(context.WithValue(ctx, testTimeoutKey{}, g.timeout()), g.outbound, g.history, g.logger, targets, g.link, g.interval, force)")
write(p, s)

# the test itself is bounded by its context (the group's timeout), not by a client timeout of 15 s of its own; a test
# started without a deadline keeps the old one
p = root + "common/urltest/urltest.go"
s = read(p)
s = rep(s, "\t\tTimeout: C.TCPTimeout,\n\t}\n\tdefer client.CloseIdleConnections()", "\t}\n\tdefer client.CloseIdleConnections()")
s = rep(s, "func urlTest(ctx context.Context, link string, detour N.Dialer) (t uint16, err error) {\n", "func urlTest(ctx context.Context, link string, detour N.Dialer) (t uint16, err error) {\n\tif _, has := ctx.Deadline(); !has {\n\t\tvar cancel context.CancelFunc\n\t\tctx, cancel = context.WithTimeout(ctx, C.TCPTimeout)\n\t\tdefer cancel()\n\t}\n")
write(p, s)
print("timeout ok")
