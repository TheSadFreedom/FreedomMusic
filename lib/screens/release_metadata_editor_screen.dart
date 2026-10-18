import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/track_key.dart';
import '../models/artist_release.dart';
import '../services/library_service.dart';
import '../services/metadata_writer.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/release_cover_picker.dart';
import '../widgets/track_overflow_menu.dart';

const _kYellow = Color(0xFFFFDB4D);

Future<bool> openReleaseMetadataEditor(
  BuildContext context,
  ArtistRelease release,
) async {
  final result = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ReleaseMetadataEditorScreen(release: release),
    ),
  );
  return result ?? false;
}

List<TrackMenuAction> releaseMenuActions(
  BuildContext context,
  ArtistRelease release, {
  VoidCallback? onSaved,
}) {
  final cover = releaseCoverMenuAction(context, release);
  return [
    releaseMetadataAction(context, release, onSaved: onSaved),
    ?cover,
  ];
}

TrackMenuAction releaseMetadataAction(
  BuildContext context,
  ArtistRelease release, {
  VoidCallback? onSaved,
}) {
  return TrackMenuAction(
    icon: Icons.edit_outlined,
    label: 'Метаданные',
    onSelected: () async {
      final ok = await openReleaseMetadataEditor(context, release);
      if (ok) onSaved?.call();
    },
  );
}

class ReleaseMetadataEditorScreen extends StatefulWidget {
  const ReleaseMetadataEditorScreen({super.key, required this.release});

  final ArtistRelease release;

  @override
  State<ReleaseMetadataEditorScreen> createState() =>
      _ReleaseMetadataEditorScreenState();
}

class _ReleaseMetadataEditorScreenState
    extends State<ReleaseMetadataEditorScreen> {
  late final TextEditingController _album;
  late final TextEditingController _albumArtist;
  late final TextEditingController _trackTotal;
  late final TextEditingController _year;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;
  String? _progress;

  Uint8List? _newCoverBytes;
  String? _newCoverMime;
  bool _removeCover = false;

  @override
  void initState() {
    super.initState();
    final release = widget.release;
    _album = TextEditingController(text: metaFieldText(release.title));
    _albumArtist = TextEditingController(
      text: metaFieldText(
        formatArtists(releaseAlbumArtists(release).join(', ')),
      ),
    );
    final total = _initialTrackTotal(release);
    _trackTotal = TextEditingController(
      text: total == null ? '' : '$total',
    );
    final year = release.year;
    _year = TextEditingController(
      text: (year == null || year <= 0) ? '' : '$year',
    );
  }

  int? _initialTrackTotal(ArtistRelease release) {
    var total = 0;
    for (final track in release.tracks) {
      final value = track.trackTotal;
      if (value != null && value > total) total = value;
    }
    if (total < 1) total = release.tracks.length;
    return total < 1 ? null : total;
  }

  @override
  void dispose() {
    _album.dispose();
    _albumArtist.dispose();
    _trackTotal.dispose();
    _year.dispose();
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
    if (bytes == null || bytes.isEmpty || !mounted) return;
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

  int? _parseOptional(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final tracks = widget.release.tracks;
    if (tracks.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
      _progress = null;
    });

    final album = _album.text;
    final albumArtist = _albumArtist.text;
    final year = _parseOptional(_year.text);
    final trackTotal = _parseOptional(_trackTotal.text);
    final library = context.read<LibraryService>();
    final player = context.read<PlayerService>();

    try {
      for (var i = 0; i < tracks.length; i++) {
        if (!mounted) return;
        setState(() => _progress = '${i + 1} из ${tracks.length}');
        final track = tracks[i];
        final draft = MetadataDraft.fromTrack(track)
          ..album = album
          ..albumArtist = albumArtist
          ..year = year
          ..trackTotal = trackTotal
          ..coverBytes = _newCoverBytes
          ..coverMime = _newCoverMime
          ..removeCover = _removeCover;
        final updated = await library.saveTrackMetadata(
          track,
          draft,
          refreshLibrary: false,
          notify: false,
        );
        player.syncTrack(updated, oldTrackKey: track.trackKey);
      }
      await library.reload();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      try {
        await library.reload();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _saving = false;
        _progress = null;
        _error = e.toString();
      });
    }
  }

  Future<void> _copyName() async {
    final artist = _albumArtist.text.trim();
    final album = _album.text.trim();
    final text = [
      if (artist.isNotEmpty) artist,
      if (album.isNotEmpty) album,
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
    final release = widget.release;
    final count = release.tracks.length;
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
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${releaseKindLabel(release.kind)} · ${metaFieldText(release.title)}',
                          style: GoogleFonts.figtree(
                            color: AppTheme.paper,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _progress == null
                              ? 'Запишется во все $count ${_tracksWord(count)}'
                              : 'Запись $_progress',
                          style: GoogleFonts.figtree(
                            color: AppTheme.paperMuted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _CoverEditor(
                          existingPath: release.coverPath,
                          newBytes: _newCoverBytes,
                          removed: _removeCover,
                          onPick: _saving ? null : _pickCover,
                          onClear: _saving ? null : _clearCover,
                        ),
                        const SizedBox(height: 28),
                        _field(_albumArtist, 'Исполнитель альбома'),
                        _field(
                          _trackTotal,
                          'Всего треков',
                          keyboard: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: _positiveOrEmpty,
                        ),
                        _field(
                          _year,
                          'Год',
                          keyboard: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          validator: _yearOrEmpty,
                        ),
                        _field(_album, 'Альбом'),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: GoogleFonts.figtree(
                              color: const Color(0xFFFF8A80),
                              fontSize: 13,
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

  String? _positiveOrEmpty(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null || value < 1) return 'Число больше нуля';
    return null;
  }

  String? _yearOrEmpty(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null || value < 1 || value > 9999) return 'Год от 1 до 9999';
    return null;
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    final radius = BorderRadius.circular(14);
    final idle = BorderSide(color: AppTheme.paper.withValues(alpha: 0.08));
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        enabled: !_saving,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        validator: validator,
        cursorColor: _kYellow,
        style: GoogleFonts.figtree(
          color: AppTheme.paper,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.figtree(
            color: AppTheme.paperMuted,
            fontWeight: FontWeight.w500,
          ),
          floatingLabelStyle: GoogleFonts.figtree(
            color: AppTheme.mossBright,
            fontWeight: FontWeight.w600,
          ),
          filled: true,
          fillColor: AppTheme.inkLift.withValues(alpha: 0.92),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(borderRadius: radius, borderSide: idle),
          enabledBorder:
              OutlineInputBorder(borderRadius: radius, borderSide: idle),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: const BorderSide(color: _kYellow, width: 1.4),
          ),
        ),
      ),
    );
  }
}

