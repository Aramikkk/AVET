import 'dart:async';
import 'dart:io';

import 'package:avet/ui/widgets.dart';
import 'package:avet/update/update.dart';
import 'package:flutter/material.dart';

enum _Step {
  idle,
  checking,
  latest,
  none,
  available,
  downloading,
  ready,
  permission,
  failed,
}

/// The program's update on the About page: looks the newest release up on GitHub, downloads its APK with the progress shown
/// and hands it to the system installer.
class UpdateBlock extends StatefulWidget {
  const UpdateBlock({super.key, this.info});

  /// a newer build already found (the daily look): the block begins with it, ready to download
  final UpdateInfo? info;

  @override
  State<UpdateBlock> createState() => _UpdateBlockState();
}

class _UpdateBlockState extends State<UpdateBlock> {
  _Step _step = _Step.idle;
  InstalledVersion? _installed = Updates.last;
  UpdateInfo? _info;
  File? _file;
  double _progress = 0;
  String _error = '';

  @override
  void initState() {
    super.initState();
    if (widget.info != null) {
      _info = widget.info;
      _step = _Step.available;
    }
    unawaited(_loadInstalled());
  }

  Future<void> _loadInstalled() async {
    try {
      final v = await Updates.installed();
      if (mounted) setState(() => _installed = v);
    } catch (_) {}
  }

  Future<void> _check() async {
    setState(() {
      _step = _Step.checking;
      _error = '';
    });
    try {
      final installed = _installed ?? await Updates.installed();
      final info = await Updates.latest();
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _info = info;
        _step = info == null
            ? _Step.none
            : info.isNewerThan(installed.code)
            ? _Step.available
            : _Step.latest;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _reason(e);
          _step = _Step.failed;
        });
      }
    }
  }

  Future<void> _download() async {
    final info = _info;
    if (info == null) return;
    setState(() {
      _step = _Step.downloading;
      _progress = 0;
      _error = '';
    });
    try {
      final file = await Updates.download(
        info,
        onProgress: (p) {
          if (mounted && (p - _progress).abs() >= .01) {
            setState(() => _progress = p);
          }
        },
      );
      if (!mounted) return;
      _file = file;
      await _install();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _reason(e);
          _step = _Step.failed;
        });
      }
    }
  }

  Future<void> _install() async {
    final file = _file;
    if (file == null) return;
    final r = await Updates.install(file);
    if (!mounted) return;
    setState(() {
      _step = r == 'permission'
          ? _Step.permission
          : r == 'ok'
          ? _Step.ready
          : _Step.failed;
      if (r == 'error') _error = 'Не удалось запустить установку';
    });
  }

  String _reason(Object e) {
    if (e is FormatException) {
      return 'Файл повреждён или не совпал с опубликованным';
    }
    if (e is SocketException ||
        e is TimeoutException ||
        e is HandshakeException) {
      return 'Нет соединения с GitHub';
    }
    if (e is HttpException) return 'Сервер ответил ошибкой (${e.message})';
    return 'Что-то пошло не так';
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final i = _installed;
    final info = _info;
    final busy = _step == _Step.checking || _step == _Step.downloading;

    // the line under the title and the button at the right
    // (a line is there from the start, even before the version is read: the page does not move when it comes)
    var line = i == null ? ' ' : 'Установлена версия ${i.name} (${i.code})';
    String? button;
    VoidCallback? action;
    switch (_step) {
      case _Step.idle:
        button = 'Проверить';
        action = _check;
      case _Step.checking:
        line = 'Проверка…';
      case _Step.latest:
        line = 'Установлена последняя версия: ${i?.name ?? ''}';
        button = 'Проверить';
        action = _check;
      case _Step.none:
        line = 'Опубликованных версий пока нет';
        button = 'Проверить';
        action = _check;
      case _Step.available:
        line =
            'Доступна версия ${info?.version ?? ''}${info == null || info.size == 0 ? '' : ' · ${_mb(info.size)}'}';
        button = 'Скачать';
        action = _download;
      case _Step.downloading:
        line = 'Загрузка ${(_progress * 100).round()}%';
      case _Step.ready:
        line = 'Установщик открыт. Подтвердите обновление в окне системы';
        button = 'Открыть снова';
        action = _install;
      case _Step.permission:
        line = 'Разрешите AVET устанавливать приложения и нажмите «Установить»';
        button = 'Установить';
        action = _install;
      case _Step.failed:
        line = _error;
        button = 'Повторить';
        action = info == null ? _check : _download;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Обновление программы',
                style: mono(context, 13.5, weight: FontWeight.w700),
              ),
            ),
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: Padding(
                  padding: EdgeInsets.all(1),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (button != null)
              TextButton(onPressed: action, child: Text(button)),
          ],
        ),
        if (line.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              line,
              style: mono(context, 11.5, colour: soft, spacing: 0),
            ),
          ),
        if (_step == _Step.downloading)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 6,
                color: Palette.red,
                backgroundColor: Palette.red.withValues(alpha: .18),
              ),
            ),
          ),
        if (_step == _Step.available && info != null && info.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              info.notes,
              style: mono(context, 11.5, colour: soft, spacing: 0),
            ),
          ),
      ],
    );
  }

  static String _mb(int bytes) =>
      '${(bytes / 1048576).toStringAsFixed(1).replaceAll('.', ',')} МБ';
}

/// The offer the app makes by itself when the daily look found a newer build: what is new and the download, in a sheet.
class UpdateSheet extends StatelessWidget {
  const UpdateSheet({super.key, required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Вышла новая версия AVET',
            style: mono(context, 16, weight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          UpdateBlock(info: info),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Позже'),
            ),
          ),
        ],
      ),
    ),
  );
}
