import 'package:avet/config/rules.dart';
import 'package:avet/data/dns_servers.dart';
import 'package:avet/state/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the AI group takes the countries in the order chosen, the others after them',
    () {
      final servers = [
        '🇩🇪 Германия 1',
        '🇸🇪 Швеция 1',
        '🇫🇮 Финляндия 1',
        '🇸🇪 Швеция 2',
      ];
      expect(Rules.countryCode(servers[1]), 'SE');
      expect(Rules.ordered(servers, ['FI', 'SE']), [
        '🇫🇮 Финляндия 1',
        '🇸🇪 Швеция 1',
        '🇸🇪 Швеция 2',
        '🇩🇪 Германия 1',
      ]);
      expect(Rules.ordered(servers, const []), servers);
    },
  );

  test(
    'the ping that counts as slow is the network\'s own: 250 on Wi-Fi, 500 on mobile data',
    () {
      const r = RuleSettings();
      expect(r.slowMs, 250);
      expect(r.slowMsLte, 500);
      expect(EngineState(rules: r).slowAt, 250);
      expect(EngineState(rules: r, network: 'mobile').slowAt, 500);
    },
  );

  test(
    'the first three DNS servers keep their places (a stored choice is the index)',
    () {
      expect(dnsServers[0].ip, '8.8.8.8');
      expect(dnsServers[1].ip, '1.1.1.1');
      expect(dnsServers[2].ip, '77.88.8.8');
      expect(dnsServers.length, greaterThan(3));
    },
  );
}
