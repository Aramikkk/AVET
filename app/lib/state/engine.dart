import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:avet/config/config_builder.dart';
import 'package:avet/config/networks.dart';
import 'package:avet/config/rule_lists.dart';
import 'package:avet/config/rules.dart';
import 'package:avet/core/control.dart';
import 'package:avet/data/app_names.dart';
import 'package:avet/data/dns_servers.dart';
import 'package:avet/data/flows.dart';
import 'package:avet/state/diag.dart';
import 'package:avet/data/history.dart';
import 'package:avet/data/server_name.dart';
import 'package:avet/routing/routing.dart';
import 'package:avet/subscription/fetch.dart';
import 'package:avet/subscription/links.dart';
import 'package:avet/ui/toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _vpn = MethodChannel('avet/vpn');

enum Phase { off, connecting, on }

/// The rules the user turned on (kept in rules.json).
/// The palette lost raspberry, coral, pink and amber ('accentV' 4, the wine reds came in): they go to the nearest left.
int _accentV4(int v) {
  const map = [0, 1, 2, 2, 1, 2, 7, 8, 9, 9, 10];
  return v >= 0 && v < map.length ? map[v] : v;
}

class RuleSettings {
  const RuleSettings({
    this.adLevel = 0,
    this.phishing = false,
    this.miners = false,
    this.siteGroups = true,
    this.aiGroup = false,
    this.routingList = true,
    this.blockedOnly = true,
    this.global = false,
    this.sharing = false,
    this.superLight = false,
    this.tintIcon = false,
    this.theme = 0,
    this.slowMs = 400,
    this.slowMsLte = 500,
    this.pingTimeout = 10,
    this.pingTimeoutLte = 120,
    this.dnsAuto = true,
    this.aiWifi = const [],
    this.aiLte = const [],
    this.appMode = 0,
    this.apps = const [],
    this.europeOnly = false,
    this.cisOnly = true,
    this.adAllow = const [],
    this.siteTol = 150,
    this.pingUrl = '',
    this.autoStart = true,
    this.lightLook = false,
    this.subHours = 6,
    this.mtu = 0,
    this.dots = true,
    this.hidden = const ['BY', 'RU', 'EU', 'SO'],
    this.hiddenLte = const ['RU', 'KZ'],
    this.pinned = const [],
    this.boot = true,
    this.accent = 4,
    this.paperTone = 2,
    this.dns = 6,
    this.stack = 'mixed',
    this.strict = true,
    this.fragment = false,
    this.chain = '',
    this.fewHopsWifi = false,
    this.fewHopsLte = false,
    this.pingEvery = 3,
    this.autoTol = 100,
    this.autoTolLte = 50,
    this.sleepWifi = true,
    this.sleepLte = true,
    this.sleepCount = 15,
    this.sleepCountLte = 10,
    this.depth = 3,
    this.bg = 3,
    this.looks = const {
      1: [1, 15, 5],
      2: [0, 11, 2],
    },
    this.habit = 2,
    this.priorityWifi = 100,
    this.priorityLte = 100,
    this.ipv6 = 0,
    this.mux = false,
    this.muxProtocol = 0,
    this.muxStreams = 4,
    this.muxPadding = false,
    this.directDns = '',
    this.sharePass = '',
    this.strategy = 3,
    this.homeServer = false,
    this.customApps = const [],
    this.userSites = const [],
    this.siteGroupsLte = true,
    this.strategyLte = 3,
    this.pingOnOpen = true,
    this.homeSites = const [
      'instagram',
      'whatsapp',
      'telegram',
      'youtube',
      'claude',
      'chatgpt',
    ],
    this.logLevel = 'warn',
    this.haptics = true,
    this.notifyInfo = true,
    this.nightMode = false,
    this.homePause = false,
    this.memoryMb = 500,
    this.sharePort = 12334,
    this.dnsCustom = '',
    this.homes = const [],
    this.ipCheck = true,
    this.byNetwork = true,
    this.digits = 0,
    this.fontScale = 1.0,
    this.style = 0,
    this.pingHttp = true,
    this.groupsOff = const [],
    this.restDirect = true,
  });

  final int adLevel;
  final bool phishing;
  final bool miners;
  final bool siteGroups;
  final bool aiGroup;
  final bool routingList;
  final bool blockedOnly;

  /// everything through the VPN, the routing list and the bypass off
  final bool global;

  /// the phone's VPN given to other devices on the network (a proxy port open on the LAN)
  final bool sharing;

  /// the plain screen: only the essentials
  final bool superLight;

  /// the launcher icon takes the colour of the accent (one of the icon aliases of the manifest is shown)
  final bool tintIcon;

  /// the look: 0 as the system's, 1 light, 2 dark
  final int theme;

  /// the delay from which a service's scale turns red
  final int slowMs;

  /// the same for mobile data (a ping this slow turns red there)
  final int slowMsLte;

  /// how long a server may take to answer (a test, a connection), in seconds, by network: past it the server counts as
  /// unreachable; a slow mobile network (a car's modem) needs a long one
  final int pingTimeout;
  final int pingTimeoutLte;

  /// the DNS server is chosen by the best answer at every connection
  final bool dnsAuto;

  /// the countries the AI group takes its server from, the main one first (by network); empty: by ping
  final List<String> aiWifi;
  final List<String> aiLte;

  /// apps by package: 0 not used, 1 these go direct (bypass the VPN), 2 only these go through the VPN
  final int appMode;
  final List<String> apps;

  /// only the servers of Europe / of the world without Russia and Belarus (the whitelist ones for mobile data stay)
  final bool europeOnly;
  final bool cisOnly;

  /// domains the ad blocking never touches
  final List<String> adAllow;

  /// how much slower a service's server may get before the group changes it (ms)
  final int siteTol;

  /// the page the ping is measured against ('' the default)
  final String pingUrl;

  /// connect when the app opens
  final bool autoStart;

  /// no sliding of the pages and no waves: the lighter look
  final bool lightLook;

  /// the subscriptions are loaded again every so many hours (0: never)
  final int subHours;

  /// the tunnel's packet size (0: the default)
  final int mtu;

  /// the pattern of dots on the sheet
  final bool dots;

  /// the countries (codes) whose servers are not used
  final List<String> hidden;

  /// the same for mobile data (LTE): countries whose whitelist servers are not used
  final List<String> hiddenLte;

  /// the servers the user pinned (a long press in the list): Auto keeps them awake and tested whatever the others do
  final List<String> pinned;

  /// connect when the phone has started (the last config is kept for it)
  final bool boot;

  /// the accent colour (an index of the palette) and the tone of the sheet
  final int accent;
  final int paperTone;

  /// the DNS the tunnel asks through the VPN: 0 Google, 1 Cloudflare, 2 Yandex
  final int dns;

  /// the tunnel's network stack (mixed, system, gvisor) and whether its routes are strict
  final String stack;
  final bool strict;

  /// the TLS hello cut in pieces (against filters that read it)
  final bool fragment;

  /// a server the others connect through (a chain: phone, this server, the exit server); '' none
  final String chain;

  /// the fewer-hops mode: the chain is not used, every server is reached directly
  /// Fewer hops, by network: the server in use is held until another is faster by [fewHopsWifiMs] (400) or
  /// [fewHopsLteMs] (600) ms, and the servers are checked rarely
  final bool fewHopsWifi;
  final bool fewHopsLte;
  static const fewHopsWifiMs = 400;
  static const fewHopsLteMs = 600;
  bool fewHopsOf(bool lte) => lte ? fewHopsLte : fewHopsWifi;

  /// the servers are measured again every so many minutes; Auto changes the server when another is faster by [autoTol] ms
  final int pingEvery;
  final int autoTol;

  /// the same for mobile data
  final int autoTolLte;

  /// the smart choice lets the servers outside the best ones sleep (by network), and how many it keeps awake
  final bool sleepWifi;
  final bool sleepLte;
  final int sleepCount;

  /// how many servers stay awake on mobile data ([sleepCount] is for Wi-Fi): each network has its own
  final int sleepCountLte;
  int sleepCountOf(bool lte) => lte ? sleepCountLte : sleepCount;

  /// the volume of the blocks: 0 flat, 1 relief, 2 glass with the accent's glow
  final int depth;

  /// the sheet behind the pages: 0 the look's own, then the ones of the Background setting (ui/backdrops.dart)
  final int bg;

  /// What every look keeps of its own (style number: volume, accent, sheet): the settings above hold the look in use, and the
  /// others wait here until their look is chosen again.
  final Map<int, List<int>> looks;

  /// Where each look begins: volume (0 flat, 1 relief, 2 glass, 3 Liquid), accent (a place in Palette.accents: burgundy, icy, lime) and
  /// the sheet (Backdrops: 3 sunset, 5 mosaic, 2 the theme's own).
  static const presets = <int, List<int>>{
    0: [3, 4, 3],
    1: [1, 15, 5],
    2: [0, 11, 2],
  };

  /// These settings with the look [to] in use: what the look in use has is put away, and the look [to] has what it had, or
  /// what it begins with.
  RuleSettings switchedTo(int to) {
    if (to == style) return this;
    final kept = {
      ...looks,
      style: [depth, accent, bg],
    };
    final next = kept[to] ?? presets[to]!;
    return copyWith(
      style: to,
      depth: next[0],
      accent: next[1],
      bg: next[2],
      looks: kept,
    );
  }

  /// Every look at its beginning, the one in use too (the figures of Dot Matrix in the grotesk).
  RuleSettings withPresets() {
    final p = presets[style] ?? presets[0]!;
    return copyWith(
      depth: p[0],
      accent: p[1],
      bg: p[2],
      digits: style == 0 ? 0 : null,
      looks: {
        for (final e in presets.entries)
          if (e.key != style) e.key: e.value,
      },
    );
  }

  /// the self-learning of the smart choice: 0 off, 1 weak, 2 medium, 3 strong (the most points the habit for a country can
  /// give: 6, 12, 18)
  final int habit;
  int get habitPoints => const [0, 6, 12, 18][habit.clamp(0, 3)];

  /// the main subscription's servers are preferred: others have to be faster by this many ms (0: no preference)
  final int priorityWifi;
  final int priorityLte;

  /// IPv6: 0 off (IPv4 only), 1 on, 2 IPv6 first, 3 IPv6 only
  final int ipv6;

  /// multiplexing of the servers' connections: the protocol (0 h2mux, 1 smux, 2 yamux), streams, padding
  final bool mux;
  final int muxProtocol;
  final int muxStreams;
  final bool muxPadding;

  /// the DNS server for what goes direct (an address; empty: the phone's own)
  final String directDns;

  /// the password of the shared proxy (empty: open to the network)
  final String sharePass;

  /// how Auto picks: 0 the lowest delay, 1 quick to react (checks every minute, changes for a small gain), 2 steady (rare changes)
  final int strategy;

  /// the Server mode: the user's own WireGuard server carries what its address list covers, the rest goes direct
  final bool homeServer;

  /// apps the user gave a server group of their own (package names)
  final List<String> customApps;

  /// sites routed by hand: [{'d': domain, 'vpn': bool}]
  final List<Map<String, Object?>> userSites;

  /// the multi-server mode on mobile data (its own switch; [siteGroups] is Wi-Fi's)
  final bool siteGroupsLte;

  /// the same for mobile data (its network is less steady: checks come often and a better server is taken soon)
  final int strategyLte;

  /// the servers are measured when the app is opened
  final bool pingOnOpen;

  /// the services shown (and measured) on the home screen, by key, up to six
  final List<String> homeSites;

  /// how much the core writes in its journal
  final String logLevel;

  /// a tick on the finger's choices (the bar, the swipes) and the notification's second line
  final bool haptics;
  final bool notifyInfo;

  /// the night mode of the economy group: the app dims and stops what is not needed from the evening; the IP of the exit is checked after a connect
  final bool nightMode;

  /// at home (a known router) the VPN rests; away it comes back by itself
  final bool homePause;

  /// the core is held to a memory limit (it restarts rather than eats the phone's memory); the port of the proxy given to other devices; a DNS server of the user's own
  final int memoryMb;
  final int sharePort;
  final String dnsCustom;
  final List<String> homes;
  final bool ipCheck;

  /// on mobile data only the whitelist servers, on Wi-Fi the others (off: all servers on both)
  final bool byNetwork;

  /// how the figures are drawn (an index of DigitStyle) and the scale of the text
  final int digits;
  final double fontScale;

  /// the look of the home screen and the panel: 0 Dot Matrix, 1 Mosaic
  final int style;

  /// the ping asked by HTTP (no TLS: a lower figure) instead of HTTPS
  final bool pingHttp;

  /// the routing list's groups the user switched off, and what the rest of the traffic does
  final List<String> groupsOff;
  final bool restDirect;

