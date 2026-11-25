import 'package:avet/config/config_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TCP-based servers without a detour go to every Auto group', () {
    final config = <String, Object?>{
      'outbounds': <Map<String, Object?>>[
        {'type': 'urltest', 'tag': 'auto'},
        {'type': 'urltest', 'tag': 'auto-mobile'},
        {
          'type': 'vless',
          'tag': 'a',
          'server': 'example.com',
          'server_port': 443,
        },
        {
          'type': 'trojan',
          'tag': 'b',
          'server': '2001:db8::1',
          'server_port': 8443,
        },
        {
          'type': 'hysteria2',
          'tag': 'h',
          'server': 'example.com',
          'server_port': 443,
        },
        {
          'type': 'vless',
          'tag': 'c',
          'server': 'x.com',
          'server_port': 443,
          'detour': 'a',
        },
        {'type': 'direct', 'tag': 'direct'},
      ],
    };
    ConfigBuilder.addTcpPing(config);
    final groups = config['outbounds']! as List;
    const want = {'a': 'example.com:443', 'b': '[2001:db8::1]:8443'};
    expect((groups[0] as Map)['tcp_ping'], want);
    expect((groups[1] as Map)['tcp_ping'], want);
  });
}
