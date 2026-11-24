import 'package:avet/data/country_names.dart';

/// A server as the app shows it: its flag, the country's name (and the number where there are several of it), and
/// whether it is a whitelist one ("БС"). Nothing of the provider's wording: "Доступ - Швеция 2 § 15" is "Швеция 2".
class ServerName {
  const ServerName({
    required this.flag,
    required this.title,
    required this.whitelist,
  });

  final String? flag;

  /// the country and its number; "БС" is not in it (see [whitelist])
  final String title;
  final bool whitelist;

  /// "Швеция 2 · БС" (the flag left out)
  String get label => whitelist ? '$title · БС' : title;

  static final _whitelistMark = RegExp(
    r'lte\s*only|lte\s*#|(^|[^а-яё])бс([^а-яё]|$)|белы[ей]\s+спис|white\s*list',
    caseSensitive: false,
    unicode: true,
  );

  /// The name of a server by its tag (the name the subscription gives it).
  static ServerName of(String tag) {
    var name = tag
        .replaceAll('§hide§', '')
        .replaceAll(RegExp(r'\s*§\s*\d+\s*$'), '')
        .trim();
    final whitelist = _whitelistMark.hasMatch(name);
    name = name
        .replaceAll(RegExp(r'LTE\s*Only\s*(?:-\s*)?', caseSensitive: false), '')
        .replaceAll(RegExp('[⚡️]'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    final runes = name.runes.toList();
    for (var i = 0; i + 1 < runes.length; i++) {
      final a = runes[i] - 0x1F1E6;
      final b = runes[i + 1] - 0x1F1E6;
      if (a >= 0 && a < 26 && b >= 0 && b < 26) {
        final flag = String.fromCharCodes([runes[i], runes[i + 1]]);
        final rest = name.replaceFirst(flag, '').trim();
        final country = countryNamesRu[String.fromCharCodes([a + 65, b + 65])];
        if (country != null) {
          final number = RegExp(
            r'[^\d.#]\s(\d{1,2})$',
          ).firstMatch(rest)?.group(1);
          return ServerName(
            flag: flag,
            title: number == null ? country : '$country $number',
            whitelist: whitelist,
          );
        }
        final dash = rest.indexOf(' - ');
        return ServerName(
          flag: flag,
          title: dash >= 0 ? rest.substring(dash + 3).trim() : rest,
          whitelist: whitelist,
        );
      }
    }
    return ServerName(
      flag: null,
      title: name.replaceAll(RegExp(r'\s*·?\s*БС'), '').trim(),
      whitelist: whitelist,
    );
  }
}