  RuleSettings copyWith({
    int? adLevel,
    bool? phishing,
    bool? miners,
    bool? siteGroups,
    bool? aiGroup,
    bool? routingList,
    bool? blockedOnly,
    bool? global,
    bool? sharing,
    bool? superLight,
    bool? tintIcon,
    int? theme,
    int? slowMs,
    int? slowMsLte,
    int? pingTimeout,
    int? pingTimeoutLte,
    bool? dnsAuto,
    List<String>? aiWifi,
    List<String>? aiLte,
    int? appMode,
    List<String>? apps,
    bool? europeOnly,
    bool? cisOnly,
    List<String>? adAllow,
    int? siteTol,
    String? pingUrl,
    bool? autoStart,
    bool? lightLook,
    int? subHours,
    int? mtu,
    bool? dots,
    List<String>? hidden,
    List<String>? hiddenLte,
    List<String>? pinned,
    bool? boot,
    int? accent,
    int? paperTone,
    int? dns,
    String? stack,
    bool? strict,
    bool? fragment,
    String? chain,
    bool? fewHopsWifi,
    bool? fewHopsLte,
    int? pingEvery,
    int? autoTol,
    int? autoTolLte,
    bool? sleepWifi,
    bool? sleepLte,
    int? sleepCount,
    int? sleepCountLte,
    int? depth,
    int? bg,
    Map<int, List<int>>? looks,
    int? habit,
    int? priorityWifi,
    int? priorityLte,
    int? ipv6,
    bool? mux,
    int? muxProtocol,
    int? muxStreams,
    bool? muxPadding,
    String? directDns,
    String? sharePass,
    int? strategy,
    bool? homeServer,
    List<String>? customApps,
    List<Map<String, Object?>>? userSites,
    bool? siteGroupsLte,
    int? strategyLte,
    bool? pingOnOpen,
    List<String>? homeSites,
    String? logLevel,
    bool? haptics,
    bool? notifyInfo,
    bool? nightMode,
    bool? homePause,
    int? memoryMb,
    int? sharePort,
    String? dnsCustom,
    List<String>? homes,
    bool? ipCheck,
    bool? byNetwork,
    int? digits,
    double? fontScale,
    int? style,
    bool? pingHttp,
    List<String>? groupsOff,
    bool? restDirect,
  }) => RuleSettings(
    adLevel: adLevel ?? this.adLevel,
    phishing: phishing ?? this.phishing,
    miners: miners ?? this.miners,
    siteGroups: siteGroups ?? this.siteGroups,
    aiGroup: aiGroup ?? this.aiGroup,
    routingList: routingList ?? this.routingList,
    blockedOnly: blockedOnly ?? this.blockedOnly,
    global: global ?? this.global,
    sharing: sharing ?? this.sharing,
    superLight: superLight ?? this.superLight,
    tintIcon: tintIcon ?? this.tintIcon,
    theme: theme ?? this.theme,
    slowMs: slowMs ?? this.slowMs,
    slowMsLte: slowMsLte ?? this.slowMsLte,
    pingTimeout: pingTimeout ?? this.pingTimeout,
    pingTimeoutLte: pingTimeoutLte ?? this.pingTimeoutLte,
    dnsAuto: dnsAuto ?? this.dnsAuto,
    aiWifi: aiWifi ?? this.aiWifi,
    aiLte: aiLte ?? this.aiLte,
    appMode: appMode ?? this.appMode,
    apps: apps ?? this.apps,
    europeOnly: europeOnly ?? this.europeOnly,
    cisOnly: cisOnly ?? this.cisOnly,
    adAllow: adAllow ?? this.adAllow,
    siteTol: siteTol ?? this.siteTol,
    pingUrl: pingUrl ?? this.pingUrl,
    autoStart: autoStart ?? this.autoStart,
    lightLook: lightLook ?? this.lightLook,
    subHours: subHours ?? this.subHours,
    mtu: mtu ?? this.mtu,
    dots: dots ?? this.dots,
    hidden: hidden ?? this.hidden,
    hiddenLte: hiddenLte ?? this.hiddenLte,
    pinned: pinned ?? this.pinned,
    boot: boot ?? this.boot,
    accent: accent ?? this.accent,
    paperTone: paperTone ?? this.paperTone,
    dns: dns ?? this.dns,
    stack: stack ?? this.stack,
    strict: strict ?? this.strict,
    fragment: fragment ?? this.fragment,
    chain: chain ?? this.chain,
    fewHopsWifi: fewHopsWifi ?? this.fewHopsWifi,
    fewHopsLte: fewHopsLte ?? this.fewHopsLte,
    pingEvery: pingEvery ?? this.pingEvery,
    autoTol: autoTol ?? this.autoTol,
    autoTolLte: autoTolLte ?? this.autoTolLte,
    sleepWifi: sleepWifi ?? this.sleepWifi,
    sleepLte: sleepLte ?? this.sleepLte,
    sleepCount: sleepCount ?? this.sleepCount,
    sleepCountLte: sleepCountLte ?? this.sleepCountLte,
    depth: depth ?? this.depth,
    bg: bg ?? this.bg,
    looks: looks ?? this.looks,
    habit: habit ?? this.habit,
    priorityWifi: priorityWifi ?? this.priorityWifi,
    priorityLte: priorityLte ?? this.priorityLte,
    ipv6: ipv6 ?? this.ipv6,
    mux: mux ?? this.mux,
    muxProtocol: muxProtocol ?? this.muxProtocol,
    muxStreams: muxStreams ?? this.muxStreams,
    muxPadding: muxPadding ?? this.muxPadding,
    directDns: directDns ?? this.directDns,
    sharePass: sharePass ?? this.sharePass,
    strategy: strategy ?? this.strategy,
    homeServer: homeServer ?? this.homeServer,
    customApps: customApps ?? this.customApps,
    userSites: userSites ?? this.userSites,
    siteGroupsLte: siteGroupsLte ?? this.siteGroupsLte,
    strategyLte: strategyLte ?? this.strategyLte,
    pingOnOpen: pingOnOpen ?? this.pingOnOpen,
    homeSites: homeSites ?? this.homeSites,
    logLevel: logLevel ?? this.logLevel,
    haptics: haptics ?? this.haptics,
    notifyInfo: notifyInfo ?? this.notifyInfo,
    nightMode: nightMode ?? this.nightMode,
    homePause: homePause ?? this.homePause,
    memoryMb: memoryMb ?? this.memoryMb,
    sharePort: sharePort ?? this.sharePort,
    dnsCustom: dnsCustom ?? this.dnsCustom,
    homes: homes ?? this.homes,
    ipCheck: ipCheck ?? this.ipCheck,
    byNetwork: byNetwork ?? this.byNetwork,
    digits: digits ?? this.digits,
    fontScale: fontScale ?? this.fontScale,
    style: style ?? this.style,
    pingHttp: pingHttp ?? this.pingHttp,
    groupsOff: groupsOff ?? this.groupsOff,
    restDirect: restDirect ?? this.restDirect,
  );

  RuleOptions get options => RuleOptions(
    adBlockLevel: adLevel,
    blockPhishing: phishing,
    blockMiners: miners,
    adBlockAllow: adAllow,
    siteGroups: siteGroups,
    siteGroupsLte: siteGroupsLte,
    siteGroupsTolerance: siteTol,
    siteKeys: homeSites,
    customApps: customApps,
    userSites: [
      for (final u in userSites) (domain: '${u['d']}', vpn: u['vpn'] != false),
    ],
    aiGroup: aiGroup,
    aiWifi: aiWifi,
    aiMobile: aiLte,
    sleepWifi: strategy == 3 && sleepWifi,
    sleepLte: strategyLte == 3 && sleepLte,
  );

  Map<String, Object?> toJson() => {
    'ad': adLevel,
    'phishing': phishing,
    'miners': miners,
    'sites': siteGroups,
    'ai': aiGroup,
    'list': routingList,
    'blockedOnly': blockedOnly,
    'global': global,
    'sharing': sharing,
    'superLight': superLight,
    'tintIcon': tintIcon,
    'theme': theme,
    'slowMs': slowMs,
    'slowMsLte': slowMsLte,
    'pingTimeout': pingTimeout,
    'pingTimeoutLte': pingTimeoutLte,
    'dnsAuto': dnsAuto,
    'aiWifi': aiWifi,
    'aiLte': aiLte,
    'appMode': appMode,
    'apps': apps,
    'europeOnly': europeOnly,
    'cisOnly': cisOnly,
    'adAllow': adAllow,
    'siteTol': siteTol,
    'pingUrl': pingUrl,
    'autoStart': autoStart,
    'lightLook': lightLook,
    'subHours': subHours,
    'mtu': mtu,
    'dots': dots,
    'hidden': hidden,
    'hiddenLte': hiddenLte,
    'pinned': pinned,
    'boot': boot,
    'accent': accent,
    'accentV': 4,
    'paperTone': paperTone,
    'dns': dns,
    'stack': stack,
    'strict': strict,
    'fragment': fragment,
    'chain': chain,
    'fewHopsWifi': fewHopsWifi,
    'fewHopsLte': fewHopsLte,
    'pingEvery': pingEvery,
    'autoTol': autoTol,
    'autoTolLte': autoTolLte,
    'sleepWifi': sleepWifi,
    'sleepLte': sleepLte,
    'sleepCount': sleepCount,
    'sleepCountLte': sleepCountLte,
    'depth': depth,
    'depthV': 2,
    'bg': bg,
    'looks': {for (final e in looks.entries) '${e.key}': e.value},
    'lookV': 1,
    'bgV': 5,
    'habit': habit,
    'priorityWifi': priorityWifi,
    'priorityLte': priorityLte,
    'ipv6': ipv6,
    'mux': mux,
    'muxProtocol': muxProtocol,
    'muxStreams': muxStreams,
    'muxPadding': muxPadding,
    'directDns': directDns,
    'sharePass': sharePass,
    'strategy': strategy,
    'homeServer': homeServer,
    'customApps': customApps,
    'userSites': userSites,
    'sitesLte': siteGroupsLte,
    'strategyLte': strategyLte,
    'pingOnOpen': pingOnOpen,
    'homeSites': homeSites,
    'logLevel': logLevel,
    'haptics': haptics,
    'notifyInfo': notifyInfo,
    'nightMode': nightMode,
    'homePause': homePause,
    'memoryMb': memoryMb,
    'sharePort': sharePort,
    'dnsCustom': dnsCustom,
    'homes': homes,
    'ipCheck': ipCheck,
    'byNetwork': byNetwork,
    'digits': digits,
    'fontScaleV2': fontScale,
    'style': style,
    'pingHttp': pingHttp,
    'groupsOff': groupsOff,
    'restDirect': restDirect,
  };

  /// Reads the settings; a file that has no looks yet (an older one, or none) begins every look from its preset.
  static RuleSettings fromJson(Map<dynamic, dynamic> r) {
    final s = _read(r);
    return r['lookV'] == 1 ? s : s.withPresets();
  }

