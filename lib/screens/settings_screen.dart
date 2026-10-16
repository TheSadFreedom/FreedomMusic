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
    final autoFill = context.select<SettingsService, bool>(
      (s) => s.autoFillEmptyMetadata,
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
                            const SizedBox(height: 8),
                            _SettingSwitch(
                              title: 'Дополнять пустые метаданные',
                              subtitle:
                                  'Для новых треков подставляет альбом, год, жанр '
                                  'и номер из интернета. Название, артист и обложка '
                                  'не меняются.',
                              value: autoFill,
                              onChanged: busy
                                  ? null
                                  : settings.setAutoFillEmptyMetadata,
                            ),
                            const SizedBox(height: 14),
                            _CrossfadeSlider(
                              value: crossfade,
                              onChanged: settings.setCrossfadeSeconds,
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: _PrimaryButton(
                                    onPressed: busy
                                        ? null
                                        : () => library.scanLibrary(),
                                    icon: scanning
                                        ? null
                                        : Icons.folder_open_rounded,
                                    busy: scanning && !_busyBackup,
                                    label: scanning
                                        ? 'Сканирование…'
                                        : 'Сканировать music',
                                  ),
                                ),
                                if (scanning) ...[
                                  const SizedBox(width: 10),
                                  _GhostButton(
                                    onPressed: library.cancelScan,
                                    icon: Icons.stop_rounded,
                                    label: 'Стоп',
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 10),
                            _GhostButton(
                              onPressed: busy
                                  ? null
                                  : () => library.scanLibrary(force: true),
                              icon: Icons.refresh_rounded,
                              label: 'Просканировать все треки заново',
                              expanded: true,
                            ),
                            const SizedBox(height: 10),
                            _GhostButton(
                              onPressed: busy
                                  ? null
                                  : () => library.fillEmptyMetadata(),
                              icon: Icons.travel_explore_rounded,
                              label: 'Поиск пустых метаданных',
                              expanded: true,
                            ),
                            const SizedBox(height: 10),
                            _GhostButton(
                              onPressed: busy
                                  ? null
                                  : () => _refreshArtistPhotos(library),
                              icon: Icons.face_retouching_natural_rounded,
                              label: photosBusy
                                  ? 'Обновление фото артистов…'
                                  : 'Обновить фото артистов',
                              expanded: true,
                            ),
                            if (photoProgress != null) ...[
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: photoProgress.ratio,
                                  minHeight: 6,
                                  backgroundColor:
                                      AppTheme.paper.withValues(alpha: 0.08),
                                  color: _kYellow,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${photoProgress.done} / ${photoProgress.total}'
                                '${photoProgress.updated > 0 ? ' · сохранено ${photoProgress.updated}' : ''}'
                                '${photoProgress.current != null ? ' — ${photoProgress.current}' : ''}',
                                style: GoogleFonts.figtree(
                                  color: AppTheme.paperMuted,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                            if (_photosMessage != null) ...[
                              const SizedBox(height: 12),
                              _StatusNote(text: _photosMessage!),
                            ],
                            const SizedBox(height: 10),
                            Text(
                              'Полный повторный скан перечитает теги из всех файлов. '
                              'Автодополнение из сети при этом не запускается. '
                              '«Поиск пустых метаданных» проходит по всей библиотеке '
                              'и дополняет альбом, год, жанр и номер из интернета '
                              '(название, артист и обложка не меняются). '
                              '«Обновить фото артистов» — Яндекс Музыка → '
                              'Genius → Deezer → TheAudioDB → iTunes → '
                              'MusicBrainz/Wikidata; вручную выбранные фото '
                              'не перезаписываются. '
                              'Прослушивания и плейлисты не сбрасываются.',
                              style: GoogleFonts.figtree(
                                color: AppTheme.paperMuted.withValues(
                                  alpha: 0.9,
                                ),
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                            if (progress != null) ...[
                              const SizedBox(height: 16),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: progress.ratio,
                                  minHeight: 6,
                                  backgroundColor: AppTheme.paper
                                      .withValues(alpha: 0.08),
                                  color: _kYellow,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${progress.processed} / ${progress.total}'
                                '${progress.currentFile != null ? ' — ${progress.currentFile}' : ''}',
                                style: GoogleFonts.figtree(
                                  color: AppTheme.paperMuted,
                                  fontSize: 12.5,
                                ),
                              ),
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
                            LayoutBuilder(
                              builder: (context, c) {
                                final wide = c.maxWidth >= 420;
                                final exportBtn = _PrimaryButton(
                                  onPressed: busy
                                      ? null
                                      : () => _export(library),
                                  icon: Icons.upload_rounded,
                                  busy: false,
                                  label: 'Экспорт',
                                );
                                final importBtn = _GhostButton(
                                  onPressed: busy
                                      ? null
                                      : () => _import(library),
                                  icon: Icons.download_rounded,
                                  label: 'Импорт',
                                  expanded: true,
                                );
                                if (!wide) {
                                  return Column(
                                    children: [
                                      exportBtn,
                                      const SizedBox(height: 10),
                                      importBtn,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    Expanded(child: exportBtn),
                                    const SizedBox(width: 10),
                                    Expanded(child: importBtn),
                                  ],
                                );
                              },
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
                            const SizedBox(height: 14),
                            _GhostButton(
                              onPressed: busy
                                  ? null
                                  : () => _clearPlayCounts(library),
                              icon: Icons.restart_alt_rounded,
                              label: 'Обнулить счётчики прослушиваний',
                              expanded: true,
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

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.onPressed,
    required this.label,
    required this.busy,
    this.icon,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _kYellow,
        foregroundColor: AppTheme.ink,
        disabledBackgroundColor: _kYellow.withValues(alpha: 0.35),
        disabledForegroundColor: AppTheme.ink.withValues(alpha: 0.55),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: GoogleFonts.figtree(
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.ink,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 18),
          if (busy || icon != null) const SizedBox(width: 8),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.expanded = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.paper,
        disabledForegroundColor: AppTheme.paperMuted.withValues(alpha: 0.5),
        side: BorderSide(
          color: AppTheme.paper.withValues(alpha: onPressed == null ? 0.06 : 0.14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: GoogleFonts.figtree(
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
        ),
      ),
    );
    if (expanded) return SizedBox(width: double.infinity, child: button);
    return button;
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
