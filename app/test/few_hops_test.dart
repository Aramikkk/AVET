import 'package:avet/state/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fewer hops: slow checks, a high threshold, a long hold', () {
    const normal = RuleSettings(strategy: 1, strategyLte: 3);
    const few = RuleSettings(
      strategy: 1,
      strategyLte: 3,
      fewHopsWifi: true,
      fewHopsLte: true,
    );
    // one network only
    const wifiOnly = RuleSettings(
      strategy: 1,
      strategyLte: 1,
      fewHopsWifi: true,
    );
    expect(Engine.autoInterval(normal, false), '1m');
    expect(Engine.autoInterval(few, false), '30m');
    expect(Engine.autoInterval(few, true), '30m');
    expect(Engine.autoTolerance(normal, false), 10);
    expect(Engine.autoTolerance(few, false), 400);
    expect(Engine.autoTolerance(few, true), 600);
    expect(Engine.autoTolerance(wifiOnly, false), 400);
    expect(Engine.autoTolerance(wifiOnly, true), 10);
    expect(Engine.autoInterval(wifiOnly, true), '30s');
    final smart = Engine.autoSmart(few, true)!;
    expect(smart['smart_dwell'], '20m');
    expect(smart['smart_gain_ms'], 600);
    expect(Engine.autoSmart(normal, true)!['smart_dwell'], '90s');
  });

  test('the single switch of before turns both on', () {
    final r = RuleSettings.fromJson({'fewHops': true});
    expect(r.fewHopsWifi, isTrue);
    expect(r.fewHopsLte, isTrue);
    expect(RuleSettings.fromJson({'fewHopsLte': true}).fewHopsWifi, isFalse);
  });
}
