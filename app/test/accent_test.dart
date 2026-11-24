import 'package:avet/state/engine.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every accent has a name, and "no colour" is the last one', () {
    expect(Palette.accentNames.length, Palette.accents.length);
    expect(Palette.accentNames.last, 'Без цвета');
    expect(
      Palette.accentOn(Palette.accents.length - 1, true),
      const Color(0xFFF2F2EE),
    );
  });

  test('a colour of an older list goes to the same or the nearest of the new', () {
    // the first list: green (5) stays green (12), sky blue (11) stays sky blue (16), "no colour" stays the last
    expect(RuleSettings.fromJson({'lookV': 1, 'accent': 5}).accent, 12);
    expect(RuleSettings.fromJson({'lookV': 1, 'accent': 11}).accent, 16);
    expect(
      RuleSettings.fromJson({'lookV': 1, 'accent': 17}).accent,
      Palette.accents.length - 1,
    );
    // the list of reds and blues only (2): its blue (6) is the blue now (18)
    expect(
      RuleSettings.fromJson({'lookV': 1, 'accent': 6, 'accentV': 2}).accent,
      18,
    );
    // the list of before the wine reds (3): raspberry, coral and pink go to ruby and scarlet, amber to gold, the others
    // by their names
    expect(
      RuleSettings.fromJson({'lookV': 1, 'accent': 3, 'accentV': 3}).accent,
      2,
    );
    expect(
      RuleSettings.fromJson({'lookV': 1, 'accent': 4, 'accentV': 3}).accent,
      1,
    );
    expect(
      RuleSettings.fromJson({'lookV': 1, 'accent': 8, 'accentV': 3}).accent,
      9,
    );
    expect(
      RuleSettings.fromJson({'lookV': 1, 'accent': 6, 'accentV': 3}).accent,
      7,
    );
    expect(
      RuleSettings.fromJson({'lookV': 1, 'accent': 18, 'accentV': 3}).accent,
      18,
    );
    expect(
      RuleSettings.fromJson({'lookV': 1, 'accent': 7, 'accentV': 4}).accent,
      7,
    );
    expect(RuleSettings.fromJson({'lookV': 1}).accent, -1);
  });

  test('the presets name the colours asked for', () {
    expect(Palette.accentNames[RuleSettings.presets[0]![1]], 'Бургунди');
    expect(Palette.accentNames[RuleSettings.presets[1]![1]], 'Ледяной');
    expect(Palette.accentNames[RuleSettings.presets[2]![1]], 'Лайм');
  });

  test('every look keeps its own volume, accent and sheet', () {
    // no file: Glass begins with Liquid, burgundy and the sunset, in the grotesk figures
    final fresh = RuleSettings.fromJson({});
    expect([fresh.style, fresh.depth, fresh.bg, fresh.digits], [0, 3, 3, 0]);
    expect(Palette.accentNames[fresh.accent], 'Бургунди');
    // every look begins with Liquid: Studio lime, on the theme's own sheet; Mosaic icy, on the mosaic sheet
    final studio = fresh.switchedTo(2);
    expect([studio.depth, studio.bg], [3, 2]);
    expect(Palette.accentNames[studio.accent], 'Лайм');
    final mosaic = studio.switchedTo(1);
    expect([mosaic.depth, mosaic.bg], [3, 5]);
    expect(Palette.accentNames[mosaic.accent], 'Ледяной');
    // a change made in a look stays with that look
    final changed = mosaic.copyWith(depth: 1, bg: 0).switchedTo(0);
    expect([changed.depth, changed.bg], [3, 3]);
    final again = changed.switchedTo(1);
    expect([again.depth, again.bg], [1, 0]);
    // and it is stored
    final back = RuleSettings.fromJson(again.toJson());
    expect(back.switchedTo(2).depth, 3);
    expect(back.switchedTo(0).bg, 3);
  });
  test('the launcher icon setting is kept and defaults to off', () {
    expect(const RuleSettings().tintIcon, isFalse);
    final on = RuleSettings.fromJson(
      (const RuleSettings().copyWith(tintIcon: true)).toJson(),
    );
    expect(on.tintIcon, isTrue);
    expect(RuleSettings.fromJson(const {}).tintIcon, isFalse);
  });
}
