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
import '../widgets/screen_title.dart';
import '../widgets/track_cover_play.dart';
import '../widgets/track_meta_links.dart';
import '../utils/trash_actions.dart';
import '../widgets/track_tile.dart';
import 'genres_screen.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  static const _yellow = Color(0xFFFFDB4D);

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final system = _systemPlaylists(library.playlists);
    final mine = library.playlists.where((p) => !p.isSystem).toList();
    final genres = library.tracksByGenre();
    final missingCount = library.tracksMissingMetadata().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenTitle(
          title: 'Плейлисты',
          trailing: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _yellow,
              foregroundColor: Colors.black,
              shape: const StadiumBorder(),
              textStyle: GoogleFonts.figtree(fontWeight: FontWeight.w800),
            ),
            onPressed: () => _create(context),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Создать'),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 48),
            children: [
              _SectionTitle(
                title: 'Системные',
                onTap: () => _openGrid(
                  context,
                  title: 'Системные',
                  items: [
                    for (final pl in system)
                      _itemForPlaylist(
                        context,
                        pl,
                        count: pl.isIncomplete ? missingCount : pl.trackCount,
                      ),
                  ],
                ),
              ),
              _CoverCarousel(
                items: [
                  for (final pl in system)
                    _itemForPlaylist(
                      context,
                      pl,
                      count: pl.isIncomplete ? missingCount : pl.trackCount,
                    ),
                ],
              ),
              _SectionTitle(
                title: 'Мои',
                onTap: mine.isEmpty
                    ? null
                    : () => _openGrid(
                          context,
                          title: 'Мои',
                          items: [
                            for (final pl in mine)
                              _itemForPlaylist(
                                context,
                                pl,
                                count: pl.trackCount,
                                onRename: () => _rename(context, pl),
                                onDelete: () => library.deletePlaylist(pl.id),
                              ),
                          ],
                        ),
              ),
              if (mine.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    'Своих плейлистов пока нет.',
                    style: GoogleFonts.figtree(color: AppTheme.paperMuted),
                  ),
                )
              else
                _CoverCarousel(
                  items: [
                    for (final pl in mine)
                      _itemForPlaylist(
                        context,
                        pl,
                        count: pl.trackCount,
                        onRename: () => _rename(context, pl),
                        onDelete: () => library.deletePlaylist(pl.id),
                      ),
                  ],
                ),
              if (genres.isNotEmpty) ...[
                _SectionTitle(
                  title: 'Жанры',
                  onTap: () => _openGrid(
                    context,
                    title: 'Жанры',
                    items: [
                      for (final entry in genres.entries)
                        _itemForGenre(context, entry.key, entry.value),
                    ],
                  ),
                ),
                _CoverCarousel(
                  items: [
                    for (final entry in genres.entries)
                      _itemForGenre(context, entry.key, entry.value),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Playlist> _systemPlaylists(List<Playlist> playlists) {
    final system = playlists.where((p) => p.isSystem).toList()
      ..sort((a, b) {
        int rank(Playlist p) {
          if (p.isNew) return 0;
          if (p.isIncomplete) return 1;
          if (p.isTrash) return 2;
          return 3;
        }

        return rank(a).compareTo(rank(b));
      });
    return system;
  }

  void _openGrid(
    BuildContext context, {
    required String title,
    required List<_CoverItem> items,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PlaylistGridScreen(title: title, items: items),
      ),
    );
  }

  _CoverItem _itemForPlaylist(
    BuildContext context,
    Playlist playlist, {
    required int count,
    VoidCallback? onRename,
    VoidCallback? onDelete,
  }) {
    return _CoverItem(
      title: playlist.name,
      kind: playlist.isSystem ? 'Системный' : 'Плейлист',
      meta: _playlistMeta(playlist, count),
      coverPath: playlist.coverPath,
      icon: _systemIcon(playlist),
      iconColor: _systemIconColor(playlist),
      onOpen: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
          ),
        );
      },
      onRename: playlist.isSystem ? null : onRename,
      onDelete: playlist.isSystem ? null : onDelete,
    );
  }

  _CoverItem _itemForGenre(
    BuildContext context,
    String name,
    List<Track> tracks,
  ) {
    String? cover;
    for (final track in tracks) {
      final path = track.coverPath;
      if (path != null && path.isNotEmpty) {
        cover = path;
        break;
      }
    }
    return _CoverItem(
      title: name,
      kind: 'Жанр',
      meta: _tracksLabel(tracks.length),
      coverPath: cover,
      icon: Icons.library_music,
      iconColor: AppTheme.mossBright,
      onOpen: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GenreDetailScreen(genre: name, tracks: tracks),
          ),
        );
      },
    );
  }

  String _playlistMeta(Playlist playlist, int count) {
    if (playlist.isTrash) {
      return count == 0 ? 'Пусто' : '$count удалённых';
    }
    if (playlist.isNew) {
      return count == 0
          ? 'Пока пусто'
          : '$count за ${Playlist.newTrackDays} дн.';
    }
    if (playlist.isIncomplete) {
      return count == 0 ? 'Всё заполнено' : '$count без метаданных';
    }
    return _tracksLabel(count);
  }

  String _tracksLabel(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return '$count трек';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return '$count трека';
    }
    return '$count треков';
  }

  IconData _systemIcon(Playlist playlist) {
    if (playlist.isTrash) return Icons.delete_outline_rounded;
    if (playlist.isNew) return Icons.fiber_new_rounded;
    if (playlist.isIncomplete) return Icons.article_outlined;
    return Icons.queue_music;
  }

  Color _systemIconColor(Playlist playlist) {
    if (playlist.isTrash) return AppTheme.paperMuted;
    if (playlist.isNew) return _yellow;
    if (playlist.isIncomplete) return AppTheme.lime;
    return AppTheme.mossBright;
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

class _CoverItem {
  const _CoverItem({
    required this.title,
    required this.kind,
    required this.meta,
    required this.onOpen,
    this.coverPath,
    this.icon,
    this.iconColor,
    this.onRename,
    this.onDelete,
  });

  final String title;
  final String kind;
  final String meta;
  final String? coverPath;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback onOpen;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      child: InkWell(
        mouseCursor:
            onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Text(
              title,
              style: GoogleFonts.syne(
                color: AppTheme.paper,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppTheme.paperMuted),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoverCarousel extends StatefulWidget {
  const _CoverCarousel({required this.items});

  final List<_CoverItem> items;

  @override
  State<_CoverCarousel> createState() => _CoverCarouselState();
}

class _CoverCarouselState extends State<_CoverCarousel> {
  final _controller = ScrollController();
  bool _canBack = false;
  bool _canForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrows());
  }

  @override
  void didUpdateWidget(covariant _CoverCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncArrows());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncArrows);
    _controller.dispose();
    super.dispose();
  }

  void _syncArrows() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final back = pos.pixels > 4;
    final forward = pos.pixels < pos.maxScrollExtent - 4;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  void _page(bool forward) {
    if (!_controller.hasClients) return;
    final delta = forward ? 320.0 : -320.0;
    final target = (_controller.offset + delta)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  static const _coverSize = 148.0;
  static const _arrowSize = 40.0;

  @override
  Widget build(BuildContext context) {
    final arrowTop = (_coverSize - _arrowSize) / 2;
    return SizedBox(
      height: 236,
      child: Stack(
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _syncArrows();
              return false;
            },
            child: ListView.separated(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: widget.items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                return _CoverCard(item: widget.items[index]);
              },
            ),
          ),
          if (_canBack)
            Positioned(
              left: 4,
              top: arrowTop,
              child: _CarouselArrow(
                forward: false,
                onPressed: () => _page(false),
              ),
            ),
          if (_canForward)
            Positioned(
              right: 4,
              top: arrowTop,
              child: _CarouselArrow(
                forward: true,
                onPressed: () => _page(true),
              ),
            ),
        ],
      ),
    );
  }
}

