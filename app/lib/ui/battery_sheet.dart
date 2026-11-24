import 'dart:async';

import 'package:avet/state/engine.dart';
import 'package:avet/ui/settings_page.dart' show desc;
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks to let the app work with no battery limits: the VPN and the statistics then go on without pauses while the screen
/// is off for long. The system's own window answers (it is opened by "Разрешить"); asked once by itself, and again from the
/// settings whenever wanted.
Future<void> showBatterySheet(BuildContext context, WidgetRef ref) {
  final engine = ref.read(engineProvider.notifier);
  engine.markBatteryAsked();
  return showSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (context) {
      final dark = isDark(context);
      final ink = Palette.ink(dark);
      final soft = Palette.soft(dark);
      return Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1B1B1B) : const Color(0xFFF7F9FA),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 52,
                    height: 6,
                    decoration: BoxDecoration(
                      color: soft.withValues(alpha: .7),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: ink,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.battery_charging_full_rounded,
                        size: 28,
                        color: Palette.paper(dark),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Работа в фоне',
                        style: mono(context, 18, weight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Разрешите AVET работать без ограничений батареи: VPN и статистика пойдут без пауз, даже когда экран долго выключен. Система покажет своё окно подтверждения.',
                  style: desc(context, 12),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(engine.askBattery());
                  },
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Palette.red,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Text(
                      'Разрешить',
                      style: mono(
                        context,
                        14,
                        weight: FontWeight.w800,
                        colour: Palette.onAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    child: Text(
                      'Не сейчас',
                      style: mono(
                        context,
                        13.5,
                        weight: FontWeight.w700,
                        colour: soft,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
