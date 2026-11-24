import 'package:avet/config/config_builder.dart';
import 'package:avet/routing/data/app_groups.dart';
import 'package:avet/routing/data/rule_groups.dart';
import 'package:avet/routing/data/ru_services.dart';

/// Where a group's traffic goes.
enum Way { direct, proxy, block }

/// A routing group: sites, phone apps and computer programs that go one way.
class RouteGroup {
  const RouteGroup(
    this.key,
    this.way, {
    this.domains = const [],
    this.keywords = const [],
    this.cidrs = const [],
    this.packages = const [],
    this.packagePatterns = const [],
    this.processes = const [],
    this.quic = false,
  });

  final String key;
  final Way way;
  final List<String> domains;
  final List<String> keywords;
  final List<String> cidrs;
  final List<String> packages;
  final List<String> packagePatterns;
  final List<String> processes;

  /// The group is QUIC itself (HTTP/3), whatever the site.
  final bool quic;
}

/// The routing list, in its order: the first group that matches decides. What is blocked in Russia first (no app
/// reaches it direct), then the Russian apps whole, then the groups that take the VPN for everyone else.
final routeGroups = <RouteGroup>[
  // QUIC crawls through a TCP tunnel and is often throttled in Russia: refused, apps fall back to TCP at once
  const RouteGroup('blockQuic', Way.block, quic: true),
  const RouteGroup(
    'chinaChatDirect',
    Way.direct,
    domains: chinaChatDomains,
    packages: chinaChatApps,
  ),
  RouteGroup(
    'socialProxy',
    Way.proxy,
    domains: socialDomains,
    cidrs: socialCidrs,
    packages: socialApps,
  ),
  RouteGroup(
    'adultProxy',
    Way.proxy,
    domains: adultDomains,
    keywords: adultKeywords,
  ),
  RouteGroup(
    'blockedProxy',
    Way.proxy,
    domains: otherBlockedDomains,
    packages: otherBlockedApps,
    processes: otherBlockedProcesses,
  ),
  const RouteGroup(
    'yandexDirect',
    Way.direct,
    domains: yandexDomains,
    packages: yandexApps,
  ),
  const RouteGroup(
    'marketsDirect',
    Way.direct,
    domains: marketDomains,
    packages: marketApps,
  ),
  const RouteGroup(
    'banksDirect',
    Way.direct,
    domains: bankDomains,
    packages: bankApps,
  ),
  const RouteGroup('ruAppsDirect', Way.direct, packages: ruAppPackages),
  RouteGroup('aiProxy', Way.proxy, domains: aiDomains, packages: aiApps),
  RouteGroup(
    'videoProxy',
    Way.proxy,
    domains: videoDomains,
    packages: videoApps,
  ),
  const RouteGroup(
    'storesProxy',
    Way.proxy,
    domains: storeDomains,
    packages: storeApps,
  ),
  RouteGroup(
    'googleProxy',
    Way.proxy,
    domains: googleDomains,
    packages: googleApps,
    packagePatterns: googleAppPatterns,
  ),
  RouteGroup(
    'chinaProxy',
    Way.proxy,
    domains: chinaDomains,
    packages: chinaApps,
  ),
  const RouteGroup('foreignProxy', Way.proxy, packages: foreignApps),
  const RouteGroup(
    'ruDomainsDirect',
    Way.direct,
    domains: ['ru', 'su', 'xn--p1ai', ...ruServiceDomains],
  ),
];

/// The routing list and the "only blocked sites through the VPN" mode, added to a config.
abstract final class Routing {
  /// A group's rules for sing-box. Its sites, apps and programs are separate rules (sing-box ANDs a rule's fields,
  /// and the group means any of them); all keep the group's place.
  static List<Map<String, Object?>> rulesOf(RouteGroup g) {
    final action = switch (g.way) {
      Way.block => {'action': 'reject', 'no_drop': true},
      Way.proxy => {'action': 'route', 'outbound': ConfigBuilder.selectTag},
      Way.direct => {'action': 'route', 'outbound': ConfigBuilder.directTag},
    };
    return [
      if (g.quic)
        {
          'protocol': ['quic'],
          ...action,
        },
      if (g.domains.isNotEmpty || g.cidrs.isNotEmpty || g.keywords.isNotEmpty)
        {
          if (g.domains.isNotEmpty) 'domain_suffix': g.domains,
          if (g.keywords.isNotEmpty) 'domain_keyword': g.keywords,
          if (g.cidrs.isNotEmpty) 'ip_cidr': g.cidrs,
          ...action,
        },
      if (g.packages.isNotEmpty) {'package_name': g.packages, ...action},
      if (g.packagePatterns.isNotEmpty)
        {'package_name_regex': g.packagePatterns, ...action},
      if (g.processes.isNotEmpty) {'process_name': g.processes, ...action},
    ];
  }

  /// [config] with the routing list (when [list] is on) and, when [blockedOnly] is on, everything the list doesn't
  /// send through the VPN going direct, on Wi-Fi only: on mobile data everything goes through the VPN (the whitelist
  /// servers are the way out there). [testHost] always goes through the VPN, so the ping shows the VPN's latency.
  static Map<String, Object?> apply(
    Map<String, Object?> config, {
    bool list = true,
    bool blockedOnly = false,
    String testHost = 'www.gstatic.com',
    // groups switched off by the user (by key)
    Set<String> off = const {},
    // what the list does not name: through the VPN (the default) or direct
    bool restDirect = false,
  }) {
    if (!list && !blockedOnly) return config;
    final route = config['route']! as Map<String, Object?>;
    final rules = List<Object?>.of(route['rules']! as List);
    route['rules'] = rules;
    if (list || blockedOnly) {
      // QUIC refused early, right after sniffing, the DNS hijack and the ad blocking
      final quic = rulesOf(routeGroups.first);
      final afterAds = rules.indexWhere(
        (r) => (r as Map)['action'] == 'reject',
      );
      rules.insertAll(afterAds < 0 ? 2 : afterAds + 1, quic);
      if (blockedOnly) {
        rules.add({
          'domain_suffix': [testHost],
          'action': 'route',
          'outbound': ConfigBuilder.selectTag,
        });
      }
      for (final g in routeGroups.skip(1)) {
        if (off.contains(g.key)) continue;
        rules.addAll(rulesOf(g));
      }
    }
    if (restDirect && list && !blockedOnly) {
      // everything the list leaves goes direct (only the listed VPN groups use it)
      route['final'] = ConfigBuilder.directTag;
    }
    if (blockedOnly) {
      rules.add({
        'network_type': ['wifi', 'ethernet', 'other'],
        'action': 'route',
        'outbound': ConfigBuilder.directTag,
      });
    }
    return config;
  }
}
