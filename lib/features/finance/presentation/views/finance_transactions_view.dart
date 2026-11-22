import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/finance_models.dart';
import '../controllers/finance_controller.dart';
import '../widgets/finance_dialogs.dart';
import '../widgets/finance_shared_widgets.dart';

class FinanceTransactionsView extends StatefulWidget {
  const FinanceTransactionsView({
    super.key,
    required this.controller,
    this.onBudgetWarning,
  });

  final FinanceController controller;
  final void Function(String message)? onBudgetWarning;

  @override
  State<FinanceTransactionsView> createState() =>
      _FinanceTransactionsViewState();
}

class _FinanceTransactionsViewState extends State<FinanceTransactionsView> {
  TransactionKind? _ledgerFilter;
  String? _accountFilter;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final sym = ctrl.currencySymbol;
    final hide = ctrl.hideBalances;
    final query = _searchCtrl.text.trim().toLowerCase();

    final filtered = ctrl.monthTransactions.where((tx) {
      if (_ledgerFilter != null && tx.kind != _ledgerFilter) return false;
      if (_accountFilter != null &&
          tx.accountId != _accountFilter &&
          tx.toAccountId != _accountFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final cat = ctrl.categoryById(tx.categoryId)?.name.toLowerCase() ?? '';
      final acc = ctrl.accountById(tx.accountId)?.name.toLowerCase() ?? '';
      return tx.note.toLowerCase().contains(query) ||
          cat.contains(query) ||
          acc.contains(query);
    }).toList();

    var filteredIn = 0.0;
    var filteredOut = 0.0;
    var inCount = 0;
    var outCount = 0;
    for (final tx in filtered) {
      if (tx.kind == TransactionKind.income) {
        filteredIn += tx.amount;
        inCount++;
      } else if (tx.kind == TransactionKind.expense) {
        filteredOut += tx.amount + tx.feeAmount;
        outCount++;
      } else if (tx.feeAmount > 0) {
        filteredOut += tx.feeAmount;
      }
    }
    final filteredNet = filteredIn - filteredOut;
    final totalFlow = filteredIn + filteredOut;
    final inShare = totalFlow > 0 ? (filteredIn / totalFlow).clamp(0.0, 1.0) : 0.0;
    final outShare = totalFlow > 0 ? (filteredOut / totalFlow).clamp(0.0, 1.0) : 0.0;

    // Group filtered transactions by calendar day (newest first)
    final grouped = <DateTime, List<FinanceTransaction>>{};
    for (final tx in filtered) {
      final dayKey = DateTime(tx.date.year, tx.date.month, tx.date.day);
      grouped.putIfAbsent(dayKey, () => []).add(tx);
    }
    final dayKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    final accountFilterOptions = <FolioSelectOption<String>>[
      const FolioSelectOption(
        value: '__all__',
        label: 'Todas las cuentas',
        icon: Icons.account_balance_wallet_rounded,
      ),
      for (final acc in ctrl.accounts)
        FolioSelectOption(
          value: acc.id,
          label: acc.name,
          icon: FinanceFormat.accountIcon(acc.kind),
          tint: palette.adaptiveHex(acc.colorHex),
        ),
    ];

    Widget buildMovementsList({EdgeInsets padding = const EdgeInsets.only(bottom: 86)}) {
      if (filtered.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.receipt_long_rounded,
                  size: 36,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 10),
                Text(
                  'No hay movimientos con estos filtros',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return ListView.builder(
        padding: padding,
        itemCount: dayKeys.length,
        itemBuilder: (context, index) {
          final day = dayKeys[index];
          final txs = grouped[day]!;
          var dayNet = 0.0;
          for (final tx in txs) {
            if (tx.kind == TransactionKind.income) {
              dayNet += tx.amount;
            } else if (tx.kind == TransactionKind.expense) {
              dayNet -= (tx.amount + tx.feeAmount);
            } else if (tx.feeAmount > 0) {
              dayNet -= tx.feeAmount;
            }
          }
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: palette.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 11, 16, 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${FinanceFormat.shortDate(day)} · ${txs.length} ${txs.length == 1 ? 'movimiento' : 'movimientos'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (dayNet.abs() > 0.005)
                        Text(
                          FinanceFormat.money(
                            dayNet,
                            symbol: sym,
                            hide: hide,
                            showSign: true,
                          ),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: dayNet >= 0
                                ? palette.positive
                                : colors.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: palette.border.withValues(alpha: 0.65),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < txs.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 52,
                            color: palette.border.withValues(alpha: 0.45),
                          ),
                        FinanceTransactionRow(
                          tx: txs[i],
                          controller: ctrl,
                          showDate: false,
                          onTap: () => unawaited(
                            showFinanceTransactionDialog(
                              context,
                              controller: ctrl,
                              existing: txs[i],
                              onBudgetWarning: widget.onBudgetWarning,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    final savingsRate = filteredIn > 0
        ? ((filteredNet / filteredIn) * 100).round()
        : null;

    final rightSummaryCards = [
      _LedgerBigStatCard(
        label: 'Entradas',
        subtitle: '$inCount ${inCount == 1 ? 'ingreso' : 'ingresos'}',
        value: '+${FinanceFormat.money(filteredIn, symbol: sym, hide: hide)}',
        color: palette.positive,
        icon: LucideIcons.arrowDownLeft,
        ratio: inShare,
        ratioCaption: totalFlow > 0
            ? '${(inShare * 100).round()}% del flujo'
            : 'Sin flujo',
      ),
      _LedgerBigStatCard(
        label: 'Salidas',
        subtitle: '$outCount ${outCount == 1 ? 'gasto' : 'gastos'}',
        value: '-${FinanceFormat.money(filteredOut, symbol: sym, hide: hide)}',
        color: palette.negative,
        icon: LucideIcons.arrowUpRight,
        ratio: outShare,
        ratioCaption: totalFlow > 0
            ? '${(outShare * 100).round()}% del flujo'
            : 'Sin flujo',
      ),
      _LedgerBalanceBigCard(
        count: filtered.length,
        value: FinanceFormat.money(
          filteredNet,
          symbol: sym,
          hide: hide,
          showSign: true,
        ),
        isPositive: filteredNet >= 0,
        inShare: inShare,
        outShare: outShare,
        savingsRate: savingsRate,
      ),
    ];

    return Column(
      children: [
        // Top Filter Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1140),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 230,
                      child: CupertinoSearchTextField(
                        controller: _searchCtrl,
                        placeholder: 'Buscar concepto o categoría…',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    FinanceFilterPill(
                      label: 'Todos',
                      selected: _ledgerFilter == null,
                      onTap: () => setState(() => _ledgerFilter = null),
                    ),
                    FinanceFilterPill(
                      label: 'Gastos',
                      selected: _ledgerFilter == TransactionKind.expense,
                      onTap: () => setState(
                        () => _ledgerFilter = TransactionKind.expense,
                      ),
                    ),
                    FinanceFilterPill(
                      label: 'Ingresos',
                      selected: _ledgerFilter == TransactionKind.income,
                      onTap: () => setState(
                        () => _ledgerFilter = TransactionKind.income,
                      ),
                    ),
                    FinanceFilterPill(
                      label: 'Transferencias',
                      selected: _ledgerFilter == TransactionKind.transfer,
                      onTap: () => setState(
                        () => _ledgerFilter = TransactionKind.transfer,
                      ),
                    ),
                    FolioSelectPill<String>(
                      value: _accountFilter ?? '__all__',
                      height: 34,
                      options: accountFilterOptions,
                      onChanged: (v) => setState(
                        () => _accountFilter = v == '__all__' ? null : v,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Main 2-Column Body (Movements Left | 3 Large Summary Cards Right)
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final twoCol = constraints.maxWidth >= 860;
              if (twoCol) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1140),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left column: All grouped movements
                          Expanded(
                            child: buildMovementsList(
                              padding: const EdgeInsets.only(top: 2, bottom: 86),
                            ),
                          ),
                          const SizedBox(width: 18),
                          // Right column: 3 Large Cards (Entradas, Salidas, Balance)
                          SizedBox(
                            width: 312,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(top: 2, bottom: 86),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  rightSummaryCards[0],
                                  const SizedBox(height: 14),
                                  rightSummaryCards[1],
                                  const SizedBox(height: 14),
                                  rightSummaryCards[2],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              // Compact stacked layout for narrow/mobile screens
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: _CompactSummaryChip(
                            label: 'Entradas',
                            value:
                                '+${FinanceFormat.money(filteredIn, symbol: sym, hide: hide)}',
                            color: palette.positive,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _CompactSummaryChip(
                            label: 'Salidas',
                            value:
                                '-${FinanceFormat.money(filteredOut, symbol: sym, hide: hide)}',
                            color: palette.negative,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _CompactSummaryChip(
                            label: 'Balance',
                            value: FinanceFormat.money(
                              filteredNet,
                              symbol: sym,
                              hide: hide,
                              showSign: true,
                            ),
                            color: filteredNet >= 0
                                ? palette.positive
                                : palette.negative,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: buildMovementsList(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 86),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LedgerBigStatCard extends StatelessWidget {
  const _LedgerBigStatCard({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.color,
    required this.icon,
    required this.ratio,
    required this.ratioCaption,
  });

  final String label;
  final String subtitle;
  final String value;
  final Color color;
  final IconData icon;
  final double ratio;
  final String ratioCaption;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return FolioInteractiveBento(
      enableHover: false,
      padding: const EdgeInsets.all(20),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FolioIconBadge(
                icon: icon,
                tint: color,
                size: 38,
                iconSize: 18,
                borderRadius: 11,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
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
            ],
          ),
          const SizedBox(height: 18),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: colors.surfaceContainerHighest,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            ratioCaption,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerBalanceBigCard extends StatelessWidget {
  const _LedgerBalanceBigCard({
    required this.count,
    required this.value,
    required this.isPositive,
    required this.inShare,
    required this.outShare,
    this.savingsRate,
  });

  final int count;
  final String value;
  final bool isPositive;
  final double inShare;
  final double outShare;
  final int? savingsRate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final accent = isPositive ? palette.positive : palette.negative;

    return FolioInteractiveBento(
      enableHover: false,
      padding: const EdgeInsets.all(20),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FolioIconBadge(
                icon: LucideIcons.scale,
                tint: accent,
                size: 38,
                iconSize: 18,
                borderRadius: 11,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Balance',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      '$count ${count == 1 ? 'movimiento' : 'movimientos'}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (savingsRate != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.innerBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    '${savingsRate! >= 0 ? '+' : ''}$savingsRate%',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
              color: accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (inShare > 0)
                    Expanded(
                      flex: (inShare * 1000).round().clamp(1, 1000),
                      child: Container(color: palette.positive),
                    ),
                  if (inShare > 0 && outShare > 0) const SizedBox(width: 2),
                  if (outShare > 0)
                    Expanded(
                      flex: (outShare * 1000).round().clamp(1, 1000),
                      child: Container(color: palette.negative),
                    ),
                  if (inShare == 0 && outShare == 0)
                    Expanded(
                      child: Container(color: colors.surfaceContainerHighest),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Entradas ${(inShare * 100).round()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
              Text(
                'Salidas ${(outShare * 100).round()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactSummaryChip extends StatelessWidget {
  const _CompactSummaryChip({
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
    final palette = FinancePalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: palette.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
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
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
