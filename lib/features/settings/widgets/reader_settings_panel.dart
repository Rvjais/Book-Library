import 'package:flutter/material.dart';

import '../../../core/app_theme.dart';
import '../../../data/reader_settings.dart';

/// Shared typography + page-turn controls used by the reader sheet and the
/// settings screen.
class ReaderSettingsPanel extends StatelessWidget {
  const ReaderSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    this.showPageTurn = true,
    this.showBrightness = true,
  });

  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;
  final bool showPageTurn;
  final bool showBrightness;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionLabel('Page theme'),
        _ThemeRow(settings: settings, onChanged: onChanged),
        const SizedBox(height: 18),
        const _SectionLabel('Typeface'),
        Row(
          children: [
            _PillButton(
              label: 'Serif',
              selected: settings.serif,
              onTap: () => onChanged(settings.copyWith(serif: true)),
            ),
            const SizedBox(width: 8),
            _PillButton(
              label: 'Sans serif',
              selected: !settings.serif,
              onTap: () => onChanged(settings.copyWith(serif: false)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SliderRow(
          label: 'Text size',
          value: settings.fontSize,
          min: 13,
          max: 32,
          divisions: 19,
          display: '${settings.fontSize.round()}',
          onChanged: (value) => onChanged(settings.copyWith(fontSize: value)),
        ),
        _SliderRow(
          label: 'Line spacing',
          value: settings.lineHeight,
          min: 1.15,
          max: 2.4,
          divisions: 25,
          display: settings.lineHeight.toStringAsFixed(2),
          onChanged: (value) => onChanged(settings.copyWith(lineHeight: value)),
        ),
        _SliderRow(
          label: 'Margins',
          value: settings.margins,
          min: 8,
          max: 64,
          divisions: 28,
          display: '${settings.margins.round()}',
          onChanged: (value) => onChanged(settings.copyWith(margins: value)),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Justify text', style: TextStyle(fontSize: 14)),
          value: settings.justify,
          onChanged: (value) => onChanged(settings.copyWith(justify: value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Show page numbers', style: TextStyle(fontSize: 14)),
          value: settings.showPageNumber,
          onChanged: (value) =>
              onChanged(settings.copyWith(showPageNumber: value)),
        ),
        if (showPageTurn) ...[
          const SizedBox(height: 12),
          const _SectionLabel('Page turn'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final style in PageTurnStyle.values)
                _PillButton(
                  label: style.label,
                  selected: settings.turnStyle == style,
                  onTap: () => onChanged(settings.copyWith(turnStyle: style)),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            settings.turnStyle.description,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (showBrightness) ...[
          const SizedBox(height: 14),
          _SliderRow(
            label: 'Dim the page',
            value: settings.brightness,
            min: 0,
            max: 0.65,
            divisions: 13,
            display: '${(settings.brightness * 100).round()}%',
            onChanged: (value) =>
                onChanged(settings.copyWith(brightness: value)),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.settings, required this.onChanged});

  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final option in ReaderTheme.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onChanged(settings.copyWith(theme: option)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 42,
                      decoration: BoxDecoration(
                        color: paletteFor(option).page,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: settings.theme == option
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline
                                  .withValues(alpha: 0.5),
                          width: settings.theme == option ? 2 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Aa',
                        style: serifStyle(
                          fontSize: 15,
                          color: paletteFor(option).text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: settings.theme == option
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Text(
              display,
              style: TextStyle(
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: display,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.6)
                  : theme.colorScheme.outline.withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
