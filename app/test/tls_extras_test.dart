import 'package:avet/subscription/links.dart';
import 'package:avet/subscription/tls_extras.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hysteria2 port hopping', () {
    test('mport in the query', () {
      final o = Links.parse(
        'hysteria2://pw@example.com:443/?sni=a.com&mport=20000-30000&hop_interval=20-40#hy',
      )!;
      expect(o['server_port'], 443);
      expect(o['server_ports'], ['443:443', '20000:30000']);
      expect(o['hop_interval'], '20s');
      expect(o['hop_interval_max'], '40s');
    });

    test('ports in the address', () {
      final o = Links.parse(
        'hy2://pw@example.com:443,20000-30000?sni=a.com#x',
      )!;
      expect(o['server'], 'example.com');
      expect(o['server_port'], 443);
      expect(o['server_ports'], ['443:443', '20000:30000']);
      expect(o['tag'], 'x');
    });

    test('main port inside the range is not repeated', () {
      expect(TlsExtras.hopping('400-500', 443, null), {
        'server_ports': ['400:500'],
      });
    });

    test('no hopping without ports', () {
      final o = Links.parse('hysteria2://pw@example.com:443#a')!;
      expect(o.containsKey('server_ports'), isFalse);
    });

    test('Clash ports', () {
      const yaml = '''
proxies:
  - name: h
    type: hysteria2
    server: example.com
    port: 443
    password: pw
    ports: 20000-30000
    hop-interval: 30
''';
      final o = Links.parseSubscription(yaml).single;
      expect(o['server_ports'], ['443:443', '20000:30000']);
      expect(o['hop_interval'], '30s');
    });
  });

  group('ECH', () {
    test('ech=1 asks the DNS', () {
      final o = Links.parse(
        'vless://u@example.com:443?security=tls&sni=a.com&ech=1&type=ws#e',
      )!;
      expect((o['tls']! as Map)['ech'], {'enabled': true});
    });

    test('base64 config list', () {
      final e = TlsExtras.ech('AEX+DQBBpQAgACB/')!;
      expect(e['enabled'], true);
      expect((e['config']! as List).first, '-----BEGIN ECH CONFIGS-----');
    });

    test('Xray name+dns form', () {
      expect(TlsExtras.ech('cloudflare-ech.com+https://1.1.1.1/dns-query'), {
        'enabled': true,
        'query_server_name': 'cloudflare-ech.com',
      });
    });

    test('not with REALITY', () {
      final o = Links.parse(
        'vless://u@example.com:443?security=reality&pbk=k&sid=1&ech=1#r',
      )!;
      expect((o['tls']! as Map).containsKey('ech'), isFalse);
    });

    test('Clash ech-opts', () {
      const yaml = '''
proxies:
  - name: t
    type: trojan
    server: example.com
    port: 443
    password: pw
    ech-opts:
      enable: true
      query-server-name: cover.example
''';
      final tls = Links.parseSubscription(yaml).single['tls']! as Map;
      expect(tls['ech'], {
        'enabled': true,
        'query_server_name': 'cover.example',
      });
    });
  });

  group('certificate pinning', () {
    const hex =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    const b64 = '47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=';

    test('pcs hex to base64', () {
      final o = Links.parse(
        'vless://u@example.com:443?security=tls&pcs=$hex#p',
      )!;
      expect((o['tls']! as Map)['certificate_public_key_sha256'], [b64]);
    });

    test('Hysteria2 pinSHA256 with colons', () {
      final colons = [
        for (var i = 0; i < hex.length; i += 2) hex.substring(i, i + 2),
      ].join(':');
      final o = Links.parse('hy2://pw@example.com:443?pinSHA256=$colons#h')!;
      expect((o['tls']! as Map)['certificate_public_key_sha256'], [b64]);
    });

    test('garbage is ignored', () {
      expect(TlsExtras.pins('abc,123'), isEmpty);
    });

    test('Clash fingerprint', () {
      const yaml =
          '''
proxies:
  - name: t
    type: trojan
    server: example.com
    port: 443
    password: pw
    fingerprint: $hex
''';
      final tls = Links.parseSubscription(yaml).single['tls']! as Map;
      expect(tls['certificate_public_key_sha256'], [b64]);
    });
  });
}
