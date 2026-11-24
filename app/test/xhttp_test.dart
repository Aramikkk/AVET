import 'dart:convert';
import 'dart:io';

import 'package:avet/subscription/links.dart';
import 'package:avet/subscription/xhttp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an xhttp link becomes an xhttp transport with its extra settings', () {
    final extra = Uri.encodeComponent(
      jsonEncode({
        'xPaddingBytes': '200-900',
        'scMaxEachPostBytes': '500000-1000000',
        'scMinPostsIntervalMs': 20,
        'noGRPCHeader': true,
        'headers': {'X-Test': '1'},
      }),
    );
    final s = Links.parseSubscription(
      'vless://11111111-2222-3333-4444-555555555555@example.com:443?security=reality&sni=www.example.com&pbk=abc&sid=ab&fp=chrome&type=xhttp&path=%2Fxh&host=cdn.example.com&mode=packet-up&extra=$extra#x',
    );
    expect(s, hasLength(1));
    final t = s.first['transport']! as Map;
    expect(t['type'], 'xhttp');
    expect(t['path'], '/xh');
    expect(t['host'], 'cdn.example.com');
    expect(t['mode'], 'packet-up');
    expect(t['x_padding_bytes'], '200-900');
    expect(t['sc_max_each_post_bytes'], 500000);
    expect(t['sc_min_posts_interval_ms'], 20);
    expect(t['no_grpc_header'], true);
    expect(t['headers'], {'X-Test': '1'});
  });

  test('the legacy name splithttp and an auto mode', () {
    final s = Links.parseSubscription(
      'vless://11111111-2222-3333-4444-555555555555@example.com:443?security=tls&type=splithttp&path=/a&mode=auto#x',
    );
    final t = s.first['transport']! as Map;
    expect(t['type'], 'xhttp');
    expect(t.containsKey('mode'), isFalse);
  });

  test('an Xray config with xhttpSettings', () {
    final body = jsonEncode({
      'remarks': 'x',
      'outbounds': [
        {
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': 'example.com',
                'port': 443,
                'users': [
                  {'id': '11111111-2222-3333-4444-555555555555'},
                ],
              },
            ],
          },
          'streamSettings': {
            'network': 'xhttp',
            'security': 'tls',
            'tlsSettings': {'serverName': 'example.com'},
            'xhttpSettings': {
              'path': '/p',
              'host': 'example.com',
              'mode': 'stream-up',
              'extra': {'xPaddingBytes': '100-1000'},
            },
          },
        },
      ],
    });
    final s = Links.parseSubscription(body);
    expect(s, isNotEmpty);
    final t = s.first['transport']! as Map;
    expect(t['type'], 'xhttp');
    expect(t['path'], '/p');
    expect(t['mode'], 'stream-up');
  });

  test('xhttpTransport reads a range given as a map', () {
    final t = xhttpTransport(
      extra: {
        'xPaddingBytes': {'from': 50, 'to': 60},
      },
    );
    expect(t['x_padding_bytes'], '50-60');
  });

  test('xmux and downloadSettings of the extra are carried over', () {
    final t = xhttpTransport(
      extra: {
        'xmux': {
          'maxConcurrency': '16-32',
          'hMaxRequestTimes': '600-900',
          'hMaxReusableSecs': '1800-3000',
        },
        'downloadSettings': {
          'address': 'cdn.example.com',
          'port': 8443,
          'network': 'xhttp',
          'security': 'tls',
          'tlsSettings': {
            'serverName': 'cdn.example.com',
            'alpn': ['h2'],
          },
          'xhttpSettings': {'path': '/dl', 'host': 'cdn.example.com'},
        },
      },
      tlsOf: (stream, server) => {
        'tls': {'enabled': true, 'server_name': server},
      },
    );
    expect(t['xmux'], {
      'max_concurrency': '16-32',
      'h_max_request_times': '600-900',
      'h_max_reusable_secs': '1800-3000',
    });
    final d = t['download']! as Map;
    expect(d['server'], 'cdn.example.com');
    expect(d['server_port'], 8443);
    expect(d['path'], '/dl');
    expect((d['tls']! as Map)['enabled'], true);
  });

  final singbox = Platform.environment['SINGBOX'];
  test(
    'sing-box accepts the config with an xhttp server',
    () async {
      final servers = Links.parseSubscription(
        'vless://11111111-2222-3333-4444-555555555555@example.com:443?security=tls&sni=example.com&type=xhttp&path=/xh&mode=packet-up&extra=${Uri.encodeComponent(jsonEncode({
          'xmux': {'maxConcurrency': '16-32'},
          'downloadSettings': {
            'address': 'cdn.example.com',
            'port': 443,
            'security': 'tls',
            'tlsSettings': {'serverName': 'cdn.example.com'},
            'xhttpSettings': {'path': '/dl'},
          },
        }))}#x',
      );
      final config = {
        'log': {'level': 'error'},
        'outbounds': servers,
        'route': {'final': servers.first['tag']},
      };
      final f = File('${Directory.systemTemp.path}/avet-xhttp.json')
        ..writeAsStringSync(jsonEncode(config));
      final r = await Process.run(singbox!, ['check', '-c', f.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    },
    skip: singbox == null ? 'SINGBOX not set' : false,
  );
}
