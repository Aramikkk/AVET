import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// What the newest release says about its build (its `latest.json`).
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.build,
    required this.apk,
    required this.size,
    required this.notes,
    this.sha256 = '',
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
    version: json['version'] as String,
    build: (json['build'] as num).toInt(),
    apk: json['apk'] as String,
    size: (json['size'] as num?)?.toInt() ?? 0,
    notes: (json['notes'] as String?) ?? '',
    sha256: ((json['sha256'] as String?) ?? '').trim().toLowerCase(),
  );

  /// "2.0.1"
  final String version;

  /// the Android build number, which grows with every release
  final int build;

  /// the APK's file name among the release's files
  final String apk;

  /// its size in bytes (0: not said)
  final int size;

  /// what is new
  final String notes;

  /// the APK's SHA-256 (hex; empty: not said)
  final String sha256;

  bool isNewerThan(int installedBuild) => build > installedBuild;
}

/// The installed build: its name ("2.0.0") and number (the one the updates are compared by).
class InstalledVersion {
  const InstalledVersion(this.name, this.code);

  final String name;
  final int code;
}

/// AVET's own update over the network. The newest build is looked up in the GitHub Releases of the project: its
/// `latest.json` and the APK are among the release's files. The APK is downloaded to the cache (carried on from where a
/// broken download stopped), checked against the SHA-256 of `latest.json` and handed to the system installer.
abstract class Updates {
  /// The project whose releases the app updates itself from.
  static const repo = 'Aramikkk/AVET';

  static const _channel = MethodChannel('avet/vpn');

  /// For tests only: the release's files are taken from this address (a server on the same device) instead of GitHub.
  /// Empty in the release build (set with --dart-define=AVET_UPDATE_BASE=http://127.0.0.1:8099).
  static const _testBase = String.fromEnvironment('AVET_UPDATE_BASE');

  /// The address of a file of the newest release. The name is a plain file name.
  static String fileUrl(String name) {
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.contains('..')) {
      throw const FormatException('not a file name');
    }
    if (_testBase.isNotEmpty) return '$_testBase/${Uri.encodeComponent(name)}';
    return 'https://github.com/$repo/releases/latest/download/${Uri.encodeComponent(name)}';
  }

  /// The installed build as last read (read once at the start: the About page has it when it is built).
  static InstalledVersion? last;

  static Future<InstalledVersion> installed() async {
    final m = await _channel.invokeMapMethod<String, dynamic>('version');
    return last = InstalledVersion(
      (m?['name'] as String?) ?? '',
      (m?['code'] as num?)?.toInt() ?? 0,
    );
  }

  /// The look the app takes by itself once a day: the newest build when it is newer than the installed one, otherwise
  /// null (no look was due yet, nothing new, or no connection: then it looks again at the next opening). The time of the
  /// last look is kept in [dir] (the app's files).
  static Future<UpdateInfo?> dailyCheck(String dir) async {
    final file = File('$dir/update_check.json');
    var last = 0;
    try {
      last = ((jsonDecode(file.readAsStringSync()) as Map)['at'] as num)
          .toInt();
    } catch (_) {}
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(hours: 24).inMilliseconds) return null;
    try {
      final installed = await Updates.installed();
      final info = await latest();
      file.writeAsStringSync(jsonEncode({'at': now}));
      if (info == null || !info.isNewerThan(installed.code)) return null;
      return info;
    } catch (_) {
      return null;
    }
  }

  /// The newest build the project has published, or null when there is no release (yet).
  static Future<UpdateInfo?> latest() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(fileUrl('latest.json')));
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode == 404) {
        await res.drain<void>();
        return null;
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('HTTP ${res.statusCode}');
      }
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      return UpdateInfo.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads the APK of [info] to the cache, [onProgress] told the share done (0 to 1). What already came of a broken
  /// download is kept and carried on from. The file is checked against the size and the SHA-256 `latest.json` gives.
  static Future<File> download(
    UpdateInfo info, {
    void Function(double)? onProgress,
  }) async {
    final dir = Directory((await _channel.invokeMethod<String>('updateDir'))!);
    // what is left of other builds goes; the part of this one stays
    for (final e in dir.listSync()) {
      final name = e.path.split(RegExp(r'[\\/]')).last;
      if (!name.startsWith(info.apk)) e.deleteSync(recursive: true);
    }
    final file = File('${dir.path}/${info.apk}');
    final part = File('${file.path}.part');
    if (file.existsSync()) file.deleteSync();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      for (var attempt = 0; ; attempt++) {
        var have = part.existsSync() ? part.lengthSync() : 0;
        if (info.size > 0 && have > info.size) {
          part.deleteSync();
          have = 0;
        }
        if (info.size > 0 && have == info.size) break;
        try {
          final req = await client.getUrl(Uri.parse(fileUrl(info.apk)));
          if (have > 0) {
            req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
          }
          final res = await req.close().timeout(const Duration(seconds: 30));
          var append = have > 0;
          if (res.statusCode == 200) {
            // the server took no range: from the start
            append = false;
            have = 0;
          } else if (res.statusCode != 206) {
            await res.drain<void>();
            if (res.statusCode == 416 && part.existsSync()) part.deleteSync();
            throw HttpException('HTTP ${res.statusCode}');
          }
          final total = info.size > 0
              ? info.size
              : (res.contentLength > 0 ? have + res.contentLength : 0);
          final sink = part.openWrite(
            mode: append ? FileMode.append : FileMode.write,
          );
          try {
            // a stalled connection is given up on and carried on from where it stopped
            await for (final chunk in res.timeout(
              const Duration(seconds: 30),
            )) {
              sink.add(chunk);
              have += chunk.length;
              if (total > 0) onProgress?.call((have / total).clamp(0.0, 1.0));
            }
          } finally {
            await sink.close();
          }
          break;
        } catch (e) {
          if (attempt >= 5) rethrow;
          await Future<void>.delayed(Duration(seconds: attempt < 3 ? 1 : 3));
        }
      }
    } finally {
      client.close(force: true);
    }
    part.renameSync(file.path);
    if (info.size > 0 && file.lengthSync() != info.size) {
      file.deleteSync();
      throw const FormatException('the file came incomplete');
    }
    if (info.sha256.isNotEmpty) {
      final got =
          (await _channel.invokeMethod<String>('sha256', {
            'path': file.path,
          })) ??
          '';
      if (got != info.sha256) {
        file.deleteSync();
        throw const FormatException(
          'the file is not the one that was published',
        );
      }
    }
    return file;
  }

  /// Hands the downloaded APK to the installer: "ok", "permission" (the page that allows installing from the app was opened)
  /// or "error".
  static Future<String> install(File apk, {bool allowSettings = true}) async =>
      (await _channel.invokeMethod<String>('install', {
        'path': apk.path,
        'allowSettings': allowSettings,
      })) ??
      'error';
}
