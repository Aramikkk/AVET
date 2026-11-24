part of 'settings_page.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _dateTime(int ms) {
  if (ms <= 0) return 'ещё не обновлялась';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';
}

String _date(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

Future<bool> _confirm(BuildContext context, String title, String text) async {
  final ok = await showDialog<bool>(
    animationStyle: sheetMotion,
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// A sheet from the bottom with a head and rows (a title, an icon, what it does).
Future<void> _rowsSheet(
  BuildContext context,
  String title,
  List<({IconData icon, String text, VoidCallback onTap, bool danger})> rows,
) => showSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black54,
  builder: (ctx) {
    final dark = isDark(ctx);
    final soft = Palette.soft(dark);
    return Container(
      // a long list (all the countries) scrolls inside the sheet instead of running off the screen
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(ctx).height * .86,
      ),
      decoration: BoxDecoration(
        color: Palette.plate(dark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(ctx, 16, weight: FontWeight.w800),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final r in rows)
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            Navigator.pop(ctx);
                            r.onTap();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  r.icon,
                                  color: r.danger
                                      ? Palette.alert
                                      : Palette.ink(dark),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    r.text,
                                    style: mono(
                                      ctx,
                                      14.5,
                                      weight: FontWeight.w700,
                                      colour: r.danger ? Palette.alert : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
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

/// The subscription's share and copy actions.
void _shareSheet(BuildContext context, EngineNotifierRef engine, SubInfo x) =>
    unawaited(
      _rowsSheet(context, 'Поделиться', [
        (
          icon: Icons.link_rounded,
          text: 'Скопировать ссылку',
          danger: false,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: x.url));
            toast('Ссылка скопирована');
          },
        ),
        (
          icon: Icons.data_object_rounded,
          text: 'Скопировать конфиг (JSON)',
          danger: false,
          onTap: () async {
            await Clipboard.setData(
              ClipboardData(text: engine.subscriptionJson(x.url)),
            );
            toast('Конфиг скопирован');
          },
        ),
      ]),
    );

typedef EngineNotifierRef = Engine;

/// The subscriptions: a card for each, its actions in a menu, its details on a tap, dragged to another place.
class _Subscription extends ConsumerWidget {
  const _Subscription();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(engineProvider);
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    final soft = Palette.soft(dark);

    void sortSheet() {
      Future<void> pick(String by) async {
        final asc = by != 'usage' && by != 'update';
        engine.sortSubscriptions(by, asc);
      }

      unawaited(
        _rowsSheet(context, 'Сортировка', [
          (
            icon: Icons.sort_by_alpha_rounded,
            text: 'По названию',
            danger: false,
            onTap: () => pick('name'),
          ),
          (
            icon: Icons.data_usage_rounded,
            text: 'По трафику: больше сверху',
            danger: false,
            onTap: () => pick('usage'),
          ),
          (
            icon: Icons.event_rounded,
            text: 'По окончанию: ближе сверху',
            danger: false,
            onTap: () => pick('expire'),
          ),
          (
            icon: Icons.update_rounded,
            text: 'По обновлению: свежие сверху',
            danger: false,
            onTap: () => pick('update'),
          ),
        ]),
      );
    }

    void menu(SubInfo x, int index) => unawaited(
      _rowsSheet(context, x.name.isEmpty ? 'Подписка' : x.name, [
        if (index > 0)
          (
            icon: Icons.push_pin_outlined,
            text: 'Сделать главной',
            danger: false,
            onTap: () => engine.pinSubscription(x.url),
          ),
        (
          icon: Icons.sync_rounded,
          text: 'Обновить',
          danger: false,
          onTap: () => unawaited(engine.updateSubscription(x.url)),
        ),
        (
          icon: Icons.ios_share_rounded,
          text: 'Поделиться',
          danger: false,
          onTap: () => _shareSheet(context, engine, x),
        ),
        (
          icon: Icons.edit_rounded,
          text: 'Изменить',
          danger: false,
          onTap: () => _open(context, _SubDetails(url: x.url)),
        ),
        (
          icon: Icons.delete_outline_rounded,
          text: 'Удалить',
          danger: true,
          onTap: () async {
            if (await _confirm(
              context,
              'Удалить подписку?',
              x.name.isEmpty ? x.url : x.name,
            )) {
              engine.removeSubscription(x.url);
            }
          },
        ),
      ]),
    );

    Widget leading(SubInfo x) {
      final busy = s.updating.contains(x.url);
      final flash = s.subFlash[x.url];
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: busy ? null : () => unawaited(engine.updateSubscription(x.url)),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: busy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Palette.ink(dark),
                    ),
                  )
                : flash != null
                ? Icon(
                    flash
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded,
                    color: flash ? const Color(0xFF3FB56A) : Palette.red,
                  )
                : Icon(Icons.sync_rounded, color: soft),
          ),
        ),
      );
    }

    Widget card(SubInfo x, int index) => Padding(
      key: ValueKey(x.url),
      padding: const EdgeInsets.only(bottom: 10),
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: Opacity(
          opacity: x.enabled ? 1 : .55,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _open(context, _SubDetails(url: x.url)),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              decoration: BoxDecoration(
                color: Palette.plate(dark),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Palette.ink(
                    dark,
                  ).withValues(alpha: index == 0 ? .5 : .28),
                  width: index == 0 ? 1.6 : 1,
                ),
              ),
              child: Row(
                children: [
                  leading(x),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                x.name.isEmpty ? 'Подписка' : x.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: mono(
                                  context,
                                  14.5,
                                  weight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (index == 0) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.push_pin_rounded,
                                size: 15,
                                color: soft,
                              ),
                            ],
                          ],
                        ),
                        if (x.total > 0) ...[
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: (x.used / x.total).clamp(0.0, 1.0),
                              minHeight: 4,
                              color: Palette.red,
                              backgroundColor: Palette.ink(
                                dark,
                              ).withValues(alpha: .12),
                            ),
                          ),
                        ],
                        if (SubscriptionFetch.messages(x.body).isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Провайдер: ${SubscriptionFetch.messages(x.body).join(' · ')}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: desc(
                              context,
                              10.5,
                            ).copyWith(color: Palette.alert),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                x.total > 0
                                    ? '${bytesText(x.used)} / ${bytesText(x.total)}'
                                    : '${s.providers.values.where((t) => t == x.name).length} ${serversWord(s.providers.values.where((t) => t == x.name).length).toLowerCase()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: desc(context, 10.5),
                              ),
                            ),
                            if (x.expire != null)
                              Text(
                                'Осталось ${x.expire!.difference(DateTime.now()).inDays.clamp(0, 9999)} дн.',
                                style: desc(context, 10.5),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: x.enabled,
                    onChanged: (v) => engine.enableSubscription(x.url, v),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => menu(x, index),
                    child: SizedBox(
                      width: 36,
                      height: 44,
                      child: Icon(Icons.more_vert_rounded, color: soft),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return _Sub(
      title: 'Подписки',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'Что можно добавить',
            onPressed: () => unawaited(showSupportedFormats(context)),
          ),
          IconButton(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Сортировка',
            onPressed: s.subs.length > 1 ? sortSheet : null,
          ),
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Обновить все',
            onPressed: () => unawaited(engine.refreshAll()),
          ),
        ],
      ),
      children: [
        // how often all the subscriptions are loaded again (a subscription may have its own period)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: Palette.plate(dark),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Palette.ink(dark).withValues(alpha: .28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.update_rounded, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Обновлять автоматически',
                      style: mono(context, 14.5, weight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SegmentedChoice(
                  height: 40,
                  compact: true,
                  labels: const ['Нет', '6 ч', '12 ч', 'Сутки'],
                  icons: const [
                    Icons.circle,
                    Icons.circle,
                    Icons.circle,
                    Icons.circle,
                  ],
                  selected: const [
                    0,
                    6,
                    12,
                    24,
                  ].indexOf(s.rules.subHours).clamp(0, 3),
                  onChanged: (i) => engine.setRules(
                    s.rules.copyWith(subHours: const [0, 6, 12, 24][i]),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Серверы загружаются заново, пока приложение работает. Для отдельной подписки период задаётся на её странице.',
                  style: desc(context, 10.5),
                ),
              ],
            ),
          ),
        ),
        // the cards are dragged to other places: a card held a moment follows the finger
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          padding: EdgeInsets.zero,
          itemCount: s.subs.length,
          onReorder: (from, to) {
            if (to > from) to -= 1;
            engine.moveSubscription(from, to);
          },
          proxyDecorator: (child, index, animation) => Material(
            color: Colors.transparent,
            elevation: 6,
            borderRadius: BorderRadius.circular(22),
            child: child,
          ),
          itemBuilder: (context, i) => card(s.subs[i], i),
        ),
        // in the page, not over it: it used to float above the content and cover what was under it
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: _BigButton(
            label: 'Добавить подписку',
            icon: Icons.add_rounded,
            onTap: () => unawaited(showAddSubscription(context, ref)),
          ),
        ),
        if (s.subs.length > 1)
          _hint(
            context,
            'Порядок меняется перетаскиванием: зажмите карточку и ведите. Первая в списке главная, её название на главном экране.',
          ),
        if (s.note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(s.note!, style: desc(context, 12)),
          ),
        if (s.servers.isNotEmpty)
          _hint(context, 'Всего серверов: ${s.servers.length}'),
        if (s.subs.where((x) => x.enabled).length > 1) ...[
          const SizedBox(height: 18),
          const _Priority(),
        ],
        const SizedBox(height: 18),
        const _DeviceId(),
      ],
    );
  }
}

