import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/equalizer_state.dart';
import '../services/player_service.dart';

const _kYellow = Color(0xFFFFDB4D);
const _kCard = Color(0xFF1C1C1C);
const _kCardLift = Color(0xFF2A2A2A);
const _kTrack = Color(0xFF4A4A4A);

/// Floating graphic EQ card styled like Yandex Music.
class EqualizerPanel extends StatefulWidget {
  const EqualizerPanel({super.key});

  @override
  State<EqualizerPanel> createState() => _EqualizerPanelState();
}

class _EqualizerPanelState extends State<EqualizerPanel> {
  bool _presetsOpen = false;

  void _togglePresets() {
    setState(() => _presetsOpen = !_presetsOpen);
  }

  void _closePresets() {
    if (!_presetsOpen) return;
    setState(() => _presetsOpen = false);
  }

  Future<void> _pickPreset(String id) async {
    _closePresets();
    if (id == EqualizerPresets.customId) return;
    await context.read<PlayerService>().applyEqualizerPreset(id);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final eq = player.equalizer;
    final presetLabel = EqualizerPresets.displayName(eq.presetId);
    final eqWidth = MediaQuery.sizeOf(context).width < 520 ? 420.0 : 460.0;
    // Ширина растёт влево при открытых пресетах — Align(right) держит EQ на месте.
    final panelWidth = _presetsOpen ? 300 + 12 + eqWidth : eqWidth;

    return SizedBox(
      width: panelWidth,
      // Высота пресетов при открытии — EQ прижат к низу и не подпрыгивает.
      height: _presetsOpen ? 420 : null,
      child: Stack(
        alignment: Alignment.bottomRight,
        clipBehavior: Clip.none,
        children: [
          if (_presetsOpen)
            Positioned(
              left: 0,
              bottom: 0,
              child: SizedBox(
                width: 300,
                height: 420,
                child: _SoundSettingsCard(
                  selectedId: eq.presetId,
                  onClose: _closePresets,
                  onPick: _pickPreset,
                ),
              ),
            ),
          SizedBox(
            width: eqWidth,
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 16, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Эквалайзер',
                              style: GoogleFonts.figtree(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Switch(
                            value: eq.enabled,
                            onChanged: player.setEqualizerEnabled,
                            activeThumbColor: Colors.black,
                            activeTrackColor: _kYellow,
                            inactiveThumbColor: const Color(0xFFB0B0B0),
                            inactiveTrackColor: const Color(0xFF3A3A3A),
                            trackOutlineColor: const WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                            mouseCursor: SystemMouseCursors.click,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 210,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 40,
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _scaleLabel('12dB'),
                                  _scaleLabel('0dB'),
                                  _scaleLabel('-12dB'),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _EqSlider(
                                      label: 'уровень',
                                      value: eq.level,
                                      enabled: eq.enabled,
                                      onChanged: player.setEqualizerLevel,
                                    ),
                                  ),
                                  for (var i = 0;
                                      i < EqualizerState.bandCount;
                                      i++)
                                    Expanded(
                                      child: _EqSlider(
                                        label: EqualizerState.bandLabels[i],
                                        value: eq.bands[i],
                                        enabled: eq.enabled,
                                        onChanged: (v) =>
                                            player.setEqualizerBand(i, v),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _togglePresets,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 6, 4, 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    presetLabel,
                                    style: GoogleFonts.figtree(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _presetsOpen
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: const Color(0xFFB0B0B0),
                                  size: 22,
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
            ),
          ),
        ],
      ),
    );
  }

  static Widget _scaleLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.figtree(
        color: const Color(0xFF9A9A9A),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _SoundSettingsCard extends StatelessWidget {
  const _SoundSettingsCard({
    required this.selectedId,
    required this.onClose,
    required this.onPick,
  });

  final String selectedId;
  final VoidCallback onClose;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final entries = <({String id, String name})>[
      if (selectedId == EqualizerPresets.customId)
        (id: EqualizerPresets.customId, name: EqualizerPresets.customName),
      for (final preset in EqualizerPresets.all)
        (id: preset.id, name: preset.name),
    ];

    return Material(
      color: _kCard,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      elevation: 12,
      shadowColor: Colors.black,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Настройки звука',
                    style: GoogleFonts.figtree(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  mouseCursor: SystemMouseCursors.click,
                  onPressed: onClose,
                  icon: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: _kCardLift,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final selected = entry.id == selectedId;
                return Material(
                  color: selected ? _kCardLift : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    mouseCursor: SystemMouseCursors.click,
                    onTap: () => onPick(entry.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Text(
                        entry.name,
                        style: GoogleFonts.figtree(
                          color: Colors.white,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EqSlider extends StatelessWidget {
  const _EqSlider({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                activeTrackColor: _kTrack,
                inactiveTrackColor: _kTrack,
                thumbColor: _kCard,
                overlayColor: _kYellow.withValues(alpha: 0.15),
                thumbShape: const _EqThumbShape(),
                trackShape: const RectangularSliderTrackShape(),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                min: EqualizerState.minDb,
                max: EqualizerState.maxDb,
                value: value.clamp(EqualizerState.minDb, EqualizerState.maxDb),
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.figtree(
            color: const Color(0xFF9A9A9A),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _EqThumbShape extends SliderComponentShape {
  const _EqThumbShape();

  static const _radius = 7.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size.fromRadius(_radius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter? labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final enabled = enableAnimation.value > 0.5;
    canvas.drawCircle(
      center,
      _radius,
      Paint()..color = enabled ? _kCard : const Color(0xFF3A3A3A),
    );
    canvas.drawCircle(
      center,
      _radius,
      Paint()
        ..color = enabled ? _kYellow : const Color(0xFF9A9A9A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
