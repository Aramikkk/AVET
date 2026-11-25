/// The sing-box config AVET runs: the servers of the subscriptions, a choice by hand over an automatic one by
/// latency, and a route that sends the device's traffic through the choice.
abstract final class ConfigBuilder {
  /// The automatic choice: the server with the lowest latency, kept until another is better by [tolerance] ms.
  static const autoTag = 'auto';

  /// The choice the app shows and changes: [autoTag] or one server.
  static const selectTag = 'select';

  static const directTag = 'direct';

  /// Server types that run over TCP: their port is checked with a plain TCP connection before the full test.
  static const _tcpTypes = {
    'vless',
    'vmess',
    'trojan',
    'shadowsocks',
    'anytls',
    'socks',
    'http',
    'naive',
    'shadowtls',
  };

  /// Gives every Auto group the addresses of the TCP-based servers (a core of ours, `tcp_ping`): a server whose port
  /// does not take a TCP connection is marked unreachable at once, without the full test through it. Servers behind
  /// another one (`detour`) and UDP ones (Hysteria, TUIC, WireGuard) are left to the full test.
  static void addTcpPing(Map<String, Object?> config) {
    final outbounds = config['outbounds'];
    if (outbounds is! List) return;
    final targets = <String, String>{};
    for (final o in outbounds) {
      if (o is! Map || !_tcpTypes.contains(o['type'])) continue;
      if ((o['detour'] ?? '').toString().isNotEmpty) continue;
      final server = '${o['server'] ?? ''}';
      final port = o['server_port'];
      if (server.isEmpty || port is! int || port <= 0) continue;
      final host = server.contains(':') ? '[$server]' : server;
      targets['${o['tag']}'] = '$host:$port';
    }
    if (targets.isEmpty) return;
    for (final o in outbounds) {
      if (o is Map && o['type'] == 'urltest') o['tcp_ping'] = targets;
    }
  }

  /// What the latency of every server is measured on.
  static const testUrl = 'https://www.gstatic.com/generate_204';

  /// The automatic choice among a network's own servers: `auto-wifi` and `auto-mobile`.
  static String autoFor(String network) => 'auto-$network';

  /// One config for both networks, so the phone moves between them without restarting the core: the servers of each
  /// in an automatic choice of its own ([autoFor]), the choice by hand over both and every server. The VPN service
  /// The options that make [main] (the tags of the main subscription's servers) preferred in a group of [servers]: the
  /// others have to be faster by [margin] ms. Nothing when there is no margin or the group has servers of one kind only.
  static Map<String, Object?> priorityFor(
    List<String> servers,
    List<String> main,
    int margin,
  ) {
    if (margin <= 0 || main.isEmpty) return const {};
    final mine = [
      for (final t in servers)
        if (main.contains(t)) t,
    ];
    if (mine.isEmpty || mine.length == servers.length) return const {};
    return {'priority_tags': mine, 'priority_margin': margin};
  }

  /// points the choice at the network's automatic one when the network changes.
  static Map<String, Object?> buildForNetworks({
    required List<Map<String, Object?>> wifi,
    required List<Map<String, Object?>> mobile,
    int tolerance = 50,
    int? mobileTolerance,
    String interval = '3m',
    String? mobileInterval,
    Map<String, Object?>? smartWifi,
    Map<String, Object?>? smartMobile,
    List<String> priority = const [],
    int priorityWifi = 0,
    int priorityMobile = 0,
    String url = testUrl,
    String? controlSecret,
    int controlPort = 9090,
    String? logFile,
    String logLevel = 'warn',
  }) {
    if (wifi.isEmpty || mobile.isEmpty) throw ArgumentError('no servers');
    final all = <String, Map<String, Object?>>{
      for (final s in [...wifi, ...mobile]) s['tag']! as String: s,
    };
    final config = build(
      servers: all.values.toList(),
      tolerance: tolerance,
      interval: interval,
      url: url,
      controlSecret: controlSecret,
      controlPort: controlPort,
      logFile: logFile,
      logLevel: logLevel,
    );
    Map<String, Object?> auto(
      String network,
      List<Map<String, Object?>> servers,
    ) => {
      'type': 'urltest',
      'tag': autoFor(network),
      'outbounds': [for (final s in servers) s['tag']! as String],
      'url': url,
      'interval': network == 'mobile' ? (mobileInterval ?? interval) : interval,
      'tolerance': network == 'mobile'
          ? (mobileTolerance ?? tolerance)
          : tolerance,
      // as in the old app: the connections already open stay on their server when Auto moves to another
      'interrupt_exist_connections': false,
      // the smart choice of a network (a core of ours): the margins it works with
      ...?(network == 'mobile' ? smartMobile : smartWifi),
      // the servers of the main subscription are preferred: any others have to be faster by the margin to be chosen
      ...priorityFor(
        [for (final s in servers) s['tag']! as String],
        priority,
        network == 'mobile' ? priorityMobile : priorityWifi,
      ),
    };
    final outbounds = (config['outbounds']! as List)
        .cast<Map<String, Object?>>();
    final select = outbounds.firstWhere((o) => o['tag'] == selectTag);
    select['outbounds'] = [autoFor('wifi'), autoFor('mobile'), ...all.keys];
    select['default'] = autoFor('wifi');
    outbounds
      ..removeWhere((o) => o['tag'] == autoTag)
      ..insertAll(1, [auto('wifi', wifi), auto('mobile', mobile)]);
    return config;
  }

