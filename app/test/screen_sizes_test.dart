import 'dart:io';

import 'package:avet/ui/connections_page.dart';
import 'package:avet/ui/home_mosaic.dart';
import 'package:avet/ui/home_page.dart';
import 'package:avet/ui/home_studio.dart';
import 'package:avet/ui/stats_page.dart';
import 'package:avet/ui/topology_page.dart';
import 'package:avet/ui/traffic_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every page at phones from 320 to 800 points wide (and a landscape one), at the normal text size and at 1.4 times: nothing
/// may run over the edge of its box.
void main() {
  final sizes = <(String, Size)>[
    ('small 320x568', const Size(320, 568)),
    ('360x640', const Size(360, 640)),
    ('360x780', const Size(360, 780)),
    ('411x915', const Size(411, 915)),
    ('small tablet 600x960', const Size(600, 960)),
    ('foldable inner 700x740', const Size(700, 740)),
    ('tablet 800x1280', const Size(800, 1280)),
    ('landscape 915x411', const Size(915, 411)),
  ];
  final pages = <(String, Widget)>[
    ('home', const HomePage()),
    ('mosaic', const MosaicHome()),
    ('studio', const StudioHome()),
    ('stats', const StatsPage()),
    ('connections', const ConnectionsPage()),
    ('topology', const TopologyPage()),
    ('traffic', const TrafficPage()),
  ];
  final problems = <String>[];
  for (final (sizeName, size) in sizes) {
    for (final scale in [1.0, 1.4]) {
      for (final (pageName, page) in pages) {
        testWidgets('$pageName at $sizeName x$scale', (tester) async {
          final dir = Directory.systemTemp.createTempSync('avet');
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(const MethodChannel('avet/vpn'), (
                call,
              ) async {
                if (call.method == 'dir') return dir.path;
                if (call.method == 'status') return {'running': false};
                return null;
              });
          final oldHandler = FlutterError.onError;
          FlutterError.onError = (details) {
            final text = details.toString();
            final where = RegExp(
              r'lib/ui/[a-z_]+\.dart:\d+',
            ).allMatches(text).map((m) => m.group(0)!).toSet().join(' ');
            final what = RegExp(
              r'overflowed by [0-9.]+ pixels on the [a-z]+',
            ).firstMatch(text)?.group(0);
            if (what != null) {
              problems.add('$pageName @ $sizeName x$scale: $what [$where]');
            }
          };
          addTearDown(() => FlutterError.onError = oldHandler);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(body: page),
              ),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          final e = tester.takeException();
          if (e != null) {
            final where = RegExp(r'file:///\S+?\.dart:\d+')
                .allMatches(e.toString())
                .map((m) => m.group(0)!.split('/').last)
                .toSet()
                .join(' ');
            problems.add(
              '$pageName @ $sizeName x$scale: ${e.toString().split('\n').first} [$where]',
            );
          }
        });
      }
    }
  }
  // the tests above only collect what overflowed; this one is the verdict
  test('nothing overflows at any size or text scale', () {
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
