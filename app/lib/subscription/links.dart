import 'dart:convert';

import 'package:avet/subscription/xhttp.dart';

import 'package:avet/subscription/clash.dart';
import 'package:avet/subscription/json_config.dart';

/// Server links of a subscription turned into sing-box outbounds.
///
/// Supported links: `vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://` (`hy2://`), `hysteria://`, `tuic://`,
/// `anytls://`, `socks://` (`socks5://`). A subscription body is such links one per line, the same list in base64,
/// a Clash (Mihomo) config, a sing-box JSON config, or an Xray / V2Ray JSON config (or a list of them).
abstract final class Links {
  /// The outbounds of a subscription's body; links that can not be read are skipped. Every tag is unique.
  static List<Map<String, Object?>> parseSubscription(String body) {
    final used = <String>{};
    if (Clash.looksLike(body)) {
      return [
        for (final o in Clash.parse(body))
          {...o, 'tag': _unique(o['tag']! as String, used)},
      ];
    }
    if (JsonConfig.looksLike(body)) {
      final json = JsonConfig.parse(body);
      if (json.isNotEmpty) {
        return [
          for (final o in json)
            {...o, 'tag': _unique(o['tag']! as String, used)},
        ];
      }
    }
    final text = _maybeBase64(body.trim());
    final out = <Map<String, Object?>>[];
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final outbound = parse(line);
      if (outbound == null) continue;
      outbound['tag'] = _unique(outbound['tag'] as String, used);
      out.add(outbound);
    }
    return out;
  }

  /// One link as a sing-box outbound, or null when it is not a server link this app reads.
  static Map<String, Object?>? parse(String link) {
    try {
      final scheme = link.split('://').first.toLowerCase();
      return switch (scheme) {
        'vless' => _vless(Uri.parse(link)),
        'vmess' => _vmess(link.substring('vmess://'.length)),
        'trojan' => _trojan(Uri.parse(link)),
        'ss' => _shadowsocks(link),
        'hysteria2' || 'hy2' => _hysteria2(Uri.parse(link)),
        'hysteria' || 'hy' => _hysteria(Uri.parse(link)),
        'tuic' => _tuic(Uri.parse(link)),
        'anytls' => _anytls(Uri.parse(link)),
        'socks' || 'socks5' || 'socks4' => _socks(Uri.parse(link)),
        _ => null,
      };
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  // ---------------------------------------------------------------------------------------------------- protocols

  static Map<String, Object?>? _vless(Uri uri) {
    final q = uri.queryParameters;
    if (uri.userInfo.isEmpty || uri.host.isEmpty) return null;
    return {
      'type': 'vless',
      'tag': _name(uri),
      'server': uri.host,
      'server_port': _port(uri),
      'uuid': Uri.decodeComponent(uri.userInfo),
      if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow'],
      if ((q['packetEncoding'] ?? q['packet_encoding'] ?? 'xudp').isNotEmpty)
        'packet_encoding':
            q['packetEncoding'] ?? q['packet_encoding'] ?? 'xudp',
      ...?_tls(q, uri.host),
      ...?_transport(q),
    };
  }

  static Map<String, Object?>? _trojan(Uri uri) {
    final q = uri.queryParameters;
    if (uri.userInfo.isEmpty || uri.host.isEmpty) return null;
    return {
      'type': 'trojan',
      'tag': _name(uri),
      'server': uri.host,
      'server_port': _port(uri),
      'password': Uri.decodeComponent(uri.userInfo),
      // trojan is TLS unless the link says otherwise
      ...?_tls({'security': 'tls', ...q}, uri.host),
      ...?_transport(q),
    };
  }

  static Map<String, Object?>? _vmess(String payload) {
    final json = jsonDecode(
      utf8.decode(
        base64.decode(base64.normalize(payload.split('#').first.trim())),
      ),
    );
    if (json is! Map) return null;
    String s(String key) => '${json[key] ?? ''}'.trim();
    final host = s('add');
    final port = int.tryParse(s('port'));
    if (host.isEmpty || port == null || s('id').isEmpty) return null;
    final q = <String, String>{
      'type': s('net').isEmpty ? 'tcp' : s('net'),
      'security': s('tls') == 'tls' ? 'tls' : 'none',
      if (s('sni').isNotEmpty) 'sni': s('sni'),
      if (s('host').isNotEmpty) 'host': s('host'),
      if (s('path').isNotEmpty) 'path': s('path'),
      if (s('alpn').isNotEmpty) 'alpn': s('alpn'),
      if (s('fp').isNotEmpty) 'fp': s('fp'),
      if (s('net') == 'grpc' && s('path').isNotEmpty) 'serviceName': s('path'),
      if (s('type') == 'http') 'headerType': 'http',
    };
    return {
      'type': 'vmess',
      'tag': s('ps').isEmpty ? '$host:$port' : s('ps'),
      'server': host,
      'server_port': port,
      'uuid': s('id'),
      'security': s('scy').isEmpty ? 'auto' : s('scy'),
      'alter_id': int.tryParse(s('aid')) ?? 0,
      ...?_tls(q, host),
      ...?_transport(q),
    };
  }

  /// SIP002 (`ss://base64(method:password)@host:port#name`, the user part may also be plain) and the older form
  /// (`ss://base64(method:password@host:port)#name`).
  static Map<String, Object?>? _shadowsocks(String link) {
    final hash = link.indexOf('#');
    final name = hash < 0 ? '' : Uri.decodeComponent(link.substring(hash + 1));
    var body = link.substring('ss://'.length, hash < 0 ? link.length : hash);
    final queryAt = body.indexOf('?');
    if (queryAt >= 0) body = body.substring(0, queryAt);
    if (body.endsWith('/')) body = body.substring(0, body.length - 1);
    String userInfo;
    String hostPort;
    final at = body.lastIndexOf('@');
    if (at < 0) {
      final decoded = utf8.decode(base64.decode(base64.normalize(body)));
      final at2 = decoded.lastIndexOf('@');
      if (at2 < 0) return null;
      userInfo = decoded.substring(0, at2);
      hostPort = decoded.substring(at2 + 1);
    } else {
      final user = Uri.decodeComponent(body.substring(0, at));
      userInfo = user.contains(':')
          ? user
          : utf8.decode(base64.decode(base64.normalize(user)));
      hostPort = body.substring(at + 1);
    }
    final colon = userInfo.indexOf(':');
    final portAt = hostPort.lastIndexOf(':');
    if (colon < 0 || portAt < 0) return null;
    var host = hostPort.substring(0, portAt);
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    final port = int.tryParse(hostPort.substring(portAt + 1));
    if (host.isEmpty || port == null) return null;
    return {
      'type': 'shadowsocks',
      'tag': name.isEmpty ? '$host:$port' : name,
      'server': host,
      'server_port': port,
      'method': userInfo.substring(0, colon),
      'password': userInfo.substring(colon + 1),
    };
  }

  static Map<String, Object?>? _hysteria2(Uri uri) {
    final q = uri.queryParameters;
    if (uri.host.isEmpty) return null;
    final obfs = q['obfs'] ?? '';
    return {
      'type': 'hysteria2',
      'tag': _name(uri),
      'server': uri.host,
      'server_port': _port(uri, fallback: 443),
      'password': Uri.decodeComponent(uri.userInfo),
      if (obfs.isNotEmpty)
        'obfs': {'type': obfs, 'password': q['obfs-password'] ?? ''},
      'tls': {
        'enabled': true,
        'server_name': (q['sni'] ?? '').isEmpty ? uri.host : q['sni'],
        if (_isTrue(q['insecure'])) 'insecure': true,
        if ((q['alpn'] ?? '').isNotEmpty) 'alpn': q['alpn']!.split(','),
      },
    };
  }

  static Map<String, Object?> _tlsOf(
    Map<String, String> q,
    String host, {
    String alpnDefault = '',
  }) {
    final sni = q['sni'] ?? q['peer'] ?? q['servername'] ?? '';
    final alpn = (q['alpn'] ?? alpnDefault);
    return {
      'enabled': true,
      'server_name': sni.isEmpty ? host : sni,
      if (_isTrue(q['insecure']) ||
          _isTrue(q['allow_insecure']) ||
          _isTrue(q['allowInsecure']))
        'insecure': true,
      if (alpn.isNotEmpty) 'alpn': alpn.split(','),
    };
  }

  /// `tuic://uuid:password@host:port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=...#name`
  static Map<String, Object?>? _tuic(Uri uri) {
    final q = uri.queryParameters;
    if (uri.host.isEmpty || uri.userInfo.isEmpty) return null;
    final user = uri.userInfo.split(':');
    if (user.length < 2) return null;
    return {
      'type': 'tuic',
      'tag': _name(uri),
      'server': uri.host,
      'server_port': _port(uri),
      'uuid': Uri.decodeComponent(user.first),
      'password': Uri.decodeComponent(user.sublist(1).join(':')),
      if ((q['congestion_control'] ?? q['congestion-controller'] ?? '')
          .isNotEmpty)
        'congestion_control':
            q['congestion_control'] ?? q['congestion-controller'],
      if ((q['udp_relay_mode'] ?? '').isNotEmpty)
        'udp_relay_mode': q['udp_relay_mode'],
      'tls': _tlsOf(q, uri.host, alpnDefault: 'h3'),
    };
  }

  /// `hysteria://host:port?auth=...&upmbps=..&downmbps=..&obfsParam=..&peer=sni&insecure=1&alpn=h3#name` (version 1)
  static Map<String, Object?>? _hysteria(Uri uri) {
    final q = uri.queryParameters;
    if (uri.host.isEmpty) return null;
    final auth = q['auth'] ?? q['auth_str'] ?? '';
    final obfs = q['obfsParam'] ?? q['obfs'] ?? '';
    return {
      'type': 'hysteria',
      'tag': _name(uri),
      'server': uri.host,
      'server_port': _port(uri),
      if (auth.isNotEmpty) 'auth_str': auth,
      'up_mbps': int.tryParse(q['upmbps'] ?? q['up'] ?? '') ?? 50,
      'down_mbps': int.tryParse(q['downmbps'] ?? q['down'] ?? '') ?? 100,
      if (obfs.isNotEmpty && obfs != 'xplus') 'obfs': obfs,
      'tls': _tlsOf(q, uri.host),
    };
  }

  /// `anytls://password@host:port?sni=...&insecure=1#name`
  static Map<String, Object?>? _anytls(Uri uri) {
    final q = uri.queryParameters;
    if (uri.host.isEmpty || uri.userInfo.isEmpty) return null;
    return {
      'type': 'anytls',
      'tag': _name(uri),
      'server': uri.host,
      'server_port': _port(uri),
      'password': Uri.decodeComponent(uri.userInfo),
      'tls': _tlsOf(q, uri.host),
    };
  }

  /// `socks5://user:password@host:port#name` (the user part may be base64 of `user:password`)
  static Map<String, Object?>? _socks(Uri uri) {
    if (uri.host.isEmpty) return null;
    var user = '';
    var pass = '';
    if (uri.userInfo.isNotEmpty) {
      var info = Uri.decodeComponent(uri.userInfo);
      if (!info.contains(':')) {
        try {
          info = utf8.decode(base64.decode(base64.normalize(info)));
        } on FormatException {
          // not base64: a user name alone
        }
      }
      final at = info.indexOf(':');
      user = at < 0 ? info : info.substring(0, at);
      pass = at < 0 ? '' : info.substring(at + 1);
    }
    return {
      'type': 'socks',
      'tag': _name(uri),
      'server': uri.host,
      'server_port': _port(uri, fallback: 1080),
      'version': '5',
      if (user.isNotEmpty) 'username': user,
      if (pass.isNotEmpty) 'password': pass,
    };
  }

  // ------------------------------------------------------------------------------------------------- shared parts

  /// The `tls` block from a link's query (`security=tls|reality`), or null without TLS.
  static Map<String, Object?>? _tls(Map<String, String> q, String host) {
    final security = (q['security'] ?? 'none').toLowerCase();
    if (security != 'tls' && security != 'reality' && security != 'xtls') {
      return null;
    }
    final sni = q['sni'] ?? q['peer'] ?? q['servername'] ?? '';
    final fp = q['fp'] ?? '';
    return {
      'tls': {
        'enabled': true,
        'server_name': sni.isEmpty ? host : sni,
        if (_isTrue(q['allowInsecure']) || _isTrue(q['insecure']))
          'insecure': true,
        if ((q['alpn'] ?? '').isNotEmpty) 'alpn': q['alpn']!.split(','),
        if (fp.isNotEmpty || security == 'reality')
          'utls': {'enabled': true, 'fingerprint': fp.isEmpty ? 'chrome' : fp},
        if (security == 'reality')
          'reality': {
            'enabled': true,
            'public_key': q['pbk'] ?? '',
            'short_id': q['sid'] ?? '',
          },
      },
    };
  }

  /// The `transport` block for ws / grpc / http / httpupgrade / xhttp, or null for plain TCP.
  static Map<String, Object?>? _transport(Map<String, String> q) {
    final type = (q['type'] ?? 'tcp').toLowerCase();
    final host = q['host'] ?? '';
    final path = q['path'] ?? '';
    final Map<String, Object?>? transport = switch (type) {
      'ws' => {
        'type': 'ws',
        if (path.isNotEmpty) 'path': path,
        if (host.isNotEmpty) 'headers': {'Host': host},
      },
      'grpc' => {
        'type': 'grpc',
        'service_name': q['serviceName'] ?? q['service_name'] ?? path,
      },
      'httpupgrade' => {
        'type': 'httpupgrade',
        if (path.isNotEmpty) 'path': path,
        if (host.isNotEmpty) 'host': host,
      },
      'xhttp' || 'splithttp' => xhttpTransport(
        host: host,
        path: path,
        mode: q['mode'] ?? '',
        extra: q['extra'],
        tlsOf: JsonConfig.streamTls,
      ),
      'http' || 'h2' => {
        'type': 'http',
        if (path.isNotEmpty) 'path': path,
        if (host.isNotEmpty) 'host': host.split(','),
      },
      'tcp' when q['headerType'] == 'http' => {
        'type': 'http',
        if (path.isNotEmpty) 'path': path,
        if (host.isNotEmpty) 'host': host.split(','),
      },
      _ => null,
    };
    return transport == null ? null : {'transport': transport};
  }

  static String _name(Uri uri) {
    final name = uri.fragment.isEmpty ? '' : Uri.decodeComponent(uri.fragment);
    return name.isEmpty ? '${uri.host}:${_port(uri)}' : name;
  }

  static int _port(Uri uri, {int fallback = 443}) =>
      uri.hasPort ? uri.port : fallback;

  static bool _isTrue(String? v) => v == '1' || v?.toLowerCase() == 'true';

  static String _unique(String tag, Set<String> used) {
    var t = tag;
    for (var n = 2; used.contains(t); n++) {
      t = '$tag ($n)';
    }
    used.add(t);
    return t;
  }

  /// The text itself, or its base64 decoding when the whole body is base64 of server links.
  static String _maybeBase64(String body) {
    if (body.contains('://')) return body;
    try {
      final compact = body.replaceAll(RegExp(r'\s'), '');
      return utf8.decode(
        base64.decode(
          base64.normalize(compact.replaceAll('-', '+').replaceAll('_', '/')),
        ),
      );
    } on FormatException {
      return body;
    }
  }
}
