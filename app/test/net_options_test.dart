import 'dart:convert';
import 'dart:io';

import 'package:avet/config/config_builder.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/subscription/links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final singbox = Platform.environment['SINGBOX'];
  test(
    'IPv6, direct DNS and multiplexing make a config sing-box accepts',
    () async {
      final servers = Links.parseSubscription(
        [
          'trojan://p@a.example.com:443#A',
          'vless://11111111-1111-1111-1111-111111111111@v.example.com:443?security=reality&sni=www.example.com&fp=chrome&pbk=AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHHIIIIJJJJKKK&sid=ab12&type=tcp&flow=xtls-rprx-vision#V',
          'vmess://${base64.encode(utf8.encode('{"v":"2","ps":"M","add":"m.example.com","port":"443","id":"22222222-2222-2222-2222-222222222222","aid":"0","net":"ws","tls":"tls"}'))}',
        ].join('\n'),
      );
      for (final v6 in [0, 1, 2, 3]) {
        for (final proto in [0, 1, 2]) {
          final built = ConfigBuilder.buildForNetworks(
            wifi: servers,
            mobile: servers,
          );
          Engine.applyNetOptions(
            built,
            RuleSettings(
              ipv6: v6,
              mux: true,
              muxProtocol: proto,
              muxStreams: 8,
              muxPadding: true,
              directDns: '77.88.8.8',
            ),
          );
          final outs = (built['outbounds']! as List).cast<Map>();
          // the Vision server is left alone
          expect(
            outs.firstWhere((o) => o['tag'] == 'V').containsKey('multiplex'),
            isFalse,
          );
          expect(
            outs.firstWhere((o) => o['tag'] == 'A').containsKey('multiplex'),
            isTrue,
          );
          final f = File('${Directory.systemTemp.path}/avet-net-$v6$proto.json')
            ..writeAsStringSync(jsonEncode(built));
          final r = await Process.run(singbox!, ['check', '-c', f.path]);
          expect(r.exitCode, 0, reason: '$v6/$proto: ${r.stdout}${r.stderr}');
        }
      }
    },
    skip: singbox == null ? 'SINGBOX not set' : false,
  );
}
