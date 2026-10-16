import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../utils/duration_format.dart';
import '../utils/image_pick.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/listen_actions.dart';
import '../widgets/pill_segmented.dart';
import '../widgets/screen_title.dart';
import '../widgets/track_cover_play.dart';
import '../widgets/track_meta_links.dart';
import '../utils/trash_actions.dart';
import '../widgets/track_tile.dart';
import 'genres_screen.dart';

enum _PlaylistsSection {
  mine,
  genres,
}

extension on _PlaylistsSection {
  String get label => switch (this) {
        _PlaylistsSection.mine => 'Мои плейлисты',
        _PlaylistsSection.genres => 'Плейлисты по жанрам',
      };
}

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  static const _yellow = Color(0xFFFFDB4D);

  _PlaylistsSection _section = _PlaylistsSection.mine;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenTitle(
          title: 'Плейлисты',
          trailing: _section == _PlaylistsSection.mine
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _yellow,
                    foregroundColor: Colors.black,
                    shape: const StadiumBorder(),
                    textStyle: GoogleFonts.figtree(fontWeight: FontWeight.w800),
                  ),
                  onPressed: () => _create(context),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Создать'),
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: PillSegmented<_PlaylistsSection>(
              segments: [
                for (final s in _PlaylistsSection.values)
                  PillSegment(value: s, label: s.label),
              ],
              selected: _section,
              onChanged: (s) => setState(() => _section = s),
            ),
          ),
        ),
        Expanded(
          child: switch (_section) {
            _PlaylistsSection.mine => _MyPlaylistsBody(
                playlists: library.playlists,
                onRename: (pl) => _rename(context, pl),
                onDelete: (pl) => library.deletePlaylist(pl.id),
              ),
            _PlaylistsSection.genres => _GenrePlaylistsBody(
                genres: library.tracksByGenre(),
                isEmpty: library.isEmpty,
              ),
          },
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final library = context.read<LibraryService>();
    final name = await _askName(context, title: 'Новый плейлист');
    if (name == null || name.trim().isEmpty) return;
    await library.createPlaylist(name);
  }

  Future<void> _rename(BuildContext context, Playlist pl) async {
    final library = context.read<LibraryService>();
    final name = await _askName(
      context,
      title: 'Переименовать',
      initial: pl.name,
    );
    if (name == null || name.trim().isEmpty) return;
    await library.renamePlaylist(pl.id, name);
  }

  Future<String?> _askName(
    BuildContext context, {
    required String title,
    String? initial,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Название'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _MyPlaylistsBody extends StatelessWidget {
  const _MyPlaylistsBody({
    required this.playlists,
    required this.onRename,
    required this.onDelete,
  });

  final List<Playlist> playlists;
  final ValueChanged<Playlist> onRename;
  final ValueChanged<Playlist> onDelete;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return Center(
        child: Text(
          'Плейлистов пока нет.',
          style: GoogleFonts.figtree(color: AppTheme.paperMuted),
        ),
      );
    }

    // System playlists stay pinned: Новинки, then Корзина, then user lists.
    final pinned = playlists.where((p) => p.isSystem).toList()
      ..sort((a, b) {
        int rank(Playlist p) => p.isNew ? 0 : (p.isTrash ? 1 : 2);
        return rank(a).compareTo(rank(b));
      });
    final rest = playlists.where((p) => !p.isSystem).toList();
    final ordered = [...pinned, ...rest];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: ordered.length,
      itemBuilder: (context, index) {
        final pl = ordered[index];
        return _PlaylistCard(
          playlist: pl,
          onOpen: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlaylistDetailScreen(playlistId: pl.id),
              ),
            );
          },
          onRename: () => onRename(pl),
          onDelete: () => onDelete(pl),
        );
      },
    );
  }
}

class _GenrePlaylistsBody extends StatelessWidget {
  const _GenrePlaylistsBody({
    required this.genres,
    required this.isEmpty,
  });

