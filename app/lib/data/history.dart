import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// The periods the Statistics tab can show.
enum Range {
  minute('1 мин'),
  tenMinutes('10 мин'),
  hour('1 ч'),
  day('24 ч'),
  all('Всё');

  const Range(this.label);

  final String label;

  /// the length of a slot of the graph, and how many there are
  Duration get slot => switch (this) {
    Range.minute => const Duration(seconds: 1),
    Range.tenMinutes => const Duration(seconds: 10),
    Range.hour => const Duration(minutes: 1),
    Range.day => const Duration(minutes: 20),
    Range.all => const Duration(days: 1),
  };

  int get slots => switch (this) {
    Range.minute => 60,
    Range.tenMinutes => 60,
    Range.hour => 60,
    Range.day => 72,
    Range.all => 30,
  };
}

/// Bytes moved in some stretch of time.
class Moved {
  Moved([this.down = 0, this.up = 0]);

  int down;
  int up;

  void add(int d, int u) {
    down += d;
    up += u;
  }

  List<int> toJson() => [down, up];

  static Moved fromJson(Object? json) {
    final l = json is List
        ? json.whereType<num>().map((n) => n.toInt()).toList()
        : const <int>[];
    return Moved(l.isNotEmpty ? l[0] : 0, l.length > 1 ? l[1] : 0);
  }
}

