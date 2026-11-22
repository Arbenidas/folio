import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/finance_models.dart';
import '../controllers/finance_controller.dart';

/// Clean monochrome icon badge with thin-stroke Lucide icons, subtle neutral
/// fill, and a crisp hairline border so cards stay calm and free of rainbow noise.
class FolioIconBadge extends StatelessWidget {
  const FolioIconBadge({
    super.key,
    required this.icon,
    this.tint,
    this.size = 36,
    this.iconSize = 17,
    this.borderRadius = 10,
    this.colored = false,
  });

  final IconData icon;
  final Color? tint;
  final double size;
  final double iconSize;
  final double borderRadius;
  final bool colored;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final fg = (colored && tint != null) ? tint! : colors.onSurfaceVariant;
    final bg = (colored && tint != null)
        ? tint!.withValues(alpha: 0.10)
        : palette.innerBg;
    final border = (colored && tint != null)
        ? tint!.withValues(alpha: 0.22)
        : palette.border;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: border, width: 1),
      ),
      child: Icon(icon, size: iconSize, color: fg),
    );
  }
}

/// Tactile Bento card primitive with subtle hover lift, clean neutral border,
/// and optional tap interaction. Safe inside `IntrinsicHeight`.
class FolioInteractiveBento extends StatefulWidget {
  const FolioInteractiveBento({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 16,
    this.backgroundColor,
    this.borderColor,
    this.hoverAccent,
    this.enableHover = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? hoverAccent;
  final bool enableHover;

  @override
  State<FolioInteractiveBento> createState() => _FolioInteractiveBentoState();
}

class _FolioInteractiveBentoState extends State<FolioInteractiveBento> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final interactive = widget.onTap != null;
    final activeHover = widget.enableHover && _hovered;
    final baseBg = widget.backgroundColor ?? palette.cardBg;
    final baseBorder = widget.borderColor ?? palette.border;

    final effectiveBorder = activeHover
        ? Color.lerp(baseBorder, colors.onSurfaceVariant, 0.35)!
        : baseBorder;

    final dy = _pressed
        ? 0.0
        : (activeHover ? (interactive ? -1.5 : -0.5) : 0.0);

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, dy, 0),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: baseBg,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: effectiveBorder, width: 1.0),
        boxShadow: activeHover
            ? [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: palette.isDark ? 0.14 : 0.05,
                  ),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: widget.child,
    );

    if (interactive) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: content,
      );
    }

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: content,
    );
  }
}

/// Subtle hoverable row wrapper for list items (transactions, recurring rows, sidebar nodes).
class FolioHoverRow extends StatefulWidget {
  const FolioHoverRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    this.borderRadius = 11,
    this.selected = false,
    this.selectedColor,
    this.hoverColor,
    this.borderColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool selected;
  final Color? selectedColor;
  final Color? hoverColor;
  final Color? borderColor;

  @override
  State<FolioHoverRow> createState() => _FolioHoverRowState();
}

class _FolioHoverRowState extends State<FolioHoverRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bg = widget.selected
        ? (widget.selectedColor ??
              colors.secondaryContainer.withValues(alpha: 0.9))
        : _hovered
        ? (widget.hoverColor ??
              colors.surfaceContainerHighest.withValues(alpha: 0.55))
        : Colors.transparent;

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: widget.borderColor != null
                ? Border.all(color: widget.borderColor!)
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class FinanceBentoCard extends StatelessWidget {
  const FinanceBentoCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.hoverAccent,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final VoidCallback? onTap;
  final Color? hoverAccent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 520;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    return FolioInteractiveBento(
      onTap: onTap,
      hoverAccent: hoverAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact && trailing != null) ...[
            titleBlock,
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: trailing!),
          ] else
            Row(
              children: [
                Expanded(child: titleBlock),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class FinanceFlowComparisonBar extends StatelessWidget {
  const FinanceFlowComparisonBar({
    super.key,
    required this.label,
    required this.value,
    required this.ratio,
    required this.color,
  });

  final String label;
  final String value;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: colors.surfaceContainerHighest,
            color: color,
          ),
        ),
      ],
    );
  }
}

class FinanceMiniStatChip extends StatelessWidget {
  const FinanceMiniStatChip({
    super.key,
    required this.label,
    required this.value,
    required this.dotColor,
  });

  final String label;
  final String value;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: palette.innerBg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class FinanceDateBadgeChip extends StatelessWidget {
  const FinanceDateBadgeChip({
    super.key,
    required this.label,
    required this.urgent,
    this.isPayment = false,
  });

  final String label;
  final bool urgent;
  final bool isPayment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7.5, vertical: 3),
      decoration: BoxDecoration(
        color: palette.innerBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class FinanceFilterPill extends StatelessWidget {
  const FinanceFilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colors.secondaryContainer
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colors.onSecondaryContainer : colors.onSurface,
          ),
        ),
      ),
    );
  }
}

class FinanceTransactionRow extends StatefulWidget {
  const FinanceTransactionRow({
    super.key,
    required this.tx,
    required this.controller,
    required this.onTap,
    this.showDate = true,
  });

  final FinanceTransaction tx;
  final FinanceController controller;
  final VoidCallback onTap;
  final bool showDate;

  @override
  State<FinanceTransactionRow> createState() => _FinanceTransactionRowState();
}

class _FinanceTransactionRowState extends State<FinanceTransactionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final controller = widget.controller;
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final cat = controller.categoryById(tx.categoryId);
    final acc = controller.accountById(tx.accountId);
    final toAcc = controller.accountById(tx.toAccountId);
    final isTransfer = tx.kind == TransactionKind.transfer;
    final tint = isTransfer
        ? palette.accent
        : palette.adaptiveHex(cat?.colorHex ?? '#706B60');
    final title = tx.note.isNotEmpty
        ? tx.note
        : isTransfer
        ? 'Transferencia'
        : (cat?.name ?? 'Movimiento');
    final primaryMeta = isTransfer
        ? '${acc?.name ?? ''} → ${toAcc?.name ?? ''}'
        : (cat?.name ?? 'General');
    final subtitleText = widget.showDate
        ? '$primaryMeta · ${FinanceFormat.shortDate(tx.date)}'
        : primaryMeta;

    final signedAmount = switch (tx.kind) {
      TransactionKind.expense => -(tx.amount + tx.feeAmount),
      TransactionKind.income => tx.amount,
      TransactionKind.transfer => tx.amount,
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8.5),
          decoration: BoxDecoration(
            color: _hovered
                ? colors.surfaceContainerHigh.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              FolioIconBadge(
                icon: isTransfer
                    ? LucideIcons.arrowLeftRight
                    : FinanceFormat.categoryIcon(cat?.iconKey ?? 'tag'),
                tint: tint,
                size: 34,
                iconSize: 16,
                borderRadius: 10,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        if (tx.recurringId != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5.5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: palette.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'Fijo',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: palette.accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isTransfer &&
                  acc != null &&
                  MediaQuery.sizeOf(context).width >= 520) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 112),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7.5,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: palette.border),
                    ),
                    child: Text(
                      acc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    FinanceFormat.money(
                      signedAmount,
                      symbol: controller.currencySymbol,
                      hide: controller.hideBalances,
                      showSign: !isTransfer,
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tx.kind == TransactionKind.income
                          ? palette.positive
                          : isTransfer
                          ? palette.accent
                          : colors.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (tx.feeAmount > 0)
                    Text(
                      'incl. ${FinanceFormat.money(tx.feeAmount, symbol: controller.currencySymbol, hide: controller.hideBalances)} com.',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: palette.warning,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
