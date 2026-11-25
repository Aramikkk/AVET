# TCP ping before the URL test (as v2rayNG does): a server whose port does not even take a TCP connection (dialed
# directly, past the tunnel) is marked unreachable at once, without the full test through it. The app gives the
# addresses of the servers to check this way (`tcp_ping` of an urltest group: tag -> host:port; only TCP-based servers
# without a detour). A connection that opens goes on to the URL test as before. Run by patch-singbox.sh from core/.
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
s = rep(s, '\tTestTimeout               badoption.Duration `json:"test_timeout,omitempty"`\n',
        '\tTestTimeout               badoption.Duration `json:"test_timeout,omitempty"`\n\tTCPPing                   map[string]string  `json:"tcp_ping,omitempty"`\n')
write(p, s)

p = root + "protocol/group/urltest.go"
s = read(p)
s = rep(s, "\t\ttestTimeout:                  time.Duration(options.TestTimeout),\n\t}\n",
        "\t\ttestTimeout:                  time.Duration(options.TestTimeout),\n\t}\n\tsetTCPPing(outbound.outbound, options.TCPPing)\n")
s = rep(s, "\t\t\t\ttestChan := make(chan urlTestResult, 1)\n\t\t\t\tgo func() {\n",
        "\t\t\t\tif pingErr := tcpPing(testCtx, tag); pingErr != nil {\n"
        "\t\t\t\t\tif b.ctx.Err() != nil {\n\t\t\t\t\t\treturn nil, nil\n\t\t\t\t\t}\n"
        "\t\t\t\t\tb.logger.Debug(\"outbound \", tag, \" unavailable (tcp ping): \", pingErr)\n"
        "\t\t\t\t\tb.history.DeleteURLTestHistory(tag)\n\t\t\t\t\treturn nil, nil\n\t\t\t\t}\n"
        "\t\t\t\ttestChan := make(chan urlTestResult, 1)\n\t\t\t\tgo func() {\n")
write(p, s)

write(root + "protocol/group/tcpping.go", '''package group

import (
	"context"
	"sync"
	"time"

	"github.com/sagernet/sing-box/adapter"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

// how long a server's port may take to accept a TCP connection before the server counts as unreachable
const tcpPingTimeout = 3 * time.Second

var (
	tcpPingAccess  sync.RWMutex
	tcpPingTargets = map[string]M.Socksaddr{}
	tcpPingManager adapter.OutboundManager
)

func setTCPPing(manager adapter.OutboundManager, targets map[string]string) {
	if len(targets) == 0 {
		return
	}
	tcpPingAccess.Lock()
	defer tcpPingAccess.Unlock()
	tcpPingManager = manager
	for tag, address := range targets {
		destination := M.ParseSocksaddr(address)
		if destination.IsValid() && destination.Port != 0 {
			tcpPingTargets[tag] = destination
		}
	}
}

// tcpPing opens a TCP connection to the server of [tag] through the direct outbound; nil when it opens or when the
// server is not one to check this way.
func tcpPing(ctx context.Context, tag string) error {
	tcpPingAccess.RLock()
	destination, ok := tcpPingTargets[tag]
	manager := tcpPingManager
	tcpPingAccess.RUnlock()
	if !ok || manager == nil {
		return nil
	}
	direct, ok := manager.Outbound("direct")
	if !ok {
		return nil
	}
	pingCtx, cancel := context.WithTimeout(ctx, tcpPingTimeout)
	defer cancel()
	conn, err := direct.DialContext(pingCtx, N.NetworkTCP, destination)
	if err != nil {
		return err
	}
	return conn.Close()
}
''')
print("tcpping patched")
