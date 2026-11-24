//go:build with_quic

package v2rayxhttp

import (
	"context"
	stdTLS "crypto/tls"
	"net/http"
	"time"

	"github.com/sagernet/quic-go"
	"github.com/sagernet/quic-go/http3"
	"github.com/sagernet/sing-box/common/tls"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

// newHTTP3Transport carries the requests over QUIC (HTTP/3): the packets go through the outbound's dialer as UDP.
func newHTTP3Transport(dialer N.Dialer, base tls.Config) (http.RoundTripper, error) {
	quicConfig := &quic.Config{
		KeepAlivePeriod: 10 * time.Second,
		MaxIdleTimeout:  60 * time.Second,
	}
	if timeout := base.HandshakeTimeout(); timeout > 0 {
		quicConfig.HandshakeIdleTimeout = timeout
	}
	return &http3.Transport{
		TLSClientConfig: &stdTLS.Config{},
		QUICConfig:      quicConfig,
		Dial: func(ctx context.Context, addr string, _ *stdTLS.Config, quicConfig *quic.Config) (*quic.Conn, error) {
			config := base.Clone()
			destination := M.ParseSocksaddr(addr)
			if config.ServerName() == "" && destination.IsValid() {
				config.SetServerName(destination.AddrString())
			}
			config.SetNextProtos([]string{http3.NextProtoH3})
			std, err := config.STDConfig()
			if err != nil {
				return nil, err
			}
			conn, err := dialer.DialContext(ctx, N.NetworkUDP, destination)
			if err != nil {
				return nil, err
			}
			quicConn, err := quic.DialEarlyConn(ctx, conn, std, quicConfig)
			if err != nil {
				conn.Close()
				return nil, err
			}
			go func() {
				<-quicConn.Context().Done()
				conn.Close()
			}()
			return quicConn, nil
		},
	}, nil
}
