import 'dart:convert';

import 'package:avet/subscription/xhttp.dart';

/// A subscription that is a JSON config: a sing-box one (`outbounds` with `type`), an Xray / V2Ray one (`outbounds` with
/// `protocol`), or a list of such configs (v2rayN's way, each with its `remarks`). The servers in it are turned into
/// sing-box outbounds.
abstract final class JsonConfig {
  static bool looksLike(String body) {
    final t = body.trimLeft();
    return t.startsWith('{') || t.startsWith('[');
  }

  /// The types of sing-box outbounds this app uses as servers.
  static const _types = {
    'vless',
    'vmess',
    'trojan',
    'shadowsocks',
    'hysteria',
    'hysteria2',
    'tuic',
    'anytls',
    'socks',
  };

  static List<Map<String, Object?>> parse(String body) {
    final Object? doc;
    try {
      doc = jsonDecode(body);
    } on FormatException {
      return const [];
    }
    final out = <Map<String, Object?>>[];
    void config(Object? c, {String? name}) {
      if (c is! Map) return;
      final outbounds = c['outbounds'];
      if (outbounds is! List) return;
      final remarks = '${c['remarks'] ?? c['remark'] ?? name ?? ''}'.trim();
      for (final o in outbounds) {
        if (o is! Map) continue;
        final one = o.containsKey('protocol') ? _xray(o, remarks) : _singbox(o);
        if (one != null) out.add(one);
      }
    }

    if (doc is List) {
      for (final c in doc) {
        if (c is Map && c.containsKey('outbounds')) {
          config(c);
        } else if (c is Map &&
            (c.containsKey('type') || c.containsKey('protocol'))) {
          // a bare list of outbounds
          final one = c.containsKey('protocol') ? _xray(c, '') : _singbox(c);
          if (one != null) out.add(one);
        }
      }
    } else {
      config(doc);
    }
    return out;
  }

  static Map<String, Object?>? _singbox(Map o) {
    final type = '${o['type']}'.toLowerCase();
    if (!_types.contains(type)) return null;
    if (o['server'] == null || o['server_port'] == null) return null;
    final m = <String, Object?>{for (final e in o.entries) '${e.key}': e.value};
    // a chain's hop is another outbound of the config: not followed
    m.remove('detour');
    m['type'] = type;
    m['tag'] = '${m['tag'] ?? '${o['server']}:${o['server_port']}'}';
    return m;
  }

  static Map<String, Object?>? _xray(Map o, String remarks) {
    final protocol = '${o['protocol']}'.toLowerCase();
    final settings = o['settings'];
    if (settings is! Map) return null;
    final stream = o['streamSettings'];
    final String? tagIn = o['tag'] is String ? o['tag'] as String : null;
    final name = remarks.isNotEmpty
        ? remarks
        : (tagIn != null &&
                  !const {'proxy', 'direct', 'block', 'out'}.contains(tagIn)
              ? tagIn
              : '');
    Map<String, Object?>? base(String server, int port, String fallbackName) =>
        {
          'tag': name.isEmpty ? fallbackName : name,
          'server': server,
          'server_port': port,
        };
    switch (protocol) {
      case 'vless' || 'vmess':
        final vnext = settings['vnext'];
        if (vnext is! List || vnext.isEmpty || vnext.first is! Map) return null;
        final v = vnext.first as Map;
        final users = v['users'];
        if (users is! List || users.isEmpty || users.first is! Map) return null;
        final u = users.first as Map;
        final server = '${v['address']}';
        final port = int.tryParse('${v['port']}');
        if (server.isEmpty || port == null) return null;
        final b = base(server, port, '$server:$port')!;
        return {
          'type': protocol,
          ...b,
          'uuid': '${u['id']}',
          if (protocol == 'vless' && '${u['flow'] ?? ''}'.isNotEmpty)
            'flow': '${u['flow']}',
          if (protocol == 'vless') 'packet_encoding': 'xudp',
          if (protocol == 'vmess') 'security': '${u['security'] ?? 'auto'}',
          if (protocol == 'vmess')
            'alter_id': int.tryParse('${u['alterId'] ?? 0}') ?? 0,
          ...?_streamTls(stream, server),
          ...?_streamTransport(stream),
        };
      case 'trojan' || 'shadowsocks':
        final servers = settings['servers'];
        if (servers is! List || servers.isEmpty || servers.first is! Map) {
          return null;
        }
        final s = servers.first as Map;
        final server = '${s['address']}';
        final port = int.tryParse('${s['port']}');
        if (server.isEmpty || port == null) return null;
        final b = base(server, port, '$server:$port')!;
        if (protocol == 'trojan') {
          return {
            'type': 'trojan',
            ...b,
            'password': '${s['password']}',
            ...?_streamTls(stream, server, always: true),
            ...?_streamTransport(stream),
          };
        }
        return {
          'type': 'shadowsocks',
          ...b,
          'method': '${s['method']}',
          'password': '${s['password']}',
        };
      default:
        return null;
    }
  }

