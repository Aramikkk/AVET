/// The phone's network the VPN runs on: each has its own servers.
enum NetworkKind { wifi, mobile }

/// Which servers go with which network: on mobile data the whitelist ones (made to work where only allowed sites
/// open), on Wi-Fi the regular ones.
abstract final class Networks {
  static final _mobileOnly = RegExp(
    r'lte\s*only|lte\s*#|(^|[^а-яё])бс([^а-яё]|$)|белы[ей]\s+спис|white\s*list',
    caseSensitive: false,
    unicode: true,
  );

  /// Whether a server (by its name) is a whitelist one, for mobile data only.
  static bool isMobileOnly(String tag) => _mobileOnly.hasMatch(tag);

  /// The servers for [kind]. A network with none of its own gets all of them, so there is always something to connect
  /// to.
  static List<Map<String, Object?>> serversFor(
    List<Map<String, Object?>> servers,
    NetworkKind kind,
  ) {
    final own = [
      for (final s in servers)
        if (isMobileOnly(s['tag']! as String) == (kind == NetworkKind.mobile))
          s,
    ];
    return own.isEmpty ? servers : own;
  }
}
