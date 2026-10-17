import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/library_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/screen_title.dart';

const _kYellow = Color(0xFFFFDB4D);
const _kContentMax = 720.0;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busyBackup = false;
  String? _backupMessage;
  String? _photosMessage;

  Future<void> _refreshArtistPhotos(LibraryService library) async {
    setState(() => _photosMessage = null);
    try {
      final n = await library.refreshArtistPhotos();
      if (!mounted) return;
      setState(() {
        _photosMessage = n == 0
            ? 'Новых фото не найдено (ручные не перезаписываются).'
            : 'Обновлено фото: $n.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _photosMessage = 'Ошибка: $e');
    }
  }

  Future<void> _clearPlayCounts(LibraryService library) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.inkLift,
        title: Text(
          'Обнулить прослушивания?',
          style: GoogleFonts.syne(
            color: AppTheme.paper,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Счётчики и история прослушиваний будут удалены. '
          'Чарт начнётся с нуля. Плейлисты и метаданные треков не изменятся.',
          style: GoogleFonts.figtree(
            color: AppTheme.paperMuted,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Отмена',
              style: GoogleFonts.figtree(color: AppTheme.paperMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Обнулить',
              style: GoogleFonts.figtree(
                color: Colors.redAccent.shade100,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busyBackup = true;
      _backupMessage = null;
    });
    try {
      await library.clearPlayCounts();
      if (!mounted) return;
      setState(() => _backupMessage = 'Счётчики прослушиваний обнулены.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _backupMessage = 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  Future<void> _export(LibraryService library) async {
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Экспорт данных Freedom Music',
      fileName: 'freedom_music_backup_$stamp.zip',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (path == null) return;

    setState(() {
      _busyBackup = true;
      _backupMessage = null;
    });
    try {
      final dest = path.toLowerCase().endsWith('.zip') ? path : '$path.zip';
      final result = await library.exportAppData(dest);
      if (!mounted) return;
      setState(() => _backupMessage = result.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _backupMessage = 'Ошибка экспорта: $e');
    } finally {
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  Future<void> _import(LibraryService library) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.inkLift,
        title: Text(
          'Импорт данных',
          style: GoogleFonts.syne(
            color: AppTheme.paper,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Текущие плейлисты, прослушивания, фото артистов, '
          'обложки плейлистов и снимки чарта будут заменены данными из файла. '
          'Метаданные треков и файлы music не изменятся.',
          style: GoogleFonts.figtree(
            color: AppTheme.paperMuted,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Отмена',
              style: GoogleFonts.figtree(color: AppTheme.paperMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Импортировать',
              style: GoogleFonts.figtree(
                color: _kYellow,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Импорт данных Freedom Music',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null) return;

    setState(() {
      _busyBackup = true;
      _backupMessage = null;
    });
    try {
      final result = await library.importAppData(path);
      if (!mounted) return;
      setState(() => _backupMessage = result.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _backupMessage = 'Ошибка импорта: $e');
    } finally {
      if (mounted) setState(() => _busyBackup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild only on library / the few settings shown here — not on every
    // playback-session persist from the player.
    final library = context.watch<LibraryService>();
    final settings = context.read<SettingsService>();
    final scanOnStartup = context.select<SettingsService, bool>(
      (s) => s.scanOnStartup,
    );
    final crossfade = context.select<SettingsService, int>(
      (s) => s.crossfadeSeconds,
    );
    final progress = library.scanProgress;
    final scanning = library.scanning;
    final photosBusy = library.artistPhotosRefreshing;
    final photoProgress = library.artistPhotoProgress;
    final busy = scanning || _busyBackup || photosBusy;

    return Stack(
      children: [
        const Positioned.fill(
          child: AmbientBackdrop(
            accent: AppTheme.moss,
            secondary: Color(0xFF24382F),
          ),
        ),
        ListView(
          padding: const EdgeInsets.only(bottom: 48),
          children: [
            const ScreenTitle(title: 'Настройки'),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kContentMax),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionCard(
                        title: 'Библиотека',
                        subtitle:
                            'Папка music и индекс. Метаданные остаются в файлах.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _PathRow(
                              label: 'Папка music',
                              value: library.paths.musicDir,
                            ),
                            const SizedBox(height: 10),
                            _PathRow(
                              label: 'База данных',
                              value: library.paths.databasePath,
                            ),
                            const SizedBox(height: 18),
                            _SettingSwitch(
                              title: 'Сканировать при запуске',
                              subtitle:
                                  'По умолчанию выключено — скан только по кнопке.',
                              value: scanOnStartup,
                              onChanged: busy
                                  ? null
                                  : settings.setScanOnStartup,
                            ),
                            const SizedBox(height: 14),
                            _CrossfadeSlider(
                              value: crossfade,
                              onChanged: settings.setCrossfadeSeconds,
                            ),
                            const SizedBox(height: 18),
                            _ActionTile(
                              icon: Icons.folder_open_rounded,
                              title: 'Сканировать music',
                              subtitle:
                                  'Без парсинга. Ищет новые и изменённые файлы.',
                              onPressed: busy
                                  ? null
                                  : () => library.scanLibrary(),
                            ),
                            _ActionTile(
                              icon: Icons.refresh_rounded,
                              title: 'Сканировать music полностью',
                              subtitle: 'Без парсинга. Перечитывает все треки.',
                              onPressed: busy
                                  ? null
                                  : () => library.scanLibrary(force: true),
                            ),
                            _ActionTile(
                              icon: Icons.travel_explore_rounded,
                              title: 'Поиск пустых метаданных',
                              subtitle:
                                  'Только список «Без метаданных». Альбом, артист альбома, год, номер, продюсер.',
                              onPressed: busy
                                  ? null
                                  : () => library.fillEmptyMetadata(),
                            ),
                            _ActionTile(
                              icon: Icons.lyrics_outlined,
                              title: 'Поиск текстов для треков',
                              subtitle: 'Только текст песни.',
                              onPressed: busy
                                  ? null
                                  : () => library.fillMissingLyrics(),
                            ),
                            _ActionTile(
                              icon: Icons.face_retouching_natural_rounded,
                              title: 'Обновить фотографии артистов',
                              subtitle: photosBusy
                                  ? 'Ищем новые фото…'
                                  : 'Ручные фото не перезаписываются.',
                              busy: photosBusy,
                              onPressed: busy
                                  ? null
                                  : () => _refreshArtistPhotos(library),
                            ),
                            if (scanning || progress != null) ...[
                              const SizedBox(height: 4),
                              _JobProgress(
                                label: progress == null
                                    ? 'Подготовка…'
                                    : '${progress.processed} / ${progress.total}'
                                        '${progress.currentFile != null ? ' — ${progress.currentFile}' : ''}',
                                value: progress?.ratio,
                                onStop: scanning ? library.cancelScan : null,
                              ),
                            ],
                            if (photoProgress != null) ...[
                              const SizedBox(height: 8),
                              _JobProgress(
                                label:
                                    '${photoProgress.done} / ${photoProgress.total}'
                                    '${photoProgress.updated > 0 ? ' · сохранено ${photoProgress.updated}' : ''}'
                                    '${photoProgress.current != null ? ' — ${photoProgress.current}' : ''}',
                                value: photoProgress.ratio,
                              ),
                            ],
                            if (library.jobLog.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _JobLog(lines: library.jobLog),
                            ],
                            if (_photosMessage != null) ...[
                              const SizedBox(height: 12),
                              _StatusNote(text: _photosMessage!),
                            ],
                            if (library.lastScanMessage != null) ...[
                              const SizedBox(height: 14),
                              _StatusNote(text: library.lastScanMessage!),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Данные приложения',
                        subtitle:
                            'Плейлисты, фото артистов, обложки плейлистов, '
                            'история прослушиваний, снимки чарта и эти настройки. '
                            'Метаданные MP3 не входят.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ActionTile(
                              icon: Icons.upload_rounded,
                              title: 'Экспорт',
                              subtitle: 'Архив плейлистов, фото и истории.',
                              onPressed:
                                  busy ? null : () => _export(library),
                            ),
                            _ActionTile(
                              icon: Icons.download_rounded,
                              title: 'Импорт',
                              subtitle: 'Заменит данные приложения из архива.',
                              onPressed:
                                  busy ? null : () => _import(library),
                            ),
                            if (_busyBackup) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _kYellow,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Обработка архива…',
                                    style: GoogleFonts.figtree(
                                      color: AppTheme.paperMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (_backupMessage != null) ...[
                              const SizedBox(height: 14),
                              _StatusNote(text: _backupMessage!),
                            ],
                            const SizedBox(height: 4),
                            _ActionTile(
                              icon: Icons.restart_alt_rounded,
                              title: 'Обнулить прослушивания',
                              subtitle: 'Чарт начнётся с нуля. Плейлисты останутся.',
                              danger: true,
                              onPressed: busy
                                  ? null
                                  : () => _clearPlayCounts(library),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'О приложении',
                        child: Text(
                          'Freedom Music — локальный плеер. Источник правды о '
                          'треке — метаданные файла. Одинаковые название + '
                          'исполнитель = один трек. Закрытие окна сворачивает '
                          'в трей; выход — из меню иконки.',
                          style: GoogleFonts.figtree(
                            color: AppTheme.paperMuted,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.inkLift.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.paper.withValues(alpha: 0.07),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: GoogleFonts.syne(
                color: AppTheme.paper,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: GoogleFonts.figtree(
                  color: AppTheme.paperMuted.withValues(alpha: 0.95),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.ink.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.paper.withValues(alpha: 0.06),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.figtree(
                      color: AppTheme.paperMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    value,
                    style: GoogleFonts.figtree(
                      color: AppTheme.paper,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Копировать',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Скопировано',
                      style: GoogleFonts.figtree(fontWeight: FontWeight.w600),
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppTheme.inkLift,
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              icon: Icon(
                Icons.copy_rounded,
                size: 18,
                color: AppTheme.paperMuted.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrossfadeSlider extends StatelessWidget {
  const _CrossfadeSlider({
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = value <= 0 ? 'выкл' : '$value с';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.ink.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Кроссфейд',
                    style: GoogleFonts.figtree(
                      color: AppTheme.paper,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.figtree(
                    color: _kYellow,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Мягкий переход между треками. 0 — мгновенная смена.',
              style: GoogleFonts.figtree(
                color: AppTheme.paperMuted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _kYellow,
                inactiveTrackColor: AppTheme.paper.withValues(alpha: 0.12),
                thumbColor: _kYellow,
                overlayColor: _kYellow.withValues(alpha: 0.15),
              ),
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 12,
                divisions: 12,
                label: label,
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.ink.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.figtree(
                      color: AppTheme.paper,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.figtree(
                      color: AppTheme.paperMuted,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: AppTheme.ink,
              activeTrackColor: _kYellow,
              inactiveThumbColor: AppTheme.paperMuted,
              inactiveTrackColor: AppTheme.paper.withValues(alpha: 0.12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.busy = false,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;
  final bool busy;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final accent = danger ? const Color(0xFFFF8D7A) : AppTheme.lime;
    final enabled = onPressed != null || busy;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Material(
          color: AppTheme.ink.withValues(alpha: enabled ? 0.42 : 0.28),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            hoverColor: accent.withValues(alpha: 0.06),
            splashColor: accent.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: enabled ? 0.14 : 0.08),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: enabled
                          ? accent
                          : accent.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.figtree(
                            color: enabled
                                ? AppTheme.paper
                                : AppTheme.paper.withValues(alpha: 0.45),
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: GoogleFonts.figtree(
                            color: AppTheme.paperMuted.withValues(
                              alpha: enabled ? 0.95 : 0.45,
                            ),
                            fontSize: 12.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (busy)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent.withValues(alpha: 0.9),
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.paperMuted.withValues(
                        alpha: enabled ? 0.7 : 0.3,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JobLog extends StatefulWidget {
  const _JobLog({required this.lines});

  final List<JobLogEntry> lines;

  @override
  State<_JobLog> createState() => _JobLogState();
}

class _JobLogState extends State<_JobLog> {
  final _scroll = ScrollController();
  static final _clock = DateFormat('HH:mm:ss');

  @override
  void didUpdateWidget(covariant _JobLog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length == oldWidget.lines.length) return;
    final stick = !_scroll.hasClients ||
        _scroll.position.maxScrollExtent - _scroll.offset < 64;
    if (!stick) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _errorCount(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return '$count ошибка';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return '$count ошибки';
    }
    return '$count ошибок';
  }

  @override
  Widget build(BuildContext context) {
    final written = widget.lines.where((entry) => entry.ok).length;
    final failed = widget.lines.length - written;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.ink.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.paper.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Журнал',
                  style: GoogleFonts.figtree(
                    color: AppTheme.paper,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text(
                  failed == 0
                      ? 'записано $written'
                      : 'записано $written · ${_errorCount(failed)}',
                  style: GoogleFonts.figtree(
                    color: AppTheme.paperMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 320,
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: ListView.separated(
                  controller: _scroll,
                  itemCount: widget.lines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    return _JobLogRow(
                      entry: widget.lines[index],
                      time: _clock.format(widget.lines[index].at),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobLogRow extends StatelessWidget {
  const _JobLogRow({required this.entry, required this.time});

  final JobLogEntry entry;
  final String time;

  @override
  Widget build(BuildContext context) {
    final accent = entry.ok ? AppTheme.lime : const Color(0xFFFF8A80);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.inkLift.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(10),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          time,
                          style: GoogleFonts.figtree(
                            color: AppTheme.paperMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.figtree(
                              color: AppTheme.paper,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.figtree(
                        color: AppTheme.paper.withValues(alpha: 0.86),
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                    if (entry.error != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        entry.error!,
                        style: GoogleFonts.figtree(
                          color: const Color(0xFFFF8A80),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (entry.fields.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final field in entry.fields)
                            _LogChip(label: field.label, value: field.value),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogChip extends StatelessWidget {
  const _LogChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.ink.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text.rich(
          TextSpan(
            style: GoogleFonts.figtree(fontSize: 11.5, height: 1.2),
            children: [
              TextSpan(
                text: '$label  ',
                style: const TextStyle(color: AppTheme.paperMuted),
              ),
              TextSpan(
                text: value,
                style: const TextStyle(
                  color: AppTheme.paper,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobProgress extends StatelessWidget {
  const _JobProgress({
    required this.label,
    required this.value,
    this.onStop,
  });

  final String label;
  final double? value;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.ink.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.figtree(
                      color: AppTheme.paperMuted,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ),
                if (onStop != null)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: TextButton(
                      onPressed: onStop,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.ink,
                        backgroundColor: _kYellow,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        textStyle: GoogleFonts.figtree(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      child: const Text('Стоп'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: AppTheme.paper.withValues(alpha: 0.08),
                color: _kYellow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusNote extends StatelessWidget {
  const _StatusNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.moss.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.mossBright.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          text,
          style: GoogleFonts.figtree(
            color: AppTheme.paper,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
