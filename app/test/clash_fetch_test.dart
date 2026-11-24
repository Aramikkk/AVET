import 'package:avet/subscription/fetch.dart';
import 'package:avet/subscription/links.dart';
import 'package:flutter_test/flutter_test.dart';

const _clash = '''
mixed-port: 7890
proxies:
  - name: "🇸🇪 Швеция LTE Only"
    type: vless
    server: se.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: www.example.org
    client-fingerprint: chrome
    reality-opts:
      public-key: PUBKEY
      short-id: ab12
  - name: "Germany"
    type: trojan
    server: de.example.com
    port: 443
    password: secret
    network: ws
    ws-opts:
      path: /t
      headers:
        Host: cdn.example.com
  - name: "Germany"
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-256-gcm
    password: pw
  - name: "skip me"
    type: snell
    server: x.example.com
    port: 1
proxy-groups: []
''';

void main() {
  test(
    'a Clash subscription: vless reality, trojan over ws, shadowsocks; unknown types skipped',
    () {
      final list = Links.parseSubscription(_clash);
      expect(list.map((o) => o['type']), ['vless', 'trojan', 'shadowsocks']);
      expect(list.map((o) => o['tag']), [
        '🇸🇪 Швеция LTE Only',
        'Germany',
        'Germany (2)',
      ]);
      final tls = list[0]['tls']! as Map;
      expect(tls['reality'], {
        'enabled': true,
        'public_key': 'PUBKEY',
        'short_id': 'ab12',
      });
      expect(list[0]['flow'], 'xtls-rprx-vision');
      expect(list[1]['transport'], {
        'type': 'ws',
        'path': '/t',
        'headers': {'Host': 'cdn.example.com'},
      });
      expect(list[2]['method'], 'aes-256-gcm');
    },
  );

  test(
    'decoys are told: names that ask for another app, addresses that lead nowhere',
    () {
      expect(
        SubscriptionFetch.isDecoy(
          Links.parseSubscription(
            'vless://u@0.0.0.0:1#App not supported\n'
            'vless://u@1.1.1.1:443#Переустановите конфиг в личном кабинете',
          ),
        ),
        isTrue,
      );
      expect(
        SubscriptionFetch.isDecoy(Links.parseSubscription(_clash)),
        isFalse,
      );
      expect(SubscriptionFetch.isDecoy(const []), isFalse);
    },
  );
}
