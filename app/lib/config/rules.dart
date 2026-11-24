import 'package:avet/config/config_builder.dart';

/// What the user turned on: ad blocking, the services' own groups, the AI group.
class RuleOptions {
  const RuleOptions({
    this.adBlockLevel = 0,
    this.blockPhishing = false,
    this.blockMiners = false,
    this.adBlockAllow = const [],
    this.siteGroups = false,
    this.siteGroupsLte = false,
    this.siteGroupsTolerance = 80,
    this.siteKeys = const [],
    this.customApps = const [],
    this.userSites = const [],
    this.aiGroup = false,
    this.aiWifi = const [],
    this.aiMobile = const [],
    this.sleepWifi = false,
    this.sleepLte = false,
  });

  /// 0: off; 1 mild, 2 normal, 3 strict (the more lists, the more is refused, and the more sites leaning on an ad host
  /// break).
  final int adBlockLevel;
  final bool blockPhishing;
  final bool blockMiners;

  /// Domains (and their subdomains) never blocked, as the user typed them.
  final List<String> adBlockAllow;

  /// Each service the home screen times gets an Auto of its own, tested against the service's own page.
  final bool siteGroups;

  /// the same for mobile data (its own switch)
  final bool siteGroupsLte;
  final int siteGroupsTolerance;

  /// the services that get a group (the ones the home screen shows); empty: every one
  final List<String> siteKeys;

  /// apps of the user's own that get a server group of their own (a package name each)
  final List<String> customApps;

  /// sites the user routes by hand: the domain (its subdomains too) and whether it goes through the VPN
  final List<({String domain, bool vpn})> userSites;

  /// One server for every AI service, kept while it works (the AI services dislike a changed address).
  final bool aiGroup;

  /// the countries (codes) the AI group's server is taken from, the main one first, by network
  final List<String> aiWifi;
  final List<String> aiMobile;

  /// the service groups of a network test only the best servers each round and let the others sleep (the smart choice)
  final bool sleepWifi;
  final bool sleepLte;
}

/// A service with a group of its own: the page it is tested against and what of its traffic goes to the group.
class Service {
  const Service(
    this.key,
    this.url,
    this.domains, {
    this.cidrs = const [],
    this.packages = const [],
    this.ai = false,
  });

  final String key;
  final String url;
  final List<String> domains;
  final List<String> cidrs;
  final List<String> packages;
  final bool ai;
}

const services = [
  Service(
    'instagram',
    'https://www.instagram.com/',
    [
      'instagram.com',
      'cdninstagram.com',
      'instagr.am',
      'ig.me',
      'fbcdn.net', //
    ],
    packages: ['com.instagram.android', 'com.instagram.lite'],
  ),
  Service(
    'whatsapp',
    'https://web.whatsapp.com/',
    [
      'whatsapp.com', 'whatsapp.net', 'wa.me', //
    ],
    packages: ['com.whatsapp', 'com.whatsapp.w4b'],
  ),
  Service(
    'telegram',
    'https://telegram.org/',
    [
      'telegram.org',
      't.me',
      'telegram.me',
      'telesco.pe',
      'telegra.ph',
      'tdesktop.com',
      'cdn-telegram.org',
    ],
    // Telegram's apps reach its data centres by address, not by name
    cidrs: [
      '91.105.192.0/23',
      '91.108.4.0/22',
      '91.108.8.0/22',
      '91.108.12.0/22',
      '91.108.16.0/22',
      '91.108.20.0/22',
      '91.108.56.0/22',
      '95.161.64.0/20',
      '149.154.160.0/20',
      '185.76.151.0/24', //
      '2001:67c:4e8::/48',
      '2001:b28:f23c::/47',
      '2001:b28:f23f::/48',
      '2a0a:f280::/32',
    ],
    packages: [
      'org.telegram.messenger',
      'org.telegram.messenger.web',
      'org.telegram.plus',
      'org.thunderdog.challegram',
    ],
  ),
  Service(
    'youtube',
    'https://www.youtube.com/generate_204',
    [
      'youtube.com',
      'youtu.be',
      'googlevideo.com',
      'ytimg.com',
      'ggpht.com',
      'youtube-nocookie.com',
      'youtubei.googleapis.com', //
    ],
    packages: ['com.google.android.youtube', 'app.revanced.android.youtube'],
  ),
  Service(
    'gdrive',
    'https://drive.google.com/',
    [
      'drive.google.com', 'docs.google.com', 'drive.usercontent.google.com', //
    ],
    packages: ['com.google.android.apps.docs'],
  ),
  Service(
    'chatgpt',
    'https://chatgpt.com/cdn-cgi/trace',
    [
      'chatgpt.com',
      'openai.com',
      'oaistatic.com',
      'oaiusercontent.com',
      'sora.com', //
    ],
    packages: ['com.openai.chatgpt'],
    ai: true,
  ),
  Service(
    'gemini',
    'https://gemini.google.com/',
    [
      'gemini.google.com',
      'bard.google.com',
      'aistudio.google.com',
      'generativelanguage.googleapis.com',
      'notebooklm.google.com',
      'makersuite.google.com',
      'ai.google.dev',
      'deepmind.google',
      'labs.google', //
    ],
    packages: ['com.google.android.apps.bard'],
    ai: true,
  ),
  Service(
    'claude',
    'https://claude.ai/',
    [
      'claude.ai', 'claude.com', 'anthropic.com', 'claudeusercontent.com', //
    ],
    packages: ['com.anthropic.claude'],
    ai: true,
  ),
  Service(
    'perplexity',
    'https://www.perplexity.ai/',
    [
      'perplexity.ai', 'perplexity.com', 'pplx.ai', //
    ],
    packages: ['ai.perplexity.app.android'],
    ai: true,
  ),
  Service(
    'deepseek',
    'https://chat.deepseek.com/',
    [
      'deepseek.com', 'deepseek.ai', //
    ],
    packages: ['com.deepseek.chat'],
    ai: true,
  ),
];