String _tracksWord(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return 'трек';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return 'трека';
  }
  return 'треков';
}

class _CoverEditor extends StatelessWidget {
  const _CoverEditor({
    required this.existingPath,
    required this.newBytes,
    required this.removed,
    required this.onPick,
    required this.onClear,
  });

  final String? existingPath;
  final Uint8List? newBytes;
  final bool removed;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    Widget image = const ColoredBox(
      color: AppTheme.inkLift,
      child: Icon(Icons.album, size: 64, color: AppTheme.mossBright),
    );
    if (!removed) {
      if (newBytes != null) {
        image = Image.memory(newBytes!, fit: BoxFit.cover);
      } else if (existingPath != null && File(existingPath!).existsSync()) {
        image = Image.file(File(existingPath!), fit: BoxFit.cover);
      }
    }
    final hasCover = !removed &&
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
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(width: 160, height: 160, child: image),
            ),
            const SizedBox(width: 18),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CoverButton(
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: 'Загрузить',
                  filled: true,
                  onPressed: onPick,
                ),
                const SizedBox(height: 10),
                _CoverButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: 'Удалить',
                  filled: false,
                  onPressed: hasCover ? onClear : null,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _CoverButton extends StatelessWidget {
  const _CoverButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final Widget icon;
  final String label;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final style = filled
        ? FilledButton.styleFrom(
            backgroundColor: _kYellow,
            foregroundColor: Colors.black,
            disabledBackgroundColor: _kYellow.withValues(alpha: 0.35),
            disabledForegroundColor: Colors.black54,
            enabledMouseCursor: SystemMouseCursors.click,
            disabledMouseCursor: SystemMouseCursors.basic,
          )
        : OutlinedButton.styleFrom(
            foregroundColor: AppTheme.paper,
            side: BorderSide(color: AppTheme.paper.withValues(alpha: 0.2)),
            disabledForegroundColor: AppTheme.paperMuted,
            enabledMouseCursor: SystemMouseCursors.click,
            disabledMouseCursor: SystemMouseCursors.basic,
          );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.figtree(fontWeight: FontWeight.w700),
        ),
      ],
    );
    if (filled) {
      return FilledButton(style: style, onPressed: onPressed, child: child);
    }
    return OutlinedButton(style: style, onPressed: onPressed, child: child);
  }
}
