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
    this.isPdf = false,
    this.showPageTurn = true,
    this.showBrightness = true,
  });

  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;
  final bool isPdf;
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

        const _SectionLabel('Page texture'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final texture in PageTexture.values)
              _PillButton(
                label: texture.label,
                selected: settings.texture == texture,
                onTap: () => onChanged(settings.copyWith(texture: texture)),
              ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          settings.texture.description,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),

        if (isPdf) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.brass.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.brass.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 16,
                  color: AppColors.brass,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'PDF pages have pre-formatted fixed layout. Themes, textures, page turns, margins, and pinch-zoom apply directly to PDFs.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ] else ...[
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
        ],

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

        if (!isPdf)
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
            divisions: 26,
            display: '${(settings.brightness * 100).round()}%',
            onChanged: (value) =>
                onChanged(settings.copyWith(brightness: value)),
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8A6A45),
        ),
      ),
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
    final border = selected
        ? Border.all(color: AppColors.brass, width: 1.4)
        : Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65));

    final background = selected
        ? AppColors.brass.withValues(alpha: 0.16)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);

    final textColor = selected
        ? (theme.brightness == Brightness.dark
            ? AppColors.cream
            : AppColors.leather)
        : theme.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: border,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: textColor,
          ),
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
    return Row(
      children: [
        for (final theme in ReaderTheme.values) ...[
          Expanded(
            child: _ThemeChip(
              theme: theme,
              selected: settings.theme == theme,
              onTap: () => onChanged(settings.copyWith(theme: theme)),
            ),
          ),
          if (theme != ReaderTheme.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final ReaderTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = paletteFor(theme);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: palette.page,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.brass : palette.rule,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: AppColors.brass.withValues(alpha: 0.35),
                blurRadius: 8,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Column(
          children: [
            Text(
              'Aa',
              style: TextStyle(
                fontFamily: kSerif,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              theme.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: palette.muted,
              ),
            ),
          ],
        ),
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text(
              display,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.brass,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: AppColors.brass,
            thumbColor: AppColors.brass,
            inactiveTrackColor:
                Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
