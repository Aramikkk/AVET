import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:avet/core/control.dart';
import 'package:avet/data/flows.dart';
import 'package:avet/data/history.dart';
import 'package:avet/state/engine.dart' show Engine, RuleSettings;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The statistics while the app is closed (or out of sight): the VPN service starts this on a Flutter engine of its own
/// and it keeps the session's picture as the screen does: the time since the start, the ping answers, the connections'
/// flows and the history of the traffic and the ping. It hands over to the screen when that comes back (the service asks
/// it to [flush], then stops it), and the screen takes the files up where this left them.
@pragma('vm:entry-point')
Future<void> collectorMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final collector = _Collector(args.isEmpty ? '' : args.first);
  const MethodChannel('avet/collector').setMethodCallHandler((call) async {
    if (call.method == 'flush') collector.save(force: true);
    return true;
  });
  await collector.run();
}

class _Collector {
  _Collector(this.dir);

  final String dir;
  Control? _control;
  String _secret = '';
  final flows = FlowTracker();
  late final HistoryStore history = HistoryStore(File('$dir/history.json'))
    ..load();
  DateTime since = DateTime.now();
  List<int?> pings = [];
  RuleSettings rules = const RuleSettings();
  bool _probing = false;
  bool _asking = false;
  bool _answered = false;
  HttpClient? _probeClient;
  String _probeUrl = '';
  bool _probeWarm = true;
  StreamSubscription<({int up, int down})>? _traffic;

  // what the probes did since the last line of the diagnostic log
  int _probes = 0, _lost = 0, _sum = 0, _max = 0;
  DateTime _noted = DateTime.now();

  String? _runningSecret() {
    for (final name in const ['resume.json', 'last_start.json']) {
      try {
        final f = File('$dir/$name');
        if (!f.existsSync()) continue;
        final s = (jsonDecode(f.readAsStringSync()) as Map)['secret'];
        if (s is String && s.isNotEmpty) return s;
      } catch (_) {}
    }
    return null;
  }

  Future<void> run() async {
    final secret = _runningSecret();
    _say('up dir=$dir secret=${secret != null}');
    if (secret == null) return;
    _secret = secret;
    _control = Control(secret);
    try {
      rules = RuleSettings.fromJson(
        jsonDecode(File('$dir/rules.json').readAsStringSync()) as Map,
      );
    } catch (_) {}
    _loadSession();
    _watchTraffic();
    Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_connections()),
    );
    Timer.periodic(const Duration(seconds: 3), (_) => unawaited(_probeOnce()));
    Timer.periodic(const Duration(seconds: 10), (_) => save());
    Timer.periodic(const Duration(minutes: 5), (_) => _note());
    Timer(const Duration(seconds: 30), _note);
  }

  void _loadSession() {
    try {
      final f = File('$dir/session.json');
      if (!f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync()) as Map;
      if (j['secret'] != _secret) return;
      since = DateTime.fromMillisecondsSinceEpoch((j['since'] as num).toInt());
      pings = [
        for (final p in (j['pings'] as List? ?? const []))
          p == null ? null : (p as num).toInt(),
      ];
      flows.restore((j['flows'] as Map?) ?? const {});
      _answered = pings.any((p) => p != null);
    } catch (_) {
      flows.reset();
    }
  }

  void save({bool force = false}) {
    try {
      File('$dir/session.json').writeAsStringSync(
        jsonEncode({
          'secret': _secret,
          'since': since.millisecondsSinceEpoch,
          'pings': pings,
          'flows': flows.toJson(),
        }),
      );
    } catch (_) {}
    history.save(force: force);
  }

  /// A line of the diagnostic log: the probes of the last minutes and what the flows moved.
  void _note() {
    final answered = _probes - _lost;
    final text =
        'sample: ${DateTime.now().difference(_noted).inMinutes}min probes=$_probes lost=$_lost '
        'avg=${answered > 0 ? (_sum / answered).round() : '-'}ms max=${_max}ms '
        'vpn=${flows.vpnBytes}B direct=${flows.directBytes}B flows=${flows.flows.length} '
        'conn_err=$_connErrors';
    _probes = _lost = _sum = _max = 0;
    _noted = DateTime.now();
    _say(text);
  }

  int _connErrors = 0;
  String _connFirstError = '';

  void _say(String text) {
    try {
      const MethodChannel(
        'avet/collector',
      ).invokeMethod<void>('diag', {'text': text}).catchError((_) {});
    } catch (_) {}
  }

  void _watchTraffic() {
    final c = _control;
    if (c == null) return;
    _traffic = c.traffic().listen(
      (t) => history.traffic.add(t.up, t.down),
      onError: (_) {
        // the core was not there yet (or restarted): asked again in a moment
        Timer(const Duration(seconds: 5), () {
          if (_traffic != null) _watchTraffic();
        });
      },
      onDone: () {
        Timer(const Duration(seconds: 5), () {
          if (_traffic != null) _watchTraffic();
        });
      },
    );
  }

  Future<void> _connections() async {
    final c = _control;
    if (c == null || _asking) return;
    _asking = true;
    try {
      final raw = await c.call('GET', '/connections');
      if (!rules.superLight) flows.update(Conn.parse(raw), DateTime.now());
    } catch (e) {
      _connErrors++;
      if (_connFirstError.isEmpty) {
        _connFirstError = '$e';
        _say('connections: $e');
      }
    } finally {
      _asking = false;
    }
  }

  Future<void> _headOnce(HttpClient client, String url) async {
    final wait = Duration(
      seconds:
          (rules.pingTimeout > rules.pingTimeoutLte
                  ? rules.pingTimeout
                  : rules.pingTimeoutLte)
              .clamp(2, 120),
    );
    final req = await client.headUrl(Uri.parse(url)).timeout(wait);
    final res = await req.close().timeout(wait);
    await res.drain<void>();
  }

  /// The same probe the screen makes: a HEAD request over a kept connection through the tunnel, in ms.
  Future<int?> _httpDelay(String url) async {
    if (_probeClient == null || _probeUrl != url) {
      _probeClient?.close(force: true);
      _probeClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        ..idleTimeout = const Duration(seconds: 30)
        ..findProxy = ((_) => 'DIRECT');
      _probeUrl = url;
      _probeWarm = true;
    }
    final client = _probeClient!;
    try {
      if (_probeWarm) {
        _probeWarm = false;
        try {
          await _headOnce(client, url);
        } catch (_) {}
      }
      final watch = Stopwatch()..start();
      try {
        await _headOnce(client, url);
      } on HttpException {
        watch
          ..reset()
          ..start();
        await _headOnce(client, url);
      }
      final ms = watch.elapsedMilliseconds;
      return ms > 0 ? ms : 1;
    } catch (_) {
      return null;
    }
  }

  Future<void> _probeOnce() async {
    if (_probing || rules.superLight) return;
    _probing = true;
    try {
      final target = Engine.pingTarget(rules);
      var d = await _httpDelay(target);
      d ??= await _httpDelay(target);
      if (d != null) _answered = true;
      if (!_answered) return;
      _probes++;
      if (d == null) {
        _lost++;
      } else {
        _sum += d;
        if (d > _max) _max = d;
      }
      history.ping.add(d);
      pings = [...pings, d];
      if (pings.length > Engine.keptPings) {
        pings = pings.sublist(pings.length - Engine.keptPings);
      }
    } finally {
      _probing = false;
    }
  }
}
