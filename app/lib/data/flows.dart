/// One connection as the core lists it.
class Conn {
  const Conn({
    required this.id,
    required this.app,
    required this.host,
    required this.server,
    required this.direct,
    required this.up,
    required this.down,
  });

  final String id;

  /// the app (its package) that opened it; empty when the system did not say
  final String app;

  /// where it goes: the host, or the address
  final String host;

  /// the server it went through (the last outbound but the groups), or "direct"
  final String server;
  final bool direct;
  final int up;
  final int down;

  /// Reads the core's `/connections` list.
  static List<Conn> parse(Object? json) {
    final list =
        (json is Map ? json['connections'] : null) as List? ?? const [];
    final out = <Conn>[];
    for (final c in list) {
      if (c is! Map) continue;
      final meta = (c['metadata'] as Map?) ?? const {};
      final chains = ((c['chains'] as List?) ?? const [])
          .whereType<String>()
          .toList();
      // the clash way: the node first, the groups after it
      final node = chains.isEmpty ? 'direct' : chains.first;
      final host = '${meta['host'] ?? ''}'.isNotEmpty
          ? '${meta['host']}'
          : '${meta['destinationIP'] ?? ''}';
      out.add(
        Conn(
          id: '${c['id']}',
          app: _app('${meta['processPath'] ?? ''}'),
          host: host,
          server: node,
          direct: node == 'direct',
          up: (c['upload'] as num?)?.toInt() ?? 0,
          down: (c['download'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return out;
  }

  /// The app out of what the core gives: a package name, a path, or "Name (10276)" for a shared uid, which is kept as
  /// the uid alone (the system gives the name for it).
  static String _app(String raw) {
    if (raw.isEmpty) return '';
    final uid = RegExp(r'\((\d+)\)\s*$').firstMatch(raw)?.group(1);
    if (uid != null) return uid;
    final slash = raw.lastIndexOf('/');
    return slash >= 0 ? raw.substring(slash + 1) : raw;
  }
}

/// A line of the picture of the topology: this app, to this site, through this server (or direct).
class FlowKey {
  const FlowKey(this.app, this.host, this.server);

  final String app;
  final String host;
  final String server;

  @override
  bool operator ==(Object other) =>
      other is FlowKey &&
      other.app == app &&
      other.host == host &&
      other.server == server;

  @override
  int get hashCode => Object.hash(app, host, server);
}

class FlowLine {
  FlowLine(this.key);

  final FlowKey key;

  /// bytes moved since the session began
  int bytes = 0;

  /// the speed over the last reading, bytes a second
  double speed = 0;

  /// open connections of this line now
  int open = 0;

  /// connections of this line since the session began (open or closed)
  int connections = 0;

  /// when the line last moved something
  DateTime lastMoved = DateTime.fromMillisecondsSinceEpoch(0);
}

/// What the session's connections moved, by line (app, site, server), by server and through the VPN or direct: worked
/// out from the readings of the connection list (the core forgets a connection when it closes, so each reading adds
/// only what each connection moved since the last).
class FlowTracker {
  final flows = <FlowKey, FlowLine>{};

  /// bytes by server (a server's tag, or "direct") since the session began
  final byServer = <String, int>{};
  final seen = <String, int>{};
  final _counted = <String>{};
  int vpnBytes = 0;
  int directBytes = 0;
  DateTime? _last;

  void reset() {
    flows.clear();
    byServer.clear();
    seen.clear();
    _counted.clear();
    vpnBytes = 0;
    directBytes = 0;
    _last = null;
  }

  /// What is kept on disk so that the session goes on after the app has been closed and opened again.
  Map<String, Object?> toJson() => {
    'flows': [
      for (final f in flows.values)
        [
          f.key.app,
          f.key.host,
          f.key.server,
          f.bytes,
          f.connections,
          f.lastMoved.millisecondsSinceEpoch,
        ],
    ],
    'byServer': byServer,
    'seen': seen,
    'counted': _counted.toList(),
    'vpn': vpnBytes,
    'direct': directBytes,
  };

  /// Takes back what [toJson] kept (a reading that does not fit is ignored: the session then begins again).
  void restore(Map<dynamic, dynamic> j) {
    reset();
    for (final e in (j['flows'] as List? ?? const [])) {
      final l = e as List;
      final f = FlowLine(FlowKey('${l[0]}', '${l[1]}', '${l[2]}'))
        ..bytes = (l[3] as num).toInt()
        ..connections = (l[4] as num).toInt()
        ..lastMoved = DateTime.fromMillisecondsSinceEpoch(
          (l[5] as num).toInt(),
        );
      flows[f.key] = f;
    }
    for (final e in ((j['byServer'] as Map?) ?? const {}).entries) {
      byServer['${e.key}'] = (e.value as num).toInt();
    }
    for (final e in ((j['seen'] as Map?) ?? const {}).entries) {
      seen['${e.key}'] = (e.value as num).toInt();
    }
    for (final id in (j['counted'] as List? ?? const [])) {
      _counted.add('$id');
    }
    vpnBytes = (j['vpn'] as num?)?.toInt() ?? 0;
    directBytes = (j['direct'] as num?)?.toInt() ?? 0;
  }

  /// A reading of the connection list taken at [now].
  void update(List<Conn> conns, DateTime now) {
    final seconds = _last == null
        ? 1.0
        : now.difference(_last!).inMilliseconds / 1000.0;
    _last = now;
    final open = <FlowKey, int>{};
    final gained = <FlowKey, int>{};
    final fresh = <FlowKey, int>{};
    final live = <String>{};
    for (final c in conns) {
      live.add(c.id);
      final total = c.up + c.down;
      final delta = total - (seen[c.id] ?? 0);
      seen[c.id] = total;
      final key = FlowKey(c.app, c.host, c.server);
      open[key] = (open[key] ?? 0) + 1;
      if (_counted.add(c.id)) fresh[key] = (fresh[key] ?? 0) + 1;
      if (delta > 0) {
        gained[key] = (gained[key] ?? 0) + delta;
        byServer[c.server] = (byServer[c.server] ?? 0) + delta;
        c.direct ? directBytes += delta : vpnBytes += delta;
      }
    }
    // a connection that closed is no longer followed
    seen.removeWhere((id, _) => !live.contains(id));
    for (final key in {...open.keys, ...gained.keys, ...fresh.keys}) {
      final f = flows.putIfAbsent(key, () => FlowLine(key));
      final g = gained[key] ?? 0;
      f.bytes += g;
      f.speed = seconds > 0 ? g / seconds : 0;
      f.open = open[key] ?? 0;
      f.connections += fresh[key] ?? 0;
      if (g > 0) f.lastMoved = now;
    }
    for (final f in flows.values) {
      if (!open.containsKey(f.key)) {
        f.open = 0;
        f.speed = 0;
      }
    }
  }
}

/// The lines of one app (or one site) together: what it moved, how, and where.
class FlowGroup {
  FlowGroup(this.key);

  /// the app (or the site)
  final String key;

  int vpnBytes = 0;
  int directBytes = 0;
  int open = 0;
  int connections = 0;
  double speed = 0;

  /// what the other side of the pairing moved: for an app its sites, for a site its apps (bytes by name)
  final others = <String, int>{};

  /// the servers it went through (not "direct")
  final servers = <String>{};

  int get bytes => vpnBytes + directBytes;

  /// the share of its traffic that went through a server
  double get vpnShare => bytes == 0 ? 0 : vpnBytes / bytes;

  /// the other names, the biggest first
  List<String> get topOthers {
    final list = others.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in list) e.key];
  }
}

extension FlowGroups on FlowTracker {
  /// The lines grouped by app ([byApp]) or by site, the biggest first. [only] keeps the ones that went through a
  /// server ('vpn') or direct ('direct'); null: all.
  List<FlowGroup> groups({required bool byApp, String? only}) {
    final map = <String, FlowGroup>{};
    for (final f in flows.values) {
      final direct = f.key.server == 'direct';
      if (only == 'vpn' && direct) continue;
      if (only == 'direct' && !direct) continue;
      final key = byApp ? f.key.app : f.key.host;
      final g = map.putIfAbsent(key, () => FlowGroup(key));
      direct ? g.directBytes += f.bytes : g.vpnBytes += f.bytes;
      g.open += f.open;
      g.connections += f.connections;
      g.speed += f.speed;
      final other = byApp ? f.key.host : f.key.app;
      g.others[other] = (g.others[other] ?? 0) + f.bytes;
      if (!direct) g.servers.add(f.key.server);
    }
    return map.values.toList()..sort((a, b) => b.bytes.compareTo(a.bytes));
  }
}
