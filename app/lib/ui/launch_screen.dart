import 'dart:ui' as ui;

import 'package:avet/ui/wordmark.dart';
import 'package:flutter/material.dart';

/// What the app shows from its first frame until it is ready (the system's own launch screen is only an empty page in
/// the same colour): the name large and the tagline small under it.
class LaunchScreen extends StatelessWidget {
  const LaunchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark =
        ui.PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    final paper = dark ? const Color(0xFF151515) : const Color(0xFFE4E6E8);
    final ink = dark ? const Color(0xFFF2F1EC) : const Color(0xFF000000);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        child: ColoredBox(
          color: paper,
          child: LayoutBuilder(
            builder: (context, box) {
              // the name takes two thirds of the width
              final width = box.maxWidth * .66;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppWordmark(height: width * 28 / 103.23),
                    SizedBox(height: width * .12),
                    DefaultTextStyle(
                      style: TextStyle(
                        fontFamily: 'Golos Text',
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                        letterSpacing: 3.6,
                        color: ink,
                        decoration: TextDecoration.none,
                      ),
                      child: const Text('FROM YOU NET'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
