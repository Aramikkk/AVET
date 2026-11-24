import 'package:avet/config/networks.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _s(String tag) => {
  'type': 'vless',
  'tag': tag,
  'server': 'x',
  'server_port': 443,
};

void main() {
  test('whitelist servers are told by their names', () {
    expect(Networks.isMobileOnly('🇷🇺 LTE Only - Россия'), isTrue);
    expect(Networks.isMobileOnly('LTE #1.0'), isTrue);
    expect(Networks.isMobileOnly('Швеция · БС'), isTrue);
    expect(Networks.isMobileOnly('Белые списки - Германия'), isTrue);
    expect(Networks.isMobileOnly('🇧🇬 Доступ - Болгария'), isFalse);
    expect(Networks.isMobileOnly('Бельгия'), isFalse);
  });

  test('Wi-Fi gets the regular servers, mobile data the whitelist ones', () {
    final all = [
      _s('Доступ - Германия'),
      _s('LTE Only - Швеция'),
      _s('Доступ - Финляндия'),
      _s('LTE #2.0'),
    ];
    expect(Networks.serversFor(all, NetworkKind.wifi).map((s) => s['tag']), [
      'Доступ - Германия',
      'Доступ - Финляндия',
    ]);
    expect(Networks.serversFor(all, NetworkKind.mobile).map((s) => s['tag']), [
      'LTE Only - Швеция',
      'LTE #2.0',
    ]);
  });

  test('a network with no servers of its own gets all of them', () {
    final regular = [_s('Германия'), _s('Финляндия')];
    expect(Networks.serversFor(regular, NetworkKind.mobile).length, 2);
    final whitelist = [_s('LTE Only - Швеция')];
    expect(Networks.serversFor(whitelist, NetworkKind.wifi).length, 1);
  });
}
