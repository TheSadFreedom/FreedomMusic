import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/track_key.dart';
import '../navigation/app_navigator.dart';
import '../models/track.dart';
import '../services/library_service.dart';
import '../services/metadata_writer.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../utils/breakpoints.dart';
import '../widgets/ambient_backdrop.dart';

const _kYellow = Color(0xFFFFDB4D);
const _kContentMaxWidth = 820.0;

Future<bool> openMetadataEditor(BuildContext context, Track track) async {
  final result =
      await Navigator.of(
        navigatorContext(context),
        rootNavigator: true,
      ).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => MetadataEditorScreen(track: track),
        ),
      );
  return result ?? false;
}

class MetadataEditorScreen extends StatefulWidget {
  const MetadataEditorScreen({super.key, required this.track});

  final Track track;

  @override
  State<MetadataEditorScreen> createState() => _MetadataEditorScreenState();
}

class _MetadataEditorScreenState extends State<MetadataEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _artist;
  late final TextEditingController _album;
  late final TextEditingController _albumArtist;
  late final TextEditingController _producer;
  late final TextEditingController _genre;
  late final TextEditingController _year;
  late final TextEditingController _trackNumber;
  late final TextEditingController _trackTotal;
  late final TextEditingController _discNumber;
  late final TextEditingController _lyrics;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  Uint8List? _newCoverBytes;
  String? _newCoverMime;
  bool _removeCover = false;

  @override
  void initState() {
    super.initState();
    final t = widget.track;
    _title = TextEditingController(text: metaFieldText(t.title));
    _note = TextEditingController(text: metaFieldText(t.note));
    _artist = TextEditingController(
      text: metaFieldText(storedArtists(t.artist)),
    );
    _album = TextEditingController(text: metaFieldText(t.album));
    _albumArtist = TextEditingController(
      text: metaFieldText(storedPeople(t.albumArtist)),
    );
    final storedProducer = metaFieldText(t.producer);
    final path = t.primaryPath;
    final fileProducer = storedProducer.isNotEmpty
        ? storedProducer
        : (path == null ? '' : metaFieldText(readFileProducer(path)));
    _producer = TextEditingController(text: fileProducer);
    _genre = TextEditingController(text: metaFieldText(t.genre));
    final y = t.year;
    _year = TextEditingController(
      text: (y == null || y == 0) ? '' : y.toString(),
    );
    _trackNumber = TextEditingController(
      text: (t.trackNumber == null || t.trackNumber! < 1)
          ? ''
          : t.trackNumber.toString(),
    );
    _trackTotal = TextEditingController(
      text: (t.trackTotal == null || t.trackTotal! < 1)
          ? ''
          : t.trackTotal.toString(),
    );
    _discNumber = TextEditingController(
      text: (t.discNumber == null || t.discNumber! < 1)
          ? ''
          : t.discNumber.toString(),
    );
    _lyrics = TextEditingController(text: t.lyrics ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _artist.dispose();
    _album.dispose();
    _albumArtist.dispose();
    _producer.dispose();
    _genre.dispose();
    _year.dispose();
    _trackNumber.dispose();
    _trackTotal.dispose();
    _discNumber.dispose();
    _lyrics.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    var bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) return;

    final ext = (file.extension ?? '').toLowerCase();
    final mime = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };

    setState(() {
      _newCoverBytes = bytes;
      _newCoverMime = mime;
      _removeCover = false;
    });
  }

  void _clearCover() {
    setState(() {
      _newCoverBytes = null;
      _newCoverMime = null;
      _removeCover = true;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final yearText = _year.text.trim();
    final year = yearText.isEmpty ? null : int.tryParse(yearText);
    int? parsePos(String raw) {
      final t = raw.trim();
      if (t.isEmpty) return null;
      return int.tryParse(t);
    }

    final draft = MetadataDraft(
      title: _title.text,
      note: _note.text,
      artist: _artist.text,
      album: _album.text,
      albumArtist: _albumArtist.text,
      producer: _producer.text,
      genre: _genre.text,
      year: year,
      trackNumber: parsePos(_trackNumber.text),
      trackTotal: parsePos(_trackTotal.text),
      discNumber: parsePos(_discNumber.text),
      lyrics: _lyrics.text,
      coverBytes: _newCoverBytes,
      coverMime: _newCoverMime,
      removeCover: _removeCover,
    );

    try {
      final library = context.read<LibraryService>();
      final player = context.read<PlayerService>();
      final oldKey = widget.track.trackKey;
      final updated = await library.saveTrackMetadata(widget.track, draft);
      player.syncTrack(updated, oldTrackKey: oldKey);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _copyName() async {
    final artist = _artist.text.trim();
    final title = _title.text.trim();
    final text = [
      if (artist.isNotEmpty) artist,
      if (title.isNotEmpty) title,
    ].join(' - ');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
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
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.track.primaryPath ?? '—';

    return Scaffold(
      backgroundColor: AppTheme.ink,
      appBar: AppBar(
        backgroundColor: AppTheme.ink.withValues(alpha: 0.92),
        title: Text(
          'Метаданные',
          style: GoogleFonts.syne(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _copyName,
            style: TextButton.styleFrom(
              enabledMouseCursor: SystemMouseCursors.click,
              disabledMouseCursor: SystemMouseCursors.basic,
            ),
            child: Text(
              'Копировать',
              style: GoogleFonts.figtree(
                color: AppTheme.paper,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _saving ? null : _save,
              style: TextButton.styleFrom(
                enabledMouseCursor: SystemMouseCursors.click,
                disabledMouseCursor: SystemMouseCursors.basic,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _kYellow,
                      ),
                    )
                  : Text(
                      'Сохранить',
                      style: GoogleFonts.figtree(
                        color: _kYellow,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: AmbientBackdrop(
              accent: AppTheme.moss,
              secondary: Color(0xFF2A4A3C),
            ),
          ),
          Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                isPhone(context) ? 16 : 24,
                12,
                isPhone(context) ? 16 : 24,
                48,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _kContentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.figtree(
                            color: AppTheme.paperMuted.withValues(alpha: 0.75),
                            fontSize: 12,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _CoverSection(
                          existingPath: widget.track.coverPath,
                          newBytes: _newCoverBytes,
                          removed: _removeCover,
                          onPick: _pickCover,
                          onClear: _clearCover,
                        ),
                        const SizedBox(height: 28),
                        _sectionLabel('Основные'),
                        const SizedBox(height: 12),
                        _field(_title, 'Название', requiredField: true),
                        _field(_note, 'Заметка'),
                        _field(
                          _artist,
                          'Артист (запятая или feat.)',
                          requiredField: true,
                        ),
                        _field(_album, 'Альбом'),
                        _field(_albumArtist, 'Артист альбома'),
                        _field(_producer, 'Продюсер'),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 480;
                            final genre = _field(_genre, 'Жанр');
                            final year = _field(
                              _year,
                              'Год',
                              keyboard: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                final n = int.tryParse(v);
                                if (n == null || n < 1000 || n > 2100) {
                                  return 'Некорректный год';
                                }
                                return null;
                              },
                            );
                            if (!wide) {
                              return Column(children: [genre, year]);
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: genre),
                                const SizedBox(width: 14),
                                Expanded(flex: 1, child: year),
                              ],
                            );
                          },
                        ),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 480;
                            final trackNo = _field(
                              _trackNumber,
                              'Номер трека',
                              keyboard: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            );
                            final trackTotal = _field(
                              _trackTotal,
                              'Всего треков',
                              keyboard: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            );
                            final disc = _field(
                              _discNumber,
                              'Диск',
                              keyboard: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            );
                            if (!wide) {
                              return Column(
                                children: [trackNo, trackTotal, disc],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: trackNo),
                                const SizedBox(width: 14),
                                Expanded(child: trackTotal),
                                const SizedBox(width: 14),
                                Expanded(child: disc),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        _sectionLabel('Текст'),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _lyrics,
                          maxLines: 16,
                          minLines: 10,
                          style: GoogleFonts.figtree(
                            color: AppTheme.paper,
                            height: 1.45,
                            fontSize: 15,
                          ),
                          decoration: _decoration(
                            'Текст песни',
                            floatingLabel: false,
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              _error!,
                              style: GoogleFonts.figtree(
                                color: Colors.redAccent.shade100,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.syne(
        color: AppTheme.paper,
        fontWeight: FontWeight.w700,
        fontSize: 18,
        letterSpacing: -0.3,
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool requiredField = false,
    TextInputType? keyboard,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        style: GoogleFonts.figtree(
          color: AppTheme.paper,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: _kYellow,
        decoration: _decoration(label),
        validator:
            validator ??
            (requiredField
                ? (v) => (v == null || v.trim().isEmpty)
                      ? 'Обязательное поле'
                      : null
                : null),
      ),
    );
  }

  InputDecoration _decoration(String label, {bool floatingLabel = true}) {
    final radius = BorderRadius.circular(14);
    final idle = BorderSide(color: AppTheme.paper.withValues(alpha: 0.08));
    final focused = const BorderSide(color: _kYellow, width: 1.4);

    return InputDecoration(
      labelText: floatingLabel ? label : null,
      hintText: floatingLabel ? null : label,
      labelStyle: GoogleFonts.figtree(
        color: AppTheme.paperMuted,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      floatingLabelStyle: GoogleFonts.figtree(
        color: AppTheme.mossBright,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      hintStyle: GoogleFonts.figtree(
        color: AppTheme.paperMuted.withValues(alpha: 0.65),
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: AppTheme.inkLift.withValues(alpha: 0.92),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: radius, borderSide: idle),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: idle),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: focused,
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: Colors.redAccent.withValues(alpha: 0.7)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppTheme.paper.withValues(alpha: 0.04)),
      ),
    );
  }
}

class _CoverSection extends StatelessWidget {
  const _CoverSection({
    required this.existingPath,
    required this.newBytes,
    required this.removed,
    required this.onPick,
    required this.onClear,
  });

  final String? existingPath;
  final Uint8List? newBytes;
  final bool removed;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    Widget image = ColoredBox(
      color: AppTheme.inkLift,
      child: const Icon(Icons.album, size: 64, color: AppTheme.mossBright),
    );

    if (!removed) {
      if (newBytes != null) {
        image = Image.memory(newBytes!, fit: BoxFit.cover);
      } else if (existingPath != null && File(existingPath!).existsSync()) {
        image = Image.file(File(existingPath!), fit: BoxFit.cover);
      }
    }

    final hasCover =
        !removed &&
        (newBytes != null ||
            (existingPath != null && File(existingPath!).existsSync()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Обложка',
          style: GoogleFonts.syne(
            color: AppTheme.paper,
            fontWeight: FontWeight.w700,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: AppTheme.moss.withValues(alpha: 0.18),
                    blurRadius: 36,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: image,
              ),
            ),
            const SizedBox(width: 20),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PillAction(
                    onPressed: onPick,
                    filled: true,
                    icon: Icons.image_outlined,
                    label: 'Загрузить',
                  ),
                  const SizedBox(height: 10),
                  _PillAction(
                    onPressed: hasCover || removed ? onClear : null,
                    filled: false,
                    icon: Icons.delete_outline,
                    label: 'Удалить',
                  ),
                  if (removed) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Обложка будет удалена при сохранении',
                      style: GoogleFonts.figtree(
                        color: AppTheme.paperMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.onPressed,
    required this.filled,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final bool filled;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final bg = filled
        ? AppTheme.moss.withValues(alpha: enabled ? 0.95 : 0.35)
        : Colors.transparent;
    final fg = filled
        ? AppTheme.paper
        : (enabled
              ? AppTheme.paper.withValues(alpha: 0.9)
              : AppTheme.paperMuted.withValues(alpha: 0.4));
    final border = filled
        ? BorderSide.none
        : BorderSide(
            color: enabled
                ? AppTheme.paper.withValues(alpha: 0.22)
                : AppTheme.paper.withValues(alpha: 0.08),
          );

    return Material(
      color: bg,
      shape: StadiumBorder(side: border),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        mouseCursor: onPressed != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.figtree(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
