import 'dart:convert';
import 'dart:io';

/// A server as the running core reports it.
class ServerState {
  const ServerState(this.tag, this.delay);

  final String tag;

  /// The last latency in ms; null: not measured or did not answer.
  final int? delay;
}

/// The core's local control (on 127.0.0.1, with a secret): the servers' latency and the choice.
class Control {
  Control(this.secret, {this.port = 9090});

  final String secret;
  final int port;

  Future<Object?> call(String method, String path, [Object? body]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:$port$path'),
      );
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode >= 300) throw HttpException('${res.statusCode} $text');
      return text.isEmpty ? null : jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }

  /// The choice by hand (`select`), the server Auto is on now, and every server with its latency.
  Future<
    ({
      String selected,
      String? autoNow,
      List<ServerState> servers,
      Map<String, String> sites,
      String? ai,
    })
  >
  state({String select = 'select', String auto = 'auto'}) async {
    final proxies = ((await call('GET', '/proxies'))! as Map)['proxies'] as Map;
    final group = proxies[select] as Map;
    // 'auto-wifi' -> '-wifi'
    final suffix = auto.replaceFirst('auto', '');
    int? delayOf(String tag) {
      final history = (proxies[tag] as Map?)?['history'] as List?;
      if (history == null || history.isEmpty) return null;
      final d = (history.last as Map)['delay'];
      return d is int && d > 0 ? d : null;
    }

    return (
      selected: group['now'] as String,
      autoNow: (proxies[auto] as Map?)?['now'] as String?,
      // the server each service's own group (multi-server mode) is on: `site-<service>-<network>`
      sites: {
        for (final e in proxies.entries)
          if ('${e.key}'.startsWith('site-') &&
              '${e.key}'.endsWith(suffix) &&
              (e.value as Map)['now'] is String)
            '${e.key}'.substring(5, '${e.key}'.length - suffix.length):
                (e.value as Map)['now'] as String,
      },
      // the server of the one group of the AI services
      ai: (proxies['ai$suffix'] as Map?)?['now'] as String?,
      servers: [
        for (final tag in (group['all'] as List).cast<String>())
          if (!tag.startsWith('auto')) ServerState(tag, delayOf(tag)),
      ],
    );
  }

  /// Measures every server of Auto now.
  Future<void> testAll({
    String auto = 'auto',
    String url = 'https://www.gstatic.com/generate_204',
  }) async {
    await call(
      'GET',
      '/group/$auto/delay?url=${Uri.encodeQueryComponent(url)}&timeout=5000',
    );
  }

  Future<void> choose(String tag, {String select = 'select'}) async {
    await call('PUT', '/proxies/$select', {'name': tag});
  }
}

/// What the core says about the traffic and the connections.
extension ControlLive on Control {
  /// The delay to [url] through one server (or an automatic choice's current one), in ms; null: no answer.
  Future<int?> delay(
    String tag, {
    String url = 'https://www.gstatic.com/generate_204',
    int timeoutMs = 3000,
  }) async {
    try {
      final res = await call(
        'GET',
        '/proxies/${Uri.encodeComponent(tag)}/delay?url=${Uri.encodeQueryComponent(url)}&timeout=$timeoutMs',
      );
      final d = (res as Map?)?['delay'];
      return d is int && d > 0 ? d : null;
    } catch (_) {
      return null;
    }
  }

  /// The speed, once a second: bytes up and down.
  Stream<({int up, int down})> traffic() async* {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/traffic'),
      );
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $secret');
      final res = await req.close();
      await for (final line
          in res.transform(utf8.decoder).transform(const LineSplitter())) {
        try {
          final m = jsonDecode(line) as Map;
          yield (
            up: (m['up'] as num).toInt(),
            down: (m['down'] as num).toInt(),
          );
        } catch (_) {}
      }
    } finally {
      client.close(force: true);
    }
  }

  /// The connections open now: how many, how many went through a server and how many direct, and the totals.
  Future<({int open, int vpn, int direct, int totalUp, int totalDown})>
  connections() async {
    final m = (await call('GET', '/connections'))! as Map;
    final list = (m['connections'] as List?) ?? const [];
    var vpn = 0;
    var direct = 0;
    for (final c in list) {
      final chains =
          ((c as Map)['chains'] as List?)?.cast<String>() ?? const [];
      (chains.isNotEmpty && chains.last == 'direct') ? direct++ : vpn++;
    }
    return (
      open: list.length,
      vpn: vpn,
      direct: direct,
      totalUp: (m['uploadTotal'] as num?)?.toInt() ?? 0,
      totalDown: (m['downloadTotal'] as num?)?.toInt() ?? 0,
    );
  }
}
