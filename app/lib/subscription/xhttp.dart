import 'dart:convert';

/// The `transport` block of an XHTTP server (Xray's "xhttp", once "splithttp"): the path, the host, the mode
/// (auto, packet-up, stream-up, stream-one) and the few settings of Xray's `extra` the core uses. [extra] is what a
/// share link carries in `extra=` (a JSON text) or an Xray config in its xhttp settings (a map); the keys of the
/// settings themselves (host, path, mode, headers) are read from it as well, but what came as separate parameters wins.
Map<String, Object?> xhttpTransport({
  String host = '',
  String path = '',
  String mode = '',
  Object? extra,
  Map<String, Object?>? Function(Object? stream, String server)? tlsOf,
}) {
  Map<dynamic, dynamic> settings = const {};
  if (extra is String && extra.trim().isNotEmpty) {
    try {
      final j = jsonDecode(extra);
      if (j is Map) settings = j;
    } catch (_) {}
  } else if (extra is Map) {
    settings = extra;
  }
  String text(String key) => '${settings[key] ?? ''}'.trim();
  final h = host.isNotEmpty ? host : text('host');
  final p = path.isNotEmpty ? path : text('path');
  final m = mode.isNotEmpty ? mode : text('mode');
  final padding = _range(settings['xPaddingBytes']);
  final maxPost = _range(settings['scMaxEachPostBytes']);
  final interval = _range(settings['scMinPostsIntervalMs']);
  final headers = settings['headers'];
  // xmux: how the connections are used and renewed
  final mux = settings['xmux'];
  final muxOut = <String, Object?>{};
  if (mux is Map) {
    for (final (xray, ours) in const [
      ('maxConcurrency', 'max_concurrency'),
      ('maxConnections', 'max_connections'),
      ('cMaxReuseTimes', 'c_max_reuse_times'),
      ('hMaxRequestTimes', 'h_max_request_times'),
      ('hMaxReusableSecs', 'h_max_reusable_secs'),
    ]) {
      final r = _range(mux[xray]);
      if (r != null && r.$2 > 0) muxOut[ours] = r.$3;
    }
  }
  // downloadSettings: the download goes another way (its own address, TLS or REALITY, host and path)
  final dl = settings['downloadSettings'];
  Map<String, Object?>? download;
  if (dl is Map && '${dl['address'] ?? ''}'.isNotEmpty) {
    final server = '${dl['address']}';
    final dx = dl['xhttpSettings'] is Map
        ? dl['xhttpSettings'] as Map
        : dl['splithttpSettings'] is Map
        ? dl['splithttpSettings'] as Map
        : const {};
    final tls = tlsOf?.call(dl, server);
    final dHeaders = dx['headers'];
    download = {
      'server': server,
      'server_port': int.tryParse('${dl['port'] ?? ''}') ?? 443,
      if ('${dx['host'] ?? ''}'.isNotEmpty) 'host': '${dx['host']}',
      if ('${dx['path'] ?? ''}'.isNotEmpty) 'path': '${dx['path']}',
      if (dHeaders is Map && dHeaders.isNotEmpty)
        'headers': {for (final e in dHeaders.entries) '${e.key}': '${e.value}'},
      if (tls != null) 'tls': tls['tls'] ?? tls,
    };
  }
  return {
    'type': 'xhttp',
    if (p.isNotEmpty) 'path': p,
    if (h.isNotEmpty) 'host': h,
    if (m.isNotEmpty && m != 'auto') 'mode': m,
    if (headers is Map && headers.isNotEmpty)
      'headers': {for (final e in headers.entries) '${e.key}': '${e.value}'},
    if (padding != null) 'x_padding_bytes': padding.$3,
    if (settings['noGRPCHeader'] == true) 'no_grpc_header': true,
    // a range of the largest piece: the smaller end is safe for a server that holds to its own limit
    if (maxPost != null && maxPost.$1 > 0) 'sc_max_each_post_bytes': maxPost.$1,
    if (interval != null && interval.$2 > 0)
      'sc_min_posts_interval_ms': interval.$2,
    if (muxOut.isNotEmpty) 'xmux': muxOut,
    'download': ?download,
  };
}

/// A number, a "from-to" text or a {from, to} map as (from, to, text).
(int, int, String)? _range(Object? v) {
  if (v == null) return null;
  int? a;
  int? b;
  if (v is num) {
    a = b = v.toInt();
  } else if (v is Map) {
    a = int.tryParse('${v['from']}');
    b = int.tryParse('${v['to']}');
  } else {
    final t = '$v'.trim();
    if (t.isEmpty) return null;
    final i = t.indexOf('-', 1);
    if (i > 0) {
      a = int.tryParse(t.substring(0, i).trim());
      b = int.tryParse(t.substring(i + 1).trim());
    } else {
      a = b = int.tryParse(t);
    }
  }
  if (a == null || b == null || b < a) return null;
  return (a, b, a == b ? '$a' : '$a-$b');
}
