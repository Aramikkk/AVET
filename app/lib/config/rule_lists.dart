import 'dart:io';

/// The block lists kept by the app itself, so the core never has to download anything to start: a list is fetched once
/// a day (through whatever way out the phone has then) and the core reads the copy. A list that can't be had is left
/// out until it can; the VPN starts either way.
abstract final class RuleLists {
  static const maxAge = Duration(hours: 24);

  /// The local copies of [lists] (tag → address) in [dir]: tag → file path, for every list there is a copy of. Copies
  /// older than [maxAge] are fetched again; when that fails the old copy serves.
  static Future<Map<String, String>> ensure(
    String dir,
    Map<String, String> lists,
  ) async {
    final folder = Directory('$dir/rule-sets')..createSync(recursive: true);
    final out = <String, String>{};
    for (final MapEntry(key: tag, value: url) in lists.entries) {
      final file = File('${folder.path}/$tag.srs');
      final fresh =
          file.existsSync() &&
          DateTime.now().difference(file.lastModifiedSync()) < maxAge;
      if (!fresh) await _fetch(url, file);
      if (file.existsSync() && file.lengthSync() > 0) out[tag] = file.path;
    }
    return out;
  }

  static Future<void> _fetch(String url, File to) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final res = await (await client.getUrl(
        Uri.parse(url),
      )).close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return;
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
      }
      if (bytes.isEmpty) return;
      final part = File('${to.path}.part')..writeAsBytesSync(bytes);
      part.renameSync(to.path);
    } catch (_) {
      // the old copy (if any) serves
    } finally {
      client.close(force: true);
    }
  }
}
