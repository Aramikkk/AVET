import 'package:avet/state/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  sleepTests();
  test('the smart choice asks the core for points and the habit', () {
    const rules = RuleSettings(strategy: 3, strategyLte: 3);
    final wifi = Engine.autoSmart(rules, false, memory: '/data/habits.json')!;
    expect(wifi['smart_points'], true);
    expect(wifi['smart_gain_pts'], 6);
    expect(wifi['smart_country_pts'], 4);
    // medium strength by default: twelve points
    expect(wifi['smart_habit'], 12);
    expect(wifi['smart_memory'], '/data/habits.json');
    final mobile = Engine.autoSmart(rules, true)!;
    expect(mobile['smart_gain_pts'], 4);
    expect(mobile.containsKey('smart_memory'), false);
  });

  test('the strength of the habit follows the setting, and off is none', () {
    for (final (habit, points) in [(0, 0), (1, 6), (2, 12), (3, 18)]) {
      final rules = RuleSettings(strategy: 3, habit: habit);
      expect(Engine.autoSmart(rules, false)!['smart_habit'], points);
    }
  });

  test('fewer hops needs a clearly better server, in points', () {
    const rules = RuleSettings(strategy: 3, strategyLte: 3, fewHopsLte: true);
    final smart = Engine.autoSmart(rules, true)!;
    expect(smart['smart_gain_pts'], 30);
    expect(smart['smart_country_pts'], 8);
  });

  test('the country is read from the flag in the name', () {
    expect(countryOfTag('\u{1F1E9}\u{1F1EA} Germany'), 'DE');
    expect(countryOfTag('Plain name'), '');
    expect(countryOfTag('x \u{1F1F3}\u{1F1F1} NL 01'), 'NL');
  });

  test('the habit setting is stored', () {
    final r = RuleSettings.fromJson(const RuleSettings(habit: 3).toJson());
    expect(r.habit, 3);
    expect(RuleSettings.fromJson({}).habit, 2);
  });
}

void sleepTests() {
  test('each network has its own count of awake servers', () {
    const rules = RuleSettings(
      strategy: 3,
      strategyLte: 3,
      sleepCount: 5,
      sleepCountLte: 20,
    );
    expect(Engine.autoSmart(rules, false)!['smart_active'], 5);
    expect(Engine.autoSmart(rules, true)!['smart_active'], 20);
    // an old file has one count: mobile data starts from it
    final old = RuleSettings.fromJson({'sleepCount': 15});
    expect(old.sleepCountLte, 15);
    final back = RuleSettings.fromJson(rules.toJson());
    expect(back.sleepCount, 5);
    expect(back.sleepCountLte, 20);
  });

  test('pinned servers are stored and handed to the core as a file', () {
    final rules = RuleSettings.fromJson(
      const RuleSettings(pinned: ['a', 'b'], strategy: 3).toJson(),
    );
    expect(rules.pinned, ['a', 'b']);
    expect(RuleSettings.fromJson({}).pinned, isEmpty);
    expect(
      Engine.autoSmart(rules, false, pins: '/x/pinned.json')!['smart_pins'],
      '/x/pinned.json',
    );
  });
}