/// One subscription: its name, link, state, how often it is loaded, the provider's links and the actions.
class _SubDetails extends ConsumerStatefulWidget {
  const _SubDetails({required this.url});

  final String url;

  @override
  ConsumerState<_SubDetails> createState() => _SubDetailsState();
}

class _SubDetailsState extends ConsumerState<_SubDetails> {
  TextEditingController? _name;

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  static const _periods = [1, 3, 6, 12, 24, 48];

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(engineProvider);
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final i = s.subs.indexWhere((x) => x.url == widget.url);
    if (i < 0) {
      return _Sub(
        title: 'Подписка',
        children: [_hint(context, 'Подписка удалена.')],
      );
    }
    final x = s.subs[i];
    _name ??= TextEditingController(text: x.name);
    final servers = s.providers.values.where((t) => t == x.name).length;
    final busy = s.updating.contains(x.url);

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

    Widget title(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t, style: mono(context, 14.5, weight: FontWeight.w800)),
    );

    Widget chip(String label, bool on, VoidCallback tap) => GestureDetector(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on
              ? Palette.ink(dark).withValues(alpha: .14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: on
                ? Palette.ink(dark)
                : Palette.ink(dark).withValues(alpha: .32),
            width: on ? 1.6 : 1,
          ),
        ),
        child: Text(label, style: mono(context, 12.5, weight: FontWeight.w700)),
      ),
    );

    Widget link(String label, String url) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: desc(context, 10.5)),
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(context, 12.5, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy_rounded, color: soft),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              toast('Ссылка скопирована');
            },
          ),
        ],
      ),
    );

    return _Sub(
      title: 'Подписка',
      children: [
        plate([
          title('Название'),
          TextField(
            controller: _name,
            style: mono(context, 14),
            decoration: const InputDecoration(hintText: 'Название подписки'),
            onSubmitted: (v) => engine.renameSubscription(x.url, v),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                engine.renameSubscription(x.url, _name!.text);
                FocusScope.of(context).unfocus();
                toast('Название сохранено');
              },
              child: const Text('Сохранить'),
            ),
          ),
        ]),
        plate([
          title('Ссылка'),
          SelectableText(x.url, style: mono(context, 12, colour: soft)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Скопировать'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: x.url));
                toast('Ссылка скопирована');
              },
            ),
          ),
        ]),
        plate([
          title('Состояние'),
          if (x.total > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (x.used / x.total).clamp(0.0, 1.0),
                minHeight: 6,
                color: Palette.red,
                backgroundColor: Palette.ink(dark).withValues(alpha: .12),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Трафик: ${bytesText(x.used)} из ${bytesText(x.total)}',
              style: desc(context, 11),
            ),
          ],
          if (x.expire != null)
            Text(
              'Действует до ${_date(x.expire!)} · осталось ${x.expire!.difference(DateTime.now()).inDays.clamp(0, 9999)} дн.',
              style: desc(context, 11),
            ),
          Text('Серверов: $servers', style: desc(context, 11)),
          if (SubscriptionFetch.messages(x.body).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Провайдер сообщает: ${SubscriptionFetch.messages(x.body).join(' · ')}',
              style: desc(context, 11).copyWith(color: Palette.alert),
            ),
            const SizedBox(height: 4),
            Text(
              'Это ответ провайдера, а не ошибка приложения. Лимит устройств освобождается в личном кабинете или у поддержки (ссылки ниже).',
              style: desc(context, 11),
            ),
          ],
          Text('Обновлялась: ${_dateTime(x.at)}', style: desc(context, 11)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Использовать подписку',
                  style: mono(context, 13, weight: FontWeight.w700),
                ),
              ),
              Switch(
                value: x.enabled,
                onChanged: (v) => engine.enableSubscription(x.url, v),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: const Text('Обновить сейчас'),
              onPressed: busy
                  ? null
                  : () => unawaited(engine.updateSubscription(x.url)),
            ),
          ),
        ]),
        plate([
          title('Как часто обновлять'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip(
                'Как в общих',
                x.hours == 0,
                () => engine.setSubscriptionHours(x.url, 0),
              ),
              for (final h in _periods)
                chip(
                  '$h ч',
                  x.hours == h,
                  () => engine.setSubscriptionHours(x.url, h),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            x.hours == 0
                ? 'Общий период задаётся вверху страницы «Подписки».'
                : 'Эта подписка загружается заново каждые ${x.hours} ч, пока приложение работает.',
            style: desc(context, 10.5),
          ),
        ]),
        if (x.web.isNotEmpty || x.support.isNotEmpty)
          plate([
            title('От провайдера'),
            if (x.web.isNotEmpty) link('Сайт', x.web),
            if (x.support.isNotEmpty) link('Поддержка', x.support),
          ]),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(context, const _Countries()),
          child: plate([
            Row(
              children: [
                const Icon(Icons.public_rounded),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Страны по сетям',
                        style: mono(context, 14, weight: FontWeight.w700),
                      ),
                      Text(
                        'Какие страны использовать в Wi-Fi и в LTE',
                        style: desc(context, 10.5),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: soft),
              ],
            ),
          ]),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Поделиться'),
                onPressed: () => _shareSheet(context, engine, x),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: Palette.alert,
                ),
                label: Text('Удалить', style: TextStyle(color: Palette.alert)),
                onPressed: () async {
                  if (await _confirm(
                    context,
                    'Удалить подписку?',
                    x.name.isEmpty ? x.url : x.name,
                  )) {
                    engine.removeSubscription(x.url);
                    if (context.mounted) Navigator.of(context).maybePop();
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The id of this install that providers limit the number of devices by: shown, to be given to a provider or
/// replaced by that of a device the provider already knows.
class _DeviceId extends ConsumerStatefulWidget {
  const _DeviceId();

  @override
  ConsumerState<_DeviceId> createState() => _DeviceIdState();
}

class _DeviceIdState extends ConsumerState<_DeviceId> {
  @override
  Widget build(BuildContext context) {
    final engine = ref.read(engineProvider.notifier);
    final id = engine.deviceId;
    final dark = isDark(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Palette.plate(dark),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Palette.ink(dark).withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Идентификатор устройства',
            style: mono(context, 14.5, weight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Некоторые провайдеры считают устройства по этому идентификатору и пишут «Лимит устройств», когда места нет. Освободите место у провайдера или укажите идентификатор устройства, которое он знает.',
            style: desc(context, 11),
          ),
          const SizedBox(height: 10),
          SelectableText(id, style: mono(context, 12)),
          const SizedBox(height: 10),
          _BigButton(
            label: 'Скопировать',
            icon: Icons.copy_rounded,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: id));
              toast('Идентификатор скопирован');
            },
          ),
          const SizedBox(height: 10),
          _TextSetting(
            initial: '',
            hint: 'Свой идентификатор (8–64 знака)',
            onDone: (v) {
              if (v.isEmpty) return;
              if (engine.setDeviceId(v)) {
                toast('Идентификатор заменён');
                setState(() {});
              } else {
                toast('Нужны латиница, цифры, «-» и «_», 8–64 знака');
              }
            },
          ),
        ],
      ),
    );
  }
}