  /// [servers]: outbounds as the subscription parser makes them, unique tags. [systemProxy]: the computer's way (a
  /// local proxy set as the system's, no admin rights); otherwise the phone's (a TUN through the VPN service).
  static Map<String, Object?> build({
    required List<Map<String, Object?>> servers,
    bool systemProxy = false,
    int tolerance = 50,
    String interval = '3m',
    String url = testUrl,
    int proxyPort = 12334,
    // the local control the app reads the servers' latency from and changes the choice through
    String? controlSecret,
    int controlPort = 9090,
    // the core's log: a file (for debugging), or the default output
    String? logFile,
    String logLevel = 'warn',
  }) {
    if (servers.isEmpty) throw ArgumentError('no servers');
    final tags = [for (final s in servers) s['tag']! as String];
    return {
      'log': {'level': logLevel, 'timestamp': true, 'output': ?logFile},
      'dns': {
        // (typed: the app changes a server's type and adds ports and TLS to it)
        'servers': <Map<String, Object?>>[
          {
            'type': 'https',
            'tag': 'remote',
            'server': '8.8.8.8',
            'detour': selectTag,
          },
          {'type': 'local', 'tag': 'local'},
        ],
        'rules': [
          {'clash_mode': 'Direct', 'server': 'local'},
        ],
        'final': 'remote',
        'strategy': 'ipv4_only',
        // an expired answer is given at once and refreshed in the background: sites opened often do not wait for DNS
        'optimistic': true,
      },
      'inbounds': [
        if (systemProxy)
          {
            'type': 'mixed',
            'tag': 'mixed-in',
            'listen': '127.0.0.1',
            'listen_port': proxyPort,
            'set_system_proxy': true,
          }
        else
          {
            'type': 'tun',
            'tag': 'tun-in',
            'address': ['172.19.0.1/30'],
            'mtu': 9000,
            'auto_route': true,
            'strict_route': true,
            'stack': 'mixed',
          },
      ],
      'outbounds': [
        {
          'type': 'selector',
          'tag': selectTag,
          'outbounds': [autoTag, ...tags],
          'default': autoTag,
          'interrupt_exist_connections': true,
        },
        {
          'type': 'urltest',
          'tag': autoTag,
          'outbounds': tags,
          'url': url,
          'interval': interval,
          'tolerance': tolerance,
          'interrupt_exist_connections': false,
        },
        ...servers,
        {'type': 'direct', 'tag': directTag},
      ],
      'route': {
        'rules': [
          {'action': 'sniff'},
          {'protocol': 'dns', 'action': 'hijack-dns'},
          {'ip_is_private': true, 'outbound': directTag},
        ],
        'final': selectTag,
        'auto_detect_interface': true,
        'default_domain_resolver': 'local',
      },
      'experimental': {
        'cache_file': {'enabled': true, 'store_fakeip': false},
        if (controlSecret != null)
          'clash_api': {
            'external_controller': '127.0.0.1:$controlPort',
            'secret': controlSecret,
          },
      },
    };
  }
}
