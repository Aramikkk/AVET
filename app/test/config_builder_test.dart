import 'dart:convert';
import 'dart:io';

import 'package:avet/config/config_builder.dart';
import 'package:avet/subscription/links.dart';
import 'package:flutter_test/flutter_test.dart';

final _servers = Links.parseSubscription(
  [
    'vless://11111111-2222-3333-4444-555555555555@nl.example.com:443'
        '?security=reality&sni=www.example.org&fp=chrome&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=ab12'
        '&flow=xtls-rprx-vision#Netherlands',
    'trojan://secret@se.example.com:443?sni=se.example.com&type=ws&path=%2Ft#Sweden',
    'hy2://pass@hy.example.com:8443?sni=hy.example.com#Finland',
  ].join('\n'),
);

void main() {
  test(
    'the choice by hand lists Auto first and every server; Auto measures every server',
    () {
      final c = ConfigBuilder.build(servers: _servers);
      final outbounds = c['outbounds']! as List;
      final select =
          outbounds.firstWhere(
                (o) => (o as Map)['tag'] == ConfigBuilder.selectTag,
              )
              as Map;
      final auto =
          outbounds.firstWhere(
                (o) => (o as Map)['tag'] == ConfigBuilder.autoTag,
              )
              as Map;
      expect(select['outbounds'], ['auto', 'Netherlands', 'Sweden', 'Finland']);
      expect(select['default'], 'auto');
      expect(auto['outbounds'], ['Netherlands', 'Sweden', 'Finland']);
      expect((c['route']! as Map)['final'], 'select');
    },
  );

  test('the phone gets a TUN, the computer a local system proxy', () {
    final phone = ConfigBuilder.build(servers: _servers);
    final pc = ConfigBuilder.build(servers: _servers, systemProxy: true);
    expect(((phone['inbounds']! as List).single as Map)['type'], 'tun');
    final mixed = (pc['inbounds']! as List).single as Map;
    expect(mixed['type'], 'mixed');
    expect(mixed['set_system_proxy'], true);
    expect(mixed['listen'], '127.0.0.1');
  });

  test(
    'one config for both networks: an automatic choice for each, the choice by hand over both',
    () {
      final wifi = [_servers[0], _servers[1]];
      final mobile = [_servers[2]];
      final c = ConfigBuilder.buildForNetworks(wifi: wifi, mobile: mobile);
      final outbounds = (c['outbounds']! as List).cast<Map>();
      Map byTag(String t) => outbounds.firstWhere((o) => o['tag'] == t);
      expect(byTag('auto-wifi')['outbounds'], ['Netherlands', 'Sweden']);
      expect(byTag('auto-mobile')['outbounds'], ['Finland']);
      expect(byTag('select')['outbounds'], [
        'auto-wifi',
        'auto-mobile',
        'Netherlands',
        'Sweden',
        'Finland',
      ]);
      expect(outbounds.where((o) => o['tag'] == 'auto'), isEmpty);
      // a server in both sets is there once
      final both = ConfigBuilder.buildForNetworks(
        wifi: _servers,
        mobile: _servers,
      );
      expect(
        (both['outbounds']! as List)
            .where((o) => (o as Map)['tag'] == 'Finland')
            .length,
        1,
      );
    },
  );

  test('no servers: no config', () {
    expect(() => ConfigBuilder.build(servers: const []), throwsArgumentError);
  });

  // sing-box itself checks the config when SINGBOX is set to its binary (core/bin/sing-box.exe)
  final singbox = Platform.environment['SINGBOX'];
  test(
    'sing-box accepts the config, for the phone and for the computer',
    () async {
      for (final systemProxy in [false, true]) {
        final file =
            File('${Directory.systemTemp.path}/avet-check-$systemProxy.json')
              ..writeAsStringSync(
                jsonEncode(
                  ConfigBuilder.build(
                    servers: _servers,
                    systemProxy: systemProxy,
                  ),
                ),
              );
        final r = await Process.run(singbox!, ['check', '-c', file.path]);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      }
      final both = File('${Directory.systemTemp.path}/avet-check-networks.json')
        ..writeAsStringSync(
          jsonEncode(
            ConfigBuilder.buildForNetworks(
              wifi: _servers.sublist(0, 2),
              mobile: [_servers[2]],
            ),
          ),
        );
      final r = await Process.run(singbox!, ['check', '-c', both.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    },
    skip: singbox == null ? 'SINGBOX not set' : false,
  );
}
