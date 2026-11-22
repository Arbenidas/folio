import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/finance_models.dart';
import '../controllers/finance_controller.dart';
import '../widgets/finance_dialogs.dart';
import '../widgets/finance_shared_widgets.dart';

class FinanceRecurringView extends StatelessWidget {
  const FinanceRecurringView({
    super.key,
    required this.controller,
    this.onBudgetWarning,
  });

  final FinanceController controller;
  final void Function(String message)? onBudgetWarning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final hide = controller.hideBalances;
    final sym = controller.currencySymbol;
    final monthKey = FinanceFormat.monthKey(controller.selectedMonth);

    final incomes = controller.recurring
        .where((r) => r.kind == TransactionKind.income)
        .toList();
    final expenses = controller.recurring
        .where((r) => r.kind == TransactionKind.expense)
        .toList();

    final totalIncome = controller.monthlyRecurringIncome;
    final totalExpense = controller.monthlyRecurringExpenses;
    final net = totalIncome - totalExpense;
    final appliedCount = controller.recurring
        .where((r) => r.lastAppliedMonth == monthKey)
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1020),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Bento KPI Summary Strip
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 700;
                  final tiles = [
                    _RecurringKpiTile(
                      icon: LucideIcons.arrowDownLeft,
                      label: 'Ingresos fijos',
                      value: FinanceFormat.money(
                        totalIncome,
                        symbol: sym,
                        hide: hide,
                        showSign: totalIncome > 0,
                      ),
                      sub:
                          '${incomes.length} ${incomes.length == 1 ? 'ingreso' : 'ingresos'}',
                      tint: palette.positive,
                    ),
                    _RecurringKpiTile(
                      icon: LucideIcons.arrowUpRight,
                      label: 'Gastos fijos',
                      value: FinanceFormat.money(
                        totalExpense > 0 ? -totalExpense : 0,
                        symbol: sym,
                        hide: hide,
                        showSign: totalExpense > 0,
                      ),
                      sub:
                          '${expenses.length} ${expenses.length == 1 ? 'gasto' : 'gastos'}',
                      tint: palette.negative,
                    ),
                    _RecurringKpiTile(
                      icon: LucideIcons.circleCheck,
                      label: 'Neto recurrente',
                      value: FinanceFormat.money(
                        net,
                        symbol: sym,
                        hide: hide,
                        showSign: true,
                      ),
                      sub: controller.recurring.isEmpty
                          ? 'Sin registros'
                          : '$appliedCount/${controller.recurring.length} aplicados este mes',
                      tint: net >= 0 ? palette.accent : palette.warning,
                    ),
                  ];

                  if (wide) {
                    return Row(
                      children: [
                        for (var i = 0; i < tiles.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Expanded(child: tiles[i]),
                        ],
                      ],
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < tiles.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        tiles[i],
                      ],
                    ],
                  );
                },
              ),

              const SizedBox(height: 16),

              // 2. Action Bar
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Toca cualquier tarjeta para editar día, cuenta o monto',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: () => unawaited(
                      showFinanceRecurringDialog(
                        context,
                        controller: controller,
                      ),
                    ),
                    child: const Text(
                      '+ Nuevo recurrente',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              if (controller.recurring.isEmpty)
                FolioInteractiveBento(
                  enableHover: false,
                  padding: const EdgeInsets.all(36),
                  child: Column(
                    children: [
                      Icon(
                        LucideIcons.calendarClock,
                        size: 34,
                        color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sin gastos o ingresos recurrentes',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Registra tu salario, suscripciones, alquiler o internet para aplicarlos cada mes en un clic.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                if (incomes.isNotEmpty) ...[
                  _GroupHeading(
                    title: 'Ingresos fijos',
                    count: '${incomes.length}',
                    tint: palette.positive,
                  ),
                  const SizedBox(height: 10),
                  _buildBentoGrid(
                    context,
                    items: incomes,
                    monthKey: monthKey,
                    colors: colors,
                    palette: palette,
                    sym: sym,
                    hide: hide,
                  ),
                  const SizedBox(height: 22),
                ],
                if (expenses.isNotEmpty) ...[
                  _GroupHeading(
                    title: 'Gastos fijos',
                    count: '${expenses.length}',
                    tint: palette.accent,
                  ),
                  const SizedBox(height: 10),
                  _buildBentoGrid(
                    context,
                    items: expenses,
                    monthKey: monthKey,
                    colors: colors,
                    palette: palette,
                    sym: sym,
                    hide: hide,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBentoGrid(
    BuildContext context, {
    required List<RecurringPayment> items,
    required String monthKey,
    required ColorScheme colors,
    required FinancePalette palette,
    required String sym,
    required bool hide,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 740 ? 2 : 1;
        const gap = 12.0;
        final cardW = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final rec in items)
              SizedBox(
                width: cardW,
                child: _buildRecurringCard(
                  context,
                  rec: rec,
                  monthKey: monthKey,
                  colors: colors,
                  palette: palette,
                  sym: sym,
                  hide: hide,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildRecurringCard(
    BuildContext context, {
    required RecurringPayment rec,
    required String monthKey,
    required ColorScheme colors,
    required FinancePalette palette,
    required String sym,
    required bool hide,
  }) {
    final isIncome = rec.kind == TransactionKind.income;
    final applied = rec.lastAppliedMonth == monthKey;
    final cat = controller.categoryById(rec.categoryId);
    final acc = controller.accountById(rec.accountId);
    final tint = isIncome
        ? palette.positive
        : palette.adaptiveHex(cat?.colorHex ?? '#C97B4B');

    return FolioInteractiveBento(
      hoverAccent: tint,
      padding: const EdgeInsets.all(15),
      borderRadius: 15,
      onTap: () => unawaited(
        showFinanceRecurringDialog(
          context,
          controller: controller,
          existing: rec,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: tint.withValues(alpha: 0.28)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'DÍA',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    color: tint,
                  ),
                ),
                Text(
                  '${rec.dayOfMonth}',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rec.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${cat?.name ?? 'General'} · ${acc?.name ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                FinanceFormat.money(
                  isIncome ? rec.amount : -rec.amount,
                  symbol: sym,
                  hide: hide,
                  showSign: true,
                ),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isIncome ? palette.positive : colors.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (applied)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: palette.positive.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.check,
                            size: 12,
                            color: palette.positive,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Aplicado',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: palette.positive,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(7),
                      onPressed: () {
                        final warn = controller.applyRecurringToSelectedMonth(
                          rec,
                        );
                        if (warn != null) onBudgetWarning?.call(warn);
                      },
                      child: Text(
                        'Aplicar',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  CupertinoButton(
                    padding: const EdgeInsets.all(4),
                    minimumSize: Size.zero,
                    onPressed: () => controller.deleteRecurring(rec.id),
                    child: Icon(
                      LucideIcons.trash2,
                      size: 14.5,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecurringKpiTile extends StatelessWidget {
  const _RecurringKpiTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FolioInteractiveBento(
      hoverAccent: tint,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      borderRadius: 16,
      child: Row(
        children: [
          FolioIconBadge(
            icon: icon,
            tint: tint,
            size: 36,
            iconSize: 17,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeading extends StatelessWidget {
  const _GroupHeading({
    required this.title,
    required this.count,
    required this.tint,
  });

  final String title;
  final String count;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
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
      ],
    );
  }
}
