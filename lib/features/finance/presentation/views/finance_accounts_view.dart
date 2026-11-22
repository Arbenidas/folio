import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/finance_models.dart';
import '../controllers/finance_controller.dart';
import '../widgets/finance_dialogs.dart';
import '../widgets/finance_shared_widgets.dart';

class FinanceAccountsView extends StatelessWidget {
  const FinanceAccountsView({
    super.key,
    required this.controller,
    required this.onPayOffAccount,
  });

  final FinanceController controller;
  final ValueChanged<FinanceAccount> onPayOffAccount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final hide = controller.hideBalances;
    final sym = controller.currencySymbol;

    final liquidAccounts = controller.accounts
        .where((a) => !a.isDebtAccount)
        .toList();
    final debtAccounts = controller.accounts
        .where((a) => a.isDebtAccount)
        .toList();
    final netWorth = controller.liquidBalance - controller.totalDebt;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 64),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. UNIFIED MODERN HERO BENTO CARD (Net Liquidity + Metrics + Inline Actions)
              FolioInteractiveBento(
                enableHover: false,
                padding: const EdgeInsets.all(22),
                borderRadius: 22,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 680;
                    final actions = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ActionPillButton(
                          icon: LucideIcons.arrowLeftRight,
                          label: 'Transferir',
                          onTap: () => unawaited(
                            showFinanceTransactionDialog(
                              context,
                              controller: controller,
                              initialKind: TransactionKind.transfer,
                            ),
                          ),
                        ),
                        CupertinoButton.filled(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8.5,
                          ),
                          minimumSize: Size.zero,
                          borderRadius: BorderRadius.circular(10),
                          onPressed: () => unawaited(
                            showFinanceAccountDialog(
                              context,
                              controller: controller,
                            ),
                          ),
                          child: const Text(
                            '+ Nueva cuenta',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    );

                    final heroTitle = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Disponible hoy',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          FinanceFormat.money(
                            controller.liquidBalance,
                            symbol: sym,
                            hide: hide,
                          ),
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.9,
                            color: controller.liquidBalance > 0
                                ? palette.positive
                                : colors.onSurface,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    );

                    final metricStrip = Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: palette.innerBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: palette.border),
                      ),
                      child: wide
                          ? Row(
                              children: [
                                Expanded(
                                  child: _HeroMetricCell(
                                    label: 'Por pagar',
                                    value: FinanceFormat.money(
                                      controller.totalDebt,
                                      symbol: sym,
                                      hide: hide,
                                    ),
                                    color: controller.totalDebt > 0
                                        ? palette.negative
                                        : palette.positive,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 30,
                                  color: palette.border,
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 16),
                                    child: _HeroMetricCell(
                                      label: 'Cupo libre',
                                      value: FinanceFormat.money(
                                        controller.totalAvailableCredit,
                                        symbol: sym,
                                        hide: hide,
                                      ),
                                      color: palette.positive,
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 30,
                                  color: palette.border,
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 16),
                                    child: _HeroMetricCell(
                                      label: 'Patrimonio neto',
                                      value: FinanceFormat.money(
                                        netWorth,
                                        symbol: sym,
                                        hide: hide,
                                        showSign: netWorth < 0,
                                      ),
                                      color: netWorth >= 0
                                          ? palette.positive
                                          : palette.negative,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Wrap(
                              spacing: 20,
                              runSpacing: 10,
                              children: [
                                _HeroMetricCell(
                                  label: 'Por pagar',
                                  value: FinanceFormat.money(
                                    controller.totalDebt,
                                    symbol: sym,
                                    hide: hide,
                                  ),
                                  color: controller.totalDebt > 0
                                      ? palette.negative
                                      : palette.positive,
                                ),
                                _HeroMetricCell(
                                  label: 'Cupo libre',
                                  value: FinanceFormat.money(
                                    controller.totalAvailableCredit,
                                    symbol: sym,
                                    hide: hide,
                                  ),
                                  color: palette.positive,
                                ),
                                _HeroMetricCell(
                                  label: 'Patrimonio neto',
                                  value: FinanceFormat.money(
                                    netWorth,
                                    symbol: sym,
                                    hide: hide,
                                    showSign: netWorth < 0,
                                  ),
                                  color: netWorth >= 0
                                      ? palette.positive
                                      : palette.negative,
                                ),
                              ],
                            ),
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: heroTitle),
                              actions,
                            ],
                          )
                        else ...[
                          heroTitle,
                          const SizedBox(height: 12),
                          actions,
                        ],
                        const SizedBox(height: 16),
                        metricStrip,
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 22),

              // 2. MODERN 2-COLUMN EDITORIAL SPLIT (Efectivo y banco | Tarjetas y líneas)
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoCol = constraints.maxWidth >= 820;

                  final liquidSection = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionHeader(
                        title: 'Efectivo y banco',
                        count: '${liquidAccounts.length}',
                        trailing: FinanceFormat.money(
                          controller.liquidBalance,
                          symbol: sym,
                          hide: hide,
                        ),
                        trailingColor: controller.liquidBalance > 0
                            ? palette.positive
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 10),
                      if (liquidAccounts.isEmpty)
                        FolioInteractiveBento(
                          enableHover: false,
                          padding: const EdgeInsets.all(20),
                          borderRadius: 18,
                          child: Text(
                            'Agrega tu efectivo o cuenta bancaria.',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: palette.cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: palette.border),
                          ),
                          child: Column(
                            children: [
                              for (var i = 0; i < liquidAccounts.length; i++) ...[
                                if (i > 0)
                                  Divider(
                                    height: 1,
                                    indent: 66,
                                    endIndent: 18,
                                    color: palette.border.withValues(alpha: 0.6),
                                  ),
                                _buildLiquidLedgerRow(
                                  context,
                                  liquidAccounts[i],
                                  colors,
                                  palette,
                                  sym,
                                  hide,
                                  isFirst: i == 0,
                                  isLast: i == liquidAccounts.length - 1,
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  );

                  final debtSection = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionHeader(
                        title: 'Tarjetas y líneas',
                        count: '${debtAccounts.length}',
                        trailing: FinanceFormat.money(
                          controller.totalDebt,
                          symbol: sym,
                          hide: hide,
                        ),
                        trailingColor: controller.totalDebt > 0
                            ? palette.negative
                            : palette.positive,
                      ),
                      const SizedBox(height: 10),
                      if (debtAccounts.isEmpty)
                        FolioInteractiveBento(
                          enableHover: false,
                          padding: const EdgeInsets.all(20),
                          borderRadius: 18,
                          child: Text(
                            'Sin tarjetas ni líneas de crédito activas.',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        Column(
                          children: [
                            for (var i = 0; i < debtAccounts.length; i++) ...[
                              if (i > 0) const SizedBox(height: 12),
                              _buildDebtCard(
                                context,
                                debtAccounts[i],
                                colors,
                                palette,
                                sym,
                                hide,
                              ),
                            ],
                          ],
                        ),
                    ],
                  );

                  if (twoCol) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: liquidSection),
                        const SizedBox(width: 18),
                        Expanded(flex: 6, child: debtSection),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      liquidSection,
                      const SizedBox(height: 22),
                      debtSection,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiquidLedgerRow(
    BuildContext context,
    FinanceAccount acc,
    ColorScheme colors,
    FinancePalette palette,
    String sym,
    bool hide, {
    required bool isFirst,
    required bool isLast,
  }) {
    final bal = controller.balanceOfAccount(acc.id);
    final kindLabel = switch (acc.kind) {
      AccountKind.cash => 'Efectivo',
      AccountKind.debit => 'Débito',
      AccountKind.savings => 'Ahorro',
      _ => 'Cuenta',
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(20) : Radius.zero,
          bottom: isLast ? const Radius.circular(20) : Radius.zero,
        ),
        onTap: () => unawaited(
          showFinanceAccountDialog(
            context,
            controller: controller,
            existing: acc,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              FolioIconBadge(
                icon: FinanceFormat.accountIcon(acc.kind),
                tint: colors.onSurface,
                size: 40,
                iconSize: 18,
                borderRadius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      acc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kindLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                FinanceFormat.money(bal, symbol: sym, hide: hide),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: bal < 0
                      ? palette.negative
                      : bal > 0
                      ? palette.positive
                      : colors.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                LucideIcons.chevronRight,
                size: 15,
                color: colors.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDebtCard(
    BuildContext context,
    FinanceAccount acc,
    ColorScheme colors,
    FinancePalette palette,
    String sym,
    bool hide,
  ) {
    final debt = controller.debtOfAccount(acc.id);
    final avail = controller.availableLimitOf(acc);
    final isAdvance = acc.kind == AccountKind.salaryAdvance;
    final limit = acc.creditLimit;
    final hasLimit = limit != null && limit > 0;
    final ratio = hasLimit ? (debt / limit).clamp(0.0, 1.0) : 0.0;
    final highUsage = ratio >= 0.8;

    final metaParts = <String>[
      if (acc.statementDay != null) 'Corte ${acc.statementDay}',
      if (acc.paymentDueDay != null)
        isAdvance ? 'Día ${acc.paymentDueDay}' : 'Pago ${acc.paymentDueDay}',
      if (acc.hasTransactionFee)
        '${acc.transactionFeePercent!.toStringAsFixed(acc.transactionFeePercent! % 1 == 0 ? 0 : 1)}%',
    ];

    return FolioInteractiveBento(
      padding: const EdgeInsets.all(20),
      borderRadius: 20,
      borderColor: highUsage
          ? palette.negative.withValues(alpha: 0.45)
          : palette.border,
      onTap: () => unawaited(
        showFinanceAccountDialog(context, controller: controller, existing: acc),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FolioIconBadge(
                icon: FinanceFormat.accountIcon(acc.kind),
                tint: colors.onSurface,
                size: 40,
                iconSize: 18,
                borderRadius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      acc.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    if (metaParts.isNotEmpty)
                      Text(
                        metaParts.join(' · '),
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
              if (debt > 0)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6.5,
                  ),
                  minimumSize: Size.zero,
                  color: palette.innerBg,
                  borderRadius: BorderRadius.circular(9),
                  onPressed: () => onPayOffAccount(acc),
                  child: Text(
                    isAdvance ? 'Liquidar' : 'Pagar',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saldo usado',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      FinanceFormat.money(debt, symbol: sym, hide: hide),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                        color: debt > 0 ? palette.negative : palette.positive,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (hasLimit)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: palette.innerBg,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    '${FinanceFormat.money(avail ?? 0, symbol: sym, hide: hide)} libre',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: palette.positive,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          if (hasLimit) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: colors.surfaceContainerHighest,
                color: highUsage
                    ? palette.negative
                    : colors.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Cupo ${FinanceFormat.money(limit, symbol: sym, hide: hide)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${(ratio * 100).round()}% usado',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: highUsage
                        ? palette.negative
                        : colors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroMetricCell extends StatelessWidget {
  const _HeroMetricCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 17.5,
            fontWeight: FontWeight.w800,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    this.trailing,
    this.trailingColor,
  });

  final String title;
  final String count;
  final String? trailing;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            count,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: trailingColor ?? colors.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

class _ActionPillButton extends StatefulWidget {
  const _ActionPillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_ActionPillButton> createState() => _ActionPillButtonState();
}

class _ActionPillButtonState extends State<_ActionPillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final baseBg = _hovered ? colors.surfaceContainerHighest : palette.innerBg;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: baseBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 15, color: colors.onSurface),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