  final Map<String, List<Track>> genres;
  final bool isEmpty;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) {
      return Center(
        child: Text(
          'Нет треков. Сканируйте папку music в Настройках.',
          style: GoogleFonts.figtree(color: AppTheme.paperMuted),
        ),
      );
    }

    if (genres.isEmpty) {
      return Center(
        child: Text(
          'Жанров пока нет.',
          style: GoogleFonts.figtree(color: AppTheme.paperMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: genres.length,
      itemBuilder: (context, index) {
        final name = genres.keys.elementAt(index);
        final tracks = genres[name]!;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GenreDetailScreen(
                    genre: name,
                    tracks: tracks,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: const SizedBox(
                      width: 64,
                      height: 64,
                      child: ColoredBox(
                        color: AppTheme.inkLift,
                        child: Icon(
                          Icons.library_music,
                          color: AppTheme.mossBright,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.figtree(
                            color: AppTheme.paper,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${tracks.length} треков',
                          style: GoogleFonts.figtree(
                            color: AppTheme.paperMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppTheme.paperMuted,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final Playlist playlist;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isTrash = playlist.isTrash;
    final isNew = playlist.isNew;
    Widget cover = ColoredBox(
      color: AppTheme.inkLift,
      child: Icon(
        isTrash
            ? Icons.delete_outline_rounded
            : isNew
                ? Icons.fiber_new_rounded
                : Icons.queue_music,
        color: isTrash
            ? AppTheme.paperMuted
            : isNew
                ? const Color(0xFFFFDB4D)
                : AppTheme.mossBright,
        size: 28,
      ),
    );
    final path = playlist.coverPath;
    if (path != null && File(path).existsSync()) {
      cover = Image.file(File(path), fit: BoxFit.cover);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(width: 64, height: 64, child: cover),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.figtree(
                        color: AppTheme.paper,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isTrash
                          ? (playlist.trackCount == 0
                              ? 'Пусто'
                              : '${playlist.trackCount} удалённых')
                          : isNew
                              ? (playlist.trackCount == 0
                                  ? 'Пока пусто'
                                  : '${playlist.trackCount} за ${Playlist.newTrackDays} дн.')
                              : '${playlist.trackCount} треков',
                      style: GoogleFonts.figtree(
                        color: AppTheme.paperMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (!playlist.isSystem)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') onRename();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text('Переименовать'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final int playlistId;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  Future<List<Track>>? _future;
  String _query = '';
  int? _lastTrackCount;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??=
        context.read<LibraryService>().playlistTracks(widget.playlistId);
  }

  void _reload() {
    setState(() {
      _future =
          context.read<LibraryService>().playlistTracks(widget.playlistId);
    });
  }

  Playlist? _playlist(LibraryService library) {
    for (final p in library.playlists) {
      if (p.id == widget.playlistId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final player = context.read<PlayerService>();
    final pl = _playlist(library);
    if (pl == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Плейлист удалён')),
      );
    }

    if (_lastTrackCount != null && _lastTrackCount != pl.trackCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    _lastTrackCount = pl.trackCount;

    final dateLabel = DateFormat.MMMd().format(pl.lastTouched);
    final isTrash = pl.isTrash;
    final isNew = pl.isNew;
    final isSystem = pl.isSystem;

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: FutureBuilder<List<Track>>(
        future: _future,
        builder: (context, snapshot) {
          final tracks = snapshot.data ?? const <Track>[];
          final filtered = _query.trim().isEmpty
              ? tracks
              : tracks
                  .where((t) => t.matchesQuery(_query))
                  .toList(growable: false);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppTheme.ink.withValues(alpha: 0.92),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: Text(
                  pl.name,
                  style: GoogleFonts.syne(fontWeight: FontWeight.w700),
                ),
                actions: [
                  if (!isSystem)
                    TextButton(
                      onPressed: () => _addTrack(context),
                      child: Text(
                        'Добавить трек',
                        style: GoogleFonts.figtree(
                          color: AppTheme.paperMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              SliverToBoxAdapter(
                child: _PlaylistHeader(
                  playlist: pl,
                  dateLabel: dateLabel,
                  onListen: tracks.isEmpty
                      ? null
                      : () => player.playTracks(tracks),
                  onShuffle: tracks.isEmpty
                      ? null
                      : () => player.playTracks(tracks, shuffle: true),
                  onEditCover: isSystem
                      ? null
                      : () => _editCover(context, pl),
                  onEditDescription: isSystem
                      ? null
                      : () => _editDescription(context, pl),
                  onRename: isSystem ? null : () => _rename(context, pl),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: GoogleFonts.figtree(color: AppTheme.paper),
                    decoration: InputDecoration(
                      hintText: 'Поиск трека',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: AppTheme.inkLift,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              if (snapshot.connectionState != ConnectionState.done)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (tracks.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text(
                      isTrash
                          ? 'Корзина пуста.'
                          : isNew
                              ? 'Новых треков за ${Playlist.newTrackDays} дней нет.'
                              : 'Плейлист пуст.',
                      style: GoogleFonts.figtree(color: AppTheme.paperMuted),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final track = filtered[index];
                      final playIndex = tracks.indexOf(track);
                      return _PlaylistTrackRow(
                        track: track,
                        isTrash: isTrash,
                        isNew: isNew,
                        onPlay: () => player.playTracks(
                          tracks,
                          startIndex: playIndex < 0 ? 0 : playIndex,
                        ),
                        onRemove: isSystem
                            ? null
                            : () async {
                                await library.removeFromPlaylist(
                                  pl.id,
                                  track.trackKey,
                                );
                                _reload();
                              },
                        onRestore: isTrash
                            ? () async {
                                await restoreTrackFromTrash(context, track);
                                _reload();
                              }
                            : null,
                        onDeleteForever: isTrash
                            ? () async {
                                await deleteTrackForever(context, track);
                                _reload();
                              }
                            : null,
                        onTrash: isNew
                            ? () async {
                                await moveTrackToTrash(context, track);
                                _reload();
                              }
                            : null,
                      );
                    },
                    childCount: filtered.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editCover(BuildContext context, Playlist pl) async {
    final library = context.read<LibraryService>();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.inkLift,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Выбрать обложку'),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
            if (pl.coverPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Убрать обложку'),
                onTap: () => Navigator.pop(context, 'clear'),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'pick') {
      final bytes = await pickImageBytes();
      if (bytes == null || !context.mounted) return;
      await library.setPlaylistCover(pl.id, bytes);
    } else if (action == 'clear') {
      await library.clearPlaylistCover(pl.id);
    }
  }

  Future<void> _editDescription(BuildContext context, Playlist pl) async {
    final library = context.read<LibraryService>();
    final controller = TextEditingController(text: pl.description ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Описание'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Описание плейлиста'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    await library.setPlaylistDescription(pl.id, result);
  }

  Future<void> _rename(BuildContext context, Playlist pl) async {
    final library = context.read<LibraryService>();
    final controller = TextEditingController(text: pl.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Название'),
        content: TextField(
          controller: controller,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await library.renamePlaylist(pl.id, name);
  }

  Future<void> _addTrack(BuildContext context) async {
    final library = context.read<LibraryService>();
    final all = library.tracks;
    if (all.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сначала отсканируйте библиотеку.')),
      );
      return;
    }

    final selected = await showDialog<Track>(
      context: context,
      builder: (context) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setLocal) {
            final filtered = all.where((t) {
              final q = query.toLowerCase();
              if (q.isEmpty) return true;
              return t.displayTitle.toLowerCase().contains(q) ||
                  t.displayArtist.toLowerCase().contains(q);
            }).toList();
            return AlertDialog(
              title: const Text('Добавить трек'),
              content: SizedBox(
                width: 480,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Поиск',
                      ),
                      onChanged: (v) => setLocal(() => query = v),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final t = filtered[index];
                          return TrackTile(
                            track: t,
                            enableMetadataEdit: false,
                            showDuration: false,
                            onTap: () => Navigator.pop(context, t),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected == null) return;
    await library.addToPlaylist(widget.playlistId, selected.trackKey);
    _reload();
  }
}

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader({
    required this.playlist,
    required this.dateLabel,
    required this.onListen,
    required this.onShuffle,
    required this.onEditCover,
    required this.onEditDescription,
    required this.onRename,
  });

  final Playlist playlist;
  final String dateLabel;
  final VoidCallback? onListen;
  final VoidCallback? onShuffle;
  final VoidCallback? onEditCover;
  final VoidCallback? onEditDescription;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final isTrash = playlist.isTrash;
    final isNew = playlist.isNew;
    final cover = _EditableCover(
      path: playlist.coverPath,
      size: wide ? 200 : 160,
      onEdit: onEditCover,
      systemKind: playlist.systemKind,
    );

    final info = Column(
      crossAxisAlignment:
          wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          playlist.isSystem ? 'Системный плейлист' : 'Плейлист',
          style: GoogleFonts.figtree(
            color: AppTheme.paperMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        MouseRegion(
          cursor: onRename != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: onRename,
            child: Text(
              playlist.name,
              textAlign: wide ? TextAlign.left : TextAlign.center,
              style: GoogleFonts.syne(
                color: AppTheme.paper,
                fontSize: wide ? 42 : 30,
                fontWeight: FontWeight.w800,
                height: 1.05,
                letterSpacing: -0.8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        MouseRegion(
          cursor: onEditDescription != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: onEditDescription,
            child: Text(
              (playlist.description == null || playlist.description!.isEmpty)
                  ? (isTrash
                      ? 'Удалённые треки скрыты из библиотеки'
                      : isNew
                          ? 'Автоматически за последние ${Playlist.newTrackDays} дней'
                          : 'Добавить описание...')
                  : playlist.description!,
              textAlign: wide ? TextAlign.left : TextAlign.center,
              style: GoogleFonts.figtree(
                color: AppTheme.paperMuted,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isTrash
              ? '${playlist.trackCount} треков в корзине'
              : isNew
                  ? '${playlist.trackCount} новинок · окно ${Playlist.newTrackDays} дней'
                  : 'Обновлён $dateLabel · ${playlist.trackCount} треков',
          textAlign: wide ? TextAlign.left : TextAlign.center,
          style: GoogleFonts.figtree(
            color: AppTheme.paperMuted.withValues(alpha: 0.8),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 22),
        ListenActions(
          onListen: onListen,
          onShuffle: onShuffle,
          center: !wide,
          extra: [
            if (onRename != null)
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.inkLift,
                  foregroundColor: AppTheme.paper,
                ),
                onPressed: onRename,
                icon: const Icon(Icons.more_horiz),
                tooltip: 'Переименовать',
              ),
          ],
        ),
      ],
    );

    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          const Positioned.fill(
            child: AmbientBackdrop(
              accent: Color(0xFF5A3A6E),
              secondary: Color(0xFF3D2A5C),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      cover,
                      const SizedBox(width: 28),
                      Expanded(child: info),
                    ],
                  )
                : Column(
                    children: [
                      cover,
                      const SizedBox(height: 20),
                      info,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _EditableCover extends StatefulWidget {
  const _EditableCover({
    required this.path,
    required this.size,
    required this.onEdit,
    this.systemKind,
  });

  final String? path;
  final double size;
  final VoidCallback? onEdit;
  final String? systemKind;

  @override
  State<_EditableCover> createState() => _EditableCoverState();
}

class _EditableCoverState extends State<_EditableCover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final kind = widget.systemKind;
    final icon = switch (kind) {
      Playlist.kindTrash => Icons.delete_outline_rounded,
      Playlist.kindNew => Icons.fiber_new_rounded,
      _ => Icons.queue_music,
    };
    final iconColor = switch (kind) {
      Playlist.kindTrash => AppTheme.paperMuted,
      Playlist.kindNew => const Color(0xFFFFDB4D),
      _ => AppTheme.mossBright,
    };
    Widget image = ColoredBox(
      color: AppTheme.inkLift,
      child: Icon(
        icon,
        size: widget.size * 0.35,
        color: iconColor,
      ),
    );
    if (widget.path != null && File(widget.path!).existsSync()) {
      image = Image.file(File(widget.path!), fit: BoxFit.cover);
    }

    final editable = widget.onEdit != null;

    return MouseRegion(
      onEnter: editable ? (_) => setState(() => _hover = true) : null,
      onExit: editable ? (_) => setState(() => _hover = false) : null,
      cursor: editable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onEdit,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              if (editable && _hover) ...[
                ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
                const Center(
                  child: Icon(
                    Icons.edit_outlined,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistTrackRow extends StatefulWidget {
  const _PlaylistTrackRow({
    required this.track,
    required this.onPlay,
    this.isTrash = false,
    this.isNew = false,
    this.onRemove,
    this.onRestore,
    this.onDeleteForever,
    this.onTrash,
  });

  final Track track;
  final VoidCallback onPlay;
  final bool isTrash;
  final bool isNew;
  final VoidCallback? onRemove;
  final VoidCallback? onRestore;
  final VoidCallback? onDeleteForever;
  final VoidCallback? onTrash;

  @override
  State<_PlaylistTrackRow> createState() => _PlaylistTrackRowState();
}

class _PlaylistTrackRowState extends State<_PlaylistTrackRow> {
  bool _hover = false;

  String? get _newAgeLabel {
    final at = widget.track.addedAt;
    if (at == null) return null;
    final days = DateTime.now().difference(at).inDays;
    if (days <= 0) return 'сегодня';
    if (days == 1) return 'вчера';
    return '$days дн. назад';
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final age = _newAgeLabel;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          onTap: widget.onPlay,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                TrackCoverPlay(
                  path: track.coverPath,
                  onPlay: widget.onPlay,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TrackMetaLinks(
                        track: track,
                        titleStyle: GoogleFonts.figtree(
                          color: AppTheme.paper,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        artistStyle: GoogleFonts.figtree(
                          color: AppTheme.paperMuted,
                          fontSize: 13,
                        ),
                      ),
                      if (widget.isNew && age != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Добавлен $age',
                          style: GoogleFonts.figtree(
                            color: const Color(0xFFFFDB4D).withValues(alpha: 0.85),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.isTrash) ...[
                  IconButton(
                    tooltip: 'Восстановить',
                    onPressed: widget.onRestore,
                    icon: const Icon(Icons.restore_rounded, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Удалить файл',
                    onPressed: widget.onDeleteForever,
                    icon: Icon(
                      Icons.delete_forever_rounded,
                      size: 20,
                      color: Colors.redAccent.shade100,
                    ),
                  ),
                ] else if (widget.isNew)
                  IconButton(
                    tooltip: 'В корзину',
                    onPressed: widget.onTrash,
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  )
                else
                  IconButton(
                    tooltip: 'Убрать',
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                  ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    formatTrackDuration(track.durationMs),
                    textAlign: TextAlign.right,
                    style: GoogleFonts.figtree(
                      color: AppTheme.paperMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
