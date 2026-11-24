import 'package:flutter/services.dart';

/// The names the apps go by in the pictures: a package's well-known name, or the label the system gives the app whose uid
/// the core names a connection by.
abstract final class AppNames {
  static const _channel = MethodChannel('avet/vpn');

  static const _known = {
    'org.telegram.messenger': 'Telegram',
    'org.telegram.messenger.web': 'Telegram',
    'com.instagram.android': 'Instagram',
    'com.whatsapp': 'WhatsApp',
    'com.google.android.youtube': 'YouTube',
    'com.android.chrome': 'Chrome',
    'com.yandex.browser': 'Яндекс Браузер',
    'com.vkontakte.android': 'ВКонтакте',
    'com.openai.chatgpt': 'ChatGPT',
    'com.anthropic.claude': 'Claude',
  };

  static final _resolved = <String, String>{};
  static final _asked = <String>{};
  static final _icons = <String, Uint8List>{};

  /// An app's icon (PNG), once the system has given it.
  static Uint8List? iconOf(String app) => _icons[app];

  static bool _isUid(String app) => int.tryParse(app) != null;

  /// What an app (a package or a uid) is called.
  static String label(String app) {
    if (app.isEmpty) return 'Система';
    final named = _resolved[app] ?? _known[app];
    if (named != null) return named;
    if (_isUid(app)) return 'Приложение $app';
    final last = app.split('.').last;
    return last.isEmpty ? app : last[0].toUpperCase() + last.substring(1);
  }

  /// Whether [app] is a uid not yet asked about.
  static bool needs(String app) => _isUid(app) && !_asked.contains(app);

  /// Asks the system for the labels of the uids among [apps] (once each); true when something new came.
  static Future<bool> resolve(Iterable<String> apps) async {
    final uids = {
      for (final a in apps)
        if (needs(a)) a,
    };
    if (uids.isEmpty) return false;
    _asked.addAll(uids);
    try {
      final got = await _channel.invokeMapMethod<String, String>('appLabels', {
        'uids': [for (final u in uids) int.parse(u)],
      });
      if (got == null) {
        _asked.removeAll(uids);
        return false;
      }
      if (got.isEmpty) return false;
      _resolved.addAll(got);
      try {
        final icons = await _channel.invokeMapMethod<String, Uint8List>(
          'appIcons',
          {
            'uids': [for (final u in uids) int.parse(u)],
          },
        );
        if (icons != null) _icons.addAll(icons);
      } catch (_) {}
      return true;
    } catch (_) {
      // the system did not answer (the screen was not ready): asked again next time
      _asked.removeAll(uids);
      return false;
    }
  }
}
