import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/finance_models.dart';
import '../controllers/finance_controller.dart';
import '../widgets/finance_charts.dart';
import '../widgets/finance_dialogs.dart';
import '../widgets/finance_shared_widgets.dart';

class FinanceOverviewView extends StatefulWidget {
  const FinanceOverviewView({
    super.key,
    required this.controller,
    required this.onPayOffAccount,
    required this.onOpenDebtPlan,
    required this.onOpenTransactions,
    this.onOpenAccounts,
    this.onOpenBudgets,
    this.onOpenRecurring,
    this.onBudgetWarning,
    this.salaryCardKey,
    this.heroTileKey,
    this.chartTileKey,
    this.debtRadarTileKey,
  });

  final FinanceController controller;
  final ValueChanged<FinanceAccount> onPayOffAccount;
  final VoidCallback onOpenDebtPlan;
  final VoidCallback onOpenTransactions;
  final VoidCallback? onOpenAccounts;
  final VoidCallback? onOpenBudgets;
  final VoidCallback? onOpenRecurring;
  final void Function(String message)? onBudgetWarning;
  final GlobalKey? salaryCardKey;
  final GlobalKey? heroTileKey;
  final GlobalKey? chartTileKey;
  final GlobalKey? debtRadarTileKey;

  @override
  State<FinanceOverviewView> createState() => _FinanceOverviewViewState();
}

class _FinanceOverviewViewState extends State<FinanceOverviewView> {
  FinanceChartKind _chartKind = FinanceChartKind.waterfall;

  FinanceController get _ctrl => widget.controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final hide = _ctrl.hideBalances;
    final sym = _ctrl.currencySymbol;
    final breakdown = _ctrl.monthExpenseBreakdown;
    final daily = _ctrl.dailyMonthExpenses;
    final recent = _ctrl.monthTransactions.take(5).toList();
    final expenseRec = _ctrl.recurring
        .where((r) => r.active && r.kind == TransactionKind.expense)
        .toList();
    final currentMonthKey = FinanceFormat.monthKey(_ctrl.selectedMonth);
    final pendingRec = expenseRec
        .where((r) => r.lastAppliedMonth != currentMonthKey)
        .toList();
    final paidRecCount = expenseRec.length - pendingRec.length;
    final savingsPct = (_ctrl.monthSavingsRate * 100).round();

