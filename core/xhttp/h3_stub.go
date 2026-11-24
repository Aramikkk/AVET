//go:build !with_quic

package v2rayxhttp

import (
	"net/http"

	"github.com/sagernet/sing-box/common/tls"
	E "github.com/sagernet/sing/common/exceptions"
	N "github.com/sagernet/sing/common/network"
)

func newHTTP3Transport(dialer N.Dialer, base tls.Config) (http.RoundTripper, error) {
	return nil, E.New("xhttp over HTTP/3 needs a build with QUIC")
}
