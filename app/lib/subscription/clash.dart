import 'package:avet/subscription/tls_extras.dart';
import 'package:avet/subscription/xhttp.dart';
import 'package:yaml/yaml.dart';

/// A subscription in Clash (Mihomo) format: its `proxies` turned into sing-box outbounds.
abstract final class Clash {
  /// Whether [body] is a Clash config (a `proxies:` list at the top level).
  static bool looksLike(String body) {
    final head = body.length > 8192 ? body.substring(0, 8192) : body;
    return RegExp(r'^proxies\s*:', multiLine: true).hasMatch(head);
  }

  /// The outbounds of the `proxies` list; entries of a type this app doesn't read are skipped.
  static List<Map<String, Object?>> parse(String body) {
    final doc = loadYaml(body);
    if (doc is! YamlMap) return const [];
    final proxies = doc['proxies'];
    if (proxies is! YamlList) return const [];
    return [
      for (final p in proxies)
        if (p is YamlMap) ?_proxy(p),
    ];
  }

  static Map<String, Object?>? _proxy(YamlMap p) {
    String? s(String key) => p[key]?.toString();
    final type = s('type')?.toLowerCase();
    final server = s('server');
    final port = int.tryParse(s('port') ?? '');
    final name = s('name') ?? '$server:$port';
    if (server == null || server.isEmpty || port == null) return null;
    final base = <String, Object?>{
      'tag': name,
      'server': server,
      'server_port': port,
    };
    switch (type) {
      case 'vless':
        return {
          'type': 'vless',
          ...base,
          'uuid': s('uuid'),
          if ((s('flow') ?? '').isNotEmpty) 'flow': s('flow'),
          'packet_encoding': 'xudp',
          ...?_tls(p, server),
          ...?_transport(p),
        };
      case 'vmess':
        return {
          'type': 'vmess',
          ...base,
          'uuid': s('uuid'),
          'security': s('cipher') ?? 'auto',
          'alter_id': int.tryParse(s('alterId') ?? '0') ?? 0,
          ...?_tls(p, server),
          ...?_transport(p),
        };
      case 'trojan':
        return {
          'type': 'trojan',
          ...base,
          'password': s('password'),
          ...?_tls(p, server, always: true),
          ...?_transport(p),
        };
      case 'ss':
        return {
          'type': 'shadowsocks',
          ...base,
          'method': s('cipher'),
          'password': s('password'),
        };
      case 'hysteria2':
        final obfs = s('obfs') ?? '';
        return {
          'type': 'hysteria2',
          ...base,
          ...TlsExtras.hopping(
            s('ports'),
            base['server_port'] as int? ?? 443,
            s('hop-interval'),
          ),
          'password': s('password') ?? s('auth'),
          if (obfs.isNotEmpty)
            'obfs': {'type': obfs, 'password': s('obfs-password') ?? ''},
          ...?_tls(p, server, always: true),
        };
      case 'tuic':
        return {
          'type': 'tuic',
          ...base,
          'uuid': s('uuid'),
          'password': s('password'),
          if ((s('congestion-controller') ?? '').isNotEmpty)
            'congestion_control': s('congestion-controller'),
          if ((s('udp-relay-mode') ?? '').isNotEmpty)
            'udp_relay_mode': s('udp-relay-mode'),
          ...?_tls(p, server, always: true),
        };
      case 'hysteria':
        final up =
            int.tryParse((s('up') ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ??
            50;
        final down =
            int.tryParse((s('down') ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ??
            100;
        return {
          'type': 'hysteria',
          ...base,
          if ((s('auth-str') ?? s('auth') ?? '').isNotEmpty)
            'auth_str': s('auth-str') ?? s('auth'),
          'up_mbps': up,
          'down_mbps': down,
          if ((s('obfs') ?? '').isNotEmpty) 'obfs': s('obfs'),
          ...?_tls(p, server, always: true),
        };
      case 'anytls':
        return {
          'type': 'anytls',
          ...base,
          'password': s('password'),
          ...?_tls(p, server, always: true),
        };
      case 'socks5':
        return {
          'type': 'socks',
          ...base,
          'version': '5',
          if ((s('username') ?? '').isNotEmpty) 'username': s('username'),
          if ((s('password') ?? '').isNotEmpty) 'password': s('password'),
        };
      default:
        return null;
    }
  }

  static Map<String, Object?>? _tls(
    YamlMap p,
    String server, {
    bool always = false,
  }) {
    final reality = p['reality-opts'];
    final on = always || p['tls'] == true || reality is YamlMap;
    if (!on) return null;
    final sni = (p['servername'] ?? p['sni'])?.toString() ?? '';
    final fp = p['client-fingerprint']?.toString() ?? '';
    final alpn = p['alpn'];
    return {
      'tls': {
        'enabled': true,
        'server_name': sni.isEmpty ? server : sni,
        if (p['skip-cert-verify'] == true) 'insecure': true,
        if (alpn is YamlList) 'alpn': [for (final a in alpn) a.toString()],
        if (fp.isNotEmpty || reality is YamlMap)
          'utls': {'enabled': true, 'fingerprint': fp.isEmpty ? 'chrome' : fp},
        if (reality is YamlMap)
          'reality': {
            'enabled': true,
            'public_key': reality['public-key']?.toString() ?? '',
            'short_id': reality['short-id']?.toString() ?? '',
          }
        else
          'ech': ?TlsExtras.echFromClash(p['ech-opts']),
        if (TlsExtras.pins(p['fingerprint']?.toString()) case final pins
            when pins.isNotEmpty)
          'certificate_public_key_sha256': pins,
      },
    };
  }

  static Map<String, Object?>? _transport(YamlMap p) {
    final network = p['network']?.toString().toLowerCase() ?? 'tcp';
    switch (network) {
      case 'ws':
        final ws = p['ws-opts'];
        final headers = ws is YamlMap ? ws['headers'] : null;
        final host = headers is YamlMap ? headers['Host']?.toString() : null;
        final path = ws is YamlMap ? ws['path']?.toString() : null;
        return {
          'transport': {
            'type': 'ws',
            if (path != null && path.isNotEmpty) 'path': path,
            if (host != null && host.isNotEmpty) 'headers': {'Host': host},
          },
        };
      case 'grpc':
        final g = p['grpc-opts'];
        return {
          'transport': {
            'type': 'grpc',
            'service_name': g is YamlMap
                ? g['grpc-service-name']?.toString() ?? ''
                : '',
          },
        };
      case 'xhttp' || 'splithttp':
        // mihomo's xhttp-opts, the keys in its dashed spelling
        final o = p['xhttp-opts'] is YamlMap
            ? p['xhttp-opts'] as YamlMap
            : null;
        Object? pick(String dashed, String camel) => o?[dashed] ?? o?[camel];
        final headers = o?['headers'];
        return {
          'transport': xhttpTransport(
            host: '${o?['host'] ?? ''}',
            path: '${o?['path'] ?? ''}',
            mode: '${o?['mode'] ?? ''}',
            extra: {
              'xPaddingBytes': pick('x-padding-bytes', 'xPaddingBytes'),
              'noGRPCHeader': pick('no-grpc-header', 'noGRPCHeader'),
              'scMaxEachPostBytes': pick(
                'sc-max-each-post-bytes',
                'scMaxEachPostBytes',
              ),
              'scMinPostsIntervalMs': pick(
                'sc-min-posts-interval-ms',
                'scMinPostsIntervalMs',
              ),
              if (headers is YamlMap) 'headers': {...headers},
            },
          ),
        };
      case 'http' || 'h2':
        final h = p['${network == 'h2' ? 'h2' : 'http'}-opts'];
        final path = h is YamlMap ? h['path'] : null;
        return {
          'transport': {
            'type': 'http',
            if (path is YamlList && path.isNotEmpty)
              'path': path.first.toString(),
            if (path is String) 'path': path,
          },
        };
      default:
        return null;
    }
  }
}
