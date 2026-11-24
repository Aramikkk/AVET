import 'package:avet/ui/donate_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every card number on the thank-you page is a valid card number', () {
    for (final c in donationCards) {
      expect(isValidCardNumber(c.number), isTrue, reason: c.bank);
    }
  });

  test('a card number is written in groups of four', () {
    expect(formatCardNumber('2202205332798831'), '2202 2053 3279 8831');
  });
}
