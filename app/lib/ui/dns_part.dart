part of 'settings_page.dart';

/// DNS: which server answers the names, chosen by hand or by the best answer.
class _DnsPage extends ConsumerStatefulWidget {
  const _DnsPage();

  @override
  ConsumerState<_DnsPage> createState() => _DnsPageState();
}

class _DnsPageState extends ConsumerState<_DnsPage> {
  late final TextEditingController _custom = TextEditingController(
    text: ref.read(engineProvider).rules.dnsCustom,
  );

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final ink = Palette.ink(dark);

    Widget plate(List<Widget> kids) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Palette.plate(dark),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: ink.withValues(alpha: .28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: kids,
        ),
      ),
    );

    Widget radio(bool on) => Icon(
      on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
      color: on ? ink : soft,
    );

    return _Sub(
      title: 'DNS',
      children: [
        plate([
          Text(
            'DNS для прямого трафика',
            style: mono(context, 14.5, weight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Адрес DNS для трафика, который идёт напрямую, мимо VPN. Пусто: DNS телефона. Со следующего подключения.',
            style: desc(context, 11),
          ),
          const SizedBox(height: 12),
          _TextSetting(
            initial: r.directDns,
            hint: 'Например 77.88.8.8',
            keyboard: TextInputType.url,
            onDone: (v) => engine.setRules(r.copyWith(directDns: v)),
          ),
        ]),
        plate([
          Text(
            'Автовыбор DNS',
            style: mono(context, 14.5, weight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Опрашивает DNS из списка и берёт тот, что отвечает быстрее всех, как при проверке пинга.',
            style: desc(context, 11),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<bool>(
            valueListenable: Engine.dnsTesting,
            builder: (context, busy, _) => _BigButton(
              label: busy ? 'Проверяю…' : 'Выбрать лучший DNS',
              icon: Icons.speed_rounded,
              onTap: busy ? null : () => unawaited(engine.chooseBestDns()),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Выбирать при каждом подключении',
                  style: mono(context, 13, weight: FontWeight.w700),
                ),
              ),
              Switch(
                value: r.dnsAuto,
                onChanged: (v) => engine.setRules(r.copyWith(dnsAuto: v)),
              ),
            ],
          ),
        ]),
        ValueListenableBuilder<Map<int, int?>>(
          valueListenable: Engine.dnsResults,
          builder: (context, results, _) => plate([
            Text('Сервер', style: mono(context, 14.5, weight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final (i, d) in dnsServers.indexed) ...[
              if (i > 0) Divider(height: 1, color: ink.withValues(alpha: .14)),
              InkWell(
                onTap: () => engine.setRules(r.copyWith(dns: i)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    children: [
                      radio(r.dns == i),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.name,
                              style: mono(context, 14, weight: FontWeight.w700),
                            ),
                            Text(d.ip, style: desc(context, 10.5)),
                          ],
                        ),
                      ),
                      if (results.containsKey(i))
                        Text(
                          results[i] == null
                              ? 'нет ответа'
                              : '${results[i]} мс',
                          style: mono(
                            context,
                            12.5,
                            weight: FontWeight.w800,
                            colour: results[i] == null ? Palette.alert : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            Divider(height: 1, color: ink.withValues(alpha: .14)),
            InkWell(
              onTap: () => engine.setRules(r.copyWith(dns: dnsServers.length)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  children: [
                    radio(r.dns == dnsServers.length),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Свой DNS',
                        style: mono(context, 14, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (r.dns == dnsServers.length) ...[
              TextField(
                controller: _custom,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: mono(context, 13),
                decoration: const InputDecoration(
                  hintText: 'Адрес сервера DNS over HTTPS, например 8.8.8.8',
                ),
                onSubmitted: (v) =>
                    engine.setRules(r.copyWith(dnsCustom: v.trim())),
              ),
              const SizedBox(height: 10),
              _BigButton(
                label: 'Сохранить',
                icon: Icons.check_rounded,
                onTap: () {
                  engine.setRules(r.copyWith(dnsCustom: _custom.text.trim()));
                  FocusScope.of(context).unfocus();
                  toast('DNS сохранён');
                },
              ),
            ],
          ]),
        ),
        _hint(
          context,
          'Запросы имён идут через VPN к выбранному серверу. Со следующего подключения.',
        ),
      ],
    );
  }
}
