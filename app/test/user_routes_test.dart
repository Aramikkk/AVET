import 'package:avet/config/config_builder.dart';
import 'package:avet/config/rules.dart';
import 'package:avet/subscription/links.dart';
import 'package:flutter_test/flutter_test.dart';

final _servers = Links.parseSubscription(
  [
    'trojan://p@a.example.com:443#Germany',
    'trojan://p@b.example.com:443#Finland',
    'trojan://p@c.example.com:443#LTE Only - Sweden',
  ].join('\n'),
);

Map<String, Object?> _config(RuleOptions o) {
  final wifi = _servers.sublist(0, 2);
  final mobile = _servers.sublist(2);
  final c = ConfigBuilder.buildForNetworks(wifi: wifi, mobile: mobile);
  return Rules.apply(
    c,
    o,
    wifi: [for (final s in wifi) s['tag']! as String],
    mobile: [for (final s in mobile) s['tag']! as String],
  );
}

void main() {
  test(
    'sites the user chose go first: through the VPN or direct, subdomains too',
    () {
      final c = _config(
        const RuleOptions(
          userSites: [
            (domain: 'example.com', vpn: false),
            (domain: 'vpn-site.org', vpn: true),
          ],
        ),
      );
      final rules = ((c['route']! as Map)['rules']! as List).cast<Map>();
      final hijack = rules.indexWhere((r) => r['action'] == 'hijack-dns');
      expect(rules[hijack + 1]['domain_suffix'], ['example.com']);
      expect(rules[hijack + 1]['outbound'], ConfigBuilder.directTag);
      expect(rules[hijack + 2]['domain_suffix'], ['vpn-site.org']);
      expect(rules[hijack + 2]['outbound'], ConfigBuilder.selectTag);
    },
  );

  test(
    'an app of the user gets a group of its own, matched by its package and nothing else',
    () {
      final c = _config(
        const RuleOptions(
          siteGroups: true,
          siteGroupsLte: true,
          customApps: ['com.example.app'],
        ),
      );
      final outbounds = (c['outbounds']! as List).cast<Map>();
      expect(
        outbounds.any((o) => o['tag'] == 'site-app-com.example.app-wifi'),
        isTrue,
      );
      final rules = ((c['route']! as Map)['rules']! as List).cast<Map>();
      final mine = [
        for (final r in rules)
          if ('${r['outbound']}'.startsWith('site-app-com.example.app')) r,
      ];
      expect(mine, isNotEmpty);
      for (final r in mine) {
        // a rule that names only the network would send everything of that network to the group
        expect(r.containsKey('package_name'), isTrue);
      }
    },
  );
}
