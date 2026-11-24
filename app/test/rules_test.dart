import 'dart:convert';
import 'dart:io';

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
  test('the services go only through servers abroad, if there are any', () {
    expect(
      Rules.abroad([
        '🇷🇺 Доступ - Россия',
        'Доступ - Беларусь',
        '🇸🇪 Швеция',
        'Finland',
      ]),
      ['🇸🇪 Швеция', 'Finland'],
    );
    expect(Rules.abroad(['LTE Only - Россия']), ['LTE Only - Россия']);
  });

  test('a typed address becomes a domain', () {
    expect(
      Rules.domainOf('https://www.Example.com/page?x=1'),
      'www.example.com',
    );
    expect(Rules.domainOf('*.example.com'), 'example.com');
    expect(Rules.domainOf('example.com.'), 'example.com');
    expect(Rules.domainOf('localhost'), isNull);
    expect(Rules.domainOf('a b.com'), isNull);
  });

  test(
    'ad blocking: the stricter the level, the more lists; protection and miners by themselves',
    () {
      expect(Rules.blockLists(const RuleOptions()).keys, isEmpty);
      expect(Rules.blockLists(const RuleOptions(adBlockLevel: 1)).keys, [
        'adblock-mild',
      ]);
      expect(Rules.blockLists(const RuleOptions(adBlockLevel: 3)).length, 3);
      expect(
        Rules.blockLists(
          const RuleOptions(blockPhishing: true, blockMiners: true),
        ).keys,
        ['block-malware', 'block-phishing', 'block-miners'],
      );
    },
  );

  test(
    'blocked names: refused in DNS and at the route right after sniffing and the DNS hijack; exceptions kept',
    () {
      final c = _config(
        const RuleOptions(
          adBlockLevel: 2,
          adBlockAllow: ['https://ads.example.com/x'],
        ),
      );
      final route = c['route']! as Map;
      final rules = (route['rules']! as List).cast<Map>();
      expect(rules[0]['action'], 'sniff');
      expect(rules[1]['action'], 'hijack-dns');
      expect(rules[2]['action'], 'reject');
      expect(rules[2]['mode'], 'and');
      expect((rules[2]['rules'] as List)[1], {
        'domain_suffix': ['ads.example.com'],
        'invert': true,
      });
      expect((route['rule_set']! as List).length, 2);
      final dnsRule = ((c['dns']! as Map)['rules']! as List).first as Map;
      expect(dnsRule['rcode'], 'NXDOMAIN');
    },
  );

  test(
    "with the app's own copies of the lists the core reads files; a list with no copy is left out",
    () {
      final wifi = _servers.sublist(0, 2);
      final c = Rules.apply(
        ConfigBuilder.buildForNetworks(wifi: wifi, mobile: _servers.sublist(2)),
        const RuleOptions(adBlockLevel: 2),
        wifi: const ['Germany', 'Finland'],
        mobile: const ['LTE Only - Sweden'],
        localLists: const {'adblock-mild': '/data/adblock-mild.srs'},
      );
      final sets = ((c['route']! as Map)['rule_set']! as List).cast<Map>();
      expect(sets, [
        {
          'type': 'local',
          'tag': 'adblock-mild',
          'format': 'binary',
          'path': '/data/adblock-mild.srs',
        },
      ]);
      // no copy of any list: no blocking rule at all
      final none = Rules.apply(
        ConfigBuilder.buildForNetworks(wifi: wifi, mobile: _servers.sublist(2)),
        const RuleOptions(adBlockLevel: 2),
        wifi: const ['Germany', 'Finland'],
        mobile: const ['LTE Only - Sweden'],
        localLists: const {},
      );
      expect((none['route']! as Map).containsKey('rule_set'), isFalse);
    },
  );

  test('the multi-server switch of Wi-Fi alone makes no mobile groups', () {
    final c = _config(const RuleOptions(siteGroups: true));
    final tags = [
      for (final o in (c['outbounds']! as List).cast<Map>()) '${o['tag']}',
    ];
    expect(tags.contains('site-youtube-wifi'), isTrue);
    expect(tags.contains('site-youtube-mobile'), isFalse);
  });

  test(
    "each service gets a group per network, its rules matched by the phone's network type",
    () {
      final c = _config(
        const RuleOptions(siteGroups: true, siteGroupsLte: true),
      );
      final outbounds = (c['outbounds']! as List).cast<Map>();
      final yt = outbounds.firstWhere((o) => o['tag'] == 'site-youtube-wifi');
      expect(yt['outbounds'], ['Germany', 'Finland']);
      expect(
        outbounds.firstWhere(
          (o) => o['tag'] == 'site-youtube-mobile',
        )['outbounds'],
        ['LTE Only - Sweden'],
      );
      final rules = ((c['route']! as Map)['rules']! as List).cast<Map>();
      final ytWifi = rules.firstWhere(
        (r) =>
            r['outbound'] == 'site-youtube-wifi' &&
            r.containsKey('domain_suffix'),
      );
      expect(ytWifi['network_type'], ['wifi']);
      final ytMobile = rules.firstWhere(
        (r) =>
            r['outbound'] == 'site-youtube-mobile' &&
            r.containsKey('domain_suffix'),
      );
      expect(ytMobile['network_type'], ['cellular']);
      // the private addresses stay direct: their rule comes first
      final private = rules.indexWhere((r) => r['ip_is_private'] == true);
      expect(rules.indexOf(ytWifi), greaterThan(private));
    },
  );

  test(
    'the AI group: one group for every AI service, sticky; the AI services get no groups of their own',
    () {
      final c = _config(const RuleOptions(siteGroups: true, aiGroup: true));
      final tags = [
        for (final o in (c['outbounds']! as List).cast<Map>()) o['tag'],
      ];
      expect(tags, containsAll(['ai-wifi', 'ai-mobile']));
      expect(tags.where((t) => '$t'.startsWith('site-chatgpt')), isEmpty);
      final ai = (c['outbounds']! as List).cast<Map>().firstWhere(
        (o) => o['tag'] == 'ai-wifi',
      );
      expect(ai['tolerance'], 5000);
      final rules = ((c['route']! as Map)['rules']! as List).cast<Map>();
      expect(
        rules.where((r) => r['outbound'] == 'ai-wifi').length,
        greaterThanOrEqualTo(10),
      );
    },
  );

  final singbox = Platform.environment['SINGBOX'];
  test(
    'sing-box accepts the config with every rule on',
    () async {
      final c = _config(
        const RuleOptions(
          adBlockLevel: 3,
          blockPhishing: true,
          blockMiners: true,
          adBlockAllow: ['example.com'],
          siteGroups: true,
          aiGroup: true,
        ),
      );
      final file = File('${Directory.systemTemp.path}/avet-check-rules.json')
        ..writeAsStringSync(jsonEncode(c));
      final r = await Process.run(singbox!, ['check', '-c', file.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    },
    skip: singbox == null ? 'SINGBOX not set' : false,
  );
}
