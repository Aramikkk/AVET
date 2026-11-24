import 'dart:convert';
import 'dart:io';

import 'package:avet/config/config_builder.dart';
import 'package:avet/data/dns_servers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Yandex speaks DNS over TLS, the others DNS over HTTPS', () {
    expect(dotName('77.88.8.8'), 'common.dot.dns.yandex.net');
    expect(dotName('77.88.8.1'), isNotNull);
    expect(dotName('8.8.8.8'), isNull);
    expect(dotName('1.1.1.1'), isNull);
  });

  final singbox = Platform.environment['SINGBOX'];
  test(
    'sing-box accepts a DNS over TLS server with a name',
    () async {
      final config = ConfigBuilder.build(
        servers: [
          {
            'type': 'trojan',
            'tag': 'a',
            'server': 'a.example.com',
            'server_port': 443,
            'password': 'p',
            'tls': {'enabled': true},
          },
        ],
      );
      final remote = ((config['dns']! as Map)['servers']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((d) => d['tag'] == 'remote');
      remote
        ..['type'] = 'tls'
        ..['server'] = '77.88.8.8'
        ..['server_port'] = 853
        ..['tls'] = {
          'enabled': true,
          'server_name': 'common.dot.dns.yandex.net',
        };
      final f = File('${Directory.systemTemp.path}/avet-dot.json')
        ..writeAsStringSync(jsonEncode(config));
      final r = await Process.run(singbox!, ['check', '-c', f.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    },
    skip: singbox == null ? 'SINGBOX not set' : false,
  );
}