/// The rules added to a config made by [ConfigBuilder.buildForNetworks].
abstract final class Rules {
  static final _blockedThere = RegExp(
    r'росси|russia|беларус|belarus|🇷🇺|🇧🇾',
    caseSensitive: false,
    unicode: true,
  );

  /// The servers the foreign services can be reached through: not in Russia or Belarus (they block those services,
  /// or the services block them). None left: all of them.
  static List<String> abroad(List<String> servers) {
    final out = [
      for (final s in servers)
        if (!_blockedThere.hasMatch(s)) s,
    ];
    return out.isEmpty ? servers : out;
  }

  /// The two-letter country code from the flag in a server's name ('' when there is none).
  static String countryCode(String tag) {
    final codes = <int>[];
    for (final r in tag.runes) {
      if (r >= 0x1F1E6 && r <= 0x1F1FF) {
        codes.add(0x41 + r - 0x1F1E6);
        if (codes.length == 2) return String.fromCharCodes(codes);
      } else {
        codes.clear();
      }
    }
    return '';
  }

  /// The servers in the order of the countries [prefs] (the servers of other countries after them, as the last resort).
  static List<String> ordered(List<String> servers, List<String> prefs) {
    if (prefs.isEmpty) return servers;
    final out = <String>[];
    for (final code in prefs) {
      for (final s in servers) {
        if (countryCode(s) == code && !out.contains(s)) out.add(s);
      }
    }
    for (final s in servers) {
      if (!out.contains(s)) out.add(s);
    }
    return out;
  }

  static const _lists = 'https://raw.githubusercontent.com/';
  static const _adMild = {
    'adblock-mild':
        '${_lists}SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs',
  };
  static const _adNormal = {
    'adblock-normal':
        '${_lists}MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ads-all.srs',
  };
  static const _adStrict = {
    'adblock-strict':
        '${_lists}hiddify/hiddify-geo/rule-set/block/geosite-category-ads-all.srs',
  };
  static const _phishing = {
    'block-malware':
        '${_lists}hiddify/hiddify-geo/rule-set/block/geosite-malware.srs',
    'block-phishing':
        '${_lists}hiddify/hiddify-geo/rule-set/block/geosite-phishing.srs',
  };
  static const _miners = {
    'block-miners':
        '${_lists}hiddify/hiddify-geo/rule-set/block/geosite-cryptominers.srs',
  };

