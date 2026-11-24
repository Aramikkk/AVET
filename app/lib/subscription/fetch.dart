import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:avet/subscription/links.dart';

/// Downloads a subscription the way providers' panels accept: some answer only known client names (others get decoy
/// servers: "App not supported", "Reinstall the config"), and some limit devices by an id sent in the headers.
abstract final class SubscriptionFetch {
  /// The client names tried in turn until the provider gives real servers; the first answers in Clash format.
  static const agents = [
    'clash.meta',
    'Happ/2.4.5',
    'v2rayNG/1.9.30',
    'sing-box/1.11.0',
    'Streisand/1.7.0',
    'Hiddify/2.5.7',
    'v2rayN/6.42',
    'Shadowrocket/2.2.40',
    'NekoBox/1.3.8',
    'Happ/2.4.5/Android',
    'Happ/2.4.5/ios',
    'FlClash/0.8.76',
    'mihomo/1.18.0',
    'ClashMetaForAndroid/2.10.3.Meta',
    'karing/1.0.30',
    'v2raytun/android',
    'INCY/1.0.0',
  ];

  /// What the last download tried and got, one line for each attempt (no address, no keys): for the log, to see why a
  /// provider gives decoys.
  static final List<String> trace = [];

  /// What the user pasted as the address of a subscription: the web address itself, or the one inside an app's
  /// invitation (`clash://install-config?url=...`, `sing-box://import-remote-profile?url=...`,
  /// `v2rayng://install-sub?url=...`, `hiddify://import/https://...`, `sub://base64`). Anything else is returned as it is.
  static String unwrap(String input) {
    final t = input.trim();
    final lower = t.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return t;
    if (!t.contains('://') || t.contains('\n')) return t;
    final uri = Uri.tryParse(t);
    if (uri == null) return t;
    final q = uri.queryParameters['url'];
    if (q != null && q.isNotEmpty) return q.trim();
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'hiddify' ||
        scheme == 'happ' ||
        scheme == 'clash' ||
        scheme == 'sing-box') {
      final i = t.indexOf('http');
      if (i > 0) return t.substring(i).split('#').first;
    }
    if (scheme == 'sub') {
      try {
        final d = utf8.decode(
          base64.decode(base64.normalize(t.substring(6).split('#').first)),
        );
        if (d.startsWith('http')) return d.trim();
      } on FormatException {
        // not base64
      }
    }
    return t;
  }

  /// Whether the text is a web address (a subscription to load) and not servers or a config pasted in.
  static bool isAddress(String input) {
    final u = unwrap(input).toLowerCase();
    return (u.startsWith('http://') || u.startsWith('https://')) &&
        !u.contains('\n') &&
        !u.contains(' ');
  }

  static final _marks = RegExp(
    r'не\s+поддерживается|скачайте|установите\s+приложение|переустановите|not\s+supported|unsupported|'
    r'download\s+(the\s+)?(happ|app)|use\s+happ|please\s+use|обновите\s+приложение|missing[-\s]?hwid|'
    r'идентификатор\s+устройства|лимит\s+устройств|device\s+limit|подписка\s+не\s+ваша|освободить\s+место|'
    r'требуется\s+заголовок|устройство\s+не\s+поддерживается|hwid',
    caseSensitive: false,
    unicode: true,
  );

  static final _limit = RegExp(
    r'лимит\s+устройств|device\s+limit|hwid\s+limit',
    caseSensitive: false,
    unicode: true,
  );

  /// Whether one server is a decoy: its name is a notice (the device limit, "not supported", "download the app"), or
  /// its address leads nowhere.
  static bool isDecoyServer(Map<String, Object?> s) {
    final host = '${s['server']}';
    final port = s['server_port'] as int? ?? 443;
    return _marks.hasMatch('${s['tag']}') ||
        host == '0.0.0.0' ||
        host == '127.0.0.1' ||
        port < 2;
  }

  /// Whether every server is a decoy. No servers: not a decoy.
  static bool isDecoy(List<Map<String, Object?>> servers) =>
      servers.isNotEmpty && servers.every(isDecoyServer);

  /// What the provider says through its decoys (the names of the decoy servers of a subscription's text): the device
  /// limit reached, the client not known. Empty when there is nothing of the kind.
  static List<String> messages(String body) => [
    for (final s in Links.parseSubscription(body))
      if (isDecoyServer(s)) '${s['tag']}',
  ];

  /// The provider's name for the subscription and when it ends (from the answer's headers), if it says.
  /// the traffic used and the plan's total of the last answer (bytes; 0 when the provider does not say)
  static int lastUsed = 0;
  static int lastTotal = 0;

  /// the provider's pages from the headers of the last answer: its site and its support
  static String lastWeb = '';
  static String lastSupport = '';

  static ({String? title, DateTime? expire}) info(HttpHeaders h) {
    final ui = h.value('subscription-userinfo') ?? '';
    int num(String k) =>
        int.tryParse(RegExp('$k=(d+)').firstMatch(ui)?.group(1) ?? '') ?? 0;
    lastUsed = num('upload') + num('download');
    lastTotal = num('total');
    lastWeb = h.value('profile-web-page-url') ?? '';
    lastSupport = h.value('support-url') ?? '';
    String? title;
    final raw = h.value('profile-title');
    if (raw != null && raw.isNotEmpty) {
      title = raw;
      if (raw.startsWith('base64:')) {
        try {
          title = utf8.decode(base64.decode(raw.substring(7)));
        } catch (_) {}
      }
    }
    DateTime? expire;
    final m = RegExp(
      r'expire=(\d+)',
    ).firstMatch(h.value('subscription-userinfo') ?? '');
    final secs = int.tryParse(m?.group(1) ?? '');
    if (secs != null && secs > 0) {
      expire = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    }
    return (title: title, expire: expire);
  }

  /// The subscription's body and the client name that got real servers. [deviceId]: kept for the install.
  static Future<
    ({
      String body,
      String agent,
      List<Map<String, Object?>> servers,
      String? title,
      DateTime? expire,
    })
  >
  fetch(
    String url, {
    required String deviceId,
    String deviceOs = 'Android',
  }) async {
    ({
      String body,
      String agent,
      List<Map<String, Object?>> servers,
      String? title,
      DateTime? expire,
    })?
    first;
    Object? lastError;
    trace.clear();
    // every client name twice: with the device's headers (the id some panels limit by), and plainly
    for (final withDevice in const [true, false]) {
      for (final agent in agents) {
        try {
          final client = HttpClient()
            ..userAgent = agent
            ..connectionTimeout = const Duration(seconds: 10);
          final req = await client.getUrl(Uri.parse(url));
          if (withDevice) {
            req.headers
              ..set('x-hwid', deviceId)
              ..set('x-device-os', deviceOs)
              ..set('x-ver-os', '14')
              ..set('x-device-model', 'AVET');
          }
          final res = await req.close().timeout(const Duration(seconds: 20));
          final body = await res.transform(utf8.decoder).join();
          client.close();
          if (res.statusCode >= 300) {
            lastError = HttpException('HTTP ${res.statusCode}');
            trace.add('$agent device=$withDevice http=${res.statusCode}');
            continue;
          }
          final servers = Links.parseSubscription(body);
          final meta = info(res.headers);
          final decoy = isDecoy(servers);
          trace.add(
            '$agent device=$withDevice http=${res.statusCode} bytes=${body.length} servers=${servers.length} '
            'decoy=$decoy'
            '${decoy ? ' names=${[for (final x in servers.take(3)) x['tag']]}' : ''}'
            ' title=${meta.title}',
          );
          final got = (
            body: body,
            agent: agent,
            servers: servers,
            title: meta.title,
            expire: meta.expire,
          );
          if (servers.isNotEmpty && !decoy) return got;
          first ??= got;
          // the device limit is the provider's answer to this device, not to the client name: no other name changes it
          if (decoy && _limit.hasMatch(messages(body).join(' '))) return got;
        } catch (e) {
          lastError = e;
          trace.add('$agent device=$withDevice error=${e.runtimeType}');
        }
      }
    }
    if (first != null) return first;
    throw lastError ?? const HttpException('no answer');
  }

  /// A random id for this install (hex, 32 characters).
  static String newDeviceId() => List.generate(
    32,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();
}