    final needsSalarySetup =
        _ctrl.primaryBudgetIncome <= 0 && _ctrl.monthIncome <= 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 88),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1140),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (needsSalarySetup) ...[
                _SalaryStarterCard(
                  key: widget.salaryCardKey,
                  controller: _ctrl,
                ),
                const SizedBox(height: 16),
              ],

              // BENTO ROW 1: 3 Clear Daily-Decision Bento Cards
              // 1) Disponible hoy (hasta tu próximo pago)
              // 2) Pendiente de pagar este mes
              // 3) Balance del mes (Entradas vs Salidas)
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 820;
                  final heroTile = _buildAvailableTile(
                    context,
                    colors,
                    palette,
                    sym,
                    hide,
                  );
                  final pendingTile = _buildPendingBillsTile(
                    context,
                    colors,
                    palette,
                    sym,
                    hide,
                    pendingRec,
                    paidRecCount,
                    expenseRec.length,
                  );
                  final flowTile = _buildFlowTile(
                    context,
                    colors,
                    palette,
                    sym,
                    hide,
                    savingsPct,
                  );

                  if (wide) {
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: heroTile),
                          const SizedBox(width: 14),
                          Expanded(child: pendingTile),
                          const SizedBox(width: 14),
                          Expanded(child: flowTile),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      heroTile,
                      const SizedBox(height: 12),
                      pendingTile,
                      const SizedBox(height: 12),
                      flowTile,
                    ],
                  );
                },
              ),

              const SizedBox(height: 16),

              // BENTO ROW 2: Balanced 7:5 Split — Chart + Credit/Advance Lines
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 840;
                  final chartTile = FinanceBentoCard(
                    key: widget.chartTileKey,
                    title: switch (_chartKind) {
                      FinanceChartKind.waterfall => 'Cascada de flujo',
                      FinanceChartKind.pie => 'Distribución por categoría',
                      FinanceChartKind.daily => 'Gasto diario',
                    },
                    subtitle: FinanceFormat.monthTitle(_ctrl.selectedMonth),
                    trailing: CupertinoSlidingSegmentedControl<FinanceChartKind>(
                      groupValue: _chartKind,
                      onValueChanged: (v) {
                        if (v != null) setState(() => _chartKind = v);
                      },
                      children: const {
                        FinanceChartKind.waterfall: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            'Cascada',
                            style: TextStyle(fontSize: 11.5),
                          ),
                        ),
                        FinanceChartKind.pie: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            'Pastel',
                            style: TextStyle(fontSize: 11.5),
                          ),
                        ),
                        FinanceChartKind.daily: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            'Diario',
                            style: TextStyle(fontSize: 11.5),
                          ),
                        ),
                      },
                    ),
                    child: SizedBox(
                      height: 235,
                      child: switch (_chartKind) {
                        FinanceChartKind.waterfall => FinanceWaterfallChart(
                          income: _ctrl.monthIncome,
                          breakdown: breakdown,
                          symbol: sym,
                          hide: hide,
                        ),
                        FinanceChartKind.pie => FinancePieChart(
                          breakdown: breakdown,
                          totalExpense: _ctrl.monthExpense,
                          symbol: sym,
                          hide: hide,
                        ),
                        FinanceChartKind.daily => FinanceDailyChart(
                          values: daily,
                          accent: colors.primary,
                          muted: colors.onSurfaceVariant,
                          gridColor: colors.outlineVariant.withValues(
                            alpha: 0.45,
                          ),
                          symbol: sym,
                          hide: hide,
                        ),
                      },
                    ),
                  );

                  final debtRadarTile = _buildDebtRadarTile(
                    context,
                    colors,
                    palette,
                    sym,
                    hide,
                  );

                  if (wide) {
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 7, child: chartTile),
                          const SizedBox(width: 14),
                          Expanded(flex: 5, child: debtRadarTile),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      chartTile,
                      const SizedBox(height: 14),
                      debtRadarTile,
                    ],
                  );
                },
              ),

              const SizedBox(height: 16),

              // BENTO ROW 3: Recent Activity (7) + Focused Fixed Payments Card (5)
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 840;
                  final recentCard = _buildRecentTile(
                    context,
                    recent: recent,
                    colors: colors,
                    palette: palette,
                    sym: sym,
                    hide: hide,
                  );
                  final fixedCard = _buildFixedPaymentsTile(
                    context,
                    allExpenseRec: expenseRec,
                    pendingRec: pendingRec,
                    paidCount: paidRecCount,
                    colors: colors,
                    palette: palette,
                    sym: sym,
                    hide: hide,
                  );

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: recentCard),
                        const SizedBox(width: 14),
                        Expanded(flex: 5, child: fixedCard),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      recentCard,
                      const SizedBox(height: 14),
                      fixedCard,
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

  // ---------------------------------------------------------------------------
  // Row 1: 3 Simplified Interactive Bento KPI Tiles
  // ---------------------------------------------------------------------------

  Widget _buildAvailableTile(
    BuildContext context,
    ColorScheme colors,
    FinancePalette palette,
    String sym,
    bool hide,
  ) {
    final liquid = _ctrl.liquidBalance;
    final safeToday = _ctrl.safeToSpendToday;
    final availCredit = _ctrl.totalAvailableCredit;
    final nextIncome = _ctrl.nextRecurringIncomeInfo;

    final footer = nextIncome != null
        ? 'Próximo pago día ${nextIncome.dayOfMonth} (${FinanceFormat.countdownLabel(nextIncome.dayOfMonth)})'
        : (availCredit > 0
              ? 'Cupo en tarjetas: ${FinanceFormat.money(availCredit, symbol: sym, hide: hide)}'
              : '${_ctrl.liquidAccounts.length} cuentas');

    return FolioInteractiveBento(
      key: widget.heroTileKey,
      hoverAccent: palette.positive,
      padding: const EdgeInsets.all(18),
      onTap: () => _showAvailableModal(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FolioIconBadge(
                icon: LucideIcons.wallet,
                tint: palette.positive,
                size: 32,
                iconSize: 15,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Disponible hoy',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                LucideIcons.arrowUpRight,
                size: 14,
                color: colors.onSurfaceVariant.withValues(alpha: 0.65),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            FinanceFormat.money(safeToday, symbol: sym, hide: hide),
            style: TextStyle(
              fontSize: 31,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.05,
              color: liquid < 0 ? palette.negative : palette.positive,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  footer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                'Cuentas →',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingBillsTile(
    BuildContext context,
    ColorScheme colors,
    FinancePalette palette,
    String sym,
    bool hide,
    List<RecurringPayment> pendingRec,
    int paidRecCount,
    int totalRecCount,
  ) {
    final pendingTotal = _ctrl.pendingRecurringExpensesThisMonth;
    final paidTotal = _ctrl.paidRecurringExpensesThisMonth;
    final allPaid = pendingRec.isEmpty;
    final tint = allPaid ? palette.positive : palette.warning;
    final nextBill = pendingRec.isNotEmpty ? pendingRec.first : null;

    return FolioInteractiveBento(
      hoverAccent: tint,
      padding: const EdgeInsets.all(18),
      onTap: () => _showFixedPaymentsModal(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FolioIconBadge(
                icon: allPaid
                    ? LucideIcons.circleCheck
                    : LucideIcons.calendarClock,
                tint: tint,
                size: 32,
                iconSize: 15,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Pendiente de pagar',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: palette.innerBg,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  '$paidRecCount/$totalRecCount fijos',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            FinanceFormat.money(pendingTotal, symbol: sym, hide: hide),
            style: TextStyle(
              fontSize: 31,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.05,
              color: allPaid ? palette.positive : palette.negative,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  allPaid
                      ? 'Pagados: ${FinanceFormat.money(paidTotal, symbol: sym, hide: hide)}'
                      : 'Próximo: ${nextBill!.title} (día ${nextBill.dayOfMonth})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                'Fijos →',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFlowTile(
    BuildContext context,
    ColorScheme colors,
    FinancePalette palette,
    String sym,
    bool hide,
    int savingsPct,
  ) {
    final inc = _ctrl.monthIncome;
    final exp = _ctrl.monthExpense;
    final net = _ctrl.monthNet;
    final maxVal = math.max(inc, exp);
    final expRatio = maxVal > 0 ? (exp / maxVal).clamp(0.0, 1.0) : 0.0;
    final netTint = net >= 0 ? palette.positive : palette.negative;

    return FolioInteractiveBento(
      hoverAccent: netTint,
      padding: const EdgeInsets.all(18),
      onTap: () => _showMonthFlowModal(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FolioIconBadge(
                icon: net >= 0
                    ? LucideIcons.trendingUp
                    : LucideIcons.trendingDown,
                tint: netTint,
                size: 32,
                iconSize: 15,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Balance del mes',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              if (inc > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: netTint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${savingsPct >= 0 ? '+' : ''}$savingsPct%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: netTint,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            FinanceFormat.money(net, symbol: sym, hide: hide, showSign: true),
            style: TextStyle(
              fontSize: 31,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.05,
              color: colors.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: expRatio,
              minHeight: 5,
              backgroundColor: colors.surfaceContainerHighest,
              color: exp > inc ? palette.negative : palette.positive,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Entró ${FinanceFormat.money(inc, symbol: sym, hide: hide)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: palette.positive,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Salió ${FinanceFormat.money(exp, symbol: sym, hide: hide)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: palette.negative,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Row 2 Right: Credit & Salary Advance Interactive Cards
  // ---------------------------------------------------------------------------

  Widget _buildDebtRadarTile(
    BuildContext context,
    ColorScheme colors,
    FinancePalette palette,
    String sym,
    bool hide,
  ) {
    final debtAccounts = _ctrl.accounts.where((a) => a.isDebtAccount).toList();

    return FinanceBentoCard(
      key: widget.debtRadarTileKey,
      title: 'Crédito y adelanto',
      subtitle: 'Toca una línea para ver detalle o pagar',
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: widget.onOpenDebtPlan,
        child: Text(
          'Ver plan →',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
      ),
      child: debtAccounts.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Icon(
                    LucideIcons.shieldCheck,
                    size: 26,
                    color: palette.positive,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sin tarjetas ni adelantos registrados',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < debtAccounts.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _buildCompactDebtCard(
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
    );
  }

  Widget _buildCompactDebtCard(
    BuildContext context,
    FinanceAccount acc,
    ColorScheme colors,
    FinancePalette palette,
    String sym,
    bool hide,
  ) {
    final debt = _ctrl.debtOfAccount(acc.id);
    final limit = acc.creditLimit;
    final available = _ctrl.availableLimitOf(acc);
    final ratio = (limit != null && limit > 0)
        ? (debt / limit).clamp(0.0, 1.0)
        : 0.0;
    final isAdvance = acc.kind == AccountKind.salaryAdvance;

    return FolioInteractiveBento(
      onTap: () => _showCreditLineModal(context, acc),
      backgroundColor: palette.innerBg,
      padding: const EdgeInsets.all(13),
      borderRadius: 13,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FinanceFormat.accountIcon(acc.kind),
                size: 15,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  acc.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              if (acc.hasTransactionFee)
                Text(
                  '${acc.transactionFeePercent!.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              const SizedBox(width: 6),
              Icon(
                LucideIcons.chevronRight,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  FinanceFormat.money(debt, symbol: sym, hide: hide),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: debt > 0 ? palette.negative : palette.positive,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${FinanceFormat.money(available ?? 0, symbol: sym, hide: hide)} libre',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: palette.positive,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          if (limit != null && limit > 0) ...[
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 4,
                backgroundColor: colors.surfaceContainerHighest,
                color: palette.negative.withValues(alpha: 0.85),
              ),
            ),
          ],
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  isAdvance && acc.paymentDueDay != null
                      ? 'Día ${acc.paymentDueDay}'
                      : [
                          if (acc.statementDay != null)
                            'Corte ${acc.statementDay}',
                          if (acc.paymentDueDay != null)
                            'Pago ${acc.paymentDueDay}',
                        ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              if (debt > 0)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3.5,
                  ),
                  minimumSize: Size.zero,
                  color: palette.cardBg,
                  borderRadius: BorderRadius.circular(6),
                  onPressed: () => widget.onPayOffAccount(acc),
                  child: Text(
                    isAdvance ? 'Liquidar' : 'Pagar',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Row 3: Recent Transactions + Clean Focused Fixed Payments Card
  // ---------------------------------------------------------------------------

  Widget _buildRecentTile(
    BuildContext context, {
    required List<FinanceTransaction> recent,
    required ColorScheme colors,
    required FinancePalette palette,
    required String sym,
    required bool hide,
  }) {
    return FinanceBentoCard(
      title: 'Últimos movimientos',
      subtitle: recent.isEmpty
          ? null
          : '${_ctrl.monthTransactions.length} en ${FinanceFormat.monthTitle(_ctrl.selectedMonth).toLowerCase()} · Toca uno para editar',
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: widget.onOpenTransactions,
        child: Text(
          'Ver todos →',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
      ),
      child: recent.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Aún no hay movimientos este mes.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: palette.border.withValues(alpha: 0.45),
                    ),
                  FinanceTransactionRow(
                    controller: _ctrl,
                    tx: recent[i],
                    onTap: () => unawaited(
                      showFinanceTransactionDialog(
                        context,
                        controller: _ctrl,
                        existing: recent[i],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildFixedPaymentsTile(
    BuildContext context, {
    required List<RecurringPayment> allExpenseRec,
    required List<RecurringPayment> pendingRec,
    required int paidCount,
    required ColorScheme colors,
    required FinancePalette palette,
    required String sym,
    required bool hide,
  }) {
    final allPaid = allExpenseRec.isNotEmpty && pendingRec.isEmpty;

    return FinanceBentoCard(
      title: 'Pagos fijos',
      subtitle: allExpenseRec.isEmpty
          ? 'Suscripciones y pagos mensuales'
          : '$paidCount/${allExpenseRec.length} cubiertos · ${FinanceFormat.money(_ctrl.monthlyRecurringExpenses, symbol: sym, hide: hide)}',
      onTap: () => _showFixedPaymentsModal(context),
      hoverAccent: allPaid ? palette.positive : palette.accent,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: () => unawaited(
          showFinanceRecurringDialog(context, controller: _ctrl),
        ),
        child: Text(
          '+ Añadir',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
      ),
      child: allExpenseRec.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Registra internet, alquiler o suscripciones para aplicarlos en 1 clic cada mes.',
                style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
              ),
            )
          : allPaid
          ? Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.positive.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: palette.positive.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                children: [
                  FolioIconBadge(
                    icon: LucideIcons.check,
                    tint: palette.positive,
                    size: 36,
                    iconSize: 18,
                    borderRadius: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Todos tus fijos están al día',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Toca aquí para revisar los ${allExpenseRec.length} pagos o editar montos.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: palette.positive,
                  ),
                ],
              ),
            )
          : Column(
              children: [
                for (final rec in pendingRec.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FolioHoverRow(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      onTap: () => unawaited(
                        showFinanceRecurringDialog(
                          context,
                          controller: _ctrl,
                          existing: rec,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: palette.warning.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${rec.dayOfMonth}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: palette.warning,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rec.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurface,
                                  ),
                                ),
                                Text(
                                  _ctrl.accountById(rec.accountId)?.name ?? '',
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
                          Text(
                            FinanceFormat.money(
                              rec.amount,
                              symbol: sym,
                              hide: hide,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(7),
                            onPressed: () {
                              final warn = _ctrl.applyRecurringToSelectedMonth(
                                rec,
                              );
                              if (warn != null) {
                                widget.onBudgetWarning?.call(warn);
                              }
                            },
                            child: Text(
                              'Aplicar',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Interactive Detail Modals triggered when tapping Bento cards directly
  // ---------------------------------------------------------------------------

  Future<void> _showAvailableModal(BuildContext context) async {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final sym = _ctrl.currencySymbol;
    final hide = _ctrl.hideBalances;
    final liquid = _ctrl.liquidAccounts;

    await _showBentoDetailModal(
      context,
      icon: LucideIcons.wallet,
      tint: palette.positive,
      title: 'Detalle de disponible hoy',
      subtitle:
          'Saldo líquido total: ${FinanceFormat.money(_ctrl.liquidBalance, symbol: sym, hide: hide)}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final acc in liquid) ...[
            FolioHoverRow(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(
                  showFinanceAccountDialog(
                    context,
                    controller: _ctrl,
                    existing: acc,
                  ),
                );
              },
              child: Row(
                children: [
                  Icon(
                    FinanceFormat.accountIcon(acc.kind),
                    size: 18,
                    color: palette.adaptiveHex(acc.colorHex),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          acc.name,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                        Text(
                          FinanceFormat.accountKindLabel(acc.kind),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    FinanceFormat.money(
                      _ctrl.balanceOfAccount(acc.id),
                      symbol: sym,
                      hide: hide,
                    ),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
      actions: [
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(9),
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(
              showFinanceTransactionDialog(
                context,
                controller: _ctrl,
                initialKind: TransactionKind.transfer,
              ),
            );
          },
          child: Text(
            'Transferir',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
        ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          color: palette.positive.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(9),
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(
              showFinanceTransactionDialog(
                context,
                controller: _ctrl,
                initialKind: TransactionKind.income,
              ),
            );
          },
          child: Text(
            '+ Ingreso',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: palette.positive,
            ),
          ),
        ),
        if (widget.onOpenAccounts != null)
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            minimumSize: Size.zero,
            borderRadius: BorderRadius.circular(9),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onOpenAccounts!();
            },
            child: const Text(
              'Ir a Cuentas',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  Future<void> _showMonthFlowModal(BuildContext context) async {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final sym = _ctrl.currencySymbol;
    final hide = _ctrl.hideBalances;
    final breakdown = _ctrl.monthExpenseBreakdown.take(5).toList();
    final totalExp = _ctrl.monthExpense;

    await _showBentoDetailModal(
      context,
      icon: LucideIcons.chartColumn,
      tint: palette.accent,
      title: 'Balance de ${FinanceFormat.monthTitle(_ctrl.selectedMonth)}',
      subtitle:
          'Ingresos ${FinanceFormat.money(_ctrl.monthIncome, symbol: sym, hide: hide)} · Gastos ${FinanceFormat.money(totalExp, symbol: sym, hide: hide)}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (breakdown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Sin gastos registrados este mes.',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
            )
          else ...[
            Text(
              'Mayores categorías de gasto',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final item in breakdown) ...[
              Builder(
                builder: (_) {
                  final ratio = totalExp > 0
                      ? (item.spent / totalExp).clamp(0.0, 1.0)
                      : 0.0;
                  final tint = palette.adaptiveHex(item.category.colorHex);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              FinanceFormat.categoryIcon(item.category.iconKey),
                              size: 15,
                              color: tint,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                item.category.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                            Text(
                              '${FinanceFormat.money(item.spent, symbol: sym, hide: hide)} (${(ratio * 100).round()}%)',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 5,
                            backgroundColor: colors.surfaceContainerHighest,
                            color: tint,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ],
      ),
      actions: [
        if (widget.onOpenBudgets != null)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(9),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onOpenBudgets!();
            },
            child: Text(
              'Presupuestos',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          ),
        CupertinoButton.filled(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          minimumSize: Size.zero,
          borderRadius: BorderRadius.circular(9),
          onPressed: () {
            Navigator.of(context).pop();
            widget.onOpenTransactions();
          },
          child: const Text(
            'Ver movimientos',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Future<void> _showCreditLineModal(
    BuildContext context,
    FinanceAccount acc,
  ) async {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final sym = _ctrl.currencySymbol;
    final hide = _ctrl.hideBalances;
    final debt = _ctrl.debtOfAccount(acc.id);
    final avail = _ctrl.availableLimitOf(acc);
    final tint = palette.adaptiveHex(acc.colorHex);
    final isAdvance = acc.kind == AccountKind.salaryAdvance;

    await _showBentoDetailModal(
      context,
      icon: FinanceFormat.accountIcon(acc.kind),
      tint: tint,
      title: acc.name,
      subtitle: FinanceFormat.accountKindLabel(acc.kind),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FinanceMiniStatChip(
                  label: 'Deuda actual',
                  value: FinanceFormat.money(debt, symbol: sym, hide: hide),
                  dotColor: debt > 0 ? palette.negative : palette.positive,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FinanceMiniStatChip(
                  label: 'Disponible hoy',
                  value: FinanceFormat.money(
                    avail ?? 0,
                    symbol: sym,
                    hide: hide,
                  ),
                  dotColor: palette.positive,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (acc.creditLimit != null && acc.creditLimit! > 0)
                FinanceDateBadgeChip(
                  label:
                      'Límite ${FinanceFormat.money(acc.creditLimit!, symbol: sym, hide: hide)}',
                  urgent: false,
                ),
              if (acc.statementDay != null)
                FinanceDateBadgeChip(
                  label:
                      'Corte día ${acc.statementDay} · ${FinanceFormat.countdownLabel(acc.statementDay!)}',
                  urgent:
                      FinanceFormat.daysUntilDayOfMonth(acc.statementDay!) <= 3,
                ),
              if (acc.paymentDueDay != null)
                FinanceDateBadgeChip(
                  label: isAdvance
                      ? 'Descuento día ${acc.paymentDueDay} · ${FinanceFormat.countdownLabel(acc.paymentDueDay!)}'
                      : 'Pago día ${acc.paymentDueDay} · ${FinanceFormat.countdownLabel(acc.paymentDueDay!)}',
                  urgent:
                      FinanceFormat.daysUntilDayOfMonth(acc.paymentDueDay!) <=
                      5,
                  isPayment: true,
                ),
            ],
          ),
        ],
      ),
      actions: [
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(9),
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(
              showFinanceAccountDialog(
                context,
                controller: _ctrl,
                existing: acc,
              ),
            );
          },
          child: Text(
            'Editar línea',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
        ),
        if (debt > 0)
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            minimumSize: Size.zero,
            borderRadius: BorderRadius.circular(9),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onPayOffAccount(acc);
            },
            child: Text(
              isAdvance ? 'Liquidar adelanto' : 'Pagar tarjeta',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showFixedPaymentsModal(BuildContext context) async {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final sym = _ctrl.currencySymbol;
    final hide = _ctrl.hideBalances;
    final monthKey = FinanceFormat.monthKey(_ctrl.selectedMonth);
    final expenseRec = _ctrl.recurring
        .where((r) => r.active && r.kind == TransactionKind.expense)
        .toList();

    await _showBentoDetailModal(
      context,
      icon: LucideIcons.calendarClock,
      tint: palette.accent,
      title: 'Pagos fijos del mes',
      subtitle:
          'Compromiso total: ${FinanceFormat.money(_ctrl.monthlyRecurringExpenses, symbol: sym, hide: hide)}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final rec in expenseRec) ...[
            Builder(
              builder: (_) {
                final paid = rec.lastAppliedMonth == monthKey;
                return FolioHoverRow(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(
                      showFinanceRecurringDialog(
                        context,
                        controller: _ctrl,
                        existing: rec,
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Text(
                        'Día ${rec.dayOfMonth}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          rec.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        FinanceFormat.money(
                          rec.amount,
                          symbol: sym,
                          hide: hide,
                        ),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        paid ? LucideIcons.circleCheck : LucideIcons.clock,
                        size: 15,
                        color: paid ? palette.positive : palette.warning,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
      actions: [
        if (widget.onOpenRecurring != null)
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            minimumSize: Size.zero,
            borderRadius: BorderRadius.circular(9),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onOpenRecurring!();
            },
            child: const Text(
              'Gestionar recurrentes',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  Future<void> _showBentoDetailModal(
    BuildContext context, {
    required IconData icon,
    required Color tint,
    required String title,
    required String subtitle,
    required Widget body,
    required List<Widget> actions,
  }) async {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    FolioIconBadge(
                      icon: icon,
                      tint: tint,
                      size: 36,
                      iconSize: 17,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: palette.border),
                const SizedBox(height: 14),
                Flexible(child: SingleChildScrollView(child: body)),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// First-run guided card shown at the top of Resumen when the user has not
/// configured their monthly salary / primary income yet.
class _SalaryStarterCard extends StatefulWidget {
  const _SalaryStarterCard({super.key, required this.controller});

  final FinanceController controller;

  @override
  State<_SalaryStarterCard> createState() => _SalaryStarterCardState();
}

class _SalaryStarterCardState extends State<_SalaryStarterCard> {
  final _amountCtrl = TextEditingController();
  final _dayCtrl = TextEditingController(text: '15');
  String? _accountId;

  @override
  void initState() {
    super.initState();
    _syncDefaultAccount();
  }

  void _syncDefaultAccount() {
    final debit = widget.controller.accounts
        .where((a) => a.kind == AccountKind.debit)
        .firstOrNull;
    _accountId = debit?.id ?? widget.controller.accounts.firstOrNull?.id;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _dayCtrl.dispose();
    super.dispose();
  }

  void _saveSalary() {
    final amount = double.tryParse(
      _amountCtrl.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) return;
    final day = (int.tryParse(_dayCtrl.text.trim()) ?? 15).clamp(1, 28);
    final accId = _accountId ?? widget.controller.accounts.first.id;
    final salaryCatId =
        widget.controller.categoriesFor(TransactionKind.income).firstOrNull?.id ??
        'cat-salary';

    widget.controller.addRecurring(
      title: 'Salario mensual',
      amount: amount,
      kind: TransactionKind.income,
      categoryId: salaryCatId,
      accountId: accId,
      dayOfMonth: day,
    );
    final created = widget.controller.recurring.lastOrNull;
    if (created != null) {
      widget.controller.applyRecurringToSelectedMonth(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final sym = widget.controller.currencySymbol;
    final liquid = widget.controller.liquidAccounts.isNotEmpty
        ? widget.controller.liquidAccounts
        : widget.controller.accounts;
    if (_accountId == null || !liquid.any((a) => a.id == _accountId)) {
      _accountId = liquid.firstOrNull?.id;
    }

    final accOptions = [
      for (final acc in liquid)
        FolioSelectOption<String>(
          value: acc.id,
          label: acc.name,
          icon: FinanceFormat.accountIcon(acc.kind),
          tint: palette.adaptiveHex(acc.colorHex),
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.positive.withValues(alpha: palette.isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: palette.positive.withValues(alpha: 0.45),
          width: 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FolioIconBadge(
                icon: LucideIcons.banknote,
                tint: palette.positive,
                size: 38,
                iconSize: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PASO 1 · EMPIEZA POR TU INGRESO',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w800,
                        color: palette.positive,
                      ),
                    ),
                    Text(
                      'Configura tu salario o ingreso mensual',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tu ingreso mensual es la base de Folio: calcula tu disponible real, arma tus presupuestos y estima tu plan de deudas automáticamente (no necesitas usar «Gasto rápido» para tu salario).',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 150,
                child: CupertinoTextField(
                  controller: _amountCtrl,
                  placeholder: 'Monto mensual',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      sym,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: palette.positive,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.border),
                  ),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                  onSubmitted: (_) => _saveSalary(),
                ),
              ),
              SizedBox(
                width: 104,
                child: CupertinoTextField(
                  controller: _dayCtrl,
                  placeholder: 'Día 15',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: 9),
                    child: Text(
                      'Día',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.border),
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                  onSubmitted: (_) => _saveSalary(),
                ),
              ),
              if (accOptions.isNotEmpty)
                FolioSelectPill<String>(
                  value: _accountId,
                  options: accOptions,
                  height: 38,
                  onChanged: (v) => setState(() => _accountId = v),
                ),
              CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9.5,
                ),
                minimumSize: Size.zero,
                borderRadius: BorderRadius.circular(10),
                onPressed: _saveSalary,
                child: const Text(
                  'Guardar salario',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
