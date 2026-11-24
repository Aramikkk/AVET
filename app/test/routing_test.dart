import 'dart:convert';
import 'dart:io';

import 'package:avet/config/config_builder.dart';
import 'package:avet/config/rules.dart';
import 'package:avet/routing/routing.dart';
import 'package:avet/subscription/links.dart';
import 'package:flutter_test/flutter_test.dart';

final _servers = Links.parseSubscription(
  'trojan://p@a.example.com:443#Germany\ntrojan://p@c.example.com:443#LTE Only - Sweden',
);

Map<String, Object?> _base() =>
    ConfigBuilder.buildForNetworks(wifi: [_servers[0]], mobile: [_servers[1]]);

List<Map> _rules(Map<String, Object?> c) =>
    ((c['route']! as Map)['rules']! as List).cast<Map>();

void main() {
  test(
    "a group's sites, apps and programs are separate rules, each with the group's way",
    () {
      final g = routeGroups.firstWhere((g) => g.key == 'blockedProxy');
      final rules = Routing.rulesOf(g);
      expect(rules.length, 3);
      expect(rules.every((r) => r['outbound'] == 'select'), isTrue);
      expect(rules[0].containsKey('package_name'), isFalse);
      expect(rules[1].keys, containsAll(['package_name', 'outbound']));
      expect(rules[2].keys, contains('process_name'));
    },
  );

  test(
    'QUIC is refused right after the ad blocking; the list keeps its order',
    () {
      final c = Routing.apply(
        Rules.apply(
          _base(),
          const RuleOptions(adBlockLevel: 1),
          wifi: ['Germany'],
          mobile: ['LTE Only - Sweden'],
          localLists: const {'adblock-mild': '/x.srs'},
        ),
      );
      final rules = _rules(c);
      expect(rules[2]['action'], 'reject'); // ads
      expect(rules[3], {
        'protocol': ['quic'],
        'action': 'reject',
        'no_drop': true,
      });
      final social = rules.indexWhere(
        (r) =>
            (r['domain_suffix'] as List?)?.contains('instagram.com') ?? false,
      );
      final yandex = rules.indexWhere(
        (r) => (r['domain_suffix'] as List?)?.contains('yandex.ru') ?? false,
      );
      final ruZone = rules.indexWhere(
        (r) => (r['domain_suffix'] as List?)?.contains('ru') ?? false,
      );
      expect(social, lessThan(yandex));
      expect(yandex, lessThan(ruZone));
      expect(rules[yandex]['outbound'], 'direct');
      expect(rules[social]['outbound'], 'select');
      // without the "only blocked" mode, what the list doesn't name goes the main way
      expect((c['route']! as Map)['final'], 'select');
      expect(rules.last['network_type'], isNull);
    },
  );

  test(
    '"only blocked through the VPN": the rest direct on Wi-Fi, through the VPN on mobile data',
    () {
      final c = Routing.apply(_base(), blockedOnly: true);
      final rules = _rules(c);
      expect(rules.last, {
        'network_type': ['wifi', 'ethernet', 'other'],
        'action': 'route',
        'outbound': 'direct',
      });
      final test = rules.indexWhere(
        (r) =>
            (r['domain_suffix'] as List?)?.contains('www.gstatic.com') ?? false,
      );
      expect(test, isNonNegative);
      expect(rules[test]['outbound'], 'select');
    },
  );

  final singbox = Platform.environment['SINGBOX'];
  test(
    'sing-box accepts the routing list and the mode',
    () async {
      final c = Routing.apply(_base(), blockedOnly: true);
      final file = File('${Directory.systemTemp.path}/avet-check-routing.json')
        ..writeAsStringSync(jsonEncode(c));
      final r = await Process.run(singbox!, ['check', '-c', file.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    },
    skip: singbox == null ? 'SINGBOX not set' : false,
  );
}
