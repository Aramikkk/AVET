import 'package:avet/data/flows.dart';
import 'package:avet/data/history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrafficHistory', () {
    test('the last minute is one slot a second, the newest last', () {
      final now = DateTime.utc(2026, 11, 16, 12, 0, 30);
      final h = TrafficHistory(clock: () => now);
      h.add(100, 1000, at: now);
      h.add(200, 3000, at: now.subtract(const Duration(seconds: 1)));
      final s = h.series(Range.minute, now: now);
      expect(s.length, 60);
      expect(s.last.down, 1000);
      expect(s[58].down, 3000);
      expect(s.first.down, 0);
    });

    test('an hour is a slot a minute, summed from the seconds', () {
      final now = DateTime.utc(2026, 11, 16, 12, 30, 59);
      final h = TrafficHistory(clock: () => now);
      for (var s = 0; s < 60; s++) {
        h.add(0, 600, at: DateTime.utc(2026, 11, 16, 12, 30, s));
      }
      final series = h.series(Range.hour, now: now);
      expect(series.length, 60);
      // 60 readings of 600 bytes in the minute: 600 bytes a second on average
      expect(series.last.down, closeTo(600, 0.001));
    });

    test('the total of a range counts what moved in it', () {
      final now = DateTime.utc(2026, 11, 16, 12, 0, 30);
      final h = TrafficHistory(clock: () => now);
      h.add(5, 10, at: now);
      h.add(5, 10, at: now.subtract(const Duration(seconds: 5)));
      final t = h.total(Range.minute, now: now);
      expect(t.down, 20);
      expect(t.up, 10);
    });

    test('it comes back from its json', () {
      final now = DateTime.utc(2026, 11, 16, 12, 0, 30);
      final h = TrafficHistory(clock: () => now)..add(1, 2, at: now);
      final back = TrafficHistory(clock: () => now)
        ..load(Map<String, dynamic>.from(h.toJson()));
      expect(back.days.values.single.down, 2);
      expect(back.minutes.values.single.up, 1);
    });

    test('the seconds kept are cut, the minutes stay', () {
      final now = DateTime.utc(2026, 11, 16, 12, 0, 0);
      final h = TrafficHistory(clock: () => now);
      for (var i = 0; i < 1000; i++) {
        h.add(0, 1, at: now.add(Duration(seconds: i)));
      }
      expect(
        h.seconds.length,
        lessThanOrEqualTo(TrafficHistory.secondsKept + 31),
      );
      expect(h.minutes.length, greaterThan(10));
    });
  });

  group('PingHistory', () {
    test('lost probes and answers are counted in a slot', () {
      final now = DateTime.utc(2026, 11, 16, 12, 0, 30);
      final h = PingHistory(clock: () => now);
      h.add(100, at: now);
      h.add(null, at: now.subtract(const Duration(seconds: 1)));
      h.add(200, at: now.subtract(const Duration(seconds: 2)));
      final total = h.total(Range.minute, now: now);
      expect(total.count, 3);
      expect(total.lost, 1);
      expect(total.average, 150);
      expect(total.max, 200);
    });

    test('an hour is a bucket a minute', () {
      final now = DateTime.utc(2026, 11, 16, 12, 30, 20);
      final h = PingHistory(clock: () => now);
      h.add(50, at: now);
      h.add(70, at: now.subtract(const Duration(seconds: 3)));
      final s = h.series(Range.hour, now: now);
      expect(s.length, 60);
      expect(s.last.average, 60);
      expect(s.first.count, 0);
    });
  });

  group('FlowTracker', () {
    Conn c(
      String id,
      int up,
      int down, {
      String app = 'org.telegram',
      String host = 'a.org',
      String server = 'DE',
    }) => Conn(
      id: id,
      app: app,
      host: host,
      server: server,
      direct: server == 'direct',
      up: up,
      down: down,
    );

    test(
      'each reading adds only what the connections moved since the last',
      () {
        final t = FlowTracker();
        final t0 = DateTime(2026, 1, 1, 12);
        t.update([c('1', 10, 90)], t0);
        expect(t.vpnBytes, 100);
        t.update([c('1', 20, 190)], t0.add(const Duration(seconds: 2)));
        expect(t.vpnBytes, 210);
        expect(t.flows.values.single.bytes, 210);
        expect(t.flows.values.single.speed, 55);
      },
    );

    test('direct and through a server are told apart', () {
      final t = FlowTracker();
      t.update([
        c('1', 0, 100),
        c('2', 0, 50, server: 'direct'),
      ], DateTime(2026, 1, 1));
      expect(t.vpnBytes, 100);
      expect(t.directBytes, 50);
      expect(t.byServer['DE'], 100);
      expect(t.byServer['direct'], 50);
    });

    test(
      'a connection that closes keeps what it moved and stops being followed',
      () {
        final t = FlowTracker();
        t.update([c('1', 0, 100)], DateTime(2026, 1, 1));
        t.update([], DateTime(2026, 1, 1, 0, 0, 2));
        expect(t.vpnBytes, 100);
        expect(t.seen, isEmpty);
        expect(t.flows.values.single.open, 0);
        expect(t.flows.values.single.speed, 0);
      },
    );

    test(
      'the core list is read: the node first in the chain, the app from the process path',
      () {
        final list = Conn.parse({
          'connections': [
            {
              'id': 'x',
              'upload': 5,
              'download': 9,
              'chains': ['🇩🇪 Германия', 'auto-wifi', 'select'],
              'metadata': {
                'host': 'api.telegram.org',
                'processPath': 'org.telegram.messenger',
              },
            },
            {
              'id': 'y',
              'upload': 1,
              'download': 2,
              'chains': ['direct'],
              'metadata': {'destinationIP': '1.2.3.4'},
            },
          ],
        });
        expect(list.length, 2);
        expect(list[0].server, '🇩🇪 Германия');
        expect(list[0].direct, isFalse);
        expect(list[0].app, 'org.telegram.messenger');
        expect(list[0].host, 'api.telegram.org');
        expect(list[1].direct, isTrue);
        expect(
          Conn.parse({
            'connections': [
              {
                'id': 'z',
                'chains': ['direct'],
                'metadata': {'processPath': 'Gms (10276)'},
              },
            ],
          }).single.app,
          '10276',
        );
        expect(list[1].host, '1.2.3.4');
      },
    );
  });

  group('FlowGroups', () {
    Conn c(
      String id,
      int down, {
      String app = 'a',
      String host = 'x.org',
      String server = 'DE',
    }) => Conn(
      id: id,
      app: app,
      host: host,
      server: server,
      direct: server == 'direct',
      up: 0,
      down: down,
    );

    test(
      'lines are grouped by app, the biggest first, with how much went through a server',
      () {
        final t = FlowTracker();
        t.update([
          c('1', 300, app: 'tg', host: 'a.org'),
          c('2', 100, app: 'tg', host: 'b.org', server: 'direct'),
          c('3', 50, app: 'vk', host: 'c.org', server: 'direct'),
        ], DateTime(2026, 1, 1));
        final g = t.groups(byApp: true);
        expect(g.map((e) => e.key), ['tg', 'vk']);
        expect(g.first.bytes, 400);
        expect(g.first.vpnShare, .75);
        expect(g.first.topOthers, ['a.org', 'b.org']);
        expect(g.first.servers, {'DE'});
      },
    );

    test('by site, and filtered to what went through a server', () {
      final t = FlowTracker();
      t.update([
        c('1', 300, host: 'a.org'),
        c('2', 100, host: 'a.org', server: 'direct'),
      ], DateTime(2026, 1, 1));
      expect(t.groups(byApp: false).single.bytes, 400);
      expect(t.groups(byApp: false, only: 'vpn').single.bytes, 300);
      expect(t.groups(byApp: false, only: 'direct').single.bytes, 100);
    });
  });
}