/// The traffic, kept by the second for ten minutes, by the minute for two days and by the day for good: what the
/// speed graph of the Statistics shows for each period.
class TrafficHistory {
  TrafficHistory({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const secondsKept = 600;
  static const minutesKept = 2 * 24 * 60;

  final DateTime Function() _clock;

  /// by second since the epoch
  final seconds = <int, Moved>{};

  /// by minute since the epoch
  final minutes = <int, Moved>{};

  /// by day since the epoch (UTC days)
  final days = <int, Moved>{};

  /// A reading of the core: [up] and [down] bytes in the last second.
  void add(int up, int down, {DateTime? at}) {
    final t = (at ?? _clock()).millisecondsSinceEpoch ~/ 1000;
    (seconds[t] ??= Moved()).add(down, up);
    (minutes[t ~/ 60] ??= Moved()).add(down, up);
    (days[t ~/ 86400] ??= Moved()).add(down, up);
    if (seconds.length > secondsKept + 30) {
      final cut = t - secondsKept;
      seconds.removeWhere((k, _) => k < cut);
    }
    if (minutes.length > minutesKept + 60) {
      final cut = t ~/ 60 - minutesKept;
      minutes.removeWhere((k, _) => k < cut);
    }
  }

  /// The average speed (bytes a second) in each slot of [range], the oldest first, up to now.
  List<({double down, double up})> series(Range range, {DateTime? now}) {
    final t = (now ?? _clock()).millisecondsSinceEpoch ~/ 1000;
    final slotSeconds = range.slot.inSeconds;
    final out = <({double down, double up})>[];
    for (var i = range.slots - 1; i >= 0; i--) {
      // the slot ends at the current slot's end less i slots
      final end = (t ~/ slotSeconds + 1 - i) * slotSeconds;
      final start = end - slotSeconds;
      var down = 0;
      var up = 0;
      switch (range) {
        case Range.minute || Range.tenMinutes:
          for (var s = start; s < end; s++) {
            final m = seconds[s];
            if (m != null) {
              down += m.down;
              up += m.up;
            }
          }
        case Range.hour || Range.day:
          for (var m = start ~/ 60; m < end ~/ 60; m++) {
            final b = minutes[m];
            if (b != null) {
              down += b.down;
              up += b.up;
            }
          }
        case Range.all:
          final b = days[start ~/ 86400];
          if (b != null) {
            down = b.down;
            up = b.up;
          }
      }
      out.add((down: down / slotSeconds, up: up / slotSeconds));
    }
    return out;
  }

  /// What moved in all of [range].
  Moved total(Range range, {DateTime? now}) {
    final t = (now ?? _clock()).millisecondsSinceEpoch ~/ 1000;
    final from = t - range.slot.inSeconds * range.slots;
    final out = Moved();
    switch (range) {
      case Range.minute || Range.tenMinutes:
        seconds.forEach((k, v) {
          if (k >= from) out.add(v.down, v.up);
        });
      case Range.hour || Range.day:
        minutes.forEach((k, v) {
          if (k * 60 >= from) out.add(v.down, v.up);
        });
      case Range.all:
        days.forEach((_, v) => out.add(v.down, v.up));
    }
    return out;
  }

  Map<String, Object?> toJson() => {
    'minutes': {for (final e in minutes.entries) '${e.key}': e.value.toJson()},
    'days': {for (final e in days.entries) '${e.key}': e.value.toJson()},
  };

  void load(Map<String, dynamic> json) {
    (json['minutes'] as Map? ?? {}).forEach(
      (k, v) => minutes[int.parse('$k')] = Moved.fromJson(v),
    );
    (json['days'] as Map? ?? {}).forEach(
      (k, v) => days[int.parse('$k')] = Moved.fromJson(v),
    );
  }
}

/// A stretch of ping probes: how many, how many were lost and the sum and highest of the answers.
class PingBucket {
  PingBucket({this.count = 0, this.lost = 0, this.sum = 0, this.max = 0});

  int count;
  int lost;
  int sum;
  int max;

  int get answered => count - lost;
  int? get average => answered == 0 ? null : (sum / answered).round();

  void add(int? ms) {
    count++;
    if (ms == null) {
      lost++;
    } else {
      sum += ms;
      max = math.max(max, ms);
    }
  }

  List<int> toJson() => [count, lost, sum, max];

  static PingBucket fromJson(Object? json) {
    final l = json is List
        ? json.whereType<num>().map((n) => n.toInt()).toList()
        : const <int>[];
    return PingBucket(
      count: l.isNotEmpty ? l[0] : 0,
      lost: l.length > 1 ? l[1] : 0,
      sum: l.length > 2 ? l[2] : 0,
      max: l.length > 3 ? l[3] : 0,
    );
  }
}

/// The ping probes, kept raw for ten minutes, by the minute for two days and by the day for good.
class PingHistory {
  PingHistory({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// by second since the epoch: the answer in ms, null for a lost probe
  final raw = <int, int?>{};
  final minutes = <int, PingBucket>{};
  final days = <int, PingBucket>{};

  void add(int? ms, {DateTime? at}) {
    final t = (at ?? _clock()).millisecondsSinceEpoch ~/ 1000;
    raw[t] = ms;
    (minutes[t ~/ 60] ??= PingBucket()).add(ms);
    (days[t ~/ 86400] ??= PingBucket()).add(ms);
    if (raw.length > 260) {
      raw.removeWhere((k, _) => k < t - TrafficHistory.secondsKept);
    }
    if (minutes.length > TrafficHistory.minutesKept + 60) {
      final cut = t ~/ 60 - TrafficHistory.minutesKept;
      minutes.removeWhere((k, _) => k < cut);
    }
  }

  /// One bucket for each slot of [range], the oldest first (empty ones where nothing was probed).
  List<PingBucket> series(Range range, {DateTime? now}) {
    final t = (now ?? _clock()).millisecondsSinceEpoch ~/ 1000;
    final slotSeconds = range.slot.inSeconds;
    final out = <PingBucket>[];
    for (var i = range.slots - 1; i >= 0; i--) {
      final end = (t ~/ slotSeconds + 1 - i) * slotSeconds;
      final start = end - slotSeconds;
      final b = PingBucket();
      switch (range) {
        case Range.minute || Range.tenMinutes:
          for (var s = start; s < end; s++) {
            if (raw.containsKey(s)) b.add(raw[s]);
          }
        case Range.hour || Range.day:
          for (var m = start ~/ 60; m < end ~/ 60; m++) {
            final x = minutes[m];
            if (x != null) {
              b.count += x.count;
              b.lost += x.lost;
              b.sum += x.sum;
              b.max = math.max(b.max, x.max);
            }
          }
        case Range.all:
          final x = days[start ~/ 86400];
          if (x != null) {
            b.count = x.count;
            b.lost = x.lost;
            b.sum = x.sum;
            b.max = x.max;
          }
      }
      out.add(b);
    }
    return out;
  }

  /// The stretches of minutes in which probes were lost since [since] (the session's start), each run of minutes one episode.
  List<LossEpisode> lossEpisodes({DateTime? since}) {
    final from = since == null ? 0 : since.millisecondsSinceEpoch ~/ 60000;
    final keys = minutes.keys.where((m) => m >= from).toList()..sort();
    final out = <LossEpisode>[];
    LossEpisode? open;
    var last = 0;
    for (final m in keys) {
      final b = minutes[m]!;
      if (b.lost == 0) continue;
      if (open != null && m - last <= 1) {
        open
          ..minutes += m - last
          ..sent += b.count
          ..lost += b.lost;
      } else {
        open = LossEpisode(
          DateTime.fromMillisecondsSinceEpoch(m * 60000),
          1,
          b.count,
          b.lost,
        );
        out.add(open);
      }
      last = m;
    }
    return out;
  }

  /// The whole of [range] as one bucket.
  PingBucket total(Range range, {DateTime? now}) {
    final all = PingBucket();
    for (final b in series(range, now: now)) {
      all.count += b.count;
      all.lost += b.lost;
      all.sum += b.sum;
      all.max = math.max(all.max, b.max);
    }
    return all;
  }

  Map<String, Object?> toJson() => {
    'minutes': {for (final e in minutes.entries) '${e.key}': e.value.toJson()},
    'days': {for (final e in days.entries) '${e.key}': e.value.toJson()},
  };

  void load(Map<String, dynamic> json) {
    (json['minutes'] as Map? ?? {}).forEach(
      (k, v) => minutes[int.parse('$k')] = PingBucket.fromJson(v),
    );
    (json['days'] as Map? ?? {}).forEach(
      (k, v) => days[int.parse('$k')] = PingBucket.fromJson(v),
    );
  }
}

/// Both histories, kept in one file in the app's folder.
class HistoryStore {
  HistoryStore(this.file, {TrafficHistory? traffic, PingHistory? ping})
    : traffic = traffic ?? TrafficHistory(),
      ping = ping ?? PingHistory();

  final File file;
  final TrafficHistory traffic;
  final PingHistory ping;
  DateTime _saved = DateTime.fromMillisecondsSinceEpoch(0);

  void load() {
    try {
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      traffic.load((json['traffic'] as Map?)?.cast<String, dynamic>() ?? {});
      ping.load((json['ping'] as Map?)?.cast<String, dynamic>() ?? {});
    } catch (_) {
      // an unreadable history starts over
    }
  }

  /// Saved at most once a minute (and when [force]d).
  void save({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_saved) < const Duration(minutes: 1)) return;
    _saved = now;
    try {
      file.writeAsStringSync(
        jsonEncode({'traffic': traffic.toJson(), 'ping': ping.toJson()}),
      );
    } catch (_) {}
  }
}

/// A stretch of minutes in which probes were lost.
class LossEpisode {
  LossEpisode(this.start, this.minutes, this.sent, this.lost);

  final DateTime start;
  int minutes;
  int sent;
  int lost;
}
