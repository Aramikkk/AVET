import 'package:avet/config/config_builder.dart';
import 'package:avet/state/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the smart choice gives its margins to the network that uses it', () {
    const r = RuleSettings(strategy: 3, strategyLte: 1);
    expect(Engine.autoSmart(r, false)?['smart'], isTrue);
    expect(Engine.autoSmart(r, true), isNull);
    expect(Engine.autoInterval(r, false), '2m');
  });

  test('the smart options reach the Auto group of that network only', () {
    final servers = [
      {
        'type': 'vless',
        'tag': 'A',
        'server': 'a.example',
        'server_port': 443,
        'uuid': 'x',
      },
      {
        'type': 'vless',
        'tag': 'LTE Only - B',
        'server': 'b.example',
        'server_port': 443,
        'uuid': 'x',
      },
    ];
    final c = ConfigBuilder.buildForNetworks(
      wifi: [servers[0]],
      mobile: [servers[1]],
      smartWifi: const {'smart': true, 'smart_dwell': '5m'},
    );
    final groups = {
      for (final o in (c['outbounds']! as List).cast<Map>())
        if (o['type'] == 'urltest') o['tag']: o,
    };
    expect(groups['auto-wifi']!['smart'], isTrue);
    expect(groups['auto-wifi']!['smart_dwell'], '5m');
    expect(groups['auto-mobile']!.containsKey('smart'), isFalse);
  });
}
