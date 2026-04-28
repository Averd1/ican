// Usage:
//
//   AudioDescriptionTile(
//     key: ValueKey(item.id),
//     timestamp: item.timestamp,
//     description: item.text,
//     isImportant: item.isImportant,
//     onReplay: () => _ttsService.speak(item.text),
//     onMarkImportant: () => _markImportant(item),
//     onDismiss: () => _removeItem(item),
//   )
//
// In a ListView:
//
//   ListView.separated(
//     itemCount: descriptions.length,
//     separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
//     itemBuilder: (context, i) {
//       final item = descriptions[i];
//       return AudioDescriptionTile(
//         key: ValueKey(item.id),
//         timestamp: item.timestamp,
//         description: item.text,
//         isImportant: item.isImportant,
//         onReplay: () => _replay(item),
//         onMarkImportant: () => _toggleImportant(item),
//         onDismiss: () => _dismiss(item),
//       );
//     },
//   )

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../core/theme.dart';

class AudioDescriptionTile extends StatelessWidget {
  final DateTime timestamp;
  final String description;
  final bool isImportant;
  final VoidCallback onReplay;
  final VoidCallback onMarkImportant;
  final VoidCallback onDismiss;

  const AudioDescriptionTile({
    super.key,
    required this.timestamp,
    required this.description,
    required this.isImportant,
    required this.onReplay,
    required this.onMarkImportant,
    required this.onDismiss,
  });

  String get _formattedTime {
    final h = timestamp.hour;
    final m = timestamp.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $period';
  }

  // SemanticLabel: combines all content into a single screen-reader phrase.
  // "Double-tap to replay" comes from the hint, not the label, so
  // VoiceOver reads: label → hint in sequence.
  String get _semanticLabel {
    final important = isImportant ? 'Important. ' : '';
    return '$important$_formattedTime. $description';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dismissible(
      key: ValueKey('dismiss_${timestamp.microsecondsSinceEpoch}'),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          HapticFeedback.mediumImpact();
          onMarkImportant();
          return false;
        }
        if (direction == DismissDirection.endToStart) {
          HapticFeedback.heavyImpact();
          onDismiss();
          return true;
        }
        return false;
      },
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: isDark ? const Color(0xFF1A3A1A) : const Color(0xFFE8F5E9),
        icon: Icons.star,
        label: 'Important',
        iconColor: AppColors.warning,
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: isDark ? const Color(0xFF3A1A1A) : const Color(0xFFFFEBEE),
        icon: Icons.delete_outline,
        label: 'Dismiss',
        iconColor: AppColors.error,
      ),
      child: _TileContent(
        formattedTime: _formattedTime,
        description: description,
        isImportant: isImportant,
        isDark: isDark,
        semanticLabel: _semanticLabel,
        onReplay: onReplay,
        onMarkImportant: onMarkImportant,
        onDismiss: onDismiss,
      ),
    );
  }
}

class _TileContent extends StatelessWidget {
  final String formattedTime;
  final String description;
  final bool isImportant;
  final bool isDark;
  final String semanticLabel;
  final VoidCallback onReplay;
  final VoidCallback onMarkImportant;
  final VoidCallback onDismiss;

  const _TileContent({
    required this.formattedTime,
    required this.description,
    required this.isImportant,
    required this.isDark,
    required this.semanticLabel,
    required this.onReplay,
    required this.onMarkImportant,
    required this.onDismiss,
  });

  void _handleLongPress(BuildContext context) {
    Clipboard.setData(ClipboardData(text: description));
    HapticFeedback.lightImpact();
    SemanticsService.announce('Copied', TextDirection.ltr);
  }

  @override
  Widget build(BuildContext context) {
    final Color bg = isDark
        ? AppColors.surfaceCardDark
        : AppColors.surfaceCardLight;
    final Color border = isDark ? AppColors.borderDark : AppColors.textOnLight;
    final Color primaryText = isDark
        ? AppColors.textOnDark
        : AppColors.textOnLight;
    final Color secondaryText = isDark
        ? AppColors.textSecondaryOnDark
        : AppColors.textSecondaryOnLight;
    final Color interactive = isDark
        ? AppColors.interactiveOnDark
        : AppColors.interactive;

    return Semantics(
      label: semanticLabel,
      hint: 'Double-tap to replay. Long press to copy.',
      button: false,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Replay description'): onReplay,
        const CustomSemanticsAction(label: 'Mark as important'):
            onMarkImportant,
        const CustomSemanticsAction(label: 'Dismiss'): onDismiss,
        CustomSemanticsAction(label: 'Copy to clipboard'): () =>
            _handleLongPress(context),
      },
      child: GestureDetector(
        onLongPress: () => _handleLongPress(context),
        onTap: () {
          HapticFeedback.mediumImpact();
          onReplay();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 80),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 1),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTimestampRow(secondaryText),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16.sp,
                          color: primaryText,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                _ReplayButton(color: interactive),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimestampRow(Color secondaryText) {
    return Row(
      children: [
        if (isImportant) ...[
          // ACCESSIBILITY NOTE: star icon is supplementary — the word
          // "Important" carries the meaning for screen readers.
          Icon(Icons.star, color: AppColors.warning, size: 18),
          const SizedBox(width: 4),
          Text(
            'Important',
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        Text(
          formattedTime,
          style: TextStyle(fontSize: 13.sp, color: secondaryText),
        ),
      ],
    );
  }
}

class _ReplayButton extends StatelessWidget {
  final Color color;

  const _ReplayButton({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.replay, color: color, size: 22),
            Text(
              'Replay',
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;
  final Color iconColor;

  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alignment == Alignment.centerRight) ...[
            Text(
              label,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Icon(icon, color: iconColor, size: 24),
          if (alignment == Alignment.centerLeft) ...[
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
