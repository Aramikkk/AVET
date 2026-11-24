import 'dart:async';

import 'package:avet/ui/widgets.dart' show Palette;
import 'package:flutter/material.dart';

/// The app's snack bars from anywhere (a notifier has no context).
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// A notice: it takes the place of the tabs in the dock (the row of the Statistics, Home, Topology tabs, at its size) while it
/// lasts.
class Notice {
  const Notice(this.text, {this.big, this.bigLabel});

  final String text;

  /// something to remember, written large at the right (a port)
  final String? big;
  final String? bigLabel;
}

final homeNotice = ValueNotifier<Notice?>(null);

Timer? _noticeTimer;

void hideNotice() {
  _noticeTimer?.cancel();
  homeNotice.value = null;
}

/// Whether the home screen is what the user looks at (no other tab, no page over it): a notice is then shown on it,
/// otherwise as a snack bar.
bool homeVisibleNow = false;

void toast(String text, {int seconds = 3, String? big, String? bigLabel}) {
  // the dock is on every tab; a page of the settings lies over all of it, and there the notice is a snack bar
  if (Palette.settingsOpen == 0) {
    messengerKey.currentState?.hideCurrentSnackBar();
    homeNotice.value = Notice(text, big: big, bigLabel: bigLabel);
    _noticeTimer?.cancel();
    _noticeTimer = Timer(Duration(seconds: seconds), hideNotice);
    return;
  }
  final m = messengerKey.currentState;
  if (m == null) return;
  final shown = big == null ? text : '$text: $big';
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(shown),
        duration: Duration(seconds: seconds),
      ),
    );
}
