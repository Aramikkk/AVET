import 'dart:convert';
import 'dart:io';

import 'package:avet/config/config_builder.dart';
import 'package:avet/subscription/fetch.dart';
import 'package:avet/subscription/links.dart';
import 'package:flutter_test/flutter_test.dart';

const _vless =
    'vless://11111111-1111-1111-1111-111111111111@v.example.com:443?security=reality&sni=www.example.com&fp=chrome&pbk=AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHHIIIIJJJJKKK&sid=ab12&type=tcp&flow=xtls-rprx-vision#Vless%20Reality';

final _links = [
  _vless,
  'tuic://22222222-2222-2222-2222-222222222222:secret@t.example.com:443?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=t.example.com#Tuic',
  'hysteria://h.example.com:443?auth=pass&upmbps=20&downmbps=100&peer=h.example.com&alpn=h3#Hysteria1',
  'hy2://pw@h2.example.com:443?sni=h2.example.com#Hy2',
  'anytls://secret@a.example.com:443?sni=a.example.com#AnyTLS',
  'socks5://user:pass@s.example.com:1080#Socks',
  'ss://${base64.encode(utf8.encode('aes-256-gcm:pw'))}@ss.example.com:8388#SS',
  'trojan://pw@tr.example.com:443?type=ws&path=%2Fws&host=tr.example.com&sni=tr.example.com#Trojan WS',
];

