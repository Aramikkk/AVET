import 'package:avet/state/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the timeouts of the ping are kept and have defaults', () {
    final r = RuleSettings.fromJson({'pingTimeout': 30, 'pingTimeoutLte': 90});
    expect(r.pingTimeout, 30);
    expect(r.pingTimeoutLte, 90);
    final d = RuleSettings.fromJson({});
    expect(d.pingTimeout, 10);
    expect(d.pingTimeoutLte, 60);
    expect(r.toJson()['pingTimeoutLte'], 90);
    expect(r.copyWith(pingTimeout: 5).pingTimeout, 5);
  });
}