  static RuleSettings _read(Map<dynamic, dynamic> r) => RuleSettings(
    adLevel: r['ad'] as int? ?? 0,
    phishing: r['phishing'] == true,
    miners: r['miners'] == true,
    siteGroups: r['sites'] == true,
    aiGroup: r['ai'] == true,
    routingList: r['list'] != false,
    blockedOnly: r['blockedOnly'] == true,
    global: r['global'] == true,
    sharing: r['sharing'] == true,
    superLight: r['superLight'] == true,
    tintIcon: r['tintIcon'] == true,
    theme: r['theme'] as int? ?? 0,
    slowMs: r['slowMs'] as int? ?? 250,
    slowMsLte: r['slowMsLte'] as int? ?? 500,
    pingTimeout: r['pingTimeout'] as int? ?? 10,
    pingTimeoutLte: r['pingTimeoutLte'] as int? ?? 60,
    dnsAuto: r['dnsAuto'] == true,
    aiWifi: [for (final a in (r['aiWifi'] as List? ?? const [])) '$a'],
    aiLte: [for (final a in (r['aiLte'] as List? ?? const [])) '$a'],
    appMode: r['appMode'] as int? ?? 0,
    apps: [for (final a in (r['apps'] as List? ?? const [])) '$a'],
    europeOnly: r['europeOnly'] == true,
    cisOnly: r['cisOnly'] != false,
    adAllow: [for (final a in (r['adAllow'] as List? ?? const [])) '$a'],
    siteTol: r['siteTol'] as int? ?? 80,
    pingUrl: r['pingUrl'] as String? ?? '',
    autoStart: r['autoStart'] == true,
    lightLook: r['lightLook'] == true,
    subHours: r['subHours'] as int? ?? 0,
    mtu: r['mtu'] as int? ?? 0,
    dots: r['dots'] != false,
    hidden: [for (final a in (r['hidden'] as List? ?? const [])) '$a'],
    hiddenLte: [for (final a in (r['hiddenLte'] as List? ?? const [])) '$a'],
    pinned: [for (final a in (r['pinned'] as List? ?? const [])) '$a'],
    boot: r['boot'] == true,
    // the palette was changed twice ('accentV' 3 is the list now): a colour of an older list goes to the same or the
    // nearest of the new
    accent: () {
      final v = r['accent'] as int? ?? -1;
      final ver = r['accentV'] as int? ?? 1;
      if (ver >= 4 || v < 0) return v;
      if (ver >= 3) return _accentV4(v);
      const v1 = [
        0,
        6,
        8,
        10,
        11,
        12,
        14,
        18,
        20,
        21,
        5,
        16,
        13,
        22,
        7,
        3,
        9,
        23,
      ];
      const v2 = [
        0,
        1,
        2,
        3,
        2,
        4,
        18,
        16,
        18,
        19,
        17,
        15,
        16,
        19,
        20,
        16,
        19,
        23,
      ];
      final map = ver == 2 ? v2 : v1;
      return _accentV4(v < map.length ? map[v] : v);
    }(),
    paperTone: r['paperTone'] as int? ?? 0,
    dns: r['dns'] as int? ?? 0,
    stack: r['stack'] as String? ?? 'mixed',
    strict: r['strict'] != false,
    fragment: r['fragment'] == true,
    chain: r['chain'] as String? ?? '',
    // the single switch of before is both of them
    fewHopsWifi: r['fewHopsWifi'] == true || r['fewHops'] == true,
    fewHopsLte: r['fewHopsLte'] == true || r['fewHops'] == true,
    pingEvery: r['pingEvery'] as int? ?? 3,
    autoTol: r['autoTol'] as int? ?? 50,
    autoTolLte: r['autoTolLte'] as int? ?? (r['autoTol'] as int? ?? 50),
    sleepWifi: r['sleepWifi'] != false,
    sleepLte: r['sleepLte'] != false,
    sleepCount: r['sleepCount'] as int? ?? 10,
    // (the count was one for both networks: mobile data starts from it)
    sleepCountLte:
        r['sleepCountLte'] as int? ?? (r['sleepCount'] as int? ?? 10),
    // (before 'depthV' 2 the volumes were relief and glass: the old relief is gone, the old glass is the relief now)
    depth: r['depthV'] == 2
        ? (r['depth'] as int? ?? 0).clamp(0, 3)
        : (r['depth'] as int? ?? 0) > 0
        ? 1
        : 0,
    // (the backgrounds were listed three times before; 'bgV' 4 is now: aurora, topography, the theme's own. Older lists:
    // 1 the theme's own, aurora, mesh, orbs, topography, mesh with grain, live aurora; 2 live aurora, aurora, topography,
    // mesh with grain; 3 live aurora, aurora, live topography, topography)
    habit: (r['habit'] as int? ?? 2).clamp(0, 3),
    bg: () {
      // (nothing stored: the theme's own sheet)
      if (r['bg'] == null) return 2;
      final v = r['bg'] as int? ?? 0;
      final ver = r['bgV'] as int? ?? 1;
      if (ver >= 5) return v.clamp(0, 5);
      if (ver == 4) {
        // (the ball is gone: aurora instead; sunset and pulse moved up)
        const moved = [0, 1, 2, 0, 3, 4];
        return v >= 0 && v < moved.length ? moved[v] : 0;
      }
      var n = v;
      if (ver < 2) {
        const first = [0, 1, 3, 0, 2, 3, 0];
        n = v >= 0 && v < first.length ? first[v] : 0;
      }
      if (ver < 3) {
        const second = [0, 1, 3, 0];
        n = n >= 0 && n < second.length ? second[n] : 0;
      }
      const third = [0, 0, 1, 1];
      return n >= 0 && n < third.length ? third[n] : 0;
    }(),
    looks: {
      for (final e in ((r['looks'] as Map?) ?? const {}).entries)
        if (int.tryParse('${e.key}') != null && e.value is List)
          int.parse('${e.key}'): [
            for (final v in e.value as List) (v as num).toInt(),
          ],
    },
    priorityWifi: r['priorityWifi'] as int? ?? 100,
    priorityLte: r['priorityLte'] as int? ?? 150,
    ipv6: r['ipv6'] as int? ?? 0,
    mux: r['mux'] == true,
    muxProtocol: r['muxProtocol'] as int? ?? 0,
    muxStreams: r['muxStreams'] as int? ?? 4,
    muxPadding: r['muxPadding'] == true,
    directDns: r['directDns'] as String? ?? '',
    sharePass: r['sharePass'] as String? ?? '',
    strategy: (r['strategy'] as int? ?? 2).clamp(0, 3),
    homeServer: r['homeServer'] == true,
    customApps: [for (final a in (r['customApps'] as List? ?? const [])) '$a'],
    userSites: [
      for (final u in (r['userSites'] as List? ?? const []))
        if (u is Map && '${u['d']}'.isNotEmpty)
          {'d': '${u['d']}', 'vpn': u['vpn'] != false},
    ],
    // a stored single switch (before there were two) holds for mobile data too
    siteGroupsLte: r.containsKey('sitesLte')
        ? r['sitesLte'] == true
        : r['sites'] == true,
    strategyLte: (r['strategyLte'] as int? ?? 1).clamp(0, 3),
    pingOnOpen: r['pingOnOpen'] == true,
    homeSites: r['homeSites'] is List
        ? [for (final a in r['homeSites'] as List) '$a']
        : const [
            'instagram',
            'whatsapp',
            'telegram',
            'youtube',
            'claude',
            'chatgpt',
          ],
    logLevel: r['logLevel'] as String? ?? 'warn',
    haptics: r['haptics'] != false,
    notifyInfo: r['notifyInfo'] != false,
    nightMode: r['nightMode'] == true,
    homePause: r['homePause'] == true,
    // the limit of the core's memory in MB (0: none); a stored on/off switch of before becomes 500 or none
    memoryMb: r['memoryMb'] is int
        ? (r['memoryMb'] as int > 0 && r['memoryMb'] as int < 300
              ? 450
              : r['memoryMb'] as int)
        : (r['memoryLimit'] == false ? 0 : 450),
    sharePort: r['sharePort'] as int? ?? 12334,
    dnsCustom: r['dnsCustom'] as String? ?? '',
    homes: [for (final a in (r['homes'] as List? ?? const [])) '$a'],
    ipCheck: r['ipCheck'] == true,
    byNetwork: r['byNetwork'] != false,
    digits: r['digits'] as int? ?? 0,
    // 100% is now what 85% used to be: a stored old value is moved to the same look (90% of before is 100% now)
    fontScale: r['fontScaleV2'] is num
        ? (r['fontScaleV2'] as num).toDouble()
        : (r['fontScale'] is num
              ? (((r['fontScale'] as num).toDouble() - .05) / .85 * 20)
                        .round() /
                    20
              : 1.0),
    style: r['style'] as int? ?? 0,
    pingHttp: r['pingHttp'] != false,
    groupsOff: [for (final a in (r['groupsOff'] as List? ?? const [])) '$a'],
    restDirect: r['restDirect'] == true,
  );
}

/// One subscription kept: its link, the provider's name for it, when it ends and the body it gave last.
class SubInfo {
  SubInfo(
    this.url, {
    this.title,
    this.expire,
    this.body = '',
    this.at = 0,
    this.custom,
    this.enabled = true,
    this.used = 0,
    this.total = 0,
    this.hours = 0,
    this.web = '',
    this.support = '',
  });

  /// how often it is loaded again, in hours (0: as the general setting says)
  int hours;

  /// the provider's site and its support page (from its headers)
  String web;
  String support;

  /// off: its servers are not used
  bool enabled;

  /// the traffic used and the plan's total (bytes)
  int used;
  int total;

  /// the name the user gave it (it wins over the provider's)
  String? custom;

  /// when it was loaded (ms since the epoch)
  int at;

  final String url;
  String? title;
  DateTime? expire;
  String body;

  /// what the subscription is called: the provider's name, else the site it comes from
  /// Known providers by the host of the link: their own name, not the plan's label ("Доступ 104Д").
  static const _providers = {'accessgate.link': 'Sigma'};

  String get _host {
    final h = Uri.tryParse(url)?.host ?? '';
    for (final e in _providers.entries) {
      if (h == e.key || h.endsWith('.${e.key}')) return e.value;
    }
    return '';
  }

  String get name => (custom != null && custom!.isNotEmpty)
      ? custom!
      : (_host.isNotEmpty
            ? _host
            : title != null && title!.isNotEmpty
            ? title!
            : (Uri.tryParse(url)?.host ?? ''));

  Map<String, Object?> toJson() => {
    'url': url,
    'title': title,
    'expire': expire?.millisecondsSinceEpoch,
    'body': body,
    'at': at,
    'custom': custom,
    'enabled': enabled,
    'used': used,
    'total': total,
    'hours': hours,
    'web': web,
    'support': support,
  };

  static SubInfo fromJson(Map<dynamic, dynamic> j) => SubInfo(
    '${j['url']}',
    title: j['title'] as String?,
    expire: j['expire'] is int
        ? DateTime.fromMillisecondsSinceEpoch(j['expire'] as int)
        : null,
    body: '${j['body'] ?? ''}',
    at: j['at'] as int? ?? 0,
    custom: j['custom'] as String?,
    enabled: j['enabled'] != false,
    used: j['used'] as int? ?? 0,
    total: j['total'] as int? ?? 0,
    hours: j['hours'] as int? ?? 0,
    web: '${j['web'] ?? ''}',
    support: '${j['support'] ?? ''}',
  );
}

const _keep = Object();

/// Everything the screens show.
class EngineState {
  const EngineState({
    this.ready = false,
    this.phase = Phase.off,
    this.error,
    this.network = 'wifi',
    this.url = '',
    this.servers = const [],
    this.rules = const RuleSettings(),
    this.states = const [],
    this.selected,
    this.autoNow,
    this.pings = const [],
    this.up = 0,
    this.down = 0,
    this.open = 0,
    this.vpnConnections = 0,
    this.directConnections = 0,
    this.totalUp = 0,
    this.totalDown = 0,
    this.since,
    this.note,
    this.rev = 0,
    this.subTitle,
    this.subExpire,
    this.sites = const {},
    this.exitIp = '',
    this.subs = const [],
    this.providers = const {},
    this.vpnBytes = 0,
    this.directBytes = 0,
    this.sitesMeasured = false,
    this.homeServers = 0,
    this.homeCountry = '',
    this.siteServers = const {},
    this.updating = const {},
    this.subFlash = const {},
  });

  final bool ready;
  final Phase phase;
  final String? error;

  /// 'wifi' or 'mobile': the network the phone is on
  final String network;
  final String url;

  /// the subscription's servers (sing-box outbounds)
  final List<Map<String, Object?>> servers;
  final RuleSettings rules;

  /// the servers with their last delay, as the core reports them
  final List<ServerState> states;
  final String? selected;
  final String? autoNow;

  /// the last answers of the probe through the server in use (null: lost), the newest last
  final List<int?> pings;
  final int up;
  final int down;
  final int open;
  final int vpnConnections;
  final int directConnections;
  final int totalUp;
  final int totalDown;
  final DateTime? since;

  /// a line about what the app is doing (loading the subscription...)
  final String? note;

  /// counts every new reading of the histories and the flows: the pages that draw them follow it
  final int rev;

  /// the provider's name for the subscription and when it ends
  final String? subTitle;
  final DateTime? subExpire;

  /// the delay to each service on the home screen, by key (null: no answer)
  final Map<String, int?> sites;
  final bool sitesMeasured;

  /// how many WireGuard servers of the user's own are saved (the Server mode needs one)
  final int homeServers;

  /// the country the phone is in (two letters), where what goes direct leaves from; '' when it cannot be told
  final String homeCountry;

  /// the server each service's own group is on (multi-server mode), by the service's key
  final Map<String, String> siteServers;

  /// the subscriptions being loaded now (by link), and the outcome of the last load for a couple of seconds
  final Set<String> updating;
  final Map<String, bool> subFlash;

  /// the address and country the traffic leaves from (when the IP check is on)
  final String exitIp;

  /// the subscriptions kept, and the name of the one each server came from
  final List<SubInfo> subs;
  final Map<String, String> providers;

  /// what this session moved through a server and direct
  final int vpnBytes;
  final int directBytes;

  bool get on => phase == Phase.on;

  /// the server the traffic goes through now: the one chosen, or what Auto has chosen
  String? get current {
    final s = selected;
    if (s == null) return null;
    return s.startsWith('auto') ? autoNow : s;
  }

  int? get ping => pings.isEmpty ? null : pings.last;

  /// the share of the probes lost in the history kept, in percent
  double get loss => pings.length < 8
      ? 0
      : pings.where((p) => p == null).length * 100 / pings.length;

  /// the servers of the network the phone is on (all of them when it has none of its own)
  List<ServerState> get shown {
    final mobile = network == 'mobile';
    final own = states
        .where((s) => Networks.isMobileOnly(s.tag) == mobile)
        .toList();
    return own.isEmpty ? states : own;
  }

  /// the ping that counts as slow (red) on the network the phone is on
  int get slowAt => network == 'mobile' ? rules.slowMsLte : rules.slowMs;

  /// the servers of the network the phone is on that answered their last test, the fastest first
  List<ServerState> get answering =>
      shown.where((s) => s.delay != null && s.delay! < 65000).toList()
        ..sort((a, b) => a.delay!.compareTo(b.delay!));

