import 'dart:convert';
import 'dart:io';

import 'package:avet/config/config_builder.dart';
import 'package:avet/config/rules.dart';
import 'package:avet/subscription/links.dart';
import 'package:flutter_test/flutter_test.dart';

final _servers = Links.parseSubscription(
  [
    'trojan://p@a.example.com:443#🇩🇪 Germany 1',
    'trojan://p@b.example.com:443#🇫🇮 Finland',
    'trojan://p@c.example.com:443#🇸🇪 Sweden',
    'trojan://p@d.example.com:443#🇳🇱 Netherlands',
    'trojan://p@e.example.com:443#🇺🇸 USA',
  ].join('\n'),
);

void main() {
  final singbox = Platform.environment['SINGBOX'];

  Future<void> check(
    String name,
    RuleOptions o,
    List<Map<String, Object?>> wifi,
    List<Map<String, Object?>> mobile, {
    Map<String, Object?>? smart,
    List<String> priority = const [],
  }) async {
    final c = Rules.apply(
      ConfigBuilder.buildForNetworks(
        wifi: wifi,
        mobile: mobile,
        smartWifi: smart,
        smartMobile: smart,
        priority: priority,
        priorityWifi: 100,
        priorityMobile: 150,
      ),
      o,
      wifi: [for (final s in wifi) s['tag']! as String],
      mobile: [for (final s in mobile) s['tag']! as String],
      priority: priority,
      priorityWifi: 100,
      priorityMobile: 150,
    );
    final f = File('${Directory.systemTemp.path}/avet-full-$name.json')
      ..writeAsStringSync(jsonEncode(c));
    final r = await Process.run(singbox!, ['check', '-c', f.path]);
    expect(r.exitCode, 0, reason: '$name: ${r.stdout}${r.stderr}');
  }

  final skip = singbox == null ? 'SINGBOX not set' : false;
  const everything = RuleOptions(
    siteGroups: true,
    siteGroupsLte: true,
    customApps: ['com.example.app'],
    userSites: [(domain: 'example.com', vpn: true)],
    aiGroup: true,
    aiWifi: ['de', 'fi'],
    aiMobile: ['us', 'xx'],
    sleepWifi: true,
    sleepLte: true,
  );

  test('everything on, both networks have servers', () async {
    await check('all', everything, _servers.sublist(0, 3), _servers.sublist(2));
  }, skip: skip);

  test('everything on, mobile has one server, the country list names none of '
      'them', () async {
    await check('one', everything, _servers, [_servers.first]);
  }, skip: skip);

  test('every AI country unknown', () async {
    await check(
      'ai',
      const RuleOptions(
        siteGroups: true,
        siteGroupsLte: true,
        aiGroup: true,
        aiWifi: ['zz'],
        aiMobile: ['zz'],
      ),
      _servers.sublist(0, 2),
      _servers.sublist(2, 3),
    );
  }, skip: skip);

  test('smart on, everything on', () async {
    await check(
      'smart',
      everything,
      _servers,
      _servers,
      smart: const {
        'smart': true,
        'smart_dwell': '60s',
        'smart_gain_ms': 80,
        'smart_gain_pct': 25,
        'smart_country_pct': 40,
        'smart_window': 6,
        'smart_active': 10,
        'smart_explore': 3,
        'smart_full': '30m',
        'smart_warm': '5m',
      },
    );
  }, skip: skip);

  test('the main subscription is preferred in every group', () async {
    final main = [for (final s in _servers.take(2)) s['tag']! as String];
    await check(
      'priority',
      everything,
      _servers,
      _servers,
      priority: main,
      smart: const {'smart': true, 'smart_active': 10},
    );
    final cfg = ConfigBuilder.buildForNetworks(
      wifi: _servers,
      mobile: _servers,
      priority: main,
      priorityWifi: 100,
      priorityMobile: 150,
    );
    final auto = (cfg['outbounds']! as List).cast<Map>().firstWhere(
      (o) => o['tag'] == ConfigBuilder.autoFor('mobile'),
    );
    expect(auto['priority_margin'], 150);
    expect(auto['priority_tags'], main);
    // all of them one subscription's: nothing to prefer
    expect(ConfigBuilder.priorityFor(main, main, 100), isEmpty);
  }, skip: skip);
}
