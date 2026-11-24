import 'package:avet/ui/motion.dart';
import 'package:avet/ui/nav_icons.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One tab of the phone's bar.
typedef PhoneTab = ({String paths, String label});

/// The phone's five tabs as a floating capsule under the panel: signs only, the chosen tab opens into a dark capsule
/// with its name. A tap picks a tab; a finger held on the bar and slid along it carries the capsule with it (a tick at
/// every tab) and the tab it is let go on opens, as on an iPhone.
class PhoneTabs extends StatefulWidget {
  const PhoneTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });

  final List<PhoneTab> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  State<PhoneTabs> createState() => _PhoneTabsState();
}

class _PhoneTabsState extends State<PhoneTabs> {
  /// the tab under the finger while it is down, null otherwise
  int? _hover;

  /// the tab the capsule stood at last: with no tab lit (a page of the settings is open) it fades out where it was
  int _last = 2;
  double _width = 1;

  int _indexAt(double x) {
    final n = widget.tabs.length;
    return (x / (_width / n)).floor().clamp(0, n - 1);
  }

  void _move(double x) {
    final i = _indexAt(x);
    if (i == _hover) return;
    if (hapticsNow) HapticFeedback.selectionClick();
    setState(() => _hover = i);
  }

  void _release() {
    final i = _hover;
    setState(() => _hover = null);
    if (i != null && i != widget.selected) widget.onSelect(i);
  }

  Duration _d(int ms) =>
      reduceMotionNow ? Duration.zero : Duration(milliseconds: ms);

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final chosen = Palette.ink(dark);
    final onChosen = dark ? const Color(0xFF111111) : Colors.white;
    // the capsule is where the finger is while it is down, else on the tab that is open
    final lit = _hover ?? widget.selected;
    final none = lit < 0;
    if (!none) _last = lit;
    final at = none ? _last : lit;
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth;
        final cell = _width / widget.tabs.length;
        const curve = Cubic(0.32, 0.72, 0, 1);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _move(e.localPosition.dx),
          onPointerMove: (e) => _move(e.localPosition.dx),
          onPointerUp: (_) => _release(),
          onPointerCancel: (_) => setState(() => _hover = null),
          child: SizedBox(
            height: 54,
            child: Stack(
              children: [
                // the capsule glides to the lit tab, the same size at every stop
                AnimatedPositioned(
                  duration: _d(220),
                  curve: curve,
                  left: cell * at + 1,
                  width: cell - 2,
                  top: 5,
                  bottom: 5,
                  child: AnimatedOpacity(
                    duration: _d(140),
                    opacity: none ? 0 : 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: chosen,
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final (i, tab) in widget.tabs.indexed)
                      SizedBox(
                        width: cell,
                        height: 54,
                        child: Center(
                          // the sign, or the name inside the capsule when the tab is lit
                          child: AnimatedSwitcher(
                            duration: _d(120),
                            child: i == lit
                                ? Padding(
                                    key: ValueKey('name$i'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        tab.label,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontFamily: 'Golos Text',
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: onChosen,
                                        ),
                                      ),
                                    ),
                                  )
                                : IconTheme(
                                    key: ValueKey('sign$i'),
                                    data: IconThemeData(
                                      size: 25,
                                      color: Palette.soft(dark),
                                    ),
                                    child: NavIcon(tab.paths),
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