  EngineState copyWith({
    bool? ready,
    Phase? phase,
    Object? error = _keep,
    String? network,
    String? url,
    List<Map<String, Object?>>? servers,
    RuleSettings? rules,
    List<ServerState>? states,
    Object? selected = _keep,
    Object? autoNow = _keep,
    List<int?>? pings,
    int? up,
    int? down,
    int? open,
    int? vpnConnections,
    int? directConnections,
    int? totalUp,
    int? totalDown,
    Object? since = _keep,
    Object? note = _keep,
    int? rev,
    Object? subTitle = _keep,
    Object? subExpire = _keep,
    Map<String, int?>? sites,
    bool? sitesMeasured,
    int? homeServers,
    String? homeCountry,
    Map<String, String>? siteServers,
    Set<String>? updating,
    Map<String, bool>? subFlash,
    String? exitIp,
    List<SubInfo>? subs,
    Map<String, String>? providers,
    int? vpnBytes,
    int? directBytes,
  }) => EngineState(
    ready: ready ?? this.ready,
    phase: phase ?? this.phase,
    error: identical(error, _keep) ? this.error : error as String?,
    network: network ?? this.network,
    url: url ?? this.url,
    servers: servers ?? this.servers,
    rules: rules ?? this.rules,
    states: states ?? this.states,
    selected: identical(selected, _keep) ? this.selected : selected as String?,
    autoNow: identical(autoNow, _keep) ? this.autoNow : autoNow as String?,
    pings: pings ?? this.pings,
    up: up ?? this.up,
    down: down ?? this.down,
    open: open ?? this.open,
    vpnConnections: vpnConnections ?? this.vpnConnections,
    directConnections: directConnections ?? this.directConnections,
    totalUp: totalUp ?? this.totalUp,
    totalDown: totalDown ?? this.totalDown,
    since: identical(since, _keep) ? this.since : since as DateTime?,
    note: identical(note, _keep) ? this.note : note as String?,
    rev: rev ?? this.rev,
    subTitle: identical(subTitle, _keep) ? this.subTitle : subTitle as String?,
    sites: sites ?? this.sites,
    sitesMeasured: sitesMeasured ?? this.sitesMeasured,
    homeServers: homeServers ?? this.homeServers,
    homeCountry: homeCountry ?? this.homeCountry,
    siteServers: siteServers ?? this.siteServers,
    updating: updating ?? this.updating,
    subFlash: subFlash ?? this.subFlash,
    exitIp: exitIp ?? this.exitIp,
    subs: subs ?? this.subs,
    providers: providers ?? this.providers,
    vpnBytes: vpnBytes ?? this.vpnBytes,
    directBytes: directBytes ?? this.directBytes,
    subExpire: identical(subExpire, _keep)
        ? this.subExpire
        : subExpire as DateTime?,
  );
}

final engineProvider = NotifierProvider<Engine, EngineState>(Engine.new);

/// The app's one engine: the subscription, the rules, the connection and what the core reports while it runs.
class Engine extends Notifier<EngineState> {
  String? _dir;

  /// the app's folder (the journal and the saved data are in it)
  String? get dir => _dir;
  Control? _control;
  Timer? _poll;
  Timer? _probe;
  Timer? _conn;
  Timer? _sites;

  /// Whether the home screen is in front: the delays to its services are measured only then (each round opens a dozen
  /// connections with their handshakes: a burst of work that nobody sees on another page).
  static final homeShown = ValueNotifier<bool>(true);
  DateTime _sitesAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _seenHome() {
    if (homeShown.value &&
        state.on &&
        DateTime.now().difference(_sitesAt) > const Duration(seconds: 12)) {
      unawaited(measureSites());
    }
  }

  Timer? _autoTimer;
  Timer? _homeTimer;
  Timer? _ipTimer;
  bool _measuring = false;
  StreamSubscription<({int up, int down})>? _traffic;
  bool _probing = false;

  /// the traffic and the ping over time, kept on disk (what the Statistics show)
  HistoryStore? history;

  /// what the session's connections moved, by line (what the Topology shows)
  final flows = FlowTracker();

  /// an answer has come on this connection: the probes lost before it (the tunnel coming up) are not recorded
  bool _answered = false;

  /// the answers kept: the history the graph shows
  static const keptPings = 24;

  File get _urlFile => File('$_dir/subscription_url.txt');
  File get _bodyFile => File('$_dir/subscription.txt');
  File get _infoFile => File('$_dir/subscription_info.json');
  File get _subsFile => File('$_dir/subscriptions.json');
  File get _rulesFile => File('$_dir/rules.json');
  // the user's own WireGuard servers (with their private keys: only in the app's own folder)
  File get _wgFile => File('$_dir/wireguard.json');

  @override
  EngineState build() {
    ref.onDispose(_stopLive);
    ref.onDispose(() {
      _autoTimer?.cancel();
      _homeTimer?.cancel();
    });
    unawaited(_load());
    return const EngineState();
  }

