import 'dart:async';

import 'package:avet/state/engine.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks for a subscription's link (typed or pasted) and loads it.
Future<void> showAddSubscription(BuildContext context, WidgetRef ref) async {
  final c = TextEditingController();
  final url = await showDialog<String>(
    animationStyle: sheetMotion,
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Добавить подписку'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.multiline,
            minLines: 1,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Ссылка на подписку, ссылки на серверы или конфиг',
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null) c.text = data!.text!.trim();
              },
              icon: const Icon(Icons.content_paste_rounded),
              label: const Text('Вставить из буфера'),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(showSupportedFormats(ctx)),
              icon: const Icon(Icons.info_outline_rounded),
              label: const Text('Что можно добавить'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, c.text),
          child: const Text('Добавить'),
        ),
      ],
    ),
  );
  if (url != null && url.trim().isNotEmpty) {
    unawaited(ref.read(engineProvider.notifier).updateSubscription(url));
  }
}

/// The big "add a subscription" block: on the home screen while there is none, and under the list in Settings.
class AddSubscriptionBlock extends ConsumerWidget {
  const AddSubscriptionBlock({super.key, this.mosaic = false});

  final bool mosaic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = isDark(context);
    final loading = ref.watch(
      engineProvider.select((e) => e.note == 'Загружаю подписку…'),
    );
    final ink = Palette.ink(dark);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: loading ? null : () => showAddSubscription(context, ref),
      child: Container(
        height: 84,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: mosaic ? Palette.red : Palette.plate(dark),
          borderRadius: BorderRadius.circular(mosaic ? 26 : 8),
          border: mosaic
              ? null
              : Border.all(color: ink.withValues(alpha: .6), width: 1.2),
        ),
        child: loading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: ink),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: 28,
                    color: mosaic ? Palette.onAccent : ink,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Добавить подписку',
                        maxLines: 1,
                        style: mono(
                          context,
                          16,
                          weight: FontWeight.w800,
                          colour: mosaic ? Palette.onAccent : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// What the app takes as a subscription: written out, for the add dialog and the Subscriptions page.
Future<void> showSupportedFormats(BuildContext context) => showSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black54,
  builder: (ctx) {
    final dark = isDark(ctx);
    final soft = Palette.soft(dark);
    Widget head(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Text(t, style: mono(ctx, 13.5, weight: FontWeight.w800)),
    );
    Widget line(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Text(t, style: mono(ctx, 12, colour: soft).copyWith(height: 1.5)),
    );
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * .8,
      ),
      decoration: BoxDecoration(
        color: Palette.plate(dark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 14),
              Text(
                'Что можно добавить',
                style: mono(ctx, 17, weight: FontWeight.w800),
              ),
              head('Ссылка на подписку'),
              line(
                'Обычный адрес https://… от провайдера (Marzban, Remnawave, 3x-ui, Sigma, ChillGuy и другие). Приложение представляется разными клиентами, пока провайдер не отдаст серверы, и передаёт идентификатор устройства.',
              ),
              head('Ссылка-приглашение'),
              line(
                'clash://install-config?url=…, sing-box://import-remote-profile?url=…, v2rayng://install-sub?url=…, hiddify://import/…, sub://… Адрес внутри берётся сам.',
              ),
              head('Что внутри подписки'),
              line('• ссылки на серверы по одной в строке (можно в base64);'),
              line('• конфиг Clash / Mihomo (YAML);'),
              line('• конфиг sing-box (JSON);'),
              line(
                '• конфиг Xray / V2Ray (JSON), в том числе список конфигов.',
              ),
              head('Протоколы'),
              line(
                'VLESS (Reality, XTLS Vision, WebSocket, gRPC, HTTPUpgrade), VMess, Trojan, Shadowsocks, Hysteria, Hysteria2, TUIC, AnyTLS, SOCKS5.',
              ),
              head('Вставить напрямую'),
              line(
                'Можно вставить ссылки на серверы (vless://, vmess://, trojan://, ss://, hy2://, tuic://, anytls://, socks5://…) или текст конфига. Они сохранятся как подписка «Свои серверы»: обновлять её не нужно.',
              ),
              head('Не принимается'),
              line(
                'Зашифрованные ссылки Happ (happ://crypt…) и подписки, которые отдают серверы только своему приложению.',
              ),
            ],
          ),
        ),
      ),
    );
  },
);