  /// The TLS (or REALITY) block of an Xray stream (for the download settings of an XHTTP server).
  static Map<String, Object?>? streamTls(Object? stream, String server) =>
      _streamTls(stream, server);

  static Map<String, Object?>? _streamTls(
    Object? stream,
    String server, {
    bool always = false,
  }) {
    if (stream is! Map) {
      return always
          ? {
              'tls': {'enabled': true, 'server_name': server},
            }
          : null;
    }
    final security = '${stream['security'] ?? 'none'}'.toLowerCase();
    if (security == 'reality') {
      final r = stream['realitySettings'];
      if (r is! Map) return null;
      final fp = '${r['fingerprint'] ?? 'chrome'}';
      return {
        'tls': {
          'enabled': true,
          'server_name': '${r['serverName'] ?? server}',
          'utls': {'enabled': true, 'fingerprint': fp.isEmpty ? 'chrome' : fp},
          'reality': {
            'enabled': true,
            'public_key': '${r['publicKey'] ?? ''}',
            'short_id': '${r['shortId'] ?? ''}',
          },
        },
      };
    }
    if (security == 'tls' || always) {
      final t = stream['tlsSettings'] is Map
          ? stream['tlsSettings'] as Map
          : const {};
      final sni = '${t['serverName'] ?? ''}';
      final fp = '${t['fingerprint'] ?? ''}';
      final alpn = t['alpn'];
      return {
        'tls': {
          'enabled': true,
          'server_name': sni.isEmpty ? server : sni,
          if (t['allowInsecure'] == true) 'insecure': true,
          if (alpn is List && alpn.isNotEmpty)
            'alpn': [for (final a in alpn) '$a'],
          if (fp.isNotEmpty) 'utls': {'enabled': true, 'fingerprint': fp},
        },
      };
    }
    return null;
  }

  static Map<String, Object?>? _streamTransport(Object? stream) {
    if (stream is! Map) return null;
    final net = '${stream['network'] ?? 'tcp'}'.toLowerCase();
    switch (net) {
      case 'ws':
        final w = stream['wsSettings'] is Map
            ? stream['wsSettings'] as Map
            : const {};
        final headers = w['headers'] is Map ? w['headers'] as Map : const {};
        final host = '${headers['Host'] ?? w['host'] ?? ''}';
        final path = '${w['path'] ?? ''}';
        return {
          'transport': {
            'type': 'ws',
            if (path.isNotEmpty) 'path': path,
            if (host.isNotEmpty) 'headers': {'Host': host},
          },
        };
      case 'grpc':
        final g = stream['grpcSettings'] is Map
            ? stream['grpcSettings'] as Map
            : const {};
        return {
          'transport': {
            'type': 'grpc',
            'service_name': '${g['serviceName'] ?? ''}',
          },
        };
      case 'httpupgrade':
        final h = stream['httpupgradeSettings'] is Map
            ? stream['httpupgradeSettings'] as Map
            : const {};
        return {
          'transport': {
            'type': 'httpupgrade',
            if ('${h['path'] ?? ''}'.isNotEmpty) 'path': '${h['path']}',
            if ('${h['host'] ?? ''}'.isNotEmpty) 'host': '${h['host']}',
          },
        };
      case 'xhttp' || 'splithttp':
        final x = stream['xhttpSettings'] is Map
            ? stream['xhttpSettings'] as Map
            : stream['splithttpSettings'] is Map
            ? stream['splithttpSettings'] as Map
            : const {};
        return {
          'transport': xhttpTransport(
            extra: x,
            tlsOf: (stream, server) => _streamTls(stream, server),
          ),
        };
      case 'h2' || 'http':
        final h = stream['httpSettings'] is Map
            ? stream['httpSettings'] as Map
            : const {};
        final host = h['host'];
        return {
          'transport': {
            'type': 'http',
            if ('${h['path'] ?? ''}'.isNotEmpty) 'path': '${h['path']}',
            if (host is List && host.isNotEmpty)
              'host': [for (final x in host) '$x'],
          },
        };
      default:
        return null;
    }
  }
}
