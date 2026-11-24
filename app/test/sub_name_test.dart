import 'package:avet/data/sub_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a subscription name is cut to its first word, in capitals', () {
    expect(shortSub('Sigma'), 'SIGMA');
    expect(shortSub('ChillGuy VPN 🚀 (Недоступна)'), 'CHILLGUY');
    expect(shortSub('🚀 My Provider'), 'MY');
    expect(shortSub('SuperLongProviderName'), 'SUPERLON');
    expect(shortSub(''), '');
  });
}