  /// The lists the options ask for: tag → address.
  static Map<String, String> blockLists(RuleOptions o) => {
    if (o.adBlockLevel >= 1) ..._adMild,
    if (o.adBlockLevel >= 2) ..._adNormal,
    if (o.adBlockLevel >= 3) ..._adStrict,
    if (o.blockPhishing) ..._phishing,
    if (o.blockMiners) ..._miners,
  };

  /// What the user typed ("https://www.Example.com/page", "*.example.com") as a domain, or null.
  static String? domainOf(String typed) {
    var s = typed.trim().toLowerCase();
    if (s.contains('://')) s = Uri.tryParse(s)?.host ?? s;
    final cut = s.indexOf(RegExp(r'[/?#]'));
    if (cut >= 0) s = s.substring(0, cut);
    if (s.startsWith('*.')) s = s.substring(2);
    while (s.startsWith('.')) {
      s = s.substring(1);
    }
    while (s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty || !s.contains('.') || s.contains(RegExp(r'[\s,;]'))) {
      return null;
    }
    return s;
  }

  /// [config] with the rules of [o] added. [wifi] and [mobile] are the networks' server tags: a service's group takes
  /// the servers of the network the phone is on (a rule for each network, by sing-box's `network_type`).
  static Map<String, Object?> apply(
    Map<String, Object?> config,
    RuleOptions o, {
    required List<String> wifi,
    required List<String> mobile,
    // the app's own copies of the lists (tag → file, see RuleLists): the core reads them and never downloads at its
    // start; without it the core downloads the lists itself
    Map<String, String>? localLists,
    List<String> priority = const [],
    int priorityWifi = 0,
    int priorityMobile = 0,
  }) {
    final route = config['route']! as Map<String, Object?>;
    // the lists as they are (not typed views of them): what is put in must fit whatever type the builder gave them
    final rules = List<Object?>.of(route['rules']! as List);
    route['rules'] = rules;
    final outbounds = List<Object?>.of(config['outbounds']! as List);
    config['outbounds'] = outbounds;
    final dns = config['dns']! as Map<String, Object?>;
    final dnsRules = List<Object?>.of(dns['rules']! as List);
    dns['rules'] = dnsRules;

    // --- ad blocking: listed names refused in DNS (as names that don't exist) and at the route
    var lists = blockLists(o);
    if (localLists != null) {
      lists = {for (final tag in lists.keys) tag: ?localLists[tag]};
    }
    if (lists.isNotEmpty) {
      route['rule_set'] = [
        ...?(route['rule_set'] as List?),
        for (final MapEntry(key: tag, value: where) in lists.entries)
          if (localLists != null)
            {'type': 'local', 'tag': tag, 'format': 'binary', 'path': where}
          else
            {
              'type': 'remote',
              'tag': tag,
              'format': 'binary',
              'url': where,
              'update_interval': '24h',
              'download_detour': ConfigBuilder.selectTag,
            },
      ];
      final allow = {for (final a in o.adBlockAllow) ?domainOf(a)}.toList();
      Map<String, Object?> listed(Map<String, Object?> action) => allow.isEmpty
          ? {'rule_set': lists.keys.toList(), ...action}
          : {
              'type': 'logical',
              'mode': 'and',
              'rules': [
                {'rule_set': lists.keys.toList()},
                {'domain_suffix': allow, 'invert': true},
              ],
              ...action,
            };
      // right after sniffing and the DNS hijack; refused at once, so an app doesn't wait for a timeout
      rules.insert(
        2,
        listed({'action': 'reject', 'method': 'default', 'no_drop': true}),
      );
      dnsRules.insert(0, listed({'action': 'predefined', 'rcode': 'NXDOMAIN'}));
    }

    // --- the services' groups and the AI group, before the rule sending private addresses direct is fine: they come
    // after it, so local traffic stays local
    final groups = <Map<String, Object?>>[];
    final serviceRules = <Map<String, Object?>>[];
    Map<String, Object?> group(
      String tag,
      String url,
      List<String> servers,
      int tolerance,
    ) => {
      'type': 'urltest',
      'tag': tag,
      'outbounds': servers,
      'url': url,
      'interval': '2m',
      'idle_timeout': '30m',
      'tolerance': tolerance,
      // what's open stays where it is (a call, a video); new connections go through the new server
      'interrupt_exist_connections': false,
      // the servers of the main subscription are preferred: any others have to be faster by the margin
      ...ConfigBuilder.priorityFor(
        servers,
        priority,
        tag.endsWith('-mobile') ? priorityMobile : priorityWifi,
      ),
      // the smart choice lets most servers sleep: the best ones (and a few in turn) are tested, the rest rest
      if (tag.startsWith('site-') &&
          (tag.endsWith('-mobile') ? o.sleepLte : o.sleepWifi)) ...{
        'smart_active': 6,
        'smart_explore': 2,
        'smart_full': '30m',
        'smart_warm': '5m',
      },
    };
    void route2(
      String tagPrefix,
      Service s, {
      required String url,
      required int tolerance,
      bool wifiOn = true,
      bool mobileOn = true,
    }) {
      for (final (network, found, type) in [
        ('wifi', abroad(wifi), 'wifi'),
        ('mobile', abroad(mobile), 'cellular'),
      ]) {
        // the AI group takes its servers in the order of the countries chosen (the group keeps the first that answers)
        final servers = tagPrefix == 'ai'
            ? ordered(found, network == 'wifi' ? o.aiWifi : o.aiMobile)
            : found;
        if (servers.isEmpty) continue;
        if (network == 'wifi' ? !wifiOn : !mobileOn) continue;
        final tag = '$tagPrefix-$network';
        if (!groups.any((g) => g['tag'] == tag)) {
          groups.add(group(tag, url, servers, tolerance));
        }
        serviceRules.addAll([
          if (s.packages.isNotEmpty)
            {
              'package_name': s.packages,
              'network_type': [type],
              'outbound': tag,
            },
          if (s.domains.isNotEmpty || s.cidrs.isNotEmpty)
            {
              if (s.domains.isNotEmpty) 'domain_suffix': s.domains,
              if (s.cidrs.isNotEmpty) 'ip_cidr': s.cidrs,
              'network_type': [type],
              'outbound': tag,
            },
        ]);
      }
    }

    for (final s in services) {
      if (s.ai && o.aiGroup) {
        // one group for every AI service: a large tolerance keeps the server until it stops answering
        route2(
          'ai',
          s,
          url: 'https://chatgpt.com/cdn-cgi/trace',
          tolerance: 5000,
        );
      } else if ((o.siteGroups || o.siteGroupsLte) &&
          (o.siteKeys.isEmpty || o.siteKeys.contains(s.key))) {
        route2(
          'site-${s.key}',
          s,
          url: s.url,
          tolerance: o.siteGroupsTolerance,
          wifiOn: o.siteGroups,
          mobileOn: o.siteGroupsLte,
        );
      }
    }
    // the user's own apps: a group of servers for each, matched by the app's package
    if (o.siteGroups || o.siteGroupsLte) {
      for (final pkg in o.customApps) {
        route2(
          'site-app-$pkg',
          Service('app-$pkg', ConfigBuilder.testUrl, const [], packages: [pkg]),
          url: ConfigBuilder.testUrl,
          tolerance: o.siteGroupsTolerance,
          wifiOn: o.siteGroups,
          mobileOn: o.siteGroupsLte,
        );
      }
    }
    if (groups.isNotEmpty) {
      final at = outbounds.indexWhere(
        (x) => (x as Map)['tag'] == ConfigBuilder.directTag,
      );
      outbounds.insertAll(at < 0 ? outbounds.length : at, groups);
      final private = rules.indexWhere(
        (r) => (r as Map)['ip_is_private'] == true,
      );
      rules.insertAll(private < 0 ? rules.length : private + 1, serviceRules);
    }
    // the sites the user routes by hand come first (after the sniffing and the DNS hijack): what they chose wins
    if (o.userSites.isNotEmpty) {
      final hijack = rules.indexWhere(
        (r) => (r as Map)['action'] == 'hijack-dns',
      );
      rules.insertAll(hijack < 0 ? 0 : hijack + 1, [
        for (final u in o.userSites)
          {
            'domain_suffix': [u.domain],
            'outbound': u.vpn
                ? ConfigBuilder.selectTag
                : ConfigBuilder.directTag,
          },
      ]);
    }
    return config;
  }
}
