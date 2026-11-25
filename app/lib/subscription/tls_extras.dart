import 'dart:convert';

/// The parts of a server's settings that links and Clash configs spell in several ways: Hysteria2 port hopping, ECH and
/// certificate pinning. Each turns the provider's spelling into sing-box options (or null when the link has none).
abstract final class TlsExtras {
  // ------------------------------------------------------------------------------------------------ port hopping

  /// sing-box `server_ports` from a list of ports (`20000-30000,443`, `5000:6000`, `443`): ranges as `a:b`, a single
  /// port as `p:p` (sing-box only reads ranges). Empty when nothing in it is a port.
  static List<String> serverPorts(String? spec) {
    final out = <String>[];
    for (final part in (spec ?? '').split(RegExp(r'[,/\s]+'))) {
      final m = RegExp(
        r'^(\d{1,5})(?:\s*[-:]\s*(\d{1,5}))?$',
      ).firstMatch(part.trim());
      if (m == null) continue;
      final a = int.parse(m.group(1)!);
      final b = int.parse(m.group(2) ?? m.group(1)!);
      if (a < 1 || b > 65535 || a > b) continue;
      out.add('$a:$b');
    }
    return out;
  }

  /// `hop_interval` (and `hop_interval_max` for a range `20-40`) from seconds (`30`, `30s`, `20-40`). Null for nothing.
  static Map<String, Object?>? hopInterval(String? spec) {
    final m = RegExp(
      r'^(\d+)s?(?:\s*-\s*(\d+)s?)?$',
    ).firstMatch((spec ?? '').trim());
    if (m == null) return null;
    final a = int.parse(m.group(1)!);
    if (a < 1) return null;
    final b = int.tryParse(m.group(2) ?? '');
    return {
      'hop_interval': '${a}s',
      if (b != null && b > a) 'hop_interval_max': '${b}s',
    };
  }

  /// The port-hopping options of a Hysteria2 server: [ports] (the link's `mport` / Clash `ports`) plus its main
  /// [port], so hopping also uses it. Empty without hopping.
  static Map<String, Object?> hopping(
    String? ports,
    int port,
    String? interval,
  ) {
    final list = serverPorts(ports);
    if (list.isEmpty) return const {};
    final main = '$port:$port';
    return {
      'server_ports': [if (!_covers(list, port)) main, ...list],
      ...?hopInterval(interval),
    };
  }

  static bool _covers(List<String> ranges, int port) => ranges.any((r) {
    final p = r.split(':');
    return int.parse(p[0]) <= port && port <= int.parse(p[1]);
  });

  /// A Hysteria2 link with several ports in its address (`hy2://pass@host:443,20000-30000/?...`), which [Uri.parse]
  /// can not read: the first port stays in the address, every port goes to `mport`. Other links are returned as they are.
  static String movePortList(String link) {
    final m = RegExp(
      r'^([a-z0-9]+://[^/?#]*@?(?:\[[^\]]+\]|[^:/?#@\[]+)):([0-9][0-9,:\-]*[,\-][0-9,:\-]*)([/?#].*)?$',
      caseSensitive: false,
    ).firstMatch(link);
    if (m == null) return link;
    final ports = m.group(2)!;
    final first = RegExp(r'^\d+').firstMatch(ports)?.group(0) ?? '443';
    var rest = m.group(3) ?? '';
    final hash = rest.indexOf('#');
    final fragment = hash < 0 ? '' : rest.substring(hash);
    rest = hash < 0 ? rest : rest.substring(0, hash);
    final sep = rest.contains('?') ? '&' : (rest.startsWith('/') ? '?' : '/?');
    return '${m.group(1)}:$first$rest${sep}mport=${Uri.encodeQueryComponent(ports)}$fragment';
  }

  // --------------------------------------------------------------------------------------------------------- ECH

  /// sing-box `ech` from a link's `ech` (or `echConfigList`): `1` / `true` asks the DNS for the server's ECH keys; a
  /// base64 ECH config list is used as it is; `name+https://dns...` (Xray) asks for `name`'s keys. Null without ECH.
  static Map<String, Object?>? ech(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty || v == '0' || v.toLowerCase() == 'false') return null;
    if (v == '1' || v.toLowerCase() == 'true') return {'enabled': true};
    final plus = v.indexOf('+');
    if (plus > 0 && v.substring(plus + 1).contains('://')) {
      return {'enabled': true, 'query_server_name': v.substring(0, plus)};
    }
    if (v.contains('://')) return {'enabled': true};
    if (v.contains('BEGIN ECH CONFIGS')) {
      return {'enabled': true, 'config': const LineSplitter().convert(v)};
    }
    final b64 = v.replaceAll('-', '+').replaceAll('_', '/');
    if (!RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(b64)) {
      // a bare name: the server whose ECH keys to ask the DNS for
      return {'enabled': true, 'query_server_name': v};
    }
    return {
      'enabled': true,
      'config': [
        '-----BEGIN ECH CONFIGS-----',
        base64.normalize(b64),
        '-----END ECH CONFIGS-----',
      ],
    };
  }

  /// sing-box `ech` from Clash `ech-opts` (`enable`, `config`, `query-server-name`). Null without ECH.
  static Map<String, Object?>? echFromClash(Object? opts) {
    if (opts is! Map || opts['enable'] != true) return null;
    final config = opts['config']?.toString() ?? '';
    final name = opts['query-server-name']?.toString() ?? '';
    return {
      ...?ech(config.isEmpty ? '1' : config),
      if (name.isNotEmpty) 'query_server_name': name,
    };
  }

  // ------------------------------------------------------------------------------------------- certificate pinning

  /// `certificate_public_key_sha256` (base64 values) from pins as links give them: hex with or without colons (Xray
  /// `pcs`, Hysteria2 `pinSHA256`, Clash `fingerprint`) or base64, several separated by commas. AVET's core matches a
  /// value against the SHA-256 of the server's public key and of every certificate of its chain, so either kind works.
  /// Empty when nothing in it is a SHA-256.
  static List<String> pins(String? value) {
    final out = <String>[];
    for (final raw in (value ?? '').split(RegExp(r'[,;\s]+'))) {
      final v = raw.trim();
      if (v.isEmpty) continue;
      final hex = v.replaceAll(':', '');
      if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
        out.add(
          base64.encode([
            for (var i = 0; i < 64; i += 2)
              int.parse(hex.substring(i, i + 2), radix: 16),
          ]),
        );
        continue;
      }
      try {
        final bytes = base64.decode(
          base64.normalize(v.replaceAll('-', '+').replaceAll('_', '/')),
        );
        if (bytes.length == 32) out.add(base64.encode(bytes));
      } on FormatException {
        // not a pin
      }
    }
    return out;
  }

  /// The pin options of a link's query (`pcs`, `pinnedPeerCertSha256`, `pinSHA256`, `fingerprint` when it is a hash).
  static Map<String, Object?> pinsOf(Map<String, String> q) {
    final list = pins(
      [
        q['pcs'],
        q['pinnedPeerCertSha256'],
        q['pinSHA256'],
        q['pinsha256'],
      ].whereType<String>().join(','),
    );
    return list.isEmpty ? const {} : {'certificate_public_key_sha256': list};
  }

  /// The ECH and pin options of a link's query, to merge into its `tls` block.
  static Map<String, Object?> ofQuery(Map<String, String> q) {
    final e = ech(q['ech'] ?? q['echConfigList']);
    return {'ech': ?e, ...pinsOf(q)};
  }
}
