import 'package:avet/ui/toast.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A card the developer can be thanked on: the bank, the 16 digits and who the card is in the name of.
typedef DonationCard = ({String bank, String number, String holder});

/// The cards shown in About, "Поблагодарить разработчика". A transfer is voluntary and opens nothing in the app.
const donationCards = <DonationCard>[
  (bank: 'Сбербанк', number: '2202205332798831', holder: 'Арам Аракелян'),
  (bank: 'Т-Банк', number: '2200700617588750', holder: 'Арам Аракелян'),
];

/// "2202 2053 3279 8831": a card number in groups of four.
String formatCardNumber(String number) => [
  for (var i = 0; i < number.length; i += 4)
    number.substring(i, i + 4 > number.length ? number.length : i + 4),
].join(' ');

/// Whether [number] passes the Luhn check every bank card number does (a typo in a number on this page is caught by
/// the test).
bool isValidCardNumber(String number) {
  if (!RegExp(r'^\d{13,19}$').hasMatch(number)) return false;
  var sum = 0;
  for (var i = 0; i < number.length; i++) {
    var digit = int.parse(number[number.length - 1 - i]);
    if (i.isOdd) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
  }
  return sum % 10 == 0;
}

/// The cards in a sheet from the bottom, each with its copy button.
Future<void> showDonateSheet(BuildContext context) => showSheet<void>(
  context: context,
  isScrollControlled: true,
  useRootNavigator: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black54,
  builder: (context) => const _DonateSheet(),
);

class _DonateSheet extends StatelessWidget {
  const _DonateSheet();

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    final soft = Palette.soft(dark);
    return Container(
      decoration: BoxDecoration(
        color: Palette.plate(dark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: soft.withValues(alpha: .7),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Поблагодарить разработчика',
                style: mono(context, 17, weight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Приложение бесплатное, без рекламы. Поддержать разработку можно переводом на карту. Добровольно, ничего не открывает.',
                style: mono(context, 12, colour: soft),
              ),
              const SizedBox(height: 16),
              for (final card in donationCards) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: ink.withValues(alpha: .28)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.bank,
                        style: mono(
                          context,
                          12,
                          colour: Palette.red,
                          weight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        formatCardNumber(card.number),
                        style: mono(
                          context,
                          19,
                          weight: FontWeight.w800,
                          spacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(card.holder, style: mono(context, 11, colour: soft)),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('Скопировать номер'),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: card.number),
                            );
                            toast('Номер карты скопирован');
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'Спасибо, что пользуетесь AVET',
                textAlign: TextAlign.center,
                style: mono(context, 11, colour: soft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
