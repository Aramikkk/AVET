import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The name Yandex's DNS answers under for DNS over TLS (port 853), or null for a server that speaks DNS over HTTPS.
/// Yandex has no DNS over HTTPS: asked that way it only closes the connection, which is why it never worked.
String? dotName(String ip) =>
    ip.startsWith('77.88.8.') ? 'common.dot.dns.yandex.net' : null;

/// The DNS servers the app can use (DNS over HTTPS, asked by address; Yandex over TLS): the order is kept, a stored choice is the index.
const dnsServers = <({String name, String ip})>[
  (name: 'Google', ip: '8.8.8.8'),
  (name: 'Cloudflare', ip: '1.1.1.1'),
  (name: 'Яндекс', ip: '77.88.8.8'),
  (name: 'AdGuard', ip: '94.140.14.14'),
  (name: 'OpenDNS', ip: '208.67.222.222'),
  (name: 'Google (запасной)', ip: '8.8.4.4'),
  (name: 'Cloudflare (запасной)', ip: '1.0.0.1'),
];

/// A DNS query for the name "example.com" (type A), as DNS over HTTPS takes it in the `dns` parameter.
String _query() {
  final b = BytesBuilder()
    ..add([
      0x12,
      0x34,
      0x01,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ])
    ..add([7, ...'example'.codeUnits, 3, ...'com'.codeUnits, 0])
    ..add([0x00, 0x01, 0x00, 0x01]);
  return base64Url.encode(b.toBytes()).replaceAll('=', '');
}

/// How long the DNS server at [ip] takes to answer, in ms (the median of three answers over a connection already open:
/// the way there and back, not the handshake); null: it did not answer.
Future<int?> probeDns(String ip) async {
  final dot = dotName(ip);
  if (dot != null) return _probeDot(ip, dot);
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..findProxy = ((_) => 'DIRECT');
  Future<int?> once() async {
    final watch = Stopwatch()..start();
    final req = await client
        .getUrl(Uri.parse('https://$ip/dns-query?dns=${_query()}'))
        .timeout(const Duration(seconds: 3));
    req.headers.set('accept', 'application/dns-message');
    final res = await req.close().timeout(const Duration(seconds: 3));
    final body = await res.fold<int>(0, (n, c) => n + c.length);
    // a real answer: 200 with a DNS message in it
    return res.statusCode == 200 && body >= 12
        ? watch.elapsedMilliseconds
        : null;
  }

  try {
    // the first request opens the connection (its handshakes): not an answer
    try {
      await once();
    } catch (_) {}
    final times = <int>[];
    for (var i = 0; i < 3; i++) {
      try {
        final t = await once();
        if (t != null) times.add(t);
      } catch (_) {}
    }
    if (times.isEmpty) return null;
    times.sort();
    return times[times.length ~/ 2];
  } finally {
    client.close(force: true);
  }
}

/// The same measure for a server that speaks DNS over TLS: the way there and back of a query over a connection already
/// open (the median of three), asked on port 853 with the server's own name.
Future<int?> _probeDot(String ip, String name) async {
  SecureSocket? socket;
  try {
    final plain = await Socket.connect(
      ip,
      853,
      timeout: const Duration(seconds: 3),
    );
    socket = await SecureSocket.secure(
      plain,
      host: name,
      onBadCertificate: (_) => true,
    ).timeout(const Duration(seconds: 3));
    final queue = StreamIterator<List<int>>(socket);
    final message = _rawQuery();
    final framed = Uint8List.fromList([
      message.length >> 8,
      message.length & 255,
      ...message,
    ]);
    Future<int?> once() async {
      final watch = Stopwatch()..start();
      socket!.add(framed);
      await socket.flush();
      final got = <int>[];
      while (got.length < 2 ||
          got.length < 2 + ((got[0] << 8) | got[1]) && got.length < 4096) {
        if (!await queue.moveNext().timeout(const Duration(seconds: 3))) {
          return null;
        }
        got.addAll(queue.current);
      }
      return got.length >= 14 ? watch.elapsedMilliseconds : null;
    }

    try {
      await once();
    } catch (_) {}
    final times = <int>[];
    for (var i = 0; i < 3; i++) {
      try {
        final t = await once();
        if (t != null) times.add(t);
      } catch (_) {}
    }
    if (times.isEmpty) return null;
    times.sort();
    return times[times.length ~/ 2];
  } catch (_) {
    return null;
  } finally {
    socket?.destroy();
  }
}

/// A DNS query for "example.com" (type A) as bytes.
Uint8List _rawQuery() => Uint8List.fromList([
  0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
  7, ...'example'.codeUnits, 3, ...'com'.codeUnits, 0,
  0x00, 0x01, 0x00, 0x01,
]);