void main() {
  test('every link type is read into an outbound', () {
    final servers = Links.parseSubscription(_links.join('\n'));
    expect(servers.map((s) => s['type']).toList(), [
      'vless',
      'tuic',
      'hysteria',
      'hysteria2',
      'anytls',
      'socks',
      'shadowsocks',
      'trojan',
    ]);
  });

  test('the same list in base64 is read the same', () {
    final b = base64.encode(utf8.encode(_links.join('\n')));
    expect(Links.parseSubscription(b).length, _links.length);
  });

  test('a sing-box JSON config gives its servers, not its groups', () {
    final cfg = jsonEncode({
      'outbounds': [
        {
          'type': 'selector',
          'tag': 'select',
          'outbounds': ['a'],
        },
        {
          'type': 'vless',
          'tag': 'A',
          'server': 'a.example.com',
          'server_port': 443,
          'uuid': '11111111-1111-1111-1111-111111111111',
          'detour': 'other',
        },
        {'type': 'direct', 'tag': 'direct'},
      ],
    });
    final s = Links.parseSubscription(cfg);
    expect(s.length, 1);
    expect(s.first['tag'], 'A');
    expect(s.first.containsKey('detour'), isFalse);
  });

  test(
    'an Xray JSON config (a list of them, with remarks) gives its servers',
    () {
      final cfg = jsonEncode([
        {
          'remarks': 'Xray Reality',
          'outbounds': [
            {
              'protocol': 'vless',
              'tag': 'proxy',
              'settings': {
                'vnext': [
                  {
                    'address': 'x.example.com',
                    'port': 443,
                    'users': [
                      {
                        'id': '11111111-1111-1111-1111-111111111111',
                        'flow': 'xtls-rprx-vision',
                      },
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'tcp',
                'security': 'reality',
                'realitySettings': {
                  'serverName': 'www.example.com',
                  'publicKey': 'AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHHIIIIJJJJKKK',
                  'shortId': 'ab12',
                  'fingerprint': 'chrome',
                },
              },
            },
            {'protocol': 'freedom', 'tag': 'direct', 'settings': {}},
          ],
        },
        {
          'remarks': 'Xray VMess WS',
          'outbounds': [
            {
              'protocol': 'vmess',
              'settings': {
                'vnext': [
                  {
                    'address': 'w.example.com',
                    'port': 443,
                    'users': [
                      {
                        'id': '22222222-2222-2222-2222-222222222222',
                        'security': 'auto',
                      },
                    ],
                  },
                ],
              },
              'streamSettings': {
                'network': 'ws',
                'security': 'tls',
                'wsSettings': {
                  'path': '/ws',
                  'headers': {'Host': 'w.example.com'},
                },
                'tlsSettings': {'serverName': 'w.example.com'},
              },
            },
          ],
        },
      ]);
      final s = Links.parseSubscription(cfg);
      expect(s.map((e) => e['tag']).toList(), [
        'Xray Reality',
        'Xray VMess WS',
      ]);
      expect(s.first['type'], 'vless');
      expect((s.first['tls'] as Map)['reality'], isNotNull);
      expect((s.last['transport'] as Map)['type'], 'ws');
    },
  );

  test('a Clash config with tuic, hysteria, anytls and socks5 is read', () {
    const yaml = '''
proxies:
  - {name: T, type: tuic, server: t.example.com, port: 443, uuid: 11111111-1111-1111-1111-111111111111, password: p, alpn: [h3], sni: t.example.com}
  - {name: H, type: hysteria, server: h.example.com, port: 443, auth-str: a, up: 20 Mbps, down: 100 Mbps, sni: h.example.com}
  - {name: A, type: anytls, server: a.example.com, port: 443, password: p, sni: a.example.com}
  - {name: S, type: socks5, server: s.example.com, port: 1080, username: u, password: p}
''';
    final s = Links.parseSubscription(yaml);
    expect(s.map((e) => e['type']).toList(), [
      'tuic',
      'hysteria',
      'anytls',
      'socks',
    ]);
  });

  test('an invitation link gives the address inside it', () {
    expect(
      SubscriptionFetch.unwrap(
        'clash://install-config?url=https%3A%2F%2Fp.example.com%2Fsub%2Fabc',
      ),
      'https://p.example.com/sub/abc',
    );
    expect(
      SubscriptionFetch.unwrap(
        'sing-box://import-remote-profile?url=https%3A%2F%2Fp.example.com%2Fx#Name',
      ),
      'https://p.example.com/x',
    );
    expect(
      SubscriptionFetch.unwrap(
        'hiddify://import/https://p.example.com/sub#name',
      ),
      'https://p.example.com/sub',
    );
    expect(SubscriptionFetch.isAddress('https://p.example.com/sub'), isTrue);
    expect(SubscriptionFetch.isAddress(_vless), isFalse);
    expect(SubscriptionFetch.isAddress(_links.join('\n')), isFalse);
  });

  // sing-box itself checks that the servers of every kind make a config it accepts (SINGBOX = its binary)
  final singbox = Platform.environment['SINGBOX'];
  test(
    'sing-box accepts a config made of every server type',
    () async {
      final servers = Links.parseSubscription(_links.join('\n'));
      final wifi = servers.take(servers.length - 1).toList();
      final file = File('${Directory.systemTemp.path}/avet-formats.json')
        ..writeAsStringSync(
          jsonEncode(
            ConfigBuilder.buildForNetworks(wifi: wifi, mobile: [servers.last]),
          ),
        );
      final r = await Process.run(singbox!, ['check', '-c', file.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    },
    skip: singbox == null ? 'SINGBOX not set' : false,
  );

  test('notices of a provider in the shape of servers are told from servers', () {
    final body = [
      'vless://11111111-1111-1111-1111-111111111111@0.0.0.0:443?type=tcp#%E2%9A%A0%20%D0%9B%D0%B8%D0%BC%D0%B8%D1%82%20%D1%83%D1%81%D1%82%D1%80%D0%BE%D0%B9%D1%81%D1%82%D0%B2%20(3%2F3)',
      'vless://11111111-1111-1111-1111-111111111111@real.example.com:443?type=tcp#Finland',
    ].join(String.fromCharCode(10));
    final servers = Links.parseSubscription(body);
    expect(SubscriptionFetch.isDecoyServer(servers.first), isTrue);
    expect(SubscriptionFetch.isDecoyServer(servers.last), isFalse);
    expect(SubscriptionFetch.isDecoy(servers), isFalse);
    expect(SubscriptionFetch.messages(body).length, 1);
  });
}
