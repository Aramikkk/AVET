# Adds the XHTTP transport (Xray's "splithttp") to the copy of sing-box: its options, its type and the client.
# Run by patch-singbox.sh from core/.
import io
import os
import shutil


def read(p):
    return io.open(p, encoding="utf8").read()


def write(p, s):
    io.open(p, "w", encoding="utf8", newline="\n").write(s)


def rep(s, a, b):
    assert a in s, a[:80]
    return s.replace(a, b, 1)


root = "patched/sing-box/"

# the type
p = root + "constant/v2ray.go"
s = read(p)
s = rep(s, '\tV2RayTransportTypeHTTPUpgrade = "httpupgrade"\n', '\tV2RayTransportTypeHTTPUpgrade = "httpupgrade"\n\tV2RayTransportTypeXHTTP       = "xhttp"\n')
write(p, s)

# the options
p = root + "option/v2ray_transport.go"
s = read(p)
s = rep(s, 'enum:"http,ws,quic,grpc,httpupgrade"', 'enum:"http,ws,quic,grpc,httpupgrade,xhttp"')
s = rep(s, "\tHTTPUpgradeOptions V2RayHTTPUpgradeOptions `json:\"-\"`\n}", "\tHTTPUpgradeOptions V2RayHTTPUpgradeOptions `json:\"-\"`\n\tXHTTPOptions       V2RayXHTTPOptions       `json:\"-\"`\n}")
s = rep(s, "\tcase C.V2RayTransportTypeHTTPUpgrade:\n\t\tv = o.HTTPUpgradeOptions\n", "\tcase C.V2RayTransportTypeHTTPUpgrade:\n\t\tv = o.HTTPUpgradeOptions\n\tcase C.V2RayTransportTypeXHTTP:\n\t\tv = o.XHTTPOptions\n")
s = rep(s, "\tcase C.V2RayTransportTypeHTTPUpgrade:\n\t\tv = &o.HTTPUpgradeOptions\n", "\tcase C.V2RayTransportTypeHTTPUpgrade:\n\t\tv = &o.HTTPUpgradeOptions\n\tcase C.V2RayTransportTypeXHTTP:\n\t\tv = &o.XHTTPOptions\n")
s = rep(s, "\t\t\t{Value: C.V2RayTransportTypeHTTPUpgrade, StructType: reflect.TypeFor[V2RayHTTPUpgradeOptions]()},\n", "\t\t\t{Value: C.V2RayTransportTypeHTTPUpgrade, StructType: reflect.TypeFor[V2RayHTTPUpgradeOptions]()},\n\t\t\t{Value: C.V2RayTransportTypeXHTTP, StructType: reflect.TypeFor[V2RayXHTTPOptions]()},\n")
s += '''
// V2RayXHTTPOptions are the options of the XHTTP transport (client side). The ranges are text ("100-1000").
type V2RayXHTTPOptions struct {
	Host                 string               `json:"host,omitempty"`
	Path                 string               `json:"path,omitempty"`
	Mode                 string               `json:"mode,omitempty"`
	Headers              badoption.HTTPHeader `json:"headers,omitempty"`
	XPaddingBytes        string               `json:"x_padding_bytes,omitempty"`
	NoGRPCHeader         bool                 `json:"no_grpc_header,omitempty"`
	ScMaxEachPostBytes   int                  `json:"sc_max_each_post_bytes,omitempty"`
	ScMinPostsIntervalMs int                  `json:"sc_min_posts_interval_ms,omitempty"`
	XMux                 *V2RayXHTTPMux       `json:"xmux,omitempty"`
	Download             *V2RayXHTTPDownload  `json:"download,omitempty"`
}

// V2RayXHTTPMux is Xray's xmux (how the connections are used and renewed); the values are numbers or "from-to" ranges.
type V2RayXHTTPMux struct {
	MaxConcurrency   string `json:"max_concurrency,omitempty"`
	MaxConnections   string `json:"max_connections,omitempty"`
	CMaxReuseTimes   string `json:"c_max_reuse_times,omitempty"`
	HMaxRequestTimes string `json:"h_max_request_times,omitempty"`
	HMaxReusableSecs string `json:"h_max_reusable_secs,omitempty"`
}

// V2RayXHTTPDownload is Xray's downloadSettings: the download goes another way than the upload (another address,
// its own TLS or REALITY settings, host and path).
type V2RayXHTTPDownload struct {
	Server     string               `json:"server,omitempty"`
	ServerPort uint16               `json:"server_port,omitempty"`
	Host       string               `json:"host,omitempty"`
	Path       string               `json:"path,omitempty"`
	Headers    badoption.HTTPHeader `json:"headers,omitempty"`
	TLS        *OutboundTLSOptions  `json:"tls,omitempty"`
}
'''
write(p, s)

# the client
p = root + "transport/v2ray/transport.go"
s = read(p)
s = rep(s, '\t"github.com/sagernet/sing-box/transport/v2raywebsocket"\n', '\t"github.com/sagernet/sing-box/transport/v2raywebsocket"\n\t"github.com/sagernet/sing-box/transport/v2rayxhttp"\n')
s = rep(s, "\t\treturn v2rayhttpupgrade.NewClient(ctx, dialer, serverAddr, options.HTTPUpgradeOptions, tlsConfig)\n", "\t\treturn v2rayhttpupgrade.NewClient(ctx, dialer, serverAddr, options.HTTPUpgradeOptions, tlsConfig)\n\tcase C.V2RayTransportTypeXHTTP:\n\t\treturn v2rayxhttp.NewClient(ctx, dialer, serverAddr, options.XHTTPOptions, tlsConfig)\n")
write(p, s)

os.makedirs(root + "transport/v2rayxhttp", exist_ok=True)
for f in ("client.go", "h3.go", "h3_stub.go"):
    shutil.copy("xhttp/" + f, root + "transport/v2rayxhttp/" + f)
print("xhttp ok")