  Future<void> _load() async {
    _dir = await _vpn.invokeMethod<String>('dir');
    var rules = const RuleSettings();
    final subs = <SubInfo>[];
    try {
      if (_subsFile.existsSync()) {
        for (final j in jsonDecode(_subsFile.readAsStringSync()) as List) {
          subs.add(SubInfo.fromJson(j as Map));
        }
      } else if (_urlFile.existsSync() && _bodyFile.existsSync()) {
        // the single subscription of the first versions
        final info = SubInfo(
          _urlFile.readAsStringSync(),
          body: _bodyFile.readAsStringSync(),
        );
        try {
          if (_infoFile.existsSync()) {
            final i = jsonDecode(_infoFile.readAsStringSync()) as Map;
            info.title = i['title'] as String?;
            final e = i['expire'] as int?;
            if (e != null) info.expire = DateTime.fromMillisecondsSinceEpoch(e);
          }
        } catch (_) {}
        subs.add(info);
      }
    } catch (_) {}
    if (_rulesFile.existsSync()) {
      try {
        rules = RuleSettings.fromJson(
          jsonDecode(_rulesFile.readAsStringSync()) as Map,
        );
      } catch (_) {}
    }
    // the screen is in front: the service's collector (if it was running while the app was closed) saves and stops
    try {
      await _vpn.invokeMethod<void>('uiForeground', {'on': true});
    } catch (_) {}
    history = HistoryStore(File('$_dir/history.json'))..load();
    state = state.copyWith(homeServers: _wireguard().length);
    final st = await _vpn.invokeMapMethod<String, Object?>('status');
    final running = st?['running'] == true;
    state = state.copyWith(ready: true, rules: rules, subs: subs);
    unawaited(syncIcon());
    unawaited(_loadHomeCountry());
    _apply(subs);
    state = state.copyWith(phase: running ? Phase.on : Phase.off);
    if (running) {
      // the service is already up (started at the phone's boot, or again by the system): taken over with the key of
      // its core, so the screen reads the core as after a start made here
      final secret = _runningSecret();
      if (secret != null) {
        _control = Control(secret);
        _sessionSecret = secret;
        _answered = false;
        flows.reset();
        diag('takeover: the service was running');
        // the session goes on where the closed app left it: the time since the start, the ping history, the flows
        final saved = _readSession(secret);
        state = state.copyWith(
          since: saved?.since ?? DateTime.now(),
          pings: saved?.pings ?? const [],
        );
        _resolveApps();
        _startLive();
      }
    }
    _homeTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => unawaited(_homeTick()),
    );
    _autoTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => unawaited(_autoUpdate()),
    );
    unawaited(_autoUpdate());
    if (rules.autoStart && !running && state.servers.isNotEmpty) {
      unawaited(start());
    } else {
      unawaited(checkConnect());
    }
  }

  /// Asks the system for the names and icons of the apps in the flows (those taken from the disk too: a restarted app has
  /// lost what it knew, and the flows kept by the collector name the apps by uid only).
  void _resolveApps() {
    final unknown = <String>{
      for (final k in flows.flows.keys)
        if (AppNames.needs(k.app)) k.app,
    };
    if (unknown.isEmpty) return;
    unawaited(
      AppNames.resolve(unknown).then((came) {
        if (came) state = state.copyWith(rev: state.rev + 1);
      }),
    );
  }

  /// The key of the running core's control, from the last start (null: none known).
  String? _runningSecret() {
    for (final name in const ['resume.json', 'last_start.json']) {
      try {
        final f = File('$_dir/$name');
        if (!f.existsSync()) continue;
        final s = (jsonDecode(f.readAsStringSync()) as Map)['secret'];
        if (s is String && s.isNotEmpty) return s;
      } catch (_) {}
    }
    return null;
  }

  bool _pausedHome = false;

  /// The router's address of the Wi-Fi now ('' on mobile data or none).
  Future<String> gateway() async {
    try {
      return await _vpn.invokeMethod<String>('gateway') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Remembers the router of the Wi-Fi the phone is on as a home.
  Future<bool> addHome() async {
    final g = await gateway();
    if (g.isEmpty || state.rules.homes.contains(g)) return false;
    setRules(state.rules.copyWith(homes: [...state.rules.homes, g]));
    return true;
  }

  /// Every few seconds: at a home network the VPN rests, away from it it comes back.
  Future<void> _homeTick() async {
    // the session is kept on disk now and then (a closed app takes it up again)
    if (state.on &&
        DateTime.now().difference(_sessionSaved) >
            const Duration(seconds: 15)) {
      _saveSession();
    }
    final r = state.rules;
    if (!r.homePause || r.homes.isEmpty || !state.ready) return;
    final g = await gateway();
    final home = g.isNotEmpty && r.homes.contains(g);
    if (home && state.on) {
      _pausedHome = true;
      await stop();
    } else if (!home && _pausedHome && state.phase == Phase.off) {
      _pausedHome = false;
      await start();
    }
  }

  /// Asks a service where the traffic leaves from (it goes through the VPN like everything else).
  bool _ipBusy = false;
  DateTime _ipTried = DateTime.fromMillisecondsSinceEpoch(0);

  /// The exit's address and country, asked of a few services in turn (one that does not answer is not the end of it);
  /// when none answers, the line stays empty and the poll asks again a little later.
  Future<void> checkIp() async {
    if (!state.on ||
        !state.rules.ipCheck ||
        state.rules.superLight ||
        _ipBusy) {
      return;
    }
    _ipBusy = true;
    _ipTried = DateTime.now();
    try {
      for (final url in const [
        'https://api.country.is/',
        'https://ipinfo.io/json',
        'https://ipwho.is/',
      ]) {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 5);
        try {
          final req = await client
              .getUrl(Uri.parse(url))
              .timeout(const Duration(seconds: 6));
          final res = await req.close().timeout(const Duration(seconds: 6));
          final body = await res.transform(utf8.decoder).join();
          final j = jsonDecode(body) as Map;
          final country = '${j['country'] ?? j['country_code'] ?? ''}';
          final ip = '${j['ip'] ?? ''}';
          if (country.isEmpty || ip.isEmpty) continue;
          if (state.on) state = state.copyWith(exitIp: '$country · $ip');
          return;
        } catch (_) {
          // the next service
        } finally {
          client.close(force: true);
        }
      }
    } finally {
      _ipBusy = false;
    }
  }

  /// The app came to the front: the servers are measured if the setting says so.
  Future<void> opened() async {
    // opening the app: the servers are measured again when the setting says so, and always when some sleep (all of them
    // are tested for a while, then the sleeping begins again)
    final r = state.rules;
    final lte = state.network == 'mobile';
    final sleeps =
        (lte ? r.strategyLte : r.strategy) == 3 &&
        (lte ? r.sleepLte : r.sleepWifi);
    if (state.on && (r.pingOnOpen || sleeps)) await testAll();
  }

  /// The tile asked to connect: done once, when the app is in front.
  Future<void> checkConnect() async {
    if (state.phase != Phase.off || state.servers.isEmpty) return;
    try {
      if (await _vpn.invokeMethod<bool>('takeConnect') == true) {
        unawaited(start());
      }
    } catch (_) {}
  }

  /// The subscriptions loaded again when their time is up (the interval of the settings).
  Future<void> _autoUpdate() async {
    final general = state.rules.subHours;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final x in [...state.subs]) {
      final hours = x.hours > 0 ? x.hours : general;
      if (hours <= 0) continue;
      if (now - x.at >= hours * 3600 * 1000) {
        await updateSubscription(x.url, notify: false);
      }
    }
  }

  /// The servers of all the subscriptions together (a tag that is already taken gets a number), and which subscription each came from.
  void _apply(List<SubInfo> subs) {
    final servers = <Map<String, Object?>>[];
    final providers = <String, String>{};
    final used = <String>{};
    for (final sub in subs) {
      if (!sub.enabled) continue;
      for (final server in Links.parseSubscription(sub.body)) {
        // a notice of the provider in the shape of a server (the device limit, "download the app") is not a server
        if (SubscriptionFetch.isDecoyServer(server)) continue;
        var tag = '${server['tag']}';
        var n = 2;
        while (!used.add(tag)) {
          tag = '${server['tag']} ($n)';
          n++;
        }
        servers.add({...server, 'tag': tag});
        providers[tag] = sub.name;
      }
    }
    final first = subs.isEmpty ? null : subs.first;
    state = state.copyWith(
      subs: subs,
      servers: servers,
      providers: providers,
      url: first?.url ?? '',
      subTitle: first?.name,
      subExpire: first?.expire,
    );
  }

  void _saveSubs() => _subsFile.writeAsStringSync(
    jsonEncode([for (final x in state.subs) x.toJson()]),
  );

  /// Gives a subscription a name of the user's own ('' returns to the provider's).
  void renameSubscription(String url, String name) {
    final subs = [...state.subs];
    final i = subs.indexWhere((x) => x.url == url);
    if (i < 0) return;
    subs[i].custom = name.trim().isEmpty ? null : name.trim();
    _apply(subs);
    _saveSubs();
  }

  /// Switches a subscription on or off: its servers join or leave the list.
  void enableSubscription(String url, bool on) {
    final subs = [...state.subs];
    final i = subs.indexWhere((x) => x.url == url);
    if (i < 0) return;
    subs[i].enabled = on;
    _apply(subs);
    _saveSubs();
  }

  /// Puts a subscription first (its name is the one on the home screen and its servers come first).
  void pinSubscription(String url) {
    final subs = [...state.subs];
    final i = subs.indexWhere((x) => x.url == url);
    if (i <= 0) return;
    subs.insert(0, subs.removeAt(i));
    _apply(subs);
    _saveSubs();
  }

  /// What the last download of a subscription tried and got, into the log (Logs): to see why a provider answers with
  /// decoys. No address and no keys are in it.
  void _logSubscription() {
    final dir = _dir;
    if (dir == null || SubscriptionFetch.trace.isEmpty) return;
    try {
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final off = now.timeZoneOffset;
      final zone =
          '${off.isNegative ? '-' : '+'}${two(off.inHours.abs())}${two(off.inMinutes.abs() % 60)}';
      final at =
          '$zone ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
      File('$dir/box.log').writeAsStringSync(
        [
          for (final l in SubscriptionFetch.trace)
            '$at INFO sub: $l${String.fromCharCode(10)}',
        ].join(),
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  /// Keeps servers that were pasted in (links, a config, a list) as a subscription with no address.
  void _addLocal(String text, bool notify) {
    final servers = Links.parseSubscription(text);
    if (servers.isEmpty) {
      state = state.copyWith(
        note: 'В тексте нет серверов, которые приложение читает',
      );
      if (notify) toast('Не нашёл серверов в тексте');
      return;
    }
    final key =
        'text:${text.trim().hashCode.toRadixString(16)}${text.trim().length}';
    final subs = [...state.subs];
    final at = subs.indexWhere((x) => x.url == key);
    final info = SubInfo(
      key,
      title: 'Свои серверы',
      custom: at < 0 ? null : subs[at].custom,
      enabled: at < 0 ? true : subs[at].enabled,
      body: text,
      at: DateTime.now().millisecondsSinceEpoch,
    );
    if (at < 0) {
      subs.add(info);
    } else {
      subs[at] = info;
    }
    _apply(subs);
    _saveSubs();
    state = state.copyWith(note: 'Серверов: ${state.servers.length}');
    if (notify) toast('Добавлено серверов: ${servers.length}');
  }

  /// Sets how often one subscription is loaded again (0: as the general setting says).
  void setSubscriptionHours(String url, int hours) {
    final subs = [...state.subs];
    final i = subs.indexWhere((x) => x.url == url);
    if (i < 0) return;
    subs[i].hours = hours;
    _apply(subs);
    _saveSubs();
  }

  /// Moves a subscription to another place of the list (dragged).
  void moveSubscription(int from, int to) {
    final subs = [...state.subs];
    if (from < 0 || from >= subs.length) return;
    final item = subs.removeAt(from);
    subs.insert(to.clamp(0, subs.length), item);
    _apply(subs);
    _saveSubs();
  }

  /// Puts the subscriptions in an order: by name, by traffic used, by the day it ends, by the last load.
  void sortSubscriptions(String by, bool ascending) {
    final subs = [...state.subs];
    int cmp(SubInfo a, SubInfo b) => switch (by) {
      'usage' => a.used.compareTo(b.used),
      'expire' => (a.expire?.millisecondsSinceEpoch ?? 1 << 62).compareTo(
        b.expire?.millisecondsSinceEpoch ?? 1 << 62,
      ),
      'update' => a.at.compareTo(b.at),
      _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    };
    subs.sort((a, b) => ascending ? cmp(a, b) : cmp(b, a));
    _apply(subs);
    _saveSubs();
  }

  /// The servers of a subscription as the config of the core takes them (JSON), for sharing.
  String subscriptionJson(String url) {
    final i = state.subs.indexWhere((x) => x.url == url);
    if (i < 0) return '';
    return const JsonEncoder.withIndent(
      '  ',
    ).convert({'outbounds': Links.parseSubscription(state.subs[i].body)});
  }

  /// Takes a subscription out.
  void removeSubscription(String url) {
    final subs = [
      for (final x in state.subs)
        if (x.url != url) x,
    ];
    _apply(subs);
    _saveSubs();
  }

  /// Loads every subscription again.
  Future<void> refreshAll() async {
    for (final x in [...state.subs]) {
      await updateSubscription(x.url);
    }
  }

  static const _europe = {
    'AD',
    'AL',
    'AT',
    'BA',
    'BE',
    'BG',
    'CH',
    'CY',
    'CZ',
    'DE',
    'DK',
    'EE',
    'ES',
    'FI',
    'FR',
    'GB',
    'GR', //
    'HR',
    'HU',
    'IE',
    'IS',
    'IT',
    'LI',
    'LT',
    'LU',
    'LV',
    'MC',
    'MD',
    'ME',
    'MK',
    'MT',
    'NL',
    'NO',
    'PL', //
    'PT', 'RO', 'RS', 'SE', 'SI', 'SK', 'SM', 'UA', 'VA', 'XK',
  };

  /// A server's country code from the flag in its name (null: none).
  static String? countryOf(String tag) => _countryOf(tag);

  /// How often Auto checks the servers of a network: the optimal strategy by the ping setting, the quick one often
  /// (mobile data: every half minute), the steady one rarely.
  static String autoInterval(RuleSettings r, bool lte) {
    final base = _autoInterval(r, lte);
    var seconds =
        int.parse(base.substring(0, base.length - 1)) *
        (base.endsWith('m') ? 60 : 1);
    // Superlight: the checks are twice as rare
    if (r.superLight) seconds *= 2;
    // Fewer hops: the servers are checked at the most every half an hour
    final few = r.fewHopsOf(lte);
    if (few && seconds < 1800) seconds = 1800;
    if (!r.superLight && !few) return base;
    return seconds % 60 == 0 ? '${seconds ~/ 60}m' : '${seconds}s';
  }

  static String _autoInterval(RuleSettings r, bool lte) {
    return switch (lte ? r.strategyLte : r.strategy) {
      1 => lte ? '30s' : '1m',
      2 => '${r.pingEvery * 2}m',
      // the smart choice takes a window of measurements: rounds often enough to fill it in a few minutes
      3 => lte ? '60s' : '2m',
      _ => '${r.pingEvery}m',
    };
  }

  /// The options of the smart choice for a network's Auto, or null when that network does not use it.
  static Map<String, Object?>? autoSmart(
    RuleSettings r,
    bool lte, {
    String? memory,
    String? pins,
  }) {
    if ((lte ? r.strategyLte : r.strategy) != 3) return null;
    final base = lte
        ? {
            'smart': true,
            'smart_dwell': '90s',
            'smart_gain_ms': 20,
            'smart_gain_pct': 20,
            'smart_country_pct': 30,
            'smart_window': 6,
          }
        : {
            'smart': true,
            'smart_dwell': '5m',
            'smart_gain_ms': 30,
            'smart_gain_pct': 25,
            'smart_country_pct': 40,
            'smart_window': 7,
          };
    // the points (the core scores each server out of 100: speed first, then steadiness, the real connections and the habit
    // for the countries used most); the margins above are the old ones in ms, kept for a core without points
    final few = r.fewHopsOf(lte);
    base
      ..['smart_points'] = true
      ..['smart_gain_pts'] = few ? (lte ? 30 : 25) : (lte ? 4 : 6)
      ..['smart_country_pts'] = few ? 8 : 4
      ..['smart_habit'] = r.habitPoints;
    if (memory != null) base['smart_memory'] = memory;
    if (pins != null) base['smart_pins'] = pins;
    if (r.fewHopsOf(lte)) {
      // Fewer hops: a server is held for long and left only for a clearly better one
      base
        ..['smart_dwell'] = '20m'
        ..['smart_gain_ms'] = lte
            ? RuleSettings.fewHopsLteMs
            : RuleSettings.fewHopsWifiMs
        ..['smart_gain_pct'] = 40
        ..['smart_country_pct'] = 60;
    }
    if (!(lte ? r.sleepLte : r.sleepWifi)) return base;
    // the others sleep: the best ones (and a few in turn) are tested, all of them together now and then
    return {
      ...base,
      'smart_active': r.sleepCountOf(lte),
      'smart_explore': lte ? 2 : 3,
      'smart_full': lte ? '20m' : '30m',
      // after a start, and after every forced test (the app opened, the network changed, the bolt) all the servers are
      // tested for this long before the sleeping begins
      'smart_warm': '5m',
    };
  }

  /// Writes the pinned servers where the core reads them (it looks at the file in every round, so a change needs no restart);
  /// returns the path.
  String _writePins(List<String> pinned) {
    final path = '$_dir/pinned.json';
    try {
      File(path).writeAsStringSync(jsonEncode(pinned));
    } catch (_) {}
    return path;
  }

  /// Pins a server, or lets it go (a long press in the list): Auto keeps a pinned server awake and tested, so the sleeping
  /// never leaves it unmeasured, and it is there when it is the best.
  void togglePin(String tag) {
    final now = state.rules.pinned;
    final next = now.contains(tag)
        ? [
            for (final t in now)
              if (t != tag) t,
          ]
        : [...now, tag];
    setRules(state.rules.copyWith(pinned: next));
    _writePins(next);
    toast(
      now.contains(tag)
          ? 'Сервер откреплён'
          : 'Сервер закреплён: Авто держит его включённым',
    );
  }

  /// How much faster another server must be for Auto to change to it.
  static int autoTolerance(RuleSettings r, bool lte) {
    final own = lte ? r.autoTolLte : r.autoTol;
    final tolerance = switch (lte ? r.strategyLte : r.strategy) {
      1 => 10,
      2 => max(own * 4, 200),
      3 => 50, // not used by the smart choice (it has its own margins)
      _ => own,
    };
    // Fewer hops: another server has to be faster by 400 ms (600 on mobile data) before the choice leaves the one in use
    return r.fewHopsOf(lte)
        ? max(
            tolerance,
            lte ? RuleSettings.fewHopsLteMs : RuleSettings.fewHopsWifiMs,
          )
        : tolerance;
  }

  /// The page the ping is measured against: the chosen one (Google by default), over HTTP or HTTPS as the setting says.
  static String pingTarget(RuleSettings rules) => withScheme(
    rules,
    rules.pingUrl.isEmpty ? ConfigBuilder.testUrl : rules.pingUrl,
  );

  /// [url] over HTTP or HTTPS as the ping setting says.
  static String withScheme(RuleSettings rules, String url) {
    return rules.pingHttp
        ? url.replaceFirst('https://', 'http://')
        : url.replaceFirst('http://', 'https://');
  }

  static String? _countryOf(String tag) {
    final flag = ServerName.of(tag).flag;
    if (flag == null) return null;
    final runes = flag.runes.toList();
    if (runes.length < 2) return null;
    return String.fromCharCodes([
      for (final r in runes.take(2)) r - 0x1F1E6 + 0x41,
    ]);
  }

  /// The servers the region switches leave: Europe only, or the world without Russia and Belarus; the whitelist servers
  /// (for mobile data) always stay, and a switch that would leave nothing is not applied.
  static List<Map<String, Object?>> _regionFiltered(
    List<Map<String, Object?>> servers,
    RuleSettings rules, {
    bool mobile = false,
  }) {
    final off = mobile ? rules.hiddenLte : rules.hidden;
    if (!rules.europeOnly && !rules.cisOnly && off.isEmpty) return servers;
    bool stays(Map<String, Object?> s) {
      final tag = '${s['tag']}';
      final whitelist = Networks.isMobileOnly(tag);
      final code = _countryOf(tag);
      // the whitelist servers are for mobile data: Wi-Fi's list does not count them, LTE's list does
      if (whitelist && !mobile) return true;
      if (code != null && off.contains(code)) return false;
      if (whitelist) return true;
      if (!rules.europeOnly && !rules.cisOnly) return true;
      if (rules.cisOnly) return code != 'RU' && code != 'BY';
      return code != null && _europe.contains(code);
    }

    final left = [
      for (final s in servers)
        if (stays(s)) s,
    ];
    return left.isEmpty ? servers : left;
  }

  void setRules(RuleSettings rules) {
    state = state.copyWith(rules: rules);
    _rulesFile.writeAsStringSync(jsonEncode(rules.toJson()));
    unawaited(syncIcon());
  }

  /// the icon the launcher shows now: -1 the usual one, else the palette place of the accent it is tinted in (-2: not told yet)
  int _iconShown = -2;

  /// Shows the launcher icon in the colour of the accent when the setting asks for it (the manifest has an alias of the
  /// activity for each accent; the system takes a few seconds to redraw the icon), else the usual one.
  Future<void> syncIcon() async {
    final r = state.rules;
    final want = !r.tintIcon
        ? -1
        : (r.accent >= 0 ? r.accent : (r.style >= 1 ? 18 : 0));
    if (want == _iconShown) return;
    _iconShown = want;
    try {
      await _vpn.invokeMethod<void>('setIcon', {'index': want});
    } catch (_) {}
  }

  /// The id of this install that providers limit devices by (made once, kept in the app's folder).
  String get deviceId {
    final f = File('$_dir/device_id.txt');
    if (!f.existsSync()) f.writeAsStringSync(SubscriptionFetch.newDeviceId());
    return f.readAsStringSync().trim();
  }

  /// Takes an id the user gives (that of a device the provider already knows): letters, digits and dashes.
  bool setDeviceId(String value) {
    final v = value.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(v)) return false;
    File('$_dir/device_id.txt').writeAsStringSync(v);
    return true;
  }

  /// Loads the subscription from [url] and keeps it.
  Future<void> updateSubscription(String url, {bool notify = true}) async {
    url = url.trim();
    if (url.isEmpty) return;
    // servers kept by themselves (pasted in, with no address): nothing to load again
    if (url.startsWith('text:')) {
      if (notify) toast('Это список серверов без ссылки: обновлять нечего');
      return;
    }
    // a link or a config pasted in instead of an address: its servers are kept as a subscription of their own
    if (!SubscriptionFetch.isAddress(url)) {
      _addLocal(url, notify);
      return;
    }
    url = SubscriptionFetch.unwrap(url);
    state = state.copyWith(
      note: 'Загружаю подписку…',
      error: null,
      updating: {...state.updating, url},
    );
    if (notify) toast('Обновляю подписку…');
    var ok = false;
    try {
      final idFile = File('$_dir/device_id.txt');
      if (!idFile.existsSync()) {
        idFile.writeAsStringSync(SubscriptionFetch.newDeviceId());
      }
      final got = await SubscriptionFetch.fetch(
        url,
        deviceId: idFile.readAsStringSync().trim(),
      );
      _logSubscription();
      final subs = [...state.subs];
      final at = subs.indexWhere((x) => x.url == url);
      final info = SubInfo(
        url,
        custom: at < 0 ? null : subs[at].custom,
        enabled: at < 0 ? true : subs[at].enabled,
        used: SubscriptionFetch.lastUsed,
        total: SubscriptionFetch.lastTotal,
        title: got.title,
        expire: got.expire,
        body: got.body,
        at: DateTime.now().millisecondsSinceEpoch,
        hours: at < 0 ? 0 : subs[at].hours,
        web: SubscriptionFetch.lastWeb,
        support: SubscriptionFetch.lastSupport,
      );
      if (at < 0) {
        subs.add(info);
      } else {
        subs[at] = info;
      }
      _apply(subs);
      _saveSubs();
      final decoy = SubscriptionFetch.isDecoy(got.servers);
      ok = !decoy;
      final said = SubscriptionFetch.messages(got.body).join(' · ');
      state = state.copyWith(
        note: decoy ? 'Провайдер: $said' : 'Серверов: ${state.servers.length}',
      );
      if (notify) {
        toast(
          decoy
              ? 'Провайдер не отдал серверы: $said'
              : 'Подписка обновлена · серверов: ${state.servers.length}',
        );
      }
    } catch (e) {
      state = state.copyWith(note: 'Не загрузилась: $e');
      if (notify) toast('Не удалось обновить подписку');
    } finally {
      state = state.copyWith(
        updating: {...state.updating}..remove(url),
        subFlash: {...state.subFlash, url: ok},
      );
      // the outcome stays on the card for a moment: a tick or a cross in place of the sign
      Timer(const Duration(seconds: 2), () {
        state = state.copyWith(subFlash: {...state.subFlash}..remove(url));
      });
    }
  }

  Future<void> toggle() async {
    if (state.phase == Phase.connecting) return;
    if (state.on) return stop();
    return start();
  }

  Future<void> stop() async {
    await _vpn.invokeMethod('stop');
    _stopLive();
    history?.save(force: true);
    state = state.copyWith(
      phase: Phase.off,
      states: const [],
      pings: const [],
      up: 0,
      down: 0,
      open: 0,
      vpnConnections: 0,
      directConnections: 0,
      since: null,
      selected: null,
      autoNow: null,
      sites: const {},
      sitesMeasured: false,
      exitIp: '',
      vpnBytes: 0,
      directBytes: 0,
    );
  }

  /// The saved WireGuard endpoints, as sing-box takes them.
  List<Map<String, Object?>> _wireguard() {
    try {
      if (!_wgFile.existsSync()) return const [];
      final j = jsonDecode(_wgFile.readAsStringSync()) as Map;
      return [
        for (final e in (j['endpoints'] as List? ?? const []))
          (e as Map).cast<String, Object?>(),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// What the saved server is, without its keys: the peer's address and port and how many address ranges it carries.
  String? homeServerSummary() {
    final list = _wireguard();
    if (list.isEmpty) return null;
    final e = list.first;
    final peers = (e['peers'] as List? ?? const []);
    final peer = peers.isEmpty ? null : peers.first as Map;
    final ranges = (peer?['allowed_ips'] as List? ?? const []).length;
    return '${peer?['address']}:${peer?['port']} · адресов: $ranges';
  }

  /// Saves a WireGuard server from the text the user pasted (a sing-box endpoint, or a config with `endpoints`).
  /// Returns what is wrong with it, or null when it is saved.
  String? saveWireguard(String text) {
    try {
      final j = jsonDecode(text.trim());
      final raw = j is Map && j['endpoints'] is List
          ? j['endpoints'] as List
          : (j is List ? j : [j]);
      final out = <Map<String, Object?>>[];
      for (final e in raw) {
        if (e is! Map || e['type'] != 'wireguard') continue;
        final m = Map<String, Object?>.from(e.cast<String, Object?>());
        // the stock core has no `noise` (the fork's fake packets): left out, the handshake goes plain
        m.remove('noise');
        for (final k in ['address', 'private_key', 'peers']) {
          if (m[k] == null) return 'В конфиге нет поля $k';
        }
        m['tag'] = out.isEmpty ? 'home-wg' : 'home-wg-${out.length + 1}';
        out.add(m);
      }
      if (out.isEmpty) return 'Не нашёл сервер типа wireguard';
      _wgFile.writeAsStringSync(jsonEncode({'endpoints': out}));
      state = state.copyWith(homeServers: out.length);
      return null;
    } catch (_) {
      return 'Это не JSON-конфиг WireGuard';
    }
  }

  Future<void> removeWireguard() async {
    if (_wgFile.existsSync()) _wgFile.deleteSync();
    final wasOn = state.rules.homeServer;
    setRules(state.rules.copyWith(homeServer: false));
    state = state.copyWith(homeServers: 0);
    if (wasOn && state.phase != Phase.off) await restart();
  }

  /// The answers of the DNS servers from the last check (by their place in the list), and whether a check runs.
  static final dnsResults = ValueNotifier<Map<int, int?>>({});
  static final dnsTesting = ValueNotifier<bool>(false);

  /// Asks every DNS server of the list and chooses the one that answers fastest. Returns its name and ping.
  Future<String?> chooseBestDns({bool quiet = false}) async {
    if (dnsTesting.value) return null;
    dnsTesting.value = true;
    try {
      final times = await Future.wait([
        for (final d in dnsServers) probeDns(d.ip),
      ]);
      dnsResults.value = {for (var i = 0; i < times.length; i++) i: times[i]};
      var best = -1;
      for (var i = 0; i < times.length; i++) {
        if (times[i] != null && (best < 0 || times[i]! < times[best]!)) {
          best = i;
        }
      }
      if (best < 0) {
        if (!quiet) toast('Ни один DNS не ответил');
        return null;
      }
      setRules(state.rules.copyWith(dns: best));
      final text = '${dnsServers[best].name} · ${times[best]} мс';
      if (!quiet) {
        toast('Лучший DNS: $text. Применится при следующем подключении');
      }
      return text;
    } finally {
      dnsTesting.value = false;
    }
  }

  /// The Server mode on or off; a running core is started again with the changed config.
  Future<void> toggleHomeServer() async {
    if (state.homeServers == 0) return;
    setRules(state.rules.copyWith(homeServer: !state.rules.homeServer));
    if (state.phase != Phase.off) await restart();
  }

  /// The core started again with a changed config (a mode, the site groups), without the screen going dark: the
  /// readings stay as they were until the new ones come, and the phase goes from on to connecting, never to off.
  Future<void> restart() async {
    if (state.phase == Phase.off) return start();
    await _vpn.invokeMethod('stop');
    _stopLive();
    history?.save(force: true);
    state = state.copyWith(
      phase: Phase.connecting,
      states: const [],
      selected: null,
      autoNow: null,
      sitesMeasured: false,
    );
    await start();
  }

  /// IPv6, the DNS of the direct traffic and multiplexing, put into a config.
  static void applyNetOptions(Map<String, Object?> built, RuleSettings rules) {
    // IPv6: the way names are resolved and, when it is on, an IPv6 address on the tunnel
    (built['dns']! as Map)['strategy'] = const [
      'ipv4_only',
      'prefer_ipv4',
      'prefer_ipv6',
      'ipv6_only',
    ][rules.ipv6.clamp(0, 3)];
    if (rules.ipv6 > 0) {
      for (final i in built['inbounds']! as List) {
        if ((i as Map)['type'] == 'tun') {
          i['address'] = [...(i['address'] as List), 'fdfe:dcba:9876::1/126'];
        }
      }
    }
    // the DNS server for the direct traffic: the one chosen (an address) instead of the phone's own
    final direct = rules.directDns.trim();
    if (direct.isNotEmpty && InternetAddress.tryParse(direct) != null) {
      final servers = (built['dns']! as Map)['servers'] as List;
      for (var i = 0; i < servers.length; i++) {
        if ((servers[i] as Map)['tag'] == 'local') {
          servers[i] = <String, String>{
            'type': 'udp',
            'tag': 'local',
            'server': direct,
          };
        }
      }
    }
    if (rules.mux) {
      // one connection to the server carries many streams (not for the servers with the Vision flow: it does not mix)
      for (final o in built['outbounds']! as List) {
        final m = o as Map;
        if (!const {
              'vless',
              'vmess',
              'trojan',
              'shadowsocks',
            }.contains(m['type']) ||
            (m['flow'] != null && '${m['flow']}'.isNotEmpty)) {
          continue;
        }
        m['multiplex'] = {
          'enabled': true,
          'protocol': const [
            'h2mux',
            'smux',
            'yamux',
          ][rules.muxProtocol.clamp(0, 2)],
          'max_streams': rules.muxStreams,
          if (rules.muxPadding) 'padding': true,
        };
      }
    }
  }

  /// Starts the tunnel. Whatever goes wrong while the config is made or the service is asked to start ends in the
  /// off state with the reason shown, never in a connecting state that does not end.
  Future<void> start() async {
    try {
      await _start().timeout(const Duration(seconds: 60));
    } catch (e) {
      state = state.copyWith(
        phase: Phase.off,
        error: 'Не удалось запустить: $e',
      );
      toast('Не удалось запустить: $e');
    }
  }

  Future<void> _start() async {
    if (state.servers.isEmpty) {
      state = state.copyWith(error: 'Сначала загрузите подписку');
      return;
    }
    state = state.copyWith(phase: Phase.connecting, error: null);
    if (await _vpn.invokeMethod<bool>('prepare') != true) {
      state = state.copyWith(phase: Phase.off, error: 'Нет разрешения на VPN');
      return;
    }
    final secret = List.generate(
      16,
      (_) => Random.secure().nextInt(16).toRadixString(16),
    ).join();
    // the DNS chosen by the best answer, if the setting says so (a few seconds at most)
    if (state.rules.dnsAuto) {
      try {
        await chooseBestDns(quiet: true).timeout(const Duration(seconds: 6));
      } catch (_) {}
    }
    var rules = state.rules;
    if (rules.superLight) {
      // Superlight: only the main page and the plain tunnel; nothing that costs memory or battery
      rules = rules.copyWith(
        siteGroups: false,
        siteGroupsLte: false,
        aiGroup: false,
        sharing: false,
        fragment: false,
        logLevel: 'error',
        ipCheck: false,
        dnsAuto: false,
      );
    }
    // the main subscription's servers (the first of those in use), preferred in the choices when there are several
    final used = state.subs.where((x) => x.enabled).toList();
    final mainTags = used.length > 1
        ? [
            for (final e in state.providers.entries)
              if (e.value == used.first.name) e.key,
          ]
        : const <String>[];
    // one config for both networks: the service points the choice at the network's own group when it changes
    final chosenWifi = _regionFiltered(state.servers, rules);
    final chosenLte = _regionFiltered(state.servers, rules, mobile: true);
    final wifi = rules.byNetwork
        ? Networks.serversFor(chosenWifi, NetworkKind.wifi)
        : chosenWifi;
    final mobile = rules.byNetwork
        ? Networks.serversFor(chosenLte, NetworkKind.mobile)
        : chosenLte;
    // the block lists: the app's own copies (fetched now if missing or a day old), so the core starts without them
    final localLists = await RuleLists.ensure(
      _dir!,
      Rules.blockLists(rules.options),
    ).timeout(const Duration(seconds: 15), onTimeout: () => const {});
    final built = Routing.apply(
      Rules.apply(
        ConfigBuilder.buildForNetworks(
          wifi: wifi,
          mobile: mobile,
          controlSecret: secret,
          logFile: '$_dir/box.log',
          logLevel: rules.logLevel,
          interval: autoInterval(rules, false),
          mobileInterval: autoInterval(rules, true),
          url: pingTarget(rules),
          tolerance: autoTolerance(rules, false),
          mobileTolerance: autoTolerance(rules, true),
          smartWifi: autoSmart(
            rules,
            false,
            memory: '$_dir/habits.json',
            pins: _writePins(rules.pinned),
          ),
          smartMobile: autoSmart(
            rules,
            true,
            memory: '$_dir/habits.json',
            pins: '$_dir/pinned.json',
          ),
          priority: mainTags,
          priorityWifi: rules.priorityWifi,
          priorityMobile: rules.priorityLte,
        ),
        rules.options,
        wifi: [for (final s in wifi) s['tag']! as String],
        mobile: [for (final s in mobile) s['tag']! as String],
        localLists: localLists,
        priority: mainTags,
        priorityWifi: rules.priorityWifi,
        priorityMobile: rules.priorityLte,
      ),
      list: rules.routingList && !rules.global,
      blockedOnly: rules.blockedOnly && !rules.global,
    );
    if (rules.appMode != 0 && rules.apps.isNotEmpty) {
      // the user's apps: listed ones go direct (1), or only listed ones go through the VPN, the rest direct (2)
      final route = built['route']! as Map<String, Object?>;
      final list = List<Object?>.of(route['rules']! as List);
      final at = list.indexWhere((r) => (r as Map)['action'] == 'route');
      list.insert(at < 0 ? list.length : at, {
        'package_name': rules.apps,
        'action': 'route',
        'outbound': rules.appMode == 1
            ? ConfigBuilder.directTag
            : ConfigBuilder.selectTag,
      });
      route['rules'] = list;
      if (rules.appMode == 2) route['final'] = ConfigBuilder.directTag;
    }
    final homes = rules.homeServer
        ? _wireguard()
        : const <Map<String, Object?>>[];
    if (homes.isNotEmpty) {
      // the Server mode: the own WireGuard carries its address ranges (before the rule that sends private ranges
      // direct: a home network is private), the provider carries nothing, the rest goes direct
      built['endpoints'] = homes;
      final route = built['route']! as Map<String, Object?>;
      final list = List<Object?>.of(route['rules']! as List);
      final at = list.indexWhere((r) => (r as Map)['ip_is_private'] == true);
      var k = at < 0 ? list.length : at;
      for (final h in homes) {
        final cidrs = <String>[
          for (final p in (h['peers'] as List? ?? const []))
            for (final a in ((p as Map)['allowed_ips'] as List? ?? const []))
              '$a',
        ];
        if (cidrs.isEmpty) continue;
        list.insert(k++, {
          'ip_cidr': cidrs,
          'action': 'route',
          'outbound': h['tag'],
        });
      }
      route['rules'] = list;
      route['final'] = ConfigBuilder.directTag;
    }
    // how long a server may take to answer: the groups' tests and the connections to the servers (by network: the
    // servers made for the mobile network have the LTE time, the others the Wi-Fi's; the groups by their name)
    {
      final wifiTimeout = rules.pingTimeout.clamp(1, 120);
      final lteTimeout = rules.pingTimeoutLte.clamp(1, 120);
      for (final o in built['outbounds']! as List) {
        final m = o as Map;
        final type = '${m['type']}';
        final tag = '${m['tag']}';
        if (type == 'urltest') {
          m['test_timeout'] =
              '${tag.endsWith('-mobile') ? lteTimeout : wifiTimeout}s';
        } else if (!const {
          'selector',
          'urltest',
          'direct',
          'block',
          'dns',
        }.contains(type)) {
          final mobile = Networks.isMobileOnly(tag);
          m['connect_timeout'] =
              '${rules.byNetwork ? (mobile ? lteTimeout : wifiTimeout) : max(wifiTimeout, lteTimeout)}s';
        }
      }
    }
    // the DNS server, the tunnel's stack and routes
    final dnsOut = (built['dns']! as Map)['servers'] as List;
    for (final d in dnsOut) {
      if ((d as Map)['tag'] == 'remote') {
        final ip =
            rules.dns >= dnsServers.length && rules.dnsCustom.trim().isNotEmpty
            ? rules.dnsCustom.trim()
            : dnsServers[rules.dns.clamp(0, dnsServers.length - 1)].ip;
        d['server'] = ip;
        // Yandex speaks DNS over TLS only
        final dot = dotName(ip);
        if (dot != null) {
          d['type'] = 'tls';
          d['server_port'] = 853;
          d['tls'] = {'enabled': true, 'server_name': dot};
        }
      }
    }
    for (final i in built['inbounds']! as List) {
      if ((i as Map)['type'] == 'tun') {
        i['stack'] = rules.stack;
        i['strict_route'] = rules.strict;
      }
    }
    if (rules.chain.isNotEmpty) {
      // every other server goes out through the chosen one
      final outbounds = built['outbounds']! as List;
      final known = {for (final o in outbounds) (o as Map)['tag']};
      if (known.contains(rules.chain)) {
        for (final o in outbounds) {
          final m = o as Map;
          final type = '${m['type']}';
          if (m['tag'] == rules.chain ||
              const {
                'selector',
                'urltest',
                'direct',
                'block',
                'dns',
              }.contains(type)) {
            continue;
          }
          m['detour'] = rules.chain;
        }
      }
    }
    applyNetOptions(built, rules);
    if (rules.fragment) {
      for (final o in built['outbounds']! as List) {
        final tls = (o as Map)['tls'];
        if (tls is Map && tls['enabled'] == true) tls['record_fragment'] = true;
      }
    }
    if (rules.mtu > 0) {
      for (final i in built['inbounds']! as List) {
        if ((i as Map)['type'] == 'tun') i['mtu'] = rules.mtu;
      }
    }
    if (rules.sharing) {
      // the phone's VPN for other devices: a proxy port open on the network (they set this address as the Wi-Fi's proxy)
      (built['inbounds']! as List).add({
        'type': 'mixed',
        'tag': 'share-in',
        'listen': '0.0.0.0',
        'listen_port': rules.sharePort,
        if (rules.sharePass.isNotEmpty)
          'users': [
            {'username': 'avet', 'password': rules.sharePass},
          ],
      });
    }
    final config = jsonEncode(built);
    // below this the core is restarted by its own memory guard again and again (the tunnel never comes up)
    final memoryMb = rules.memoryMb > 0 && rules.memoryMb < 200
        ? 200
        : rules.memoryMb;
    // kept for the start after the phone's boot (the receiver has no Dart to build it); always, so that turning the
    // setting on later finds a config to start with
    File('$_dir/last_start.json').writeAsStringSync(
      jsonEncode({'config': config, 'secret': secret, 'memoryMb': memoryMb}),
    );
    await _vpn.invokeMethod('start', {
      'config': config,
      'secret': secret,
      'memoryMb': memoryMb,
    });
    _control = Control(secret);
    _sessionSecret = secret;
    diag('start: servers=${state.servers.length}');
    for (var i = 0; i < 24; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final st = await _vpn.invokeMapMethod<String, Object?>('status');
      if (st?['error'] != null) {
        state = state.copyWith(phase: Phase.off, error: '${st!['error']}');
        return;
      }
      if (st?['running'] == true) break;
    }
    _answered = false;
    flows.reset();
    state = state.copyWith(
      phase: Phase.on,
      since: DateTime.now(),
      pings: const [],
    );
    _startLive();
    _saveSession();
    unawaited(testAll());
  }

  String? _sessionSecret;
  DateTime _sessionSaved = DateTime.fromMillisecondsSinceEpoch(0);

  /// The session (when it began, the ping history, what the connections moved) is kept on disk: a closed app finds it
  /// again when it is opened, so the time and the pages go on instead of beginning again.
  void _saveSession() {
    final secret = _sessionSecret;
    final since = state.since;
    if (secret == null || since == null || !state.on) return;
    _sessionSaved = DateTime.now();
    try {
      File('$_dir/session.json').writeAsStringSync(
        jsonEncode({
          'secret': secret,
          'since': since.millisecondsSinceEpoch,
          'pings': state.pings,
          'flows': flows.toJson(),
        }),
      );
    } catch (_) {}
  }

  ({DateTime since, List<int?> pings})? _readSession(String secret) {
    try {
      final f = File('$_dir/session.json');
      if (!f.existsSync()) return null;
      final j = jsonDecode(f.readAsStringSync()) as Map;
      if (j['secret'] != secret) return null;
      flows.restore((j['flows'] as Map?) ?? const {});
      return (
        since: DateTime.fromMillisecondsSinceEpoch((j['since'] as num).toInt()),
        pings: [
          for (final p in (j['pings'] as List? ?? const []))
            p == null ? null : (p as num).toInt(),
        ],
      );
    } catch (_) {
      flows.reset();
      return null;
    }
  }

  /// Whether the app is on the screen. Out of sight only the slow look at the service stays (it keeps the
  /// notification true and notices when the service stops): no probes, no list of connections, no stream of traffic.
  bool _foreground = true;

  void setForeground(bool value) {
    if (value == _foreground) return;
    if (!value) {
      // out of sight: what this screen knows is put on disk, and the service's collector goes on from it
      _saveSession();
      history?.save(force: true);
      _foreground = false;
      if (state.on) _startLive();
      unawaited(_vpn.invokeMethod<void>('uiForeground', {'on': false}));
      return;
    }
    unawaited(_comeBack());
  }

  /// Whether the app works with no battery limits (true when that cannot be told).
  Future<bool> batteryFree() async {
    try {
      return await _vpn.invokeMethod<bool>('batteryFree') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Opens the system's window asking to lift the battery limits.
  Future<void> askBattery() async {
    try {
      await _vpn.invokeMethod<void>('askBattery');
    } catch (_) {}
  }

  /// Asks the phone which country it is in (it changes with the network, roaming): shown in the topology for what goes
  /// direct.
  Future<void> _loadHomeCountry() async {
    try {
      final c = await _vpn.invokeMethod<String>('homeCountry') ?? '';
      if (c.length == 2 && c != state.homeCountry) {
        state = state.copyWith(homeCountry: c);
      }
    } catch (_) {}
  }

  bool get batteryAsked => File('$_dir/battery_asked').existsSync();

  void markBatteryAsked() {
    try {
      File('$_dir/battery_asked').writeAsStringSync('1');
    } catch (_) {}
  }

  /// In front again: the collector saves and stops, the screen reads what it gathered and goes on from there.
  Future<void> _comeBack() async {
    try {
      await _vpn.invokeMethod<void>('uiForeground', {'on': true});
    } catch (_) {}
    if (_foreground) return;
    _foreground = true;
    if (state.on) {
      final secret = _sessionSecret;
      if (secret != null) {
        history?.load();
        final saved = _readSession(secret);
        if (saved != null) {
          state = state.copyWith(since: saved.since, pings: saved.pings);
        }
        _resolveApps();
      }
      _startLive();
    }
  }

  void _startLive() {
    _stopLive();
    if (!_foreground) {
      _poll = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(_refresh()),
      );
      return;
    }
    // Superlight: everything is looked at half as often, and what only the other pages need is not looked at
    final light = state.rules.superLight;
    _poll = Timer.periodic(
      Duration(seconds: light ? 6 : 3),
      (_) => unawaited(_refresh()),
    );
    _probe = Timer.periodic(
      Duration(seconds: light ? 6 : 3),
      (_) => unawaited(_probeOnce()),
    );
    _conn = Timer.periodic(
      Duration(seconds: light ? 8 : 2),
      (_) => unawaited(_connections()),
    );
    if (!light) {
      _sites = Timer.periodic(const Duration(seconds: 12), (_) {
        if (homeShown.value) unawaited(measureSites());
      });
      homeShown
        ..removeListener(_seenHome)
        ..addListener(_seenHome);
      Timer(const Duration(seconds: 2), () => unawaited(measureSites()));
    }
    final c = _control;
    if (c != null) {
      _traffic = c.traffic().listen((t) {
        if (!state.rules.superLight) {
          history?.traffic.add(t.up, t.down);
          history?.save();
        }
        state = state.copyWith(up: t.up, down: t.down, rev: state.rev + 1);
      }, onError: (_) {});
    }
    // the first ping at once, once the servers are known (not after the first period)
    unawaited(_refresh().then((_) => _probeOnce()));
    unawaited(_connections());
    Timer(const Duration(seconds: 4), () => unawaited(checkIp()));
  }

  void _stopLive() {
    _poll?.cancel();
    _probe?.cancel();
    _conn?.cancel();
    _sites?.cancel();
    homeShown.removeListener(_seenHome);
    unawaited(_traffic?.cancel());
    _poll = _probe = _conn = _sites = null;
    _traffic = null;
    _probeClient?.close(force: true);
    _probeClient = null;
  }

  Future<void> _refresh() async {
    final c = _control;
    if (c == null) return;
    try {
      final st = await _vpn.invokeMapMethod<String, Object?>('status');
      if (st?['running'] != true) {
        // the service went away (stopped from the notification, or died): the screen follows it
        _stopLive();
        state = state.copyWith(
          phase: Phase.off,
          error: st?['error'] as String?,
        );
        return;
      }
      final net = (st?['network'] as String?) ?? '';
      final network = net.isEmpty ? 'wifi' : net;
      final s = await c.state(auto: ConfigBuilder.autoFor(network));
      if (state.on &&
          state.rules.ipCheck &&
          state.exitIp.isEmpty &&
          !_ipBusy &&
          DateTime.now().difference(_ipTried) > const Duration(seconds: 12)) {
        unawaited(checkIp());
      }
      final before = state.current;
      if (network != state.network) unawaited(_loadHomeCountry());
      state = state.copyWith(
        network: network,
        selected: s.selected,
        autoNow: s.autoNow,
        siteServers: {
          ...s.sites,
          // the AI services all go through one group
          if (s.ai != null)
            for (final x in services)
              if (x.ai) x.key: s.ai!,
        },
        states: s.servers,
      );
      // another server now (chosen by hand, or Auto moved): where the traffic leaves from has changed too
      if (before != null && state.current != null && before != state.current) {
        state = state.copyWith(exitIp: '');
        _ipTimer?.cancel();
        _ipTimer = Timer(
          const Duration(seconds: 3),
          () => unawaited(checkIp()),
        );
      }
    } catch (_) {}
  }

  /// The services of the home screen.
  static const homeSites = [
    'instagram',
    'whatsapp',
    'telegram',
    'youtube',
    'claude',
    'chatgpt',
  ];

  /// The delay to each of the home screen's services, through the group made for it (multi-server mode) or the server in use.
  /// The time a request to a site takes through the tunnel, as the old app measured it: the first request opens the
  /// connection (its handshakes, the server finding the site), the second goes over it and times just the way there
  /// and back. HEAD (GET for the one that needs it), no redirects, over HTTP unless the setting says HTTPS.
  Future<int?> _siteDelay(HttpClient client, String url) async {
    final uri = Uri.parse(Engine.withScheme(state.rules, url));
    final get = uri.path.contains('cdn-cgi');
    Future<int?> once() async {
      final watch = Stopwatch()..start();
      final req = await (get ? client.getUrl(uri) : client.headUrl(uri))
          .timeout(const Duration(seconds: 5));
      req
        ..followRedirects = false
        ..persistentConnection = true;
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain<void>();
      return res.statusCode >= 500 ? null : watch.elapsedMilliseconds;
    }

    try {
      final first = await once();
      if (first == null) return null;
      int? second;
      try {
        second = await once();
      } catch (_) {
        second = null;
      }
      return second ?? first;
    } catch (_) {
      return null;
    }
  }

  Future<void> measureSites() async {
    final c = _control;
    if (c == null || _measuring || !state.on) return;
    _measuring = true;
    try {
      final out = <String, int?>{};
      // a client of its own each round, so a round starts from fresh connections
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..findProxy = ((_) => 'DIRECT');
      try {
        await Future.wait([
          for (final k in state.rules.homeSites)
            () async {
              final svc = services.firstWhere((e) => e.key == k);
              // the app's own request through the tunnel, not the core's delay test: that one is written into the history
              // Auto chooses by, as if it were the server's own ping, and sent Auto away from a good server
              out[k] = await _siteDelay(client, svc.url);
            }(),
        ]);
      } finally {
        client.close(force: true);
      }
      _sitesAt = DateTime.now();
      if (state.on) state = state.copyWith(sites: out, sitesMeasured: true);
    } finally {
      _measuring = false;
    }
  }

  /// The notification's second line: the server, the ping and the losses.
  Future<void> _sendNotice(int? ping) async {
    if (!state.rules.notifyInfo) return;
    final cur = state.current;
    final name = cur == null ? '' : ServerName.of(cur).label;
    final net = state.network == 'mobile' ? 'LTE' : 'Wi-Fi';
    final text = [
      if (name.isNotEmpty) name,
      if (ping != null) '$ping мс',
      if (state.loss > 0) 'потери ${state.loss.round()}%',
      net,
    ].join(' · ');
    // a changed notification costs the system (and the battery) each time: the figures alone are sent at most every
    // 20 s (a minute in Superlight); a change of the server, the network or the losses at once
    final shape = [name, state.network, state.loss > 0].join('|');
    final now = DateTime.now();
    final gap = Duration(seconds: state.rules.superLight ? 60 : 20);
    if (shape == _noticeShape && now.difference(_noticeAt) < gap) return;
    _noticeShape = shape;
    _noticeAt = now;
    try {
      await _vpn.invokeMethod<void>('notice', {'text': text});
    } catch (_) {}
  }

  String _noticeShape = '';
  DateTime _noticeAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// The kept connection of the probes (as in the old app): a request over a connection that is already open measures
  /// the way there and back, not the handshake of a new one.
  HttpClient? _probeClient;
  String _probeUrl = '';
  bool _probeWarm = true;

  Duration get _probeTimeout => Duration(
    seconds:
        (state.network == 'mobile'
                ? state.rules.pingTimeoutLte
                : state.rules.pingTimeout)
            .clamp(2, 120),
  );

  Future<void> _headOnce(HttpClient client, String url) async {
    final req = await client.headUrl(Uri.parse(url)).timeout(_probeTimeout);
    final res = await req.close().timeout(_probeTimeout);
    await res.drain<void>();
  }

  /// The time a HEAD request to [url] takes over the kept connection through the tunnel, in ms; null: no answer.
  Future<int?> _httpDelay(String url) async {
    if (_probeClient == null || _probeUrl != url) {
      _probeClient?.close(force: true);
      _probeClient = HttpClient()
        ..connectionTimeout = _probeTimeout
        ..idleTimeout = const Duration(seconds: 30)
        ..findProxy = ((_) => 'DIRECT');
      _probeUrl = url;
      _probeWarm = true;
    }
    final client = _probeClient!;
    try {
      if (_probeWarm) {
        // the first request opens the connection (well over a second): not an answer
        _probeWarm = false;
        try {
          await _headOnce(client, url);
        } catch (_) {}
      }
      final watch = Stopwatch()..start();
      try {
        await _headOnce(client, url);
      } on HttpException {
        // a connection kept from before was closed on the way: asked once more on a fresh one
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
    final c = _control;
    final tag = state.current;
    if (c == null || tag == null || _probing) return;
    _probing = true;
    try {
      // a probe that got no answer is asked once more before it counts as lost (one dropped packet is not a loss)
      final target = pingTarget(state.rules);
      // the app's own request through the tunnel, not the core's delay test: that one is written into the history
      // Auto chooses by, and a probe of the server in use made the choice jump from server to server
      var d = await _httpDelay(target);
      d ??= await _httpDelay(target);
      if (d != null) _answered = true;
      if (!_answered) return;
      history?.ping.add(d);
      unawaited(_sendNotice(d));
      final list = [...state.pings, d];
      state = state.copyWith(
        pings: list.length > keptPings
            ? list.sublist(list.length - keptPings)
            : list,
      );
    } finally {
      _probing = false;
    }
  }

  Future<void> _connections() async {
    try {
      final c = _control;
      if (c == null) return;
      final raw = await c.call('GET', '/connections');
      final list = Conn.parse(raw);
      // the pages that use the flows and the names of the apps are not there in Superlight: not kept, not looked up
      final light = state.rules.superLight;
      if (!light) {
        flows.update(list, DateTime.now());
        // the names of the apps the core named by uid (asked once; the picture follows when they come)
        _resolveApps();
      }
      final m = raw is Map ? raw : const {};
      state = state.copyWith(
        open: list.length,
        vpnBytes: flows.vpnBytes,
        directBytes: flows.directBytes,
        vpnConnections: list.where((e) => !e.direct).length,
        directConnections: list.where((e) => e.direct).length,
        totalUp: (m['uploadTotal'] as num?)?.toInt() ?? state.totalUp,
        totalDown: (m['downloadTotal'] as num?)?.toInt() ?? state.totalDown,
        rev: state.rev + 1,
      );
    } catch (_) {}
  }

  /// Measures every server of the network's Auto now.
  Future<void> testAll() async {
    try {
      await _control?.testAll(auto: ConfigBuilder.autoFor(state.network));
    } catch (_) {}
    await _refresh();
  }

  /// Set while the best server is being looked for (the bolt charges).
  static final bestRunning = ValueNotifier<bool>(false);
  int _boltWatch = 0;

  /// The bolt: every server is measured anew and the one with the lowest delay is chosen by hand. After it the choice is
  /// watched: when the connection through that server stops answering or gets slow three checks running, the choice
  /// goes back to Auto.
  Future<void> chooseBest() async {
    if (bestRunning.value || !state.on) return;
    bestRunning.value = true;
    try {
      await Future.wait([testAll(), measureSites()]);
      await _refresh();
      final real = {for (final x in state.servers) '${x['tag']}'};
      final mobile = state.network == 'mobile';
      ServerState? pick;
      for (final e in state.states) {
        final d = e.delay;
        if (!real.contains(e.tag) || d == null || d <= 0 || d >= 65000) {
          continue;
        }
        if (state.rules.byNetwork && Networks.isMobileOnly(e.tag) != mobile) {
          continue;
        }
        if (pick == null || d < pick.delay!) pick = e;
      }
      if (pick == null) {
        toast('Ни один сервер не ответил');
        return;
      }
      await choose(pick.tag);
      toast(
        'Самый быстрый: ${ServerName.of(pick.tag).label} · ${pick.delay} мс',
      );
      unawaited(_watchBolt(pick.tag));
    } catch (_) {
      // no connection: nothing to measure
    } finally {
      bestRunning.value = false;
    }
  }

  Future<void> _watchBolt(String tag) async {
    final id = ++_boltWatch;
    var bad = 0;
    var seen = 0;
    while (id == _boltWatch) {
      await Future<void>.delayed(const Duration(seconds: 10));
      if (id != _boltWatch || !state.on || state.selected != tag) return;
      final probes = state.pings;
      if (probes.length < 6 || probes.length == seen) continue;
      seen = probes.length;
      final recent = probes
          .sublist(probes.length - 6)
          .whereType<int>()
          .toList();
      final average = recent.isEmpty
          ? 0
          : recent.reduce((a, b) => a + b) / recent.length;
      final dead = recent.length <= 2;
      bad = (dead || average >= state.slowAt) ? bad + 1 : 0;
      if (bad < 3) continue;
      await choose(ConfigBuilder.autoFor(state.network));
      toast('Сервер перестал отвечать: вернул автовыбор');
      return;
    }
  }

  Future<void> choose(String tag) async {
    await _control?.choose(tag);
    // a server picked by hand is a strong sign of the country the user wants: the smart choice learns from it
    if (!tag.startsWith('auto')) {
      _habitEvent(
        country: countryOfTag(tag),
        group: ConfigBuilder.autoFor(state.network),
      );
    }
    await _refresh();
  }

  /// What the core is told of the user's choices (it reads the file when it next looks): the countries picked by hand, and
  /// the reset of what was learned. Each event has an id that only grows; the core takes each once.
  void _habitEvent({
    String country = '',
    String group = '',
    bool reset = false,
  }) {
    try {
      final f = File('$_dir/habit_events.json');
      var events = <Object?>[];
      if (f.existsSync()) {
        events =
            ((jsonDecode(f.readAsStringSync()) as Map)['events'] as List?) ??
            [];
      }
      if (!reset && (country.isEmpty || group.isEmpty)) return;
      events.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        if (reset) 'reset': true else ...{'g': group, 'c': country},
      });
      if (events.length > 30) events = events.sublist(events.length - 30);
      f.writeAsStringSync(jsonEncode({'events': events}));
    } catch (_) {}
  }

  /// Forgets what the smart choice has learned of the countries.
  void resetHabits() {
    _habitEvent(reset: true);
    try {
      File('$_dir/habits.json').deleteSync();
    } catch (_) {}
    toast('Обучение сброшено');
  }
}

/// The two-letter country code from the flag in a server's name ('' when there is none): what the smart choice counts by.
String countryOfTag(String tag) {
  final codes = <int>[];
  for (final r in tag.runes) {
    if (r >= 0x1F1E6 && r <= 0x1F1FF) {
      codes.add(0x41 + r - 0x1F1E6);
      if (codes.length == 2) return String.fromCharCodes(codes);
    } else if (codes.isNotEmpty) {
      codes.clear();
    }
  }
  return '';
}