class _CarouselArrow extends StatelessWidget {
  const _CarouselArrow({required this.forward, required this.onPressed});

  final bool forward;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = forward
        ? const Icon(
            Icons.chevron_right_rounded,
            size: 28,
            color: Color(0xFF1A1A1A),
          )
        : const Icon(
            Icons.chevron_left_rounded,
            size: 28,
            color: Color(0xFF1A1A1A),
          );
    return Material(
      color: Colors.white.withValues(alpha: 0.82),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        mouseCursor: SystemMouseCursors.click,
        onTap: onPressed,
        child: SizedBox(width: 40, height: 40, child: Center(child: icon)),
      ),
    );
  }
}

class _CoverCard extends StatelessWidget {
  const _CoverCard({required this.item, this.width = 148});

  final _CoverItem item;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final path = item.coverPath;
    Widget cover = ColoredBox(
      color: AppTheme.inkLift,
      child: Icon(
        item.icon ?? Icons.queue_music,
        color: item.iconColor ?? AppTheme.mossBright,
        size: 40,
      ),
    );
    if (path != null && File(path).existsSync()) {
      cover = Image.file(File(path), fit: BoxFit.cover);
    }

    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: item.onOpen,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(aspectRatio: 1, child: cover),
                  ),
                ),
                if (item.onRename != null || item.onDelete != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: PopupMenuButton<String>(
                      tooltip: 'Ещё',
                      color: AppTheme.inkLift,
                      icon: const Icon(
                        Icons.more_horiz,
                        color: Colors.white,
                        size: 20,
                      ),
                      onSelected: (value) {
                        if (value == 'rename') item.onRename?.call();
                        if (value == 'delete') item.onDelete?.call();
                      },
                      itemBuilder: (_) => [
                        if (item.onRename != null)
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Переименовать'),
                          ),
                        if (item.onDelete != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Удалить'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.figtree(
                color: AppTheme.paper,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.kind,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.figtree(
                color: AppTheme.paperMuted,
                fontSize: 12,
              ),
            ),
            Text(
              item.meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.figtree(
                color: AppTheme.paperMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistGridScreen extends StatelessWidget {
  const _PlaylistGridScreen({required this.title, required this.items});

  final String title;
  final List<_CoverItem> items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      appBar: AppBar(
        backgroundColor: AppTheme.ink,
        title: Text(
          title,
          style: GoogleFonts.syne(fontWeight: FontWeight.w700),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 18,
          crossAxisSpacing: 14,
          childAspectRatio: 0.62,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          return _CoverCard(item: items[index], width: null);
        },
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
    final isIncomplete = pl.isIncomplete;
    final isSystem = pl.isSystem;

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: FutureBuilder<List<Track>>(
        future: _future,
        builder: (context, snapshot) {
          final tracks = isIncomplete
              ? library.tracksMissingMetadata()
              : [
                  for (final t in snapshot.data ?? const <Track>[])
                    library.trackByKey(t.trackKey) ?? t,
                ];
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
                  playlist: isIncomplete
                      ? pl.copyWith(trackCount: tracks.length)
                      : pl,
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
              if (!isIncomplete &&
                  snapshot.connectionState != ConnectionState.done)
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
                              : isIncomplete
                                  ? 'Треков с пустыми метаданными нет.'
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
                        onTrash: (isNew || isIncomplete)
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
              return library.trackMatchesQuery(t, query);
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
    final isIncomplete = playlist.isIncomplete;
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
                          : isIncomplete
                              ? 'Альбом, артист альбома, год, номер или число треков не заполнены'
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
                  : isIncomplete
                      ? '${playlist.trackCount} без метаданных'
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
      Playlist.kindIncomplete => Icons.article_outlined,
      _ => Icons.queue_music,
    };
    final iconColor = switch (kind) {
      Playlist.kindTrash => AppTheme.paperMuted,
      Playlist.kindNew => const Color(0xFFFFDB4D),
      Playlist.kindIncomplete => AppTheme.lime,
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
                ] else if (widget.onTrash != null)
                  IconButton(
                    tooltip: 'В корзину',
                    onPressed: widget.onTrash,
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  )
                else if (widget.onRemove != null)
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
