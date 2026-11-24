import 'dart:convert';

import 'package:avet/subscription/links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('vless', () {
    test('reality with a fingerprint and a flow', () {
      final o = Links.parse(
        'vless://11111111-2222-3333-4444-555555555555@nl.example.com:443'
        '?security=reality&sni=www.example.org&fp=firefox&pbk=PUBKEY&sid=ab12&flow=xtls-rprx-vision&type=tcp'
        '#%F0%9F%87%B3%F0%9F%87%B1%20Netherlands',
      )!;
      expect(o['type'], 'vless');
      expect(o['tag'], '🇳🇱 Netherlands');
      expect(o['server'], 'nl.example.com');
      expect(o['server_port'], 443);
      expect(o['uuid'], '11111111-2222-3333-4444-555555555555');
      expect(o['flow'], 'xtls-rprx-vision');
      final tls = o['tls']! as Map;
      expect(tls['server_name'], 'www.example.org');
      expect((tls['utls']! as Map)['fingerprint'], 'firefox');
      expect(tls['reality'], {
        'enabled': true,
        'public_key': 'PUBKEY',
        'short_id': 'ab12',
      });
      expect(o.containsKey('transport'), isFalse);
    });

    test('websocket over TLS keeps the path and the Host header', () {
      final o = Links.parse(
        'vless://u@de.example.com:8443?security=tls&type=ws&path=%2Fws&host=cdn.example.com#DE',
      )!;
      expect(o['transport'], {
        'type': 'ws',
        'path': '/ws',
        'headers': {'Host': 'cdn.example.com'},
      });
      expect((o['tls']! as Map)['server_name'], 'de.example.com');
    });

    test('gRPC takes the service name', () {
      final o = Links.parse(
        'vless://u@h.example.com:443?security=tls&type=grpc&serviceName=svc#G',
      )!;
      expect(o['transport'], {'type': 'grpc', 'service_name': 'svc'});
    });
  });

  test('vmess from its base64 JSON', () {
    final json = base64.encode(
      utf8.encode(
        jsonEncode({
          'v': '2',
          'ps': 'Finland',
          'add': 'fi.example.com',
          'port': '443',
          'id': 'abcd',
          'aid': '0',
          'net': 'ws',
          'path': '/v',
          'host': 'fi.example.com',
          'tls': 'tls',
          'sni': 'fi.example.com',
        }),
      ),
    );
    final o = Links.parse('vmess://$json')!;
    expect(o['type'], 'vmess');
    expect(o['tag'], 'Finland');
    expect(o['server_port'], 443);
    expect(o['security'], 'auto');
    expect((o['transport']! as Map)['path'], '/v');
    expect((o['tls']! as Map)['enabled'], true);
  });

  test('trojan is TLS by default', () {
    final o = Links.parse(
      'trojan://secret@se.example.com:443?sni=se.example.com#Sweden',
    )!;
    expect(o['type'], 'trojan');
    expect(o['password'], 'secret');
    expect((o['tls']! as Map)['server_name'], 'se.example.com');
  });

  group('shadowsocks', () {
    test('SIP002 with the user part in base64', () {
      final user = base64Url
          .encode(utf8.encode('chacha20-ietf-poly1305:pa ss'))
          .replaceAll('=', '');
      final o = Links.parse('ss://$user@1.2.3.4:8388#SS')!;
      expect(o['method'], 'chacha20-ietf-poly1305');
      expect(o['password'], 'pa ss');
      expect(o['server'], '1.2.3.4');
      expect(o['server_port'], 8388);
    });

    test('SIP002 with a plain user part', () {
      final o = Links.parse(
        'ss://2022-blake3-aes-128-gcm:key%3D%3D@[2001:db8::1]:443#v6',
      )!;
      expect(o['method'], '2022-blake3-aes-128-gcm');
      expect(o['password'], 'key==');
      expect(o['server'], '2001:db8::1');
    });

    test('the older form, everything in base64', () {
      final all = base64.encode(
        utf8.encode('aes-256-gcm:pw@ss.example.com:443'),
      );
      final o = Links.parse('ss://$all#Old')!;
      expect(o['server'], 'ss.example.com');
      expect(o['method'], 'aes-256-gcm');
    });
  });

  test('hysteria2 with obfuscation', () {
    final o = Links.parse(
      'hy2://pass@hy.example.com:8443?sni=hy.example.com&obfs=salamander&obfs-password=x&insecure=1#HY',
    )!;
    expect(o['type'], 'hysteria2');
    expect(o['password'], 'pass');
    expect(o['obfs'], {'type': 'salamander', 'password': 'x'});
    expect((o['tls']! as Map)['insecure'], true);
  });

  group('a subscription', () {
    test(
      'base64 body: every link read, unreadable lines skipped, same names made unique',
      () {
        final body = base64.encode(
          utf8.encode(
            [
              'vless://u@a.example.com:443?security=tls#Germany',
              'not a link',
              'trojan://p@b.example.com:443#Germany',
              'wireguard://ignored',
            ].join('\n'),
          ),
        );
        final list = Links.parseSubscription(body);
        expect(list.map((o) => o['tag']), ['Germany', 'Germany (2)']);
        expect(list.map((o) => o['type']), ['vless', 'trojan']);
      },
    );

    test('plain body works the same', () {
      final list = Links.parseSubscription(
        'vless://u@a.example.com:443#A\r\n\r\nhy2://p@c.example.com#C\n',
      );
      expect(list.length, 2);
      expect(list[1]['server_port'], 443);
    });
  });
}
