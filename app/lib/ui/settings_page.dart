import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:avet/config/networks.dart';
import 'package:avet/data/dns_servers.dart';
import 'package:avet/data/server_name.dart';
import 'package:avet/data/sub_name.dart';
import 'package:avet/routing/routing.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/subscription/fetch.dart';
import 'package:avet/ui/donate_sheet.dart';
import 'package:avet/ui/battery_sheet.dart';
import 'package:avet/ui/figures.dart';
import 'package:avet/ui/pixel_flag.dart';
import 'package:avet/ui/sites_block.dart';
import 'package:avet/ui/add_subscription.dart';
import 'package:avet/ui/app_picker.dart';
import 'package:avet/ui/motion.dart';
import 'package:avet/ui/home_page.dart' show serversWord;
import 'package:avet/ui/toast.dart';
import 'package:avet/ui/update_block.dart';
import 'package:avet/ui/backdrops.dart';
import 'package:avet/ui/widgets.dart';
import 'package:avet/ui/wordmark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'subscriptions_part.dart';
part 'dns_part.dart';

/// The head of a page opened over the tabs: the way back and the name.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ink = Palette.ink(isDark(context));
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          IconButton(
            iconSize: 28,
            icon: Icon(Icons.arrow_back_rounded, color: ink),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Unbounded',
                fontWeight: FontWeight.w600,
                fontSize: 19,
                color: Palette.ink(isDark(context)),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A page of settings: the head and what it holds, over the same dotted sheet.
class _Sub extends StatelessWidget {
  const _Sub({required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;

  /// buttons in the head, at the right
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(title, trailing: trailing),
        Expanded(
          child: EdgeFade(
            child: ListView(
              // (the page goes to the very bottom of the screen: room for the system's bar too)
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                36 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: [
                for (final (i, w) in _grouped(context, children).indexed)
                  Rise(index: i, child: w),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// One row of the settings' menu: a light plate with the sign, the name and what is inside, an arrow.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 78,
          padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
          decoration: BoxDecoration(
            color: Palette.plate(dark),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: ink.withValues(alpha: .35)),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 28, color: Palette.paper(dark)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(context, 14.5, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: mono(
                        context,
                        13,
                        colour: Palette.soft(dark),
                        spacing: .6,
                      ).copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 28,
                color: Palette.soft(dark),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small explanatory text of a settings page (a description, a hint): in a proportional face (long Russian
/// paragraphs read better in it than in the mono one), lighter in colour by night and darker by day than the soft grey.
TextStyle desc(BuildContext context, double size) => TextStyle(
  fontFamily: 'Manrope',
  fontWeight: FontWeight.w500,
  fontSize: size + 2.0,
  height: 1.45,
  color: isDark(context) ? const Color(0xFFC4C4BF) : const Color(0xFF4B4B46),
);

void _open(BuildContext context, Widget page) =>
    unawaited(openPage(context, page));

/// A wide, filled button for the main action of a page (add, choose): the ink as its colour and the paper's as its text.
class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .5 : 1,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Palette.ink(dark),
            borderRadius: BorderRadius.circular(Palette.style >= 1 ? 22 : 16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Palette.paper(dark), size: 22),
              const SizedBox(width: 10),
              Text(
                label,
                style: mono(
                  context,
                  14.5,
                  weight: FontWeight.w800,
                  colour: Palette.paper(dark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The About page, from anywhere (a tap on the name on the home screen).
void openAbout(BuildContext context) => _open(context, const _About());

/// The page of the multi servers (the switches for each network and the apps that get a server of their own), from the home
/// screen's block of them.
void openSiteServers(BuildContext context) =>
    _open(context, const _SiteServers());

/// Settings: a menu of the groups, each opening its own page.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var n = 0;
    Widget row(IconData icon, String title, String sub, Widget page) => Rise(
      index: n++,
      child: _MenuRow(
        icon: icon,
        title: title,
        subtitle: sub,
        onTap: () => _open(context, page),
      ),
    );
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader('Настройки'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(26, 0, 26, 16),
              children: [
                row(
                  Icons.view_list_rounded,
                  'Подписки',
                  'Ссылки, обновление и порядок',
                  const _Subscription(),
                ),
                row(
                  Icons.tune_rounded,
                  'Управление подписками',
                  'Страны для Wi-Fi и LTE',
                  const _Countries(),
                ),
                row(
                  Icons.dns_outlined,
                  'Серверы',
                  'Регионы и цепочка серверов',
                  const _ServersSettings(),
                ),
                row(
                  Icons.auto_mode_rounded,
                  'Автовыбор',
                  'Как выбирается лучший сервер',
                  const _AutoChoice(),
                ),
                row(
                  Icons.route_rounded,
                  'Маршрутизация',
                  'Правила, сайты, приложения и ИИ',
                  const _Routing(),
                ),
                row(
                  Icons.power_settings_new_rounded,
                  'Запуск и подключение',
                  'Автозапуск, паузы, MTU',
                  const _Launch(),
                ),
                row(
                  Icons.travel_explore_rounded,
                  'DNS',
                  'Сервер имён и выбор лучшего',
                  const _DnsPage(),
                ),
                row(
                  Icons.network_ping_rounded,
                  'Пинг',
                  'Способ и пороги проверки задержки',
                  const _PingSettings(),
                ),
                row(
                  Icons.layers_rounded,
                  'Общие',
                  'Экономия, реклама, копия, язык',
                  const _General(),
                ),
                row(
                  Icons.palette_rounded,
                  'Темы',
                  'Стиль, цвета и шрифт',
                  const _Themes(),
                ),
                row(
                  Icons.description_rounded,
                  'Логи',
                  'Журнал ядра и смены сервера',
                  const _Logs(),
                ),
                row(
                  Icons.info_rounded,
                  'О программе',
                  'Версия, что нового, поддержка',
                  const _About(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A setting with a switch: the name, what it does under it, the switch with its tick. Switches that follow one another
/// are drawn together in one framed block, divided by thin lines (see [_Sub]).
class _SwitchTile extends StatelessWidget {
  const _SwitchTile(
    this.title,
    this.value,
    this.onChanged, {
    this.hint,
    this.icon,
  });

  final IconData? icon;

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
    child: Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 26, color: Palette.ink(isDark(context))),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: mono(context, 14.5, weight: FontWeight.w700)),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(hint!, style: desc(context, 11.5)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(value: value, onChanged: onChanged),
      ],
    ),
  );
}

Widget _switch(
  BuildContext context,
  String title,
  bool value,
  ValueChanged<bool> onChanged, {
  String? hint,
  IconData? icon,
}) => _SwitchTile(title, value, onChanged, hint: hint, icon: icon);

/// The children of a settings page, the runs of switches put into one block.
List<Widget> _grouped(BuildContext context, List<Widget> children) {
  final dark = isDark(context);
  final out = <Widget>[];
  var run = <Widget>[];
  void flush() {
    if (run.isEmpty) return;
    final rows = <Widget>[];
    for (final (i, w) in run.indexed) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 1,
            thickness: 1,
            color: Palette.ink(dark).withValues(alpha: .14),
          ),
        );
      }
      rows.add(w);
    }
    out.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Palette.plate(dark),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Palette.ink(dark).withValues(alpha: .28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: rows),
        ),
      ),
    );
    run = [];
  }

  for (final w in children) {
    if (w is _SwitchTile) {
      run.add(w);
    } else {
      flush();
      out.add(w);
    }
  }
  flush();
  return out;
}

Widget _hint(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
  child: Text(text, style: desc(context, 11)),
);

/// Settings -> General: a menu of its own groups.
class _General extends ConsumerWidget {
  const _General();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _MenuPage(
    title: 'Общие',
    rows: [
      (
        Icons.apps_rounded,
        'Приложение',
        'Определение IP после подключения',
        const _AppGroup(),
      ),
      (
        Icons.vibration_rounded,
        'Отклик',
        'Вибрация и уведомление',
        const _Feedback(),
      ),
      (
        Icons.battery_charging_full_rounded,
        'Экономия',
        'Суперлайт, лимит памяти, ночной режим',
        const _Economy(),
      ),
      (
        Icons.login_rounded,
        'Входящие',
        'Туннель, раздача, IPv6, мультиплексирование',
        const _Inbound(),
      ),
      (
        Icons.block_rounded,
        'Реклама',
        'Блокировка рекламы, фишинга и майнеров',
        const _Ads(),
      ),
      (
        Icons.backup_rounded,
        'Резервная копия',
        'Экспорт и импорт настроек',
        const _Backup(),
      ),
    ],
    after: [
      _MenuRow(
        icon: Icons.battery_charging_full_rounded,
        title: 'Работа в фоне',
        subtitle: 'Без ограничений батареи: VPN и статистика без пауз',
        onTap: () => unawaited(showBatterySheet(context, ref)),
      ),
      _MenuRow(
        icon: Icons.translate_rounded,
        title: 'Язык',
        subtitle: 'Русский',
        onTap: () => unawaited(showLanguageSheet(context)),
      ),
    ],
  );
}

/// A page that is a menu of further pages (the settings' second level).
class _MenuPage extends StatelessWidget {
  const _MenuPage({
    required this.title,
    required this.rows,
    this.after = const [],
  });

  final String title;
  final List<(IconData, String, String, Widget)> rows;

  /// rows that do something else than open a page (they follow the others)
  final List<Widget> after;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(title),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 16),
            children: [
              for (final (i, r) in rows.indexed)
                Rise(
                  index: i,
                  child: _MenuRow(
                    icon: r.$1,
                    title: r.$2,
                    subtitle: r.$3,
                    onTap: () => _open(context, r.$4),
                  ),
                ),
              for (final (i, w) in after.indexed)
                Rise(index: rows.length + i, child: w),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AppGroup extends ConsumerWidget {
  const _AppGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    return _Sub(
      title: 'Приложение',
      children: [
        _switch(
          context,
          'Проверять IP после подключения',
          r.ipCheck,
          (v) => ref
              .read(engineProvider.notifier)
              .setRules(r.copyWith(ipCheck: v)),
          hint:
              'Показывает страну и адрес выхода на главном экране (запрос к внешнему сервису).',
        ),
        _hint(
          context,
          'Аналитики нет, данные об использовании не отправляются.',
        ),
      ],
    );
  }
}

class _Feedback extends ConsumerWidget {
  const _Feedback();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    return _Sub(
      title: 'Отклик',
      children: [
        _switch(
          context,
          'Вибрация',
          r.haptics,
          (v) => engine.setRules(r.copyWith(haptics: v)),
          hint: 'Вибрация при переключении вкладок и свайпах.',
        ),
        _switch(
          context,
          'Данные в уведомлении',
          r.notifyInfo,
          (v) => engine.setRules(r.copyWith(notifyInfo: v)),
          hint: 'Сервер, пинг и потери в уведомлении.',
        ),
      ],
    );
  }
}

class _Economy extends ConsumerWidget {
  const _Economy();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    return _Sub(
      title: 'Экономия',
      children: [
        _switch(
          context,
          'Суперлайт',
          r.superLight,
          (v) => engine.setRules(r.copyWith(superLight: v)),
          hint:
              'Минимум нагрузки: только главный экран и настройки, проверки реже, без статистики и мульти серверов.',
        ),
        _switch(
          context,
          'Лёгкий вид',
          r.lightLook,
          (v) => engine.setRules(r.copyWith(lightLook: v)),
          hint: 'Без скольжения страниц и волн: меньше нагрузка. Цвета те же.',
        ),
        _switch(
          context,
          'Ночной режим',
          r.nightMode,
          (v) => ref
              .read(engineProvider.notifier)
              .setRules(r.copyWith(nightMode: v)),
          hint: 'С 23:00 до 7:00 всегда тёмная тема.',
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Palette.plate(isDark(context)),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Palette.ink(isDark(context)).withValues(alpha: .28),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Лимит памяти ядра',
                style: mono(context, 14.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'При достижении лимита ядро перезапускается. Меньше лимит: легче телефону, но перезапуски чаще. Действует после перезапуска приложения.',
                style: desc(context, 11.5),
              ),
              const SizedBox(height: 12),
              SegmentedChoice(
                height: 40,
                compact: true,
                labels: const ['Нет', '300 МБ', '450 МБ', '500 МБ'],
                icons: const [
                  Icons.circle,
                  Icons.circle,
                  Icons.circle,
                  Icons.circle,
                ],
                selected: const [
                  0,
                  300,
                  450,
                  500,
                ].indexOf(r.memoryMb).clamp(0, 3),
                onChanged: (i) => engine.setRules(
                  r.copyWith(memoryMb: const [0, 300, 450, 500][i]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Inbound extends ConsumerWidget {
  const _Inbound();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    final soft = Palette.soft(isDark(context));
    return _Sub(
      title: 'Входящие',
      children: [
        Text(
          'ТУННЕЛЬ',
          style: mono(
            context,
            11,
            colour: soft,
            spacing: 2.4,
            weight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        SegmentedChoice(
          height: 40,
          compact: true,
          labels: const ['mixed', 'system', 'gvisor'],
          icons: const [Icons.circle, Icons.circle, Icons.circle],
          selected: const [
            'mixed',
            'system',
            'gvisor',
          ].indexOf(r.stack).clamp(0, 2),
          onChanged: (i) => engine.setRules(
            r.copyWith(stack: const ['mixed', 'system', 'gvisor'][i]),
          ),
        ),
        _switch(
          context,
          'Строгие маршруты',
          r.strict,
          (v) => engine.setRules(r.copyWith(strict: v)),
          hint: 'Весь трафик телефона идёт в туннель, без обходных путей.',
        ),
        _switch(
          context,
          'Фрагментация TLS',
          r.fragment,
          (v) => engine.setRules(r.copyWith(fragment: v)),
          hint:
              'Приветствие TLS отправляется частями: помогает обойти фильтры, которые читают его целиком.',
        ),
        const SizedBox(height: 18),
        Text(
          'РАЗДАЧА',
          style: mono(
            context,
            11,
            colour: soft,
            spacing: 2.4,
            weight: FontWeight.w800,
          ),
        ),
        _switch(
          context,
          'Раздача',
          r.sharing,
          (v) => engine.setRules(r.copyWith(sharing: v)),
          hint:
              'Прокси на порту ${r.sharePort} для других устройств в локальной сети.',
        ),
        const SizedBox(height: 8),
        Text('Порт раздачи', style: mono(context, 14, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Paper(
          radius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(
            controller: TextEditingController(text: '${r.sharePort}'),
            onSubmitted: (v) {
              final p = int.tryParse(v.trim());
              if (p != null && p >= 1024 && p <= 65535) {
                engine.setRules(r.copyWith(sharePort: p));
              }
            },
            style: mono(context, 13),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
        _hint(context, 'Порт от 1024 до 65535. Со следующего подключения.'),
        const SizedBox(height: 8),
        Text(
          'Пароль раздачи',
          style: mono(context, 14, weight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _TextSetting(
          initial: r.sharePass,
          hint: 'Без пароля: прокси открыт для всех в сети',
          onDone: (v) => engine.setRules(r.copyWith(sharePass: v)),
        ),
        _hint(
          context,
          'Логин: avet. Введите его, пароль, адрес телефона и порт в настройках прокси другого устройства.',
        ),
        const SizedBox(height: 18),
        Text(
          'IPV6',
          style: mono(
            context,
            11,
            colour: soft,
            spacing: 2.4,
            weight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        SegmentedChoice(
          height: 40,
          compact: true,
          labels: const ['Выкл', 'Вкл', 'IPv6 первым', 'Только IPv6'],
          icons: const [Icons.circle, Icons.circle, Icons.circle, Icons.circle],
          selected: r.ipv6.clamp(0, 3),
          onChanged: (i) => engine.setRules(r.copyWith(ipv6: i)),
        ),
        _hint(
          context,
          'Выкл по умолчанию: многие серверы и сети с ним хуже. Вкл: имена в IPv4 и IPv6, IPv4 приоритетнее. Со следующего подключения.',
        ),
        const SizedBox(height: 18),
        Text(
          'МУЛЬТИПЛЕКСИРОВАНИЕ',
          style: mono(
            context,
            11,
            colour: soft,
            spacing: 2.4,
            weight: FontWeight.w800,
          ),
        ),
        _switch(
          context,
          'Мультиплексирование',
          r.mux,
          (v) => engine.setRules(r.copyWith(mux: v)),
          hint:
              'Несколько потоков в одном соединении: страницы открываются быстрее. Не работает с Vision. Со следующего подключения.',
        ),
        if (r.mux) ...[
          const SizedBox(height: 10),
          SegmentedChoice(
            height: 40,
            compact: true,
            labels: const ['h2mux', 'smux', 'yamux'],
            icons: const [Icons.circle, Icons.circle, Icons.circle],
            selected: r.muxProtocol.clamp(0, 2),
            onChanged: (i) => engine.setRules(r.copyWith(muxProtocol: i)),
          ),
          const SizedBox(height: 10),
          Text(
            'Потоков в соединении',
            style: mono(context, 13, weight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SegmentedChoice(
            height: 40,
            compact: true,
            labels: const ['2', '4', '8', '16'],
            icons: const [
              Icons.circle,
              Icons.circle,
              Icons.circle,
              Icons.circle,
            ],
            selected: const [2, 4, 8, 16].indexOf(r.muxStreams).clamp(0, 3),
            onChanged: (i) =>
                engine.setRules(r.copyWith(muxStreams: const [2, 4, 8, 16][i])),
          ),
          _switch(
            context,
            'Выравнивание (padding)',
            r.muxPadding,
            (v) => engine.setRules(r.copyWith(muxPadding: v)),
            hint:
                'Пакеты выравниваются по размеру: по длине их труднее опознать.',
          ),
        ],
      ],
    );
  }
}

/// A line of text for a setting: kept when the keyboard's button is pressed or the field is left.
class _TextSetting extends StatefulWidget {
  const _TextSetting({
    required this.initial,
    required this.hint,
    required this.onDone,
    this.keyboard,
  });

  final String initial;
  final String hint;
  final ValueChanged<String> onDone;
  final TextInputType? keyboard;

  @override
  State<_TextSetting> createState() => _TextSettingState();
}

class _TextSettingState extends State<_TextSetting> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );
  late final FocusNode _focus = FocusNode()
    ..addListener(() {
      if (!_focus.hasFocus) widget.onDone(_c.text.trim());
    });

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Paper(
    radius: 14,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: TextField(
      controller: _c,
      focusNode: _focus,
      keyboardType: widget.keyboard,
      onSubmitted: (v) => widget.onDone(v.trim()),
      style: mono(context, 13),
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: widget.hint,
        hintStyle: mono(context, 12, colour: Palette.soft(isDark(context))),
      ),
    ),
  );
}

/// Settings -> Start and connection: a menu of its groups.
class _Launch extends ConsumerWidget {
  const _Launch();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _MenuPage(
    title: 'Запуск и подключение',
    rows: [
      (
        Icons.bolt_rounded,
        'Автозапуск',
        'При открытии приложения и запуске телефона',
        const _Autostart(),
      ),
      (
        Icons.pause_circle_outline_rounded,
        'Паузы и дом',
        'Автопауза в домашнем Wi-Fi',
        const _Pauses(),
      ),
      (Icons.lan_rounded, 'Сеть', 'MTU и режим «Глобально»', const _Net()),
    ],
  );
}

class _Autostart extends ConsumerWidget {
  const _Autostart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    return _Sub(
      title: 'Автозапуск',
      children: [
        _switch(
          context,
          'Подключаться при открытии',
          r.autoStart,
          (v) => engine.setRules(r.copyWith(autoStart: v)),
          hint: 'VPN включается автоматически при открытии приложения.',
        ),
        _switch(
          context,
          'Подключаться при запуске телефона',
          r.boot,
          (v) => engine.setRules(r.copyWith(boot: v)),
          hint:
              'После перезагрузки VPN включается сам (нужно разрешение VPN). Берутся серверы последнего подключения.',
        ),
      ],
    );
  }
}

class _Pauses extends ConsumerWidget {
  const _Pauses();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    final soft = Palette.soft(isDark(context));
    return _Sub(
      title: 'Паузы и дом',
      children: [
        Text(
          'ДОМАШНИЙ WI-FI',
          style: mono(
            context,
            11,
            colour: soft,
            spacing: 2.4,
            weight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        _switch(
          context,
          'Пауза VPN дома',
          r.homePause,
          (v) => engine.setRules(r.copyWith(homePause: v)),
          hint:
              'В домашнем Wi-Fi VPN на паузе (трафик идёт через роутер), вне дома включается сам. Работает, пока приложение запущено.',
        ),
        Text(
          r.homes.isEmpty
              ? 'Домов пока нет'
              : 'Включено · домов: ${r.homes.length}',
          style: desc(context, 12),
        ),
        const SizedBox(height: 10),
        for (final (i, h) in r.homes.indexed)
          Paper(
            radius: 14,
            padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Дом ${i + 1} · роутер $h',
                    style: mono(context, 13, weight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: soft),
                  onPressed: () => engine.setRules(
                    r.copyWith(
                      homes: [
                        for (final x in r.homes)
                          if (x != h) x,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        _BigButton(
          label: 'Добавить эту сеть как дом',
          icon: Icons.add_rounded,
          onTap: () async {
            final ok = await engine.addHome();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? 'Сеть добавлена как дом'
                        : 'Подключитесь к домашнему Wi-Fi (сеть уже добавлена или это не Wi-Fi)',
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          },
        ),
        const SizedBox(height: 18),
        Text(
          'АВТОПАУЗА',
          style: mono(
            context,
            11,
            colour: soft,
            spacing: 2.4,
            weight: FontWeight.w800,
          ),
        ),
        _hint(
          context,
          'Пауза по приложению требует доступа к статистике использования Android: в AVET этого пока нет.',
        ),
      ],
    );
  }
}

class _Net extends ConsumerWidget {
  const _Net();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    return _Sub(
      title: 'Сеть',
      children: [
        Text('MTU', style: mono(context, 14, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        SegmentedChoice(
          height: 40,
          compact: true,
          labels: const ['авто', '1400', '1500', '9000'],
          icons: const [Icons.circle, Icons.circle, Icons.circle, Icons.circle],
          selected: const [0, 1400, 1500, 9000].indexOf(r.mtu).clamp(0, 3),
          onChanged: (i) =>
              engine.setRules(r.copyWith(mtu: const [0, 1400, 1500, 9000][i])),
        ),
        _hint(
          context,
          'Если часть сайтов не открывается, уменьшите значение. Со следующего подключения.',
        ),
        const SizedBox(height: 18),
        _switch(
          context,
          'Глобально',
          r.global,
          (v) => engine.setRules(r.copyWith(global: v)),
          hint: 'Весь трафик идёт через VPN, списки обхода отключены.',
        ),
        _hint(
          context,
          'Порт управления ядром 9090, доступен только на этом телефоне.',
        ),
      ],
    );
  }
}

class _Routing extends ConsumerWidget {
  const _Routing();

  static const _names = {
    'blockQuic': (
      'QUIC (HTTP/3)',
      'Приложения переключаются на TCP: через VPN так быстрее',
      'блокировать',
    ),
    'chinaChatDirect': (
      'WeChat и QQ напрямую',
      'WeChat, QQ и WeCom работают лучше без VPN',
      'напрямую',
    ),
    'socialProxy': (
      'Соцсети',
      'Instagram, Facebook, X и другие, закрытые в России',
      'VPN',
    ),
    'adultProxy': ('Сайты для взрослых', 'Закрытые в России', 'VPN'),
    'blockedProxy': (
      'Заблокированные',
      'Сайты и сервисы из списка блокировок',
      'VPN',
    ),
    'yandexDirect': ('Яндекс', 'Сервисы Яндекса идут напрямую', 'напрямую'),
    'marketsDirect': (
      'Маркетплейсы',
      'Ozon, Wildberries и другие российские магазины',
      'напрямую',
    ),
    'banksDirect': ('Банки', 'Российские банки: напрямую, без VPN', 'напрямую'),
    'ruAppsDirect': (
      'Российские приложения',
      'Идут напрямую, минуя VPN',
      'напрямую',
    ),
    'videoProxy': ('Видео', 'YouTube, Twitch и другие через VPN', 'VPN'),
    'storesProxy': (
      'Магазины приложений',
      'Google Play и другие через VPN',
      'VPN',
    ),
    'googleProxy': ('Google', 'Сервисы Google через VPN', 'VPN'),
    'chinaProxy': ('Китайские сервисы', 'Через VPN', 'VPN'),
    'foreignProxy': ('Зарубежные приложения', 'Через VPN', 'VPN'),
    'aiProxy': (
      'Нейросети',
      'ChatGPT, Claude, Gemini и другие через VPN',
      'VPN',
    ),
    'ruDomainsDirect': (
      'Российские домены',
      '.ru, .su, .рф и российские сервисы: напрямую',
      'напрямую',
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final ink = Palette.ink(dark);
    Widget caption(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        text,
        style: mono(
          context,
          11,
          colour: soft,
          spacing: 2.4,
          weight: FontWeight.w800,
        ),
      ),
    );
    return _Sub(
      title: 'Маршрутизация',
      children: [
        caption('ОСТАЛЬНОЙ ТРАФИК'),
        Paper(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.call_split_rounded, color: ink),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Всё остальное',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(context, 12.5, weight: FontWeight.w700),
                ),
              ),
              SizedBox(
                width: 190,
                child: SegmentedChoice(
                  height: 38,
                  compact: true,
                  labels: const ['VPN', 'Напрямую'],
                  icons: const [
                    Icons.shield_outlined,
                    Icons.arrow_outward_rounded,
                  ],
                  selected: r.restDirect ? 1 : 0,
                  onChanged: (i) =>
                      engine.setRules(r.copyWith(restDirect: i == 1)),
                ),
              ),
            ],
          ),
        ),
        caption('ПРИЛОЖЕНИЯ'),
        Paper(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Маршрутизация по приложениям',
                          style: mono(context, 14, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(switch (r.appMode) {
                          1 =>
                            'Выбранные приложения идут напрямую, всё остальное через VPN.',
                          2 =>
                            'Через VPN идут только выбранные приложения, всё остальное напрямую.',
                          _ =>
                            'Выберите приложения, которые идут мимо VPN или только через него.',
                        }, style: desc(context, 11.5)),
                      ],
                    ),
                  ),
                  Switch(
                    value: r.appMode != 0,
                    onChanged: (v) =>
                        engine.setRules(r.copyWith(appMode: v ? 1 : 0)),
                  ),
                ],
              ),
              if (r.appMode != 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 8, 0),
                  child: SegmentedChoice(
                    height: 40,
                    compact: true,
                    labels: const ['Мимо VPN', 'Только через VPN'],
                    icons: const [
                      Icons.arrow_outward_rounded,
                      Icons.shield_outlined,
                    ],
                    selected: r.appMode == 2 ? 1 : 0,
                    onChanged: (i) =>
                        engine.setRules(r.copyWith(appMode: i + 1)),
                  ),
                ),
              if (r.appMode != 0)
                InkWell(
                  onTap: () => _open(context, const AppPicker()),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.apps.isEmpty
                                ? 'Выбрать приложения'
                                : 'Выбрано: ${r.apps.length} приложений',
                            style: mono(context, 13, weight: FontWeight.w700),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: soft),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        caption('ПРАВИЛА'),
        Text(
          'Правила применяются сверху вниз: решает первое подходящее.',
          style: desc(context, 11.5),
        ),
        const SizedBox(height: 10),
        _switch(
          context,
          'Маршрутизация по спискам',
          r.routingList,
          (v) => engine.setRules(r.copyWith(routingList: v)),
          hint:
              'Российские сайты и сервисы идут напрямую, заблокированные — через VPN.',
        ),
        _switch(
          context,
          'Только заблокированное через VPN',
          r.blockedOnly,
          (v) => engine.setRules(r.copyWith(blockedOnly: v)),
          hint:
              'Работает в Wi-Fi. В мобильной сети весь трафик идёт через VPN.',
        ),
        if (r.routingList)
          _Collapsible(
            title: 'Правила по спискам',
            subtitle:
                '${routeGroups.length - r.groupsOff.where((k) => routeGroups.any((g) => g.key == k)).length} из ${routeGroups.length} включено',
            children: [
              for (final g in routeGroups)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.drag_handle_rounded, color: soft),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _names[g.key]?.$3 ?? '',
                              style: mono(
                                context,
                                11,
                                colour: _names[g.key]?.$3 == 'блокировать'
                                    ? const Color(0xFFE8A09C)
                                    : soft,
                              ),
                            ),
                            Text(
                              _names[g.key]?.$1 ?? g.key,
                              style: mono(context, 14, weight: FontWeight.w700),
                            ),
                            Text(
                              _names[g.key]?.$2 ?? '',
                              style: desc(context, 10.5),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: !r.groupsOff.contains(g.key),
                        onChanged: (v) => engine.setRules(
                          r.copyWith(
                            groupsOff: v
                                ? [
                                    for (final k in r.groupsOff)
                                      if (k != g.key) k,
                                  ]
                                : [...r.groupsOff, g.key],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        _hint(context, 'Применяется при следующем подключении.'),
        caption('САЙТЫ И ПРИЛОЖЕНИЯ'),
        _MenuRow(
          icon: Icons.call_split_rounded,
          title: 'Свой сервер для приложений',
          subtitle: 'Лучший сервер для каждого приложения',
          onTap: () => _open(context, const _SiteServers()),
        ),
        _MenuRow(
          icon: Icons.smart_toy_outlined,
          title: 'ИИ: один сервер',
          subtitle: 'ChatGPT, Claude, Gemini и другие',
          onTap: () => _open(context, const _AiServer()),
        ),
        _MenuRow(
          icon: Icons.language_rounded,
          title: 'Направление сайтов',
          subtitle: 'Свои сайты: через VPN или напрямую',
          onTap: () => _open(context, const _UserSites()),
        ),
      ],
    );
  }
}

class _SiteServers extends ConsumerWidget {
  const _SiteServers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    final soft = Palette.soft(isDark(context));
    return _Sub(
      title: 'Свой сервер для приложений',
      children: [
        _switch(
          context,
          'Wi-Fi: свой сервер для каждого приложения',
          r.siteGroups,
          (v) => engine.setRules(r.copyWith(siteGroups: v)),
          hint:
              'Instagram, Telegram, YouTube и другие получают свой лучший сервер, а не общий.',
        ),
        _switch(
          context,
          'LTE: свой сервер для каждого приложения',
          r.siteGroupsLte,
          (v) => engine.setRules(r.copyWith(siteGroupsLte: v)),
          hint:
              'То же для мобильной сети. Переключается и кнопкой на главном экране.',
        ),
        if (r.siteGroups || r.siteGroupsLte) ...[
          const SizedBox(height: 8),
          Text(
            'Менять сервер, если другой быстрее на',
            style: mono(context, 14, weight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SegmentedChoice(
            height: 40,
            compact: true,
            labels: const ['40 мс', '80 мс', '150 мс'],
            icons: const [Icons.circle, Icons.circle, Icons.circle],
            selected: const [40, 80, 150].indexOf(r.siteTol).clamp(0, 2),
            onChanged: (i) =>
                engine.setRules(r.copyWith(siteTol: const [40, 80, 150][i])),
          ),
          _hint(
            context,
            'Чем больше значение, тем реже смена сервера и меньше обрывов.',
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'НА ГЛАВНОЙ (до шести)',
          style: mono(
            context,
            11,
            colour: soft,
            spacing: 2.4,
            weight: FontWeight.w800,
          ),
        ),
        for (final e in serviceNames.entries)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            activeColor: Palette.red,
            controlAffinity: ListTileControlAffinity.trailing,
            title: Text(
              e.value,
              style: mono(context, 14, weight: FontWeight.w700),
            ),
            value: r.homeSites.contains(e.key),
            onChanged: (v) {
              final now = [...r.homeSites];
              if (v == true) {
                if (now.length >= 6) return;
                now.add(e.key);
              } else {
                now.remove(e.key);
              }
              engine.setRules(r.copyWith(homeSites: now));
            },
          ),
        const SizedBox(height: 18),
        Text(
          'СВОИ ПРИЛОЖЕНИЯ',
          style: mono(
            context,
            11,
            colour: soft,
            spacing: 2.4,
            weight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        for (final pkg in r.customApps)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              pkg,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(context, 13, weight: FontWeight.w700),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => engine.setRules(
                r.copyWith(
                  customApps: [
                    for (final p in r.customApps)
                      if (p != pkg) p,
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        _BigButton(
          label: 'Добавить приложение',
          icon: Icons.add_rounded,
          onTap: () => _open(context, const AppPicker(custom: true)),
        ),
        _hint(
          context,
          'Каждое добавленное приложение получает свой лучший сервер. Работает, пока включён режим выше. Со следующего подключения.',
        ),
      ],
    );
  }
}

/// "Направление сайтов": sites the user sends through the VPN or direct by hand (the domain and its subdomains).
class _UserSites extends ConsumerStatefulWidget {
  const _UserSites();

  @override
  ConsumerState<_UserSites> createState() => _UserSitesState();
}

class _UserSitesState extends ConsumerState<_UserSites> {
  final _domain = TextEditingController();
  bool _vpn = true;
  String? _error;

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  static final _valid = RegExp(
    r'^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9-]{2,}$',
  );

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    void add() {
      var d = _domain.text.trim().toLowerCase();
      d = d.replaceFirst(RegExp(r'^[a-z]+://'), '').split('/').first;
      d = d
          .replaceFirst(RegExp(r'^\*?\.?'), '')
          .replaceFirst(RegExp(r'^www\.'), '');
      if (!_valid.hasMatch(d)) {
        setState(() => _error = 'Введите домен, например example.com');
        return;
      }
      final now = [
        for (final u in r.userSites)
          if (u['d'] != d) u,
        {'d': d, 'vpn': _vpn},
      ];
      engine.setRules(r.copyWith(userSites: now));
      _domain.clear();
      setState(() => _error = null);
      FocusScope.of(context).unfocus();
    }

    Widget plate(List<Widget> kids) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Palette.plate(dark),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Palette.ink(dark).withValues(alpha: .28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: kids,
        ),
      ),
    );
    return _Sub(
      title: 'Направление сайтов',
      children: [
        plate([
          Text(
            'Добавить сайт',
            style: mono(context, 14.5, weight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Правило действует на домен и все его поддомены: example.com включает mail.example.com.',
            style: desc(context, 11.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _domain,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: mono(context, 13),
            onSubmitted: (_) => add(),
            decoration: InputDecoration(
              hintText: 'example.com',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          SegmentedChoice(
            height: 40,
            labels: const ['Через VPN', 'Напрямую'],
            icons: const [Icons.vpn_key_rounded, Icons.north_east_rounded],
            selected: _vpn ? 0 : 1,
            onChanged: (i) => setState(() => _vpn = i == 0),
          ),
          const SizedBox(height: 4),
          const SizedBox(height: 12),
          _BigButton(
            label: 'Добавить сайт',
            icon: Icons.add_rounded,
            onTap: add,
          ),
        ]),
        if (r.userSites.isNotEmpty)
          plate([
            for (final (i, u) in r.userSites.indexed) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  color: Palette.ink(dark).withValues(alpha: .14),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${u['d']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(context, 14, weight: FontWeight.w700),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => engine.setRules(
                        r.copyWith(
                          userSites: [
                            for (final x in r.userSites)
                              if (x['d'] == u['d'])
                                {'d': x['d'], 'vpn': x['vpn'] == false}
                              else
                                x,
                          ],
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: u['vpn'] != false
                              ? Palette.red.withValues(alpha: .14)
                              : Colors.transparent,
                          border: Border.all(
                            color: u['vpn'] != false
                                ? Palette.red
                                : Palette.ink(dark).withValues(alpha: .4),
                          ),
                        ),
                        child: Text(
                          u['vpn'] != false ? 'через VPN' : 'напрямую',
                          style: mono(context, 11.5, weight: FontWeight.w800),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => engine.setRules(
                        r.copyWith(
                          userSites: [
                            for (final x in r.userSites)
                              if (x['d'] != u['d']) x,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ]),
        _hint(
          context,
          'Эти сайты обрабатываются раньше остальных правил. Нажмите «через VPN» или «напрямую», чтобы переключить. Со следующего подключения.',
        ),
      ],
    );
  }
}

/// The countries a network's servers are in, each with the best ping of its servers (the whitelist servers for mobile data).
List<({String code, ServerName name, int? delay, String subs})> _countriesOf(
  EngineState s,
  bool lte,
) {
  final best = <String, int?>{};
  final names = <String, ServerName>{};
  // the subscriptions each country has servers in, as letters (S: Sigma, C: ChillGuy)
  final letters = <String, List<String>>{};
  for (final x in s.servers) {
    final tag = '${x['tag']}';
    if (Networks.isMobileOnly(tag) != lte) continue;
    final code = Engine.countryOf(tag);
    if (code == null) continue;
    names.putIfAbsent(code, () => ServerName.of(tag));
    final sub = shortSub(s.providers[tag] ?? '');
    if (sub.isNotEmpty) {
      final l = sub[0];
      final list = letters.putIfAbsent(code, () => []);
      if (!list.contains(l)) list.add(l);
    }
    final d = s.states
        .where((e) => e.tag == tag)
        .map((e) => e.delay)
        .firstOrNull;
    if (!best.containsKey(code) ||
        (d != null && (best[code] == null || d < best[code]!))) {
      best[code] = d;
    }
  }
  final list =
      [
        for (final e in best.entries)
          (
            code: e.key,
            name: names[e.key]!,
            delay: e.value,
            // only when there are several subscriptions: a letter each
            subs:
                s.subs.where((x) => x.enabled).length > 1 &&
                    (letters[e.key]?.isNotEmpty ?? false)
                ? ' (${letters[e.key]!.join(', ')})'
                : '',
          ),
      ]..sort((a, b) {
        if (a.delay != null && b.delay != null) {
          return a.delay!.compareTo(b.delay!);
        }
        if (a.delay != null) return -1;
        if (b.delay != null) return 1;
        return a.name.title.compareTo(b.name.title);
      });
  return list;
}

/// A country for one place of a network's list (the main one, a backup): a sheet of the countries with their pings.
Future<void> _pickCountry(
  BuildContext context,
  WidgetRef ref, {
  required bool lte,
  required int slot,
}) {
  final engine = ref.read(engineProvider.notifier);
  final s = ref.read(engineProvider);
  final list = _countriesOf(s, lte);
  final r = s.rules;
  final prefs = [...(lte ? r.aiLte : r.aiWifi)];
  void set(List<String> now) =>
      engine.setRules(lte ? r.copyWith(aiLte: now) : r.copyWith(aiWifi: now));
  return _rowsSheet(
    context,
    slot == 0 ? 'Основная страна' : 'Запасная страна $slot',
    [
      (
        icon: Icons.auto_mode_rounded,
        text: 'Авто (по пингу)',
        danger: false,
        onTap: () {
          if (slot < prefs.length) {
            prefs.removeAt(slot);
            set(prefs);
          }
        },
      ),
      for (final c in list)
        (
          icon: Icons.flag_outlined,
          text:
              '${c.name.title.replaceAll(RegExp(r'\s*\d+$'), '')}${c.subs}${c.delay == null ? '' : '  ·  ${c.delay} мс'}',
          danger: false,
          onTap: () {
            final now = [
              for (final p in prefs)
                if (p != c.code) p,
            ];
            now.insert(slot.clamp(0, now.length), c.code);
            set(now.take(3).toList());
          },
        ),
    ],
  );
}

class _AiServer extends ConsumerWidget {
  const _AiServer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(engineProvider);
    final r = s.rules;
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final ink = Palette.ink(dark);

    Widget slotTile(bool lte, int slot, List<String> prefs) {
      final code = slot < prefs.length ? prefs[slot] : null;
      final item = code == null
          ? null
          : _countriesOf(s, lte).where((c) => c.code == code).firstOrNull;
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () =>
            unawaited(_pickCountry(context, ref, lte: lte, slot: slot)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  '${slot + 1}',
                  style: mono(
                    context,
                    13,
                    colour: soft,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
              if (item != null) ...[
                flagMark(item.name.flag, width: 30),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  item == null
                      ? (code ?? 'Авто (по пингу)')
                      : '${item.name.title.replaceAll(RegExp(r'\s*\d+$'), '')}${item.subs}',
                  style: mono(context, 14, weight: FontWeight.w700),
                ),
              ),
              if (item?.delay != null)
                Text(
                  '${item!.delay} мс',
                  style: mono(context, 12.5, weight: FontWeight.w800),
                ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: soft),
            ],
          ),
        ),
      );
    }

    Widget network(bool lte) {
      final prefs = lte ? r.aiLte : r.aiWifi;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          decoration: BoxDecoration(
            color: Palette.plate(dark),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: ink.withValues(alpha: .28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    lte
                        ? Icons.signal_cellular_alt_rounded
                        : Icons.wifi_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    lte ? 'Мобильная сеть' : 'Wi-Fi',
                    style: mono(context, 14.5, weight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                lte
                    ? 'Страны из белых списков (БС): работает первая отвечающая, остальные запасные.'
                    : 'Работает первая отвечающая страна, остальные запасные.',
                style: desc(context, 11),
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < 3; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: ink.withValues(alpha: .14)),
                slotTile(lte, i, prefs),
              ],
            ],
          ),
        ),
      );
    }

    return _Sub(
      title: 'ИИ: один сервер',
      children: [
        _switch(
          context,
          'ИИ: один сервер для всех',
          r.aiGroup,
          (v) => engine.setRules(r.copyWith(aiGroup: v)),
          hint:
              'ChatGPT, Claude, Gemini и другие держатся одного адреса: смену они не любят.',
        ),
        if (r.aiGroup) ...[
          const SizedBox(height: 8),
          network(false),
          network(true),
        ],
        _hint(
          context,
          'Основная и запасные страны выбираются отдельно для каждой сети. Без выбора сервер подбирается по пингу. Со следующего подключения.',
        ),
      ],
    );
  }
}

class _Ads extends ConsumerStatefulWidget {
  const _Ads();

  @override
  ConsumerState<_Ads> createState() => _AdsState();
}

class _AdsState extends ConsumerState<_Ads> {
  final _domain = TextEditingController();

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  static final _valid = RegExp(
    r'^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$',
  );

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    final soft = Palette.soft(isDark(context));
    void add() {
      var d = _domain.text.trim().toLowerCase();
      d = d.replaceFirst(RegExp(r'^[a-z]+://'), '').split('/').first;
      if (!_valid.hasMatch(d)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Введите домен, например example.com'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      if (!r.adAllow.contains(d)) {
        engine.setRules(r.copyWith(adAllow: [...r.adAllow, d]));
      }
      _domain.clear();
    }

    final on = r.adLevel > 0;
    return _Sub(
      title: 'Реклама',
      children: [
        Text(
          'ДОП. ЗАЩИТА',
          style: mono(
            context,
            11,
            colour: soft,
            spacing: 2.4,
            weight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Paper(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          onTap: () => _open(context, const _ServersSettings()),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: Palette.ink(isDark(context))),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WARP, Psiphon, цепочка',
                      style: mono(context, 14, weight: FontWeight.w700),
                    ),
                    Text(
                      r.chain.isEmpty ? 'Выключена' : 'Цепочка включена',
                      style: desc(context, 11),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: soft),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'РЕКЛАМА',
          style: mono(
            context,
            11,
            colour: soft,
            spacing: 2.4,
            weight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Блокировка работает во всех приложениях: домены из списков не открываются. Если что-то сломалось, добавьте домен в исключения ниже.',
          style: desc(context, 11),
        ),
        const SizedBox(height: 10),
        _switch(
          context,
          'Блокировать рекламу',
          on,
          (v) => engine.setRules(r.copyWith(adLevel: v ? 2 : 0)),
          hint:
              'Рекламные домены. Строже уровень: больше списков и выше риск поломок.',
          icon: Icons.block_rounded,
        ),
        if (on) ...[
          const SizedBox(height: 4),
          SegmentedChoice(
            height: 40,
            compact: true,
            labels: const ['Мягко', 'Обычно', 'Строго'],
            icons: const [Icons.circle, Icons.circle, Icons.circle],
            selected: (r.adLevel - 1).clamp(0, 2),
            onChanged: (i) => engine.setRules(r.copyWith(adLevel: i + 1)),
          ),
          _hint(context, switch (r.adLevel) {
            1 => 'Один список: минимум блокировок, сайты ломаются реже.',
            3 =>
              'Три списка: максимум блокировок, выше риск поломок сайтов и приложений.',
            _ => 'Два списка: баланс между защитой и совместимостью.',
          }),
        ],
        const SizedBox(height: 8),
        _switch(
          context,
          'Защита от фишинга и вредоносных сайтов',
          r.phishing,
          (v) => engine.setRules(r.copyWith(phishing: v)),
          hint:
              'Блокирует мошеннические и заражённые сайты, обычные не затрагивает.',
          icon: Icons.gpp_good_rounded,
        ),
        _switch(
          context,
          'Майнеры',
          r.miners,
          (v) => engine.setRules(r.copyWith(miners: v)),
          hint: 'Блокирует сайты, которые майнят криптовалюту на устройстве.',
          icon: Icons.memory_rounded,
        ),
        const SizedBox(height: 18),
        Text(
          'ИСКЛЮЧЕНИЯ',
          style: mono(
            context,
            11,
            colour: soft,
            spacing: 2.4,
            weight: FontWeight.w800,
          ),
        ),
        _hint(
          context,
          'Домен и его поддомены не блокируются. Введите адрес и нажмите «+».',
        ),
        const SizedBox(height: 10),
        Paper(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _domain,
                  onSubmitted: (_) => add(),
                  style: mono(context, 13),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'example.com',
                    hintStyle: mono(context, 13, colour: soft),
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.add_rounded), onPressed: add),
            ],
          ),
        ),
        for (final d in r.adAllow)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(d, style: mono(context, 13, weight: FontWeight.w700)),
            trailing: IconButton(
              icon: Icon(Icons.close_rounded, color: soft),
              onPressed: () => engine.setRules(
                r.copyWith(
                  adAllow: [
                    for (final x in r.adAllow)
                      if (x != d) x,
                  ],
                ),
              ),
            ),
          ),
        _hint(context, 'Применяется при следующем подключении.'),
      ],
    );
  }
}

/// The core's journal: the last lines of what it wrote.
/// One line of the core's journal.
class _LogLine {
  _LogLine(this.level, this.time, this.source, this.text);

  final String level;
  final String time;
  final String source;
  final String text;

  static final _re = RegExp(
    r'^\+\d{4} \d{4}-\d{2}-\d{2} (\d{2}:\d{2}:\d{2}) (\w+) (?:\[[^\]]*\] )?(?:([\w/\[\]\-. ]+?): )?(.*)$',
  );

  static _LogLine? parse(String line) {
    final m = _re.firstMatch(line);
    if (m == null) return null;
    return _LogLine(
      m.group(2)!.toLowerCase(),
      m.group(1)!,
      m.group(3) ?? 'core',
      m.group(4) ?? '',
    );
  }
}

/// The core's journal: its lines with the level, the source and the time, a filter, the level of what is kept.
class _Logs extends ConsumerStatefulWidget {
  const _Logs();

  @override
  ConsumerState<_Logs> createState() => _LogsState();
}

class _LogsState extends ConsumerState<_Logs> {
  String _filter = '';
  String _show = 'all';
  bool _paused = false;
  List<_LogLine> _lines = const [];

  File? get _file {
    final dir = ref.read(engineProvider.notifier).dir;
    return dir == null ? null : File('$dir/box.log');
  }

  void _load() {
    final f = _file;
    if (f == null || !f.existsSync()) {
      _lines = const [];
      return;
    }
    final raw = f.readAsLinesSync();
    final tail = raw.skip(raw.length > 600 ? raw.length - 600 : 0);
    _lines = [for (final l in tail) ?_LogLine.parse(l)].reversed.toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    if (!_paused) _load();
    final shown = [
      for (final l in _lines)
        if ((_show == 'all' ||
                (_show == 'smart'
                    ? l.text.contains('smart[')
                    : l.level == _show)) &&
            (_filter.isEmpty ||
                l.text.toLowerCase().contains(_filter.toLowerCase()) ||
                l.source.toLowerCase().contains(_filter.toLowerCase())))
          l,
    ].take(200).toList();
    Color levelColour(String level) => switch (level) {
      'error' || 'fatal' || 'panic' => Palette.alert,
      'warn' || 'warning' => const Color(0xFFE8A33D),
      _ => soft,
    };
    Widget chip(String label, bool on, VoidCallback tap) => GestureDetector(
      onTap: tap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on
              ? Palette.ink(dark).withValues(alpha: .14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Palette.ink(dark).withValues(alpha: .35)),
        ),
        child: Text(label, style: mono(context, 11.5, weight: FontWeight.w700)),
      ),
    );
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            'Логи',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Palette.ink(dark).withValues(alpha: .3),
                    ),
                  ),
                  child: Text('Буфер 600', style: desc(context, 10.5)),
                ),
                IconButton(
                  icon: Icon(
                    _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  ),
                  onPressed: () => setState(() => _paused = !_paused),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () {
                    _file?.writeAsStringSync('');
                    setState(() => _lines = const []);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: [
                          for (final l in shown)
                            '${l.time} ${l.level} ${l.source}: ${l.text}',
                        ].join('\n'),
                      ),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Журнал скопирован'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      'Журнал пуст',
                      style: mono(context, 13, colour: soft),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: Palette.ink(dark).withValues(alpha: .1),
                    ),
                    itemBuilder: (context, i) {
                      final l = shown[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  l.level,
                                  style: mono(
                                    context,
                                    11,
                                    colour: levelColour(l.level),
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    l.source,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: mono(
                                      context,
                                      11.5,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(l.time, style: desc(context, 10.5)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(l.text, style: desc(context, 11.5)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Paper(
              radius: 14,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                onChanged: (v) => setState(() => _filter = v),
                style: mono(context, 13),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Фильтр',
                  hintStyle: mono(context, 13, colour: soft),
                  icon: Icon(Icons.search_rounded, color: soft),
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                for (final (v, label) in const [
                  ('all', 'Все'),
                  ('smart', 'Смены сервера'),
                  ('error', 'error'),
                  ('warn', 'warn'),
                  ('info', 'info'),
                ])
                  chip(label, _show == v, () => setState(() => _show = v)),
                const SizedBox(width: 8),
                for (final (v, label) in const [
                  ('warn', 'Ядро: warn'),
                  ('info', 'Ядро: info'),
                  ('debug', 'Ядро: debug'),
                ])
                  chip(
                    label,
                    r.logLevel == v,
                    () => engine.setRules(r.copyWith(logLevel: v)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }
}

class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    Widget entry(String version, String date, String text, bool current) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: current ? Palette.red : soft.withValues(alpha: .6),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    version,
                    style: mono(context, 14, weight: FontWeight.w800),
                  ),
                  const SizedBox(width: 10),
                  Text(date, style: desc(context, 12)),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Text(text, style: desc(context, 11.5)),
              ),
            ],
          ),
        );
    return _Sub(
      title: 'О программе',
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 120,
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Palette.plate(dark),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Palette.ink(dark).withValues(alpha: .2),
                ),
              ),
              child: const AppWordmark(height: 36),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AVET', style: mono(context, 22, weight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'Версия 2.0',
                  style: mono(context, 13, weight: FontWeight.w700),
                ),
                Text('Ядро: sing-box', style: desc(context, 11.5)),
                Text('by aramikkk', style: desc(context, 11.5)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 22),
        const UpdateBlock(),
        const SizedBox(height: 14),
        Text(
          'ЧТО НОВОГО',
          style: mono(
            context,
            11,
            colour: soft,
            spacing: 2.4,
            weight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        entry(
          '2.0',
          '17.11',
          'Первая стабильная версия, заменяет старое приложение. Всё из него перенесено, добавлено своё: умный автовыбор и спящие серверы, несколько подписок, Суперлайт, мульти серверы для Wi-Fi и LTE, IPv6, мультиплексирование, резервная копия настроек.',
          true,
        ),
        entry(
          '1.0 beta',
          '17.11',
          'Новое приложение на своём ядре sing-box: вкладки, режимы, подписки, маршрутизация, статистика, топология. Стили Glass, Mosaic и Studio, плитка быстрых настроек.',
          false,
        ),
        const SizedBox(height: 22),
        // the developer can be thanked on a card, as in the old app
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(showDonateSheet(context)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              color: Palette.plate(dark),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Palette.ink(dark).withValues(alpha: .28),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.favorite_rounded, color: Palette.red),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Поблагодарить разработчика',
                        style: mono(context, 14, weight: FontWeight.w700),
                      ),
                      Text(
                        'Перевод на карту, по желанию',
                        style: desc(context, 11.5),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: soft),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The language list as a sheet from the bottom, as the old app opens it from the Settings' row.
Future<void> showLanguageSheet(BuildContext context) => showSheet<void>(
  context: context,
  backgroundColor: Colors.transparent,
  isScrollControlled: true,
  builder: (context) {
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    const langs = [
      'English',
      'العربية',
      'Español',
      'فارسی',
      'Français',
      'Bahasa Indonesia',
      'Português (Brasil)',
      'Русский',
      'Türkçe',
      '中文 (中国)',
      '中文 (台灣)',
    ];
    return Container(
      height: MediaQuery.sizeOf(context).height * .62,
      decoration: BoxDecoration(
        color: Palette.plate(dark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: soft.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(
              children: [
                Icon(Icons.translate_rounded, color: Palette.ink(dark)),
                const SizedBox(width: 12),
                Text('Язык', style: mono(context, 16, weight: FontWeight.w800)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final l in langs)
                  ListTile(
                    title: Text(
                      l,
                      style: mono(context, 15, weight: FontWeight.w700),
                    ),
                    trailing: l == 'Русский'
                        ? Icon(Icons.check_rounded, color: Palette.red)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      if (l != 'Русский') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Пока доступен только русский'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  },
);

class _HomeServer extends ConsumerStatefulWidget {
  const _HomeServer();

  @override
  ConsumerState<_HomeServer> createState() => _HomeServerState();
}

class _HomeServerState extends ConsumerState<_HomeServer> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(engineProvider);
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    final summary = s.homeServers > 0 ? engine.homeServerSummary() : null;
    Widget block(List<Widget> kids) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Palette.plate(dark),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Palette.ink(dark).withValues(alpha: .28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: kids,
        ),
      ),
    );
    return _Sub(
      title: 'Свой сервер',
      children: [
        if (summary != null)
          block([
            Text(
              'WireGuard сохранён',
              style: mono(context, 14.5, weight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(summary, style: desc(context, 11.5)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.rules.homeServer
                        ? 'Режим «Сервер» включён'
                        : 'Режим «Сервер» выключен',
                    style: mono(context, 12.5, weight: FontWeight.w700),
                  ),
                ),
                Switch(
                  value: s.rules.homeServer,
                  onChanged: (_) => unawaited(engine.toggleHomeServer()),
                ),
              ],
            ),
            Text(
              'Включается и на главном экране: кнопкой с домиком в блоке «Мульти серверы».',
              style: desc(context, 11),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => unawaited(engine.removeWireguard()),
              child: const Text('Удалить сервер'),
            ),
          ]),
        block([
          Text(
            summary == null ? 'Добавить сервер' : 'Заменить сервер',
            style: mono(context, 14.5, weight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Вставьте конфиг WireGuard в формате sing-box (JSON с endpoints). Ключи хранятся только в закрытой папке приложения.',
            style: desc(context, 11.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            style: mono(context, 11),
            decoration: InputDecoration(
              hintText: '{"endpoints":[{"type":"wireguard", ...}]}',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _BigButton(
                  label: 'Вставить',
                  icon: Icons.content_paste_rounded,
                  onTap: () async {
                    final d = await Clipboard.getData(Clipboard.kTextPlain);
                    if (d?.text != null) setState(() => _text.text = d!.text!);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BigButton(
                  label: 'Сохранить',
                  icon: Icons.check_rounded,
                  onTap: () {
                    final err = engine.saveWireguard(_text.text);
                    setState(() => _error = err);
                    if (err == null) {
                      _text.clear();
                      FocusScope.of(context).unfocus();
                    }
                  },
                ),
              ),
            ],
          ),
        ]),
        _hint(
          context,
          'Режим «Сервер»: через ваш WireGuard идёт трафик к его адресам (например, домашняя сеть), остальное напрямую. Подписка не используется. Применяется сразу.',
        ),
      ],
    );
  }
}

class _AutoChoice extends ConsumerWidget {
  const _AutoChoice();

  static const _names = ['Оптимальная', 'Быстрая', 'Стабильная', 'Умная'];
  static const _tols = [25, 50, 100, 200];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    Widget network(bool lte) {
      final strategy = (lte ? r.strategyLte : r.strategy).clamp(0, 3);
      final tol = lte ? r.autoTolLte : r.autoTol;
      final raw = Engine.autoInterval(r, lte);
      final every = raw.endsWith('s')
          ? '${raw.substring(0, raw.length - 1)} с'
          : '${raw.substring(0, raw.length - 1)} мин';
      final change = Engine.autoTolerance(r, lte);
      final text = [
        'Баланс. Раз в $every замер серверов; переход на лучший, если он быстрее минимум на $change мс.',
        'Минимальная задержка. Замер раз в $every, переход при выигрыше от $change мс. Быстро реагирует на ухудшение, трафика чуть больше, сервер меняется чаще.',
        'Постоянство. Замер раз в $every, переход только при выигрыше от $change мс. Для долгих сессий и звонков.',
        lte
            ? 'Очки за скорость, стабильность и привычку. Смена, если другой впереди на 4 очка; сервер держится не менее 90 с.'
            : 'Очки за скорость, стабильность и привычку. Смена, если другой впереди на 6 очков; сервер держится не менее 5 минут.',
      ][strategy];
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Palette.plate(dark),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Palette.ink(dark).withValues(alpha: .28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    lte
                        ? Icons.signal_cellular_alt_rounded
                        : Icons.wifi_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    lte ? 'Мобильная сеть' : 'Wi-Fi',
                    style: mono(context, 14.5, weight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text('каждые $every', style: desc(context, 11.5)),
                ],
              ),
              const SizedBox(height: 4),
              Text(text, style: desc(context, 11.5)),
              const SizedBox(height: 12),
              SegmentedChoice(
                height: 40,
                compact: true,
                labels: _names,
                icons: const [
                  Icons.circle,
                  Icons.circle,
                  Icons.circle,
                  Icons.circle,
                ],
                selected: strategy,
                onChanged: (i) => engine.setRules(
                  lte ? r.copyWith(strategyLte: i) : r.copyWith(strategy: i),
                ),
              ),
              if (strategy == 3) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Самообучение',
                            style: mono(context, 13, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Страны, которыми вы пользуетесь чаще, получают плюс в очках. Скорость главнее.',
                            style: desc(context, 11.5),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: r.habit > 0,
                      onChanged: (v) =>
                          engine.setRules(r.copyWith(habit: v ? 2 : 0)),
                    ),
                  ],
                ),
                if (r.habit > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Сила привычки',
                    style: mono(context, 13, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  SegmentedChoice(
                    height: 40,
                    compact: true,
                    labels: const ['Слабая', 'Средняя', 'Сильная'],
                    icons: const [Icons.circle, Icons.circle, Icons.circle],
                    selected: (r.habit - 1).clamp(0, 2),
                    onChanged: (i) => engine.setRules(r.copyWith(habit: i + 1)),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: engine.resetHabits,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Сбросить обучение',
                        style: mono(
                          context,
                          12.5,
                          weight: FontWeight.w700,
                          colour: Palette.red,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Спящие серверы',
                            style: mono(context, 13, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Проверяются только лучшие серверы, остальные спят и не тратят батарею.',
                            style: desc(context, 11.5),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: lte ? r.sleepLte : r.sleepWifi,
                      onChanged: (v) => engine.setRules(
                        lte
                            ? r.copyWith(sleepLte: v)
                            : r.copyWith(sleepWifi: v),
                      ),
                    ),
                  ],
                ),
                if (lte ? r.sleepLte : r.sleepWifi) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Сколько серверов проверять',
                    style: mono(context, 13, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  SegmentedChoice(
                    height: 40,
                    compact: true,
                    labels: const ['5', '10', '15', '20'],
                    icons: const [
                      Icons.circle,
                      Icons.circle,
                      Icons.circle,
                      Icons.circle,
                    ],
                    selected: const [
                      5,
                      10,
                      15,
                      20,
                    ].indexOf(lte ? r.sleepCountLte : r.sleepCount).clamp(0, 3),
                    onChanged: (i) => engine.setRules(
                      lte
                          ? r.copyWith(sleepCountLte: const [5, 10, 15, 20][i])
                          : r.copyWith(sleepCount: const [5, 10, 15, 20][i]),
                    ),
                  ),
                ],
              ],
              if (strategy == 0) ...[
                const SizedBox(height: 14),
                Text(
                  'Менять сервер, если другой быстрее на',
                  style: mono(context, 13, weight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SegmentedChoice(
                  height: 40,
                  compact: true,
                  labels: [for (final v in _tols) '$v мс'],
                  icons: [for (final _ in _tols) Icons.circle],
                  selected: _tols.indexOf(tol).clamp(0, 3),
                  onChanged: (i) => engine.setRules(
                    lte
                        ? r.copyWith(autoTolLte: _tols[i])
                        : r.copyWith(autoTol: _tols[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return _Sub(title: 'Автовыбор', children: [network(false), network(true)]);
  }
}

class _ServersSettings extends ConsumerWidget {
  const _ServersSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    return _Sub(
      title: 'Серверы',
      children: [
        _switch(
          context,
          'Только Европа',
          r.europeOnly,
          (v) => engine.setRules(r.copyWith(europeOnly: v, cisOnly: false)),
          hint: 'Серверы вне Европы не используются.',
        ),
        _switch(
          context,
          'Весь мир, кроме России и Беларуси',
          r.cisOnly,
          (v) => engine.setRules(r.copyWith(cisOnly: v, europeOnly: false)),
          hint: 'Серверы России и Беларуси не используются.',
        ),
        _switch(
          context,
          'Серверы по типу сети',
          r.byNetwork,
          (v) => engine.setRules(r.copyWith(byNetwork: v)),
          hint:
              'На мобильном интернете — только «LTE Only», на Wi-Fi — остальные. Переключается при смене сети.',
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Palette.plate(isDark(context)),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Palette.ink(isDark(context)).withValues(alpha: .28),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.link_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Цепочка',
                    style: mono(context, 14.5, weight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Трафик идёт на выбранный сервер, затем на сервер выхода: провайдер не видит адрес выхода. Серверы для мобильной сети (БС) остаются доступными.',
                style: desc(context, 11),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  final all = ref.read(engineProvider);
                  unawaited(
                    _rowsSheet(context, 'Первый сервер цепочки', [
                      (
                        icon: Icons.link_off_rounded,
                        text: 'Без цепочки',
                        danger: false,
                        onTap: () => engine.setRules(r.copyWith(chain: '')),
                      ),
                      for (final x in all.servers)
                        (
                          icon: Icons.dns_outlined,
                          text: ServerName.of('${x['tag']}').label,
                          danger: false,
                          onTap: () =>
                              engine.setRules(r.copyWith(chain: '${x['tag']}')),
                        ),
                    ]),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Palette.ink(isDark(context)).withValues(alpha: .3),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (r.chain.isNotEmpty) ...[
                        flagMark(ServerName.of(r.chain).flag, width: 30),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          r.chain.isEmpty
                              ? 'Без цепочки'
                              : ServerName.of(r.chain).label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono(context, 14, weight: FontWeight.w700),
                        ),
                      ),
                      Icon(
                        Icons.unfold_more_rounded,
                        color: Palette.soft(isDark(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _hint(context, 'Применяется при следующем подключении.'),
        const SizedBox(height: 14),
        _MenuRow(
          icon: Icons.home_rounded,
          title: 'Свой сервер',
          subtitle: 'Личный WireGuard: дом, офис',
          onTap: () => _open(context, const _HomeServer()),
        ),
      ],
    );
  }
}

class _PingSettings extends ConsumerWidget {
  const _PingSettings();

  static const _targets = [
    ('', 'Google', 'www.gstatic.com/generate_204'),
    (
      'https://connectivitycheck.gstatic.com/generate_204',
      'Google · резерв',
      'connectivitycheck.gstatic.com/generate_204',
    ),
    (
      'https://cp.cloudflare.com/generate_204',
      'Cloudflare',
      'cp.cloudflare.com/generate_204',
    ),
    (
      'https://captive.apple.com/hotspot-detect.html',
      'Apple',
      'captive.apple.com/hotspot-detect.html',
    ),
    (
      'https://detectportal.firefox.com/success.txt',
      'Firefox',
      'detectportal.firefox.com/success.txt',
    ),
    (
      'https://www.msftconnecttest.com/connecttest.txt',
      'Microsoft',
      'www.msftconnecttest.com/connecttest.txt',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    final soft = Palette.soft(isDark(context));
    final dark = isDark(context);
    Widget block(List<Widget> rows) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Palette.plate(dark),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Palette.ink(dark).withValues(alpha: .28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
    Widget caption(String t, {String? hint}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t, style: mono(context, 14.5, weight: FontWeight.w700)),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint, style: desc(context, 11.5)),
        ],
        const SizedBox(height: 12),
      ],
    );
    Widget choice(
      List<int> values,
      String Function(int) label,
      int now,
      void Function(int) set,
    ) => SegmentedChoice(
      height: 40,
      compact: true,
      labels: [for (final v in values) label(v)],
      icons: [for (final _ in values) Icons.circle],
      selected: values.indexOf(now),
      onChanged: (i) => set(values[i]),
    );
    return _Sub(
      title: 'Пинг',
      children: [
        _switch(
          context,
          'Проверять при открытии',
          r.pingOnOpen,
          (v) => engine.setRules(r.copyWith(pingOnOpen: v)),
          hint: 'При открытии приложения серверы измеряются заново.',
        ),
        const SizedBox(height: 2),
        block([
          caption(
            'Метод запроса',
            hint:
                'HTTPS ближе к реальной загрузке сайтов, пинг выше. HTTP мерит только ответ сервера, пинг ниже.',
          ),
          SegmentedChoice(
            height: 40,
            labels: const ['HTTP', 'HTTPS'],
            icons: const [Icons.lock_open_rounded, Icons.lock_rounded],
            selected: r.pingHttp ? 0 : 1,
            onChanged: (i) => engine.setRules(r.copyWith(pingHttp: i == 0)),
          ),
        ]),
        block([
          caption('Адрес проверки'),
          for (final (i, t) in _targets.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: Palette.ink(dark).withValues(alpha: .14),
              ),
            InkWell(
              onTap: () => engine.setRules(r.copyWith(pingUrl: t.$1)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      r.pingUrl == t.$1
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: r.pingUrl == t.$1 ? Palette.ink(dark) : soft,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.$2,
                            style: mono(context, 14, weight: FontWeight.w700),
                          ),
                          Text(
                            '${r.pingHttp ? 'http' : 'https'}://${t.$3}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: desc(context, 10.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ]),
        block([
          caption(
            'Таймаут ответа сервера: Wi-Fi',
            hint:
                'Сколько ждать ответа сервера, прежде чем считать его недоступным.',
          ),
          choice(
            const [5, 10, 30, 60, 90, 120],
            (v) => '$v с',
            r.pingTimeout,
            (v) => engine.setRules(r.copyWith(pingTimeout: v)),
          ),
        ]),
        block([
          caption(
            'Таймаут ответа сервера: LTE',
            hint:
                'В мобильной сети (особенно в машине) ответ медленнее: если серверы «не отвечают», поставьте 60–90 секунд. Со следующего подключения.',
          ),
          choice(
            const [10, 30, 60, 90, 120],
            (v) => '$v с',
            r.pingTimeoutLte,
            (v) => engine.setRules(r.copyWith(pingTimeoutLte: v)),
          ),
        ]),
        block([
          caption('Проверять серверы каждые'),
          choice(
            const [1, 3, 5, 10],
            (v) => '$v мин',
            r.pingEvery,
            (v) => engine.setRules(r.copyWith(pingEvery: v)),
          ),
        ]),
        block([
          caption(
            'Wi-Fi: пинг считается плохим от',
            hint:
                'Значок пинга и шкалы краснеют, когда задержка достигает этого значения.',
          ),
          choice(
            const [150, 250, 400],
            (v) => '$v мс',
            r.slowMs,
            (v) => engine.setRules(r.copyWith(slowMs: v)),
          ),
        ]),
        block([
          caption(
            'LTE: пинг считается плохим от',
            hint:
                'В мобильной сети пинг выше, поэтому порог задаётся отдельно.',
          ),
          choice(
            const [300, 500, 800],
            (v) => '$v мс',
            r.slowMsLte,
            (v) => engine.setRules(r.copyWith(slowMsLte: v)),
          ),
        ]),
      ],
    );
  }
}

class _Themes extends ConsumerWidget {
  const _Themes();

  static const _modes = ['Системная', 'Светлая', 'Тёмная'];

  Widget _caption(BuildContext context, String text, {bool first = false}) =>
      Padding(
        padding: EdgeInsets.fromLTRB(6, first ? 4 : 22, 6, 10),
        child: Text(
          text,
          style: mono(
            context,
            11,
            colour: Palette.soft(isDark(context)),
            spacing: 2.4,
            weight: FontWeight.w800,
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final ink = Palette.ink(dark);
    final chosenAccent = r.accent;
    return _Sub(
      title: 'Темы',
      children: [
        // the style
        Paper(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  'Стиль',
                  style: mono(context, 13, weight: FontWeight.w800),
                ),
              ),
              // the three styles in a row: a sample and the name each; what the chosen one is, under them
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, e) in const [
                    (0, 'Glass'),
                    (1, 'Mosaic'),
                    (3, 'Studio'),
                  ].indexed) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: _stylePick(context, ref, r, e)),
                  ],
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: Text(switch (r.style) {
                  2 =>
                    'Studio: белые плитки на фоне из наклонных линий, кнопка-кольцо из пунктира.',
                  1 => 'Mosaic: сплошные плитки, яркий пинг, крупные цифры.',
                  _ =>
                    'Glass: прозрачные блоки на мягком цветном фоне, один акцент.',
                }, style: desc(context, 11.5)),
              ),
            ],
          ),
        ),
        _caption(context, 'ОБЪЁМ'),
        Paper(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedChoice(
                height: 40,
                compact: true,
                labels: const ['Плоско', 'Рельеф', 'Стекло', 'Liquid'],
                icons: const [
                  Icons.circle,
                  Icons.circle,
                  Icons.circle,
                  Icons.circle,
                ],
                selected: r.depth.clamp(0, 3),
                onChanged: (i) => ref
                    .read(engineProvider.notifier)
                    .setRules(r.copyWith(depth: i)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
                child: Text(switch (r.depth) {
                  1 =>
                    'Рельеф: глубокая тень, блик и подсветка акцентом по нижнему краю.',
                  2 =>
                    'Стекло: прозрачные блоки с яркой кромкой на мягком цветном фоне, как матовое стекло.',
                  3 =>
                    'Liquid: прозрачное стекло без заливки: ночью тёмное, днём светлое, цвет блоку даёт фон за ним.',
                  _ => 'Плоско: блоки без объёма.',
                }, style: desc(context, 11.5)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
                child: Text(
                  'Объём применяется на главной и во вкладках. Страницы настроек остаются плоскими.',
                  style: desc(context, 11),
                ),
              ),
            ],
          ),
        ),
        _caption(context, 'ОФОРМЛЕНИЕ'),
        Paper(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          onTap: () async {
            final v = await showSheet<int>(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (ctx) => Container(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 26),
                decoration: BoxDecoration(
                  color: Palette.plate(dark),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: soft.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final (i, m) in _modes.indexed)
                      ListTile(
                        title: Text(
                          m,
                          style: mono(context, 15, weight: FontWeight.w700),
                        ),
                        trailing: r.theme == i
                            ? Icon(Icons.check_rounded, color: Palette.red)
                            : null,
                        onTap: () => Navigator.pop(ctx, i),
                      ),
                  ],
                ),
              ),
            );
            if (v != null) engine.setRules(r.copyWith(theme: v));
          },
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: ink),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Тема оформления',
                      style: mono(context, 14.5, weight: FontWeight.w700),
                    ),
                    Text(
                      _modes[r.theme.clamp(0, 2)],
                      style: desc(context, 11.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: soft),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Paper(
          radius: 18,
          padding: EdgeInsets.zero,
          child: _switch(
            context,
            'Иконка в цвет акцента',
            r.tintIcon,
            (v) => engine.setRules(r.copyWith(tintIcon: v)),
            hint:
                'Иконка на рабочем столе повторяет цвет акцента. Система обновляет её не сразу, на это время иконка может пропасть',
            icon: Icons.palette_outlined,
          ),
        ),
        _caption(context, 'МАСШТАБ И ШРИФТ'),
        Paper(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.text_fields_rounded, color: soft),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Размер шрифта',
                      style: mono(context, 14, weight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${(r.fontScale * 100).round()}%',
                      style: mono(context, 12.5, weight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton.outlined(
                    onPressed: () => engine.setRules(
                      r.copyWith(
                        fontScale: (r.fontScale - .05).clamp(.8, 1.25),
                      ),
                    ),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  Expanded(
                    child: Slider(
                      min: .8,
                      max: 1.25,
                      divisions: 9,
                      activeColor: Palette.red,
                      value: r.fontScale.clamp(.8, 1.25),
                      onChanged: (v) =>
                          engine.setRules(r.copyWith(fontScale: v)),
                    ),
                  ),
                  IconButton.outlined(
                    onPressed: () => engine.setRules(
                      r.copyWith(
                        fontScale: (r.fontScale + .05).clamp(.8, 1.25),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              Row(
                children: [
                  for (final p in const [.8, .9, 1.0, 1.1, 1.25])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => engine.setRules(r.copyWith(fontScale: p)),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: (r.fontScale - p).abs() < .01
                                ? ink
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: ink.withValues(alpha: .35),
                            ),
                          ),
                          child: Text(
                            '${(p * 100).round()}%',
                            style: mono(
                              context,
                              11.5,
                              weight: FontWeight.w700,
                              colour: (r.fontScale - p).abs() < .01
                                  ? Palette.paper(dark)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ink.withValues(alpha: .2)),
                ),
                child: Row(
                  children: [
                    Text(
                      'Aa',
                      style: mono(context, 18, weight: FontWeight.w800),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'AVET · 54 мс · Финляндия',
                      style: mono(context, 12.5),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => engine.setRules(r.copyWith(fontScale: 1.0)),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Сбросить'),
                ),
              ),
            ],
          ),
        ),
        _caption(context, 'ЦВЕТ АКЦЕНТА'),
        Paper(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
          child: GridView.count(
            crossAxisCount: 6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 2,
            childAspectRatio: .66,
            children: [
              for (final (i, name) in Palette.accentNames.indexed)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => engine.setRules(r.copyWith(accent: i)),
                  child: Column(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                (chosenAccent == i ||
                                    (chosenAccent < 0 &&
                                        i == (r.style >= 1 ? 18 : 0)))
                                ? ink
                                : Colors.transparent,
                            width: 2.2,
                          ),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Palette.accentOn(i, dark),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(context, 11, colour: soft, spacing: 0),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // the figures, the pattern of dots and the tone of the sheet belong to the Dot Matrix look only: the others have no use for them
        if (r.style == 0) ...[
          _caption(context, 'ЦИФРЫ'),
          Paper(
            radius: 18,
            padding: const EdgeInsets.all(10),
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF151515) : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  for (final (i, d) in DigitStyle.values.indexed)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => engine.setRules(r.copyWith(digits: i)),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: r.digits == i
                                ? (dark
                                      ? const Color(0xFF2A2A2A)
                                      : const Color(0xFFEDEBE6))
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              _DigitSample(d),
                              const SizedBox(height: 8),
                              Text(
                                d.label,
                                style: mono(
                                  context,
                                  11,
                                  spacing: 0,
                                  weight: r.digits == i
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  colour: r.digits == i ? ink : soft,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _caption(context, 'ФОН'),
          Paper(
            radius: 18,
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final i in Backdrops.order)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => ref
                            .read(engineProvider.notifier)
                            .setRules(r.copyWith(bg: i)),
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: r.bg == i
                                ? Palette.red
                                : Palette.ink(
                                    isDark(context),
                                  ).withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(19),
                          ),
                          child: Text(
                            Backdrops.names[i],
                            style: mono(
                              context,
                              12.5,
                              weight: FontWeight.w700,
                              colour: r.bg == i
                                  ? Palette.onAccent
                                  : Palette.ink(isDark(context)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
                  child: Text(
                    Backdrops.descriptions[r.bg.clamp(
                      0,
                      Backdrops.names.length - 1,
                    )],
                    style: desc(context, 11.5),
                  ),
                ),
                if (r.bg == 2) ...[
                  Divider(height: 18, color: ink.withValues(alpha: .14)),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Точечная сетка',
                          style: mono(context, 14, weight: FontWeight.w700),
                        ),
                      ),
                      Switch(
                        value: r.dots,
                        onChanged: (v) => engine.setRules(r.copyWith(dots: v)),
                      ),
                    ],
                  ),
                ],
                Divider(height: 18, color: ink.withValues(alpha: .14)),
                Text(
                  'Оттенок',
                  style: mono(context, 14, weight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SegmentedChoice(
                  height: 38,
                  compact: true,
                  labels: const ['Нейтральный', 'Тёплый', 'Холодный'],
                  icons: const [
                    Icons.circle_outlined,
                    Icons.circle_outlined,
                    Icons.circle_outlined,
                  ],
                  selected: r.paperTone,
                  onChanged: (i) => engine.setRules(r.copyWith(paperTone: i)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _stylePick(
    BuildContext context,
    WidgetRef ref,
    RuleSettings r,
    (int, String) e,
  ) {
    final dark = isDark(context);
    final engine = ref.read(engineProvider.notifier);
    final styleOf = e.$1 == 3 ? 2 : (e.$1 == 1 ? 1 : 0);
    final on = r.style == styleOf;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // every look keeps its own volume, accent and sheet (and begins with its preset)
      onTap: () => engine.setRules(r.switchedTo(styleOf)),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Palette.ink(dark).withValues(alpha: .04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: on ? Palette.red : Palette.ink(dark).withValues(alpha: .2),
            width: on ? 2.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  painter: _StylePreview(e.$1),
                  size: Size.infinite,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                e.$2,
                maxLines: 1,
                style: mono(context, 12, weight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}

/// One sample of a figures style on the black tile: 128.
class _DigitSample extends StatelessWidget {
  const _DigitSample(this.style);

  final DigitStyle style;

  @override
  Widget build(BuildContext context) {
    return Figure(
      '128',
      size: 24,
      colour: Palette.ink(isDark(context)),
      style: style,
    );
  }
}

class _Countries extends ConsumerStatefulWidget {
  const _Countries();

  @override
  ConsumerState<_Countries> createState() => _CountriesState();
}

class _CountriesState extends ConsumerState<_Countries> {
  bool _lte = false;
  final _open = <String>{};

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(engineProvider);
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final off = _lte ? s.rules.hiddenLte : s.rules.hidden;
    void toggle(String c, bool on) {
      final now = on
          ? [
              for (final h in off)
                if (h != c) h,
            ]
          : [...off, c];
      engine.setRules(
        _lte ? s.rules.copyWith(hiddenLte: now) : s.rules.copyWith(hidden: now),
      );
    }

    // the best delay of a country's servers, from what the core measured
    int? delayOf(Iterable<String> tags) {
      int? best;
      for (final t in tags) {
        final d = s.states
            .where((e) => e.tag == t)
            .map((e) => e.delay)
            .firstOrNull;
        if (d != null && (best == null || d < best)) best = d;
      }
      return best;
    }

    final cards = <Widget>[];
    for (final (i, sub) in s.subs.indexed) {
      if (!sub.enabled) continue;
      final tags = [
        for (final x in s.servers)
          // mobile data lists the whitelist servers and, after them, the ordinary countries as the spare ones
          if (s.providers['${x['tag']}'] == sub.name &&
              (_lte || !Networks.isMobileOnly('${x['tag']}')))
            '${x['tag']}',
      ];
      final byCountry = <String, List<String>>{};
      final names = <String, ServerName>{};
      final mobileCodes = <String>{};
      for (final t in tags) {
        final code = Engine.countryOf(t);
        if (code == null) continue;
        if (Networks.isMobileOnly(t)) mobileCodes.add(code);
        (byCountry[code] ??= []).add(t);
        names.putIfAbsent(code, () => ServerName.of(t));
      }
      final codes = byCountry.keys.toList()
        ..sort((a, b) {
          final m =
              (mobileCodes.contains(b) ? 1 : 0) -
              (mobileCodes.contains(a) ? 1 : 0);
          if (m != 0) return m;
          // by the ping of the country's best server (those not measured yet last, by name)
          final da = delayOf(byCountry[a]!);
          final db = delayOf(byCountry[b]!);
          if (da != null && db != null && da != db) return da.compareTo(db);
          if (da != null && db == null) return -1;
          if (da == null && db != null) return 1;
          return names[a]!.title.compareTo(names[b]!.title);
        });
      final active = codes.where((c) => !off.contains(c)).length;
      Widget rowOf(String c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: Palette.ink(dark).withValues(alpha: .05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Opacity(
            opacity: off.contains(c) ? .5 : 1,
            child: Row(
              children: [
                flagMark(names[c]!.flag, width: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        names[c]!.title.replaceAll(RegExp(r'\s*\d+$'), ''),
                        style: mono(context, 14, weight: FontWeight.w800),
                      ),
                      if (_lte && mobileCodes.contains(c))
                        Text('БС', style: desc(context, 10.5)),
                    ],
                  ),
                ),
                if (delayOf(byCountry[c]!) case final d?)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: (d < 250 ? const Color(0xFF3FB56A) : Palette.red)
                          .withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$d мс',
                      style: mono(
                        context,
                        11,
                        colour: d < 250 ? const Color(0xFF3FB56A) : Palette.red,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                Switch(value: !off.contains(c), onChanged: (v) => toggle(c, v)),
              ],
            ),
          ),
        ),
      );
      final mainCodes = [
        for (final c in codes)
          if (!_lte || mobileCodes.contains(c)) c,
      ];
      final spare = [
        for (final c in codes)
          if (_lte && !mobileCodes.contains(c)) c,
      ];
      final open = _open.contains(sub.name);
      cards.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Paper(
            radius: 18,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${sub.name}${i == 0 ? '  ·  активный' : ''}',
                  style: mono(context, 14, weight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_lte ? 'LTE' : 'Wi-Fi'}: $active/${codes.length}',
                  style: desc(context, 11),
                ),
                const SizedBox(height: 10),
                for (final c in mainCodes) rowOf(c),
                if (spare.isNotEmpty) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(
                      () => open ? _open.remove(sub.name) : _open.add(sub.name),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Запасные страны · ${spare.where((c) => !off.contains(c)).length}/${spare.length}',
                              style: mono(
                                context,
                                12,
                                colour: soft,
                                weight: FontWeight.w800,
                              ),
                            ),
                          ),
                          AnimatedRotation(
                            turns: open ? .5 : 0,
                            duration: const Duration(milliseconds: 240),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: soft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: reduceMotionNow
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: open
                        ? Column(children: [for (final c in spare) rowOf(c)])
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return _Sub(
      title: 'Управление подписками',
      children: [
        _hint(
          context,
          'Страны с серверами подписки и пинг до них. Отмеченные используются, снятые нет. Отдельно для Wi-Fi и LTE.',
        ),
        const SizedBox(height: 12),
        SegmentedChoice(
          height: 40,
          labels: const ['Wi-Fi', 'LTE'],
          icons: const [Icons.wifi_rounded, Icons.signal_cellular_alt_rounded],
          selected: _lte ? 1 : 0,
          onChanged: (i) => setState(() => _lte = i == 1),
        ),
        const SizedBox(height: 14),
        if (cards.isEmpty)
          _hint(context, 'Сначала добавьте подписку.')
        else
          ...cards,
        _hint(context, 'Применяется при следующем подключении.'),
      ],
    );
  }
}

/// A square preview of a look: only the top part of the screen (the header, the modes and the first blocks), no panel.
class _StylePreview extends CustomPainter {
  _StylePreview(this.kind);

  final int kind;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final mosaic = kind == 1;
    final studio = kind == 3;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = mosaic ? const Color(0xFF0E0E10) : const Color(0xFF151515),
    );
    if (studio) {
      final fine = Paint()
        ..color = const Color(0x14FFFFFF)
        ..strokeWidth = 1;
      for (var x = -h; x < w + h; x += 9) {
        canvas.drawLine(Offset(x, 0), Offset(x + h * .62, h), fine);
      }
      final lime = Paint()
        ..color = const Color(0xFF2F7BFF)
        ..strokeWidth = 1.6;
      for (final x in [w * .2, w * .55, w * .92]) {
        canvas.drawLine(Offset(x, 0), Offset(x + h * .62, h), lime);
      }
    } else if (!mosaic) {
      final dot = Paint()..color = const Color(0x1AFFFFFF);
      for (var x = 6.0; x < w; x += 9) {
        for (var y = 6.0; y < h; y += 9) {
          canvas.drawCircle(Offset(x, y), .8, dot);
        }
      }
    }
    RRect rr(double l, double t, double r, double b, double rad) =>
        RRect.fromRectAndRadius(
          Rect.fromLTRB(l, t, r, b),
          Radius.circular(rad),
        );
    final line = Paint()
      ..color = const Color(0x55FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final red = (mosaic || studio)
        ? const Color(0xFF2F7BFF)
        : const Color(0xFFE8231C);
    canvas.drawRRect(
      rr(w * .36, h * .07, w * .64, h * .11, 2),
      Paint()..color = red,
    );
    canvas.drawCircle(Offset(w * .9, h * .09), 3, line);
    for (var i = 0; i < 3; i++) {
      final l = w * (.08 + i * .30);
      final box = rr(l, h * .16, l + w * .26, h * .27, mosaic ? 7 : 5);
      if (mosaic) {
        canvas.drawRRect(box, Paint()..color = const Color(0xFF2A2A2F));
      } else {
        canvas.drawRRect(box, line);
      }
    }
    if (studio) {
      final glass = Paint()..color = const Color(0xCC26262B);
      canvas.drawRRect(rr(w * .08, h * .32, w * .92, h * .56, 9), glass);
      for (var i = 0; i < 3; i++) {
        final l = w * (.11 + i * .27);
        canvas.drawRRect(
          rr(l, h * .345, l + w * .23, h * .535, 6),
          Paint()..color = const Color(0xFF34343A),
        );
      }
      canvas.drawRRect(rr(w * .08, h * .62, w * .92, h * .78, 9), glass);
      canvas.drawRRect(rr(w * .08, h * .82, w * .92, h * .94, 9), glass);
    } else if (mosaic) {
      canvas.drawRRect(
        rr(w * .08, h * .32, w * .92, h * .62, 12),
        Paint()..color = red,
      );
      canvas.drawRRect(
        rr(w * .08, h * .66, w * .48, h * .88, 9),
        Paint()..color = const Color(0xFF2A2A2F),
      );
      canvas.drawRRect(
        rr(w * .52, h * .66, w * .92, h * .88, 9),
        Paint()..color = const Color(0xFFFF6B3D),
      );
    } else {
      final plate = rr(w * .08, h * .32, w * .92, h * .72, 4);
      canvas.drawRRect(plate, Paint()..color = const Color(0xFF1B1B1B));
      canvas.drawRRect(plate, line);
      final bar = Paint()..color = const Color(0xCCFFFFFF);
      for (var i = 0; i < 14; i++) {
        final bh = h * (.03 + (i * 7 % 5) * .012);
        canvas.drawRect(
          Rect.fromLTWH(w * .14 + i * w * .052, h * .64 - bh, w * .03, bh),
          i > 10 ? (Paint()..color = red) : bar,
        );
      }
      canvas.drawLine(Offset(w * .12, h * .65), Offset(w * .88, h * .65), line);
      canvas.drawRRect(rr(w * .08, h * .77, w * .92, h * .9, 4), line);
    }
  }

  @override
  bool shouldRepaint(_StylePreview old) => old.kind != kind;
}

/// A block closed by default: the title with how much is inside and an arrow; a tap opens it.
class _Collapsible extends StatefulWidget {
  const _Collapsible({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final soft = Palette.soft(isDark(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Paper(
          radius: 16,
          padding: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: mono(context, 14, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(widget.subtitle, style: desc(context, 11.5)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? .5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: soft),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(children: widget.children),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Export and import of the settings as text (the clipboard): to keep them, or to move them to another phone.
class _Backup extends ConsumerWidget {
  const _Backup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.read(engineProvider.notifier);
    Future<void> importIt() async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      Map<dynamic, dynamic>? parsed;
      try {
        final d = jsonDecode((data?.text ?? '').trim());
        if (d is Map) parsed = d;
      } on FormatException {
        // not a settings text
      }
      if (parsed == null || !parsed.containsKey('strategy')) {
        toast('В буфере нет настроек AVET');
        return;
      }
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        animationStyle: sheetMotion,
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Заменить настройки?'),
          content: const Text(
            'Текущие настройки будут заменены теми из буфера. Подписки и WireGuard не меняются.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Заменить'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      engine.setRules(RuleSettings.fromJson(parsed));
      toast('Настройки возвращены');
    }

    return _Sub(
      title: 'Резервная копия',
      children: [
        Text(
          'Настройки приложения текстом: можно сохранить в заметках или перенести на другой телефон. Ссылок подписок, паролей и ключей в нём нет.',
          style: desc(context, 11.5),
        ),
        const SizedBox(height: 14),
        _BigButton(
          label: 'Скопировать настройки',
          icon: Icons.copy_rounded,
          onTap: () async {
            final json = Map<String, Object?>.of(
              ref.read(engineProvider).rules.toJson(),
            )..remove('sharePass');
            await Clipboard.setData(ClipboardData(text: jsonEncode(json)));
            toast('Настройки скопированы');
          },
        ),
        const SizedBox(height: 10),
        _BigButton(
          label: 'Вставить из буфера',
          icon: Icons.content_paste_rounded,
          onTap: () => unawaited(importIt()),
        ),
      ],
    );
  }
}