/// The preference of the main subscription (the first in the list): its servers win unless another subscription's
/// server is faster by the margin chosen here, for each network.
class _Priority extends ConsumerWidget {
  const _Priority();

  static const _wifi = [0, 50, 100, 200];
  static const _lte = [0, 100, 150, 300];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    String label(int v) => v == 0 ? 'Выкл' : '$v мс';
    Widget choice(
      String title,
      List<int> values,
      int current,
      void Function(int) set,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(title, style: mono(context, 13, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        SegmentedChoice(
          height: 40,
          compact: true,
          labels: [for (final v in values) label(v)],
          icons: [for (final _ in values) Icons.circle],
          selected: values.indexOf(current).clamp(0, values.length - 1),
          onChanged: (i) => set(values[i]),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Palette.plate(dark),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Palette.ink(dark).withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Приоритет главной подписки',
            style: mono(context, 14.5, weight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Серверы первой подписки предпочитаются: сервер другой подписки выбирается, только если он быстрее на указанное время. Со следующего подключения.',
            style: desc(context, 11),
          ),
          choice(
            'Wi-Fi',
            _wifi,
            r.priorityWifi,
            (v) => engine.setRules(r.copyWith(priorityWifi: v)),
          ),
          choice(
            'Мобильная сеть',
            _lte,
            r.priorityLte,
            (v) => engine.setRules(r.copyWith(priorityLte: v)),
          ),
        ],
      ),
    );
  }
}
