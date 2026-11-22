import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';

import '../../domain/finance_models.dart';
import '../controllers/finance_controller.dart';

enum _DebtPlanTab { advance, creditCard, loans }

class FinanceDebtPlanView extends StatefulWidget {
  const FinanceDebtPlanView({
    super.key,
    required this.controller,
    required this.onPayOffAccount,
    required this.onEditAccount,
    required this.onAddAdvanceAccount,
    required this.onAddLoan,
    required this.onEditLoan,
    required this.onOpenRecurring,
  });

  final FinanceController controller;
  final ValueChanged<FinanceAccount> onPayOffAccount;
  final ValueChanged<FinanceAccount> onEditAccount;
  final VoidCallback onAddAdvanceAccount;
  final VoidCallback onAddLoan;
  final ValueChanged<FinanceLoan> onEditLoan;
  final VoidCallback onOpenRecurring;

  @override
  State<FinanceDebtPlanView> createState() => _FinanceDebtPlanViewState();
}

class _FinanceDebtPlanViewState extends State<FinanceDebtPlanView> {
  _DebtPlanTab _tab = _DebtPlanTab.advance;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final ctrl = widget.controller;
    final sym = ctrl.currencySymbol;
    final hide = ctrl.hideBalances;

    final income = ctrl.primaryBudgetIncome;
    final fixedBills = ctrl.totalFixedAndLoanCommitments;

    final advanceAccounts = ctrl.accounts
        .where((a) => a.kind == AccountKind.salaryAdvance)
        .toList();
    final creditAccounts = ctrl.accounts
        .where((a) => a.kind == AccountKind.credit)
        .toList();
    final loans = ctrl.loans;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 84),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1020),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Clean top bar: segmented tabs + compact free margin summary
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _SegmentedDebtTabs(
                    selected: _tab,
                    advanceDebt: ctrl.totalAdvanceDebt,
                    creditDebt: ctrl.totalCreditCardDebt,
                    loanCount: loans.length,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                  _CompactMarginPill(
                    availableToday: ctrl.safeToSpendToday,
                    pendingFixedThisMonth:
                        ctrl.pendingRecurringExpensesThisMonth,
                    paidFixedCount: ctrl.paidRecurringExpenseCountThisMonth,
                    totalFixedCount: ctrl.activeRecurringExpenseCount,
                    symbol: sym,
                    hide: hide,
                    onTapFixed: widget.onOpenRecurring,
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Active tab content
              switch (_tab) {
                _DebtPlanTab.advance => _buildAdvanceSection(
                  colors: colors,
                  palette: palette,
                  advanceAccounts: advanceAccounts,
                  income: income,
                  fixedBills: fixedBills,
                  symbol: sym,
                  hide: hide,
                ),
                _DebtPlanTab.creditCard => _buildCreditCardSection(
                  colors: colors,
                  palette: palette,
                  creditAccounts: creditAccounts,
                  symbol: sym,
                  hide: hide,
                ),
                _DebtPlanTab.loans => _buildLoansSection(
                  colors: colors,
                  palette: palette,
                  loans: loans,
                  symbol: sym,
                  hide: hide,
                ),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvanceSection({
    required ColorScheme colors,
    required FinancePalette palette,
    required List<FinanceAccount> advanceAccounts,
    required double income,
    required double fixedBills,
    required String symbol,
    required bool hide,
  }) {
    if (advanceAccounts.isEmpty) {
      return _EmptySectionCard(
        icon: LucideIcons.arrowLeftRight,
        accent: palette.warning,
        title: 'Sin adelanto salarial activo',
        subtitle:
            'Si usas adelanto salarial con comisión, agrégalo aquí para bajarlo a \$0 paso a paso.',
        actionLabel: 'Agregar adelanto',
        onAction: widget.onAddAdvanceAccount,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final adv in advanceAccounts) ...[
          _AdvanceExitCard(
            key: ValueKey('adv-${adv.id}'),
            account: adv,
            debt: widget.controller.debtOfAccount(adv.id),
            available: widget.controller.availableLimitOf(adv) ?? 0,
            income: income,
            fixedBills: fixedBills,
            step: widget.controller.activeAdvanceReductionStep,
            recommended: widget.controller.recommendedAdvanceReduction,
            symbol: symbol,
            hide: hide,
            onStepChanged: (v) => widget.controller.setDebtPlanSettings(
              advanceReductionStep: v,
            ),
            onPayOff: () => widget.onPayOffAccount(adv),
            onEdit: () => widget.onEditAccount(adv),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildCreditCardSection({
    required ColorScheme colors,
    required FinancePalette palette,
    required List<FinanceAccount> creditAccounts,
    required String symbol,
    required bool hide,
  }) {
    if (creditAccounts.isEmpty) {
      return _EmptySectionCard(
        icon: LucideIcons.creditCard,
        accent: palette.accent,
        title: 'Sin tarjetas de crédito configuradas',
        subtitle:
            'Agrega tu tarjeta en Cuentas para planificar cómo llevarla a \$0 y usarla sin intereses.',
        actionLabel: 'Configurar cuenta',
        onAction: widget.onAddAdvanceAccount,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final card in creditAccounts) ...[
          _CreditCardExitCard(
            key: ValueKey('cc-${card.id}'),
            account: card,
            debt: widget.controller.debtOfAccount(card.id),
            available: widget.controller.availableLimitOf(card) ?? 0,
            step: widget.controller.activeCreditCardPayoffStep,
            recommended: widget.controller.recommendedCreditCardPayoffStep,
            symbol: symbol,
            hide: hide,
            onStepChanged: (v) => widget.controller.setDebtPlanSettings(
              creditCardPayoffStep: v,
            ),
            onPayOff: () => widget.onPayOffAccount(card),
            onEdit: () => widget.onEditAccount(card),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildLoansSection({
    required ColorScheme colors,
    required FinancePalette palette,
    required List<FinanceLoan> loans,
    required String symbol,
    required bool hide,
  }) {
    if (loans.isEmpty) {
      return _EmptySectionCard(
        icon: LucideIcons.landmark,
        accent: palette.purple,
        title: 'Registra tu préstamo',
        subtitle:
            'Visualiza cuánto de tu cuota mensual se va a intereses vs. capital y simula abonos extra para pagar menos intereses.',
        actionLabel: 'Agregar préstamo',
        onAction: widget.onAddLoan,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${loans.length} ${loans.length == 1 ? 'préstamo activo' : 'préstamos activos'} · Cuota total ${FinanceFormat.money(widget.controller.totalLoanMonthlyPayments, symbol: symbol, hide: hide)}/mes',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 10),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              minimumSize: Size.zero,
              color: palette.purple.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
              onPressed: widget.onAddLoan,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 16, color: palette.purple),
                  const SizedBox(width: 4),
                  Text(
                    'Nuevo préstamo',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: palette.purple,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final loan in loans) ...[
          _LoanCard(
            key: ValueKey('loan-${loan.id}'),
            loan: loan,
            symbol: symbol,
            hide: hide,
            isInRecurring: widget.controller.isLoanInRecurring(loan),
            onAddToRecurring: () =>
                widget.controller.addLoanToRecurring(loan),
            onEdit: () => widget.onEditLoan(loan),
            onRecordPayment: (extra) => widget.controller.recordLoanPayment(
              loan,
              extraPrincipal: extra,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _SegmentedDebtTabs extends StatelessWidget {
  const _SegmentedDebtTabs({
    required this.selected,
    required this.advanceDebt,
    required this.creditDebt,
    required this.loanCount,
    required this.onChanged,
  });

  final _DebtPlanTab selected;
  final double advanceDebt;
  final double creditDebt;
  final int loanCount;
  final ValueChanged<_DebtPlanTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: palette.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tabPill(
              context: context,
              tab: _DebtPlanTab.advance,
              icon: LucideIcons.arrowLeftRight,
              label: 'Adelanto',
              dotColor: advanceDebt > 0 ? palette.warning : null,
              colors: colors,
            ),
            _tabPill(
              context: context,
              tab: _DebtPlanTab.creditCard,
              icon: LucideIcons.creditCard,
              label: 'Tarjeta',
              dotColor: creditDebt > 0 ? palette.accent : null,
              colors: colors,
            ),
            _tabPill(
              context: context,
              tab: _DebtPlanTab.loans,
              icon: LucideIcons.landmark,
              label: loanCount > 0 ? 'Préstamos ($loanCount)' : 'Préstamos',
              dotColor: loanCount > 0 ? palette.purple : null,
              colors: colors,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabPill({
    required BuildContext context,
    required _DebtPlanTab tab,
    required IconData icon,
    required String label,
    required Color? dotColor,
    required ColorScheme colors,
  }) {
    final active = selected == tab;
    return GestureDetector(
      onTap: () => onChanged(tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7.5),
        decoration: BoxDecoration(
          color: active ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8.5),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? colors.onSurface : colors.onSurfaceVariant,
              ),
            ),
            if (dotColor != null && !active) ...[
              const SizedBox(width: 5),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactMarginPill extends StatelessWidget {
  const _CompactMarginPill({
    required this.availableToday,
    required this.pendingFixedThisMonth,
    required this.paidFixedCount,
    required this.totalFixedCount,
    required this.symbol,
    required this.hide,
    required this.onTapFixed,
  });

  final double availableToday;
  final double pendingFixedThisMonth;
  final int paidFixedCount;
  final int totalFixedCount;
  final String symbol;
  final bool hide;
  final VoidCallback onTapFixed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final allPaid = pendingFixedThisMonth <= 0.01;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8.5),
      decoration: BoxDecoration(
        color: palette.cardBg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: palette.border),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.wallet,
                size: 13.5,
                color: palette.positive,
              ),
              const SizedBox(width: 5),
              Text(
                'Disponible hoy: ',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              Text(
                FinanceFormat.money(
                  availableToday,
                  symbol: symbol,
                  hide: hide,
                ),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: palette.positive,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            onPressed: onTapFixed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  allPaid
                      ? LucideIcons.circleCheck
                      : LucideIcons.calendarClock,
                  size: 13,
                  color: allPaid ? palette.positive : palette.warning,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    allPaid
                        ? 'Pendiente fijos: ${symbol}0.00 ($paidFixedCount/$totalFixedCount pagados)'
                        : 'Pendiente de pagar: ${FinanceFormat.money(pendingFixedThisMonth, symbol: symbol, hide: hide)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: allPaid ? colors.primary : palette.warning,
                    ),
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

/// Custom editable monthly step input with -5/+5 steppers and quick preset pills.
class _CustomPaceControl extends StatefulWidget {
  const _CustomPaceControl({
    required this.label,
    required this.value,
    required this.maxRecommended,
    required this.presets,
    required this.symbol,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double maxRecommended;
  final List<(String, double)> presets;
  final String symbol;
  final Color accent;
  final ValueChanged<double> onChanged;

  @override
  State<_CustomPaceControl> createState() => _CustomPaceControlState();
}

class _CustomPaceControlState extends State<_CustomPaceControl> {
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(covariant _CustomPaceControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && (oldWidget.value - widget.value).abs() > 0.01) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  void _commitValue(double next) {
    final clamped = next
        .clamp(5.0, math.max(500.0, widget.maxRecommended))
        .toDouble();
    _ctrl.text = _fmt(clamped);
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.innerBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 560;
          final inputGroup = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepperButton(
                icon: Icons.remove_rounded,
                onTap: () => _commitValue(widget.value - 5),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 112,
                child: CupertinoTextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      widget.symbol,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: widget.accent,
                      ),
                    ),
                  ),
                  suffix: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '/m',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: widget.accent.withValues(alpha: 0.55),
                      width: 1.3,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  onChanged: (raw) {
                    final parsed = double.tryParse(
                      raw.trim().replaceAll(',', '.'),
                    );
                    if (parsed != null && parsed >= 5) {
                      widget.onChanged(parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              _StepperButton(
                icon: Icons.add_rounded,
                onTap: () => _commitValue(widget.value + 5),
              ),
            ],
          );

          final presetsRow = Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in widget.presets)
                _QuickPresetChip(
                  label: '${preset.$1} · ${widget.symbol}${preset.$2.round()}',
                  selected: (widget.value - preset.$2).abs() < 1,
                  accent: widget.accent,
                  onTap: () => _commitValue(preset.$2),
                ),
            ],
          );

          if (wide) {
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      presetsRow,
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                inputGroup,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              inputGroup,
              const SizedBox(height: 10),
              presetsRow,
            ],
          );
        },
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: palette.border),
        ),
        child: Icon(icon, size: 17, color: colors.onSurface),
      ),
    );
  }
}

class _QuickPresetChip extends StatelessWidget {
  const _QuickPresetChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? accent : palette.border,
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? accent : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _AdvanceExitCard extends StatelessWidget {
  const _AdvanceExitCard({
    super.key,
    required this.account,
    required this.debt,
    required this.available,
    required this.income,
    required this.fixedBills,
    required this.step,
    required this.recommended,
    required this.symbol,
    required this.hide,
    required this.onStepChanged,
    required this.onPayOff,
    required this.onEdit,
  });

  final FinanceAccount account;
  final double debt;
  final double available;
  final double income;
  final double fixedBills;
  final double step;
  final double recommended;
  final String symbol;
  final bool hide;
  final ValueChanged<double> onStepChanged;
  final VoidCallback onPayOff;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final feePct = account.transactionFeePercent ?? 4.0;
    final limit = account.creditLimit ?? (debt + available);
    final usedRatio = limit > 0 ? (debt / limit).clamp(0.0, 1.0) : 0.0;
    final safeStep = math.max(5.0, step);

    final nextWithdraw = math.max(0.0, debt - safeStep);
    final livingCash = math.max(
      0.0,
      income - debt + nextWithdraw - fixedBills,
    );
    final monthsToZero = debt <= 0 ? 0 : (debt / safeStep).ceil();
    final annualFeeSaved = (debt * feePct / 100.0) * 12;

    final softStep = math.max(20.0, ((recommended * 0.65) / 5).round() * 5.0);
    final fastStep = math.max(
      recommended + 25.0,
      ((recommended * 1.5) / 5).round() * 5.0,
    );

    final points = _buildPayoffPoints(debt, safeStep);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  LucideIcons.arrowLeftRight,
                  size: 20,
                  color: palette.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      account.paymentDueDay != null
                          ? 'Descuento día ${account.paymentDueDay} · ${feePct.toStringAsFixed(feePct % 1 == 0 ? 0 : 1)}% comisión'
                          : '${feePct.toStringAsFixed(feePct % 1 == 0 ? 0 : 1)}% comisión por retiro',
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
              CupertinoButton(
                padding: const EdgeInsets.all(6),
                minimumSize: Size.zero,
                onPressed: onEdit,
                child: Icon(
                  LucideIcons.pencil,
                  size: 17,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Slim status strip: Available vs Used
          _DebtStatusBar(
            leftLabel: 'Disponible hoy',
            leftValue: FinanceFormat.money(available, symbol: symbol, hide: hide),
            leftColor: palette.positive,
            rightLabel: 'Por liquidar',
            rightValue: FinanceFormat.money(debt, symbol: symbol, hide: hide),
            rightColor: debt > 0 ? palette.warning : palette.positive,
            progress: usedRatio,
            barColor: palette.warning,
            barBg: palette.positive.withValues(alpha: 0.18),
          ),

          if (debt <= 0.01) ...[
            const SizedBox(height: 16),
            _DebtFreeBanner(
              text:
                  '¡Adelanto en \$0! Ya no pierdes ${feePct.toStringAsFixed(0)}% en comisiones.',
            ),
          ] else ...[
            const SizedBox(height: 16),
            _CustomPaceControl(
              label: '¿Cuánto reduces tu adelanto cada mes?',
              value: safeStep,
              maxRecommended: math.max(debt, 500),
              presets: [
                ('Suave', softStep),
                ('Sugerido', recommended),
                ('Rápido', fastStep),
              ],
              symbol: symbol,
              accent: palette.warning,
              onChanged: onStepChanged,
            ),
            const SizedBox(height: 14),

            // 3 Essential Metric Pills
            _ThreeMetricRow(
              metrics: [
                _MiniMetric(
                  label: 'Próximo retiro máx.',
                  value: FinanceFormat.money(
                    nextWithdraw,
                    symbol: symbol,
                    hide: hide,
                  ),
                  tint: palette.warning,
                ),
                _MiniMetric(
                  label: 'Libre para vivir / mes',
                  value: FinanceFormat.money(
                    livingCash,
                    symbol: symbol,
                    hide: hide,
                  ),
                  tint: palette.positive,
                ),
                _MiniMetric(
                  label: 'Sales en',
                  value: '$monthsToZero ${monthsToZero == 1 ? 'mes' : 'meses'}',
                  sub:
                      'Ahorras ~${FinanceFormat.money(annualFeeSaved, symbol: symbol, hide: hide)}/año',
                  tint: palette.accent,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Upgraded Gradient Descending Bar Chart
            _PayoffGradientChart(
              title: 'Así baja tu adelanto hasta \$0',
              points: points,
              maxAmount: debt,
              startColor: palette.warning,
              midColor: palette.accent,
              zeroColor: palette.positive,
              symbol: symbol,
              hide: hide,
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 9,
                  ),
                  minimumSize: Size.zero,
                  borderRadius: BorderRadius.circular(10),
                  onPressed: onPayOff,
                  child: const Text(
                    'Registrar descuento',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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

class _CreditCardExitCard extends StatelessWidget {
  const _CreditCardExitCard({
    super.key,
    required this.account,
    required this.debt,
    required this.available,
    required this.step,
    required this.recommended,
    required this.symbol,
    required this.hide,
    required this.onStepChanged,
    required this.onPayOff,
    required this.onEdit,
  });

  final FinanceAccount account;
  final double debt;
  final double available;
  final double step;
  final double recommended;
  final String symbol;
  final bool hide;
  final ValueChanged<double> onStepChanged;
  final VoidCallback onPayOff;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final limit = account.creditLimit ?? (debt + available);
    final usedRatio = limit > 0 ? (debt / limit).clamp(0.0, 1.0) : 0.0;
    final safeStep = math.max(5.0, step);
    final monthsToZero = debt <= 0 ? 0 : (debt / safeStep).ceil();
    final weeklyDeposit = math.min(debt, safeStep) / 4.0;

    final softStep = math.max(25.0, ((recommended * 0.7) / 5).round() * 5.0);
    final fastStep = math.max(
      recommended + 30.0,
      ((recommended * 1.6) / 5).round() * 5.0,
    );

    final points = _buildPayoffPoints(debt, safeStep);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  LucideIcons.creditCard,
                  size: 20,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      [
                        if (account.statementDay != null)
                          'Corte día ${account.statementDay}',
                        if (account.paymentDueDay != null)
                          'Pago día ${account.paymentDueDay} (${FinanceFormat.countdownLabel(account.paymentDueDay!)})',
                      ].join(' · '),
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
              CupertinoButton(
                padding: const EdgeInsets.all(6),
                minimumSize: Size.zero,
                onPressed: onEdit,
                child: Icon(
                  LucideIcons.pencil,
                  size: 17,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _DebtStatusBar(
            leftLabel: 'Cupo libre hoy',
            leftValue: FinanceFormat.money(available, symbol: symbol, hide: hide),
            leftColor: palette.positive,
            rightLabel: 'Deuda por liquidar',
            rightValue: FinanceFormat.money(debt, symbol: symbol, hide: hide),
            rightColor: debt > 0 ? palette.accent : palette.positive,
            progress: usedRatio,
            barColor: palette.accent,
            barBg: palette.positive.withValues(alpha: 0.18),
          ),

          if (debt <= 0.01) ...[
            const SizedBox(height: 16),
            const _DebtFreeBanner(
              text:
                  '¡Tarjeta al 100% libre! Ahora puedes usarla normal pagando siempre de contado.',
            ),
          ] else ...[
            const SizedBox(height: 16),
            _CustomPaceControl(
              label: '¿Cuánto abonas neto al mes para dejarla en \$0?',
              value: safeStep,
              maxRecommended: math.max(debt, 500),
              presets: [
                ('Suave', softStep),
                ('Sugerido', recommended),
                ('Rápido', fastStep),
              ],
              symbol: symbol,
              accent: palette.accent,
              onChanged: onStepChanged,
            ),
            const SizedBox(height: 14),
            _ThreeMetricRow(
              metrics: [
                _MiniMetric(
                  label: 'Al 100% en',
                  value: '$monthsToZero ${monthsToZero == 1 ? 'mes' : 'meses'}',
                  tint: palette.accent,
                ),
                _MiniMetric(
                  label: 'Apartado semanal',
                  value:
                      '~${FinanceFormat.money(weeklyDeposit, symbol: symbol, hide: hide)}',
                  tint: palette.positive,
                ),
                _MiniMetric(
                  label: 'Cupo al terminar',
                  value: FinanceFormat.money(limit, symbol: symbol, hide: hide),
                  tint: colors.onSurface,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _PayoffGradientChart(
              title: 'Así queda tu tarjeta en \$0 para usarla normal',
              points: points,
              maxAmount: debt,
              startColor: palette.accent,
              midColor: palette.purple,
              zeroColor: palette.positive,
              symbol: symbol,
              hide: hide,
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 9,
                  ),
                  minimumSize: Size.zero,
                  borderRadius: BorderRadius.circular(10),
                  onPressed: onPayOff,
                  child: const Text(
                    'Abonar a tarjeta',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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

class _LoanCard extends StatefulWidget {
  const _LoanCard({
    super.key,
    required this.loan,
    required this.symbol,
    required this.hide,
    required this.isInRecurring,
    required this.onAddToRecurring,
    required this.onEdit,
    required this.onRecordPayment,
  });

  final FinanceLoan loan;
  final String symbol;
  final bool hide;
  final bool isInRecurring;
  final VoidCallback onAddToRecurring;
  final VoidCallback onEdit;
  final ValueChanged<double> onRecordPayment;

  @override
  State<_LoanCard> createState() => _LoanCardState();
}

class _LoanCardState extends State<_LoanCard> {
  double _extraMonthly = 0;
  late final TextEditingController _extraCtrl;

  @override
  void initState() {
    super.initState();
    _extraCtrl = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _extraCtrl.dispose();
    super.dispose();
  }

  void _setExtra(double v) {
    final clamped = math.max(0.0, v);
    setState(() {
      _extraMonthly = clamped;
      _extraCtrl.text = clamped == clamped.roundToDouble()
          ? clamped.toStringAsFixed(0)
          : clamped.toStringAsFixed(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final loan = widget.loan;
    final sym = widget.symbol;
    final hide = widget.hide;

    final baseSim = loan.simulatePayoff();
    final extraSim = loan.simulatePayoff(extraMonthly: _extraMonthly);
    final interestSaved = math.max(
      0.0,
      baseSim.totalInterestRemaining - extraSim.totalInterestRemaining,
    );
    final monthsSaved = math.max(
      0,
      baseSim.monthsRemaining - extraSim.monthsRemaining,
    );

    final nextInt = loan.nextInterestPortion;
    final nextPrin = loan.nextPrincipalPortion;
    final paymentTotal = math.max(0.01, nextInt + nextPrin);
    final principalShare = (nextPrin / paymentTotal).clamp(0.0, 1.0);
    final interestShare = (1.0 - principalShare).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  LucideIcons.landmark,
                  size: 20,
                  color: palette.purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loan.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      'Día ${loan.paymentDay} · ${loan.annualInterestRate.toStringAsFixed(1)}% anual · ${loan.paidMonths}/${loan.termMonths} cuotas',
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
              CupertinoButton(
                padding: const EdgeInsets.all(6),
                minimumSize: Size.zero,
                onPressed: widget.onEdit,
                child: Icon(
                  LucideIcons.pencil,
                  size: 17,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 1-Click Fixed Expense (Recurrentes) Suggestion Banner
          if (!widget.isInRecurring)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: palette.purple.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: palette.purple.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.calendarClock,
                    size: 16,
                    color: palette.purple,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Sugerencia: agrega tu cuota de ${FinanceFormat.money(loan.monthlyPayment, symbol: sym, hide: hide)} (día ${loan.paymentDay}) a tus gastos fijos del mes.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    color: palette.purple,
                    borderRadius: BorderRadius.circular(8),
                    onPressed: widget.onAddToRecurring,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.plus, size: 13, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Agregar a gastos fijos',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: palette.positive.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: palette.positive.withValues(alpha: 0.30),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.circleCheck,
                    size: 14,
                    color: palette.positive,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Cuota de ${FinanceFormat.money(loan.monthlyPayment, symbol: sym, hide: hide)}/mes ya vinculada en tus gastos fijos (Recurrentes · día ${loan.paymentDay}).',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: palette.positive,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 14),

          // Balance + Monthly Payment
          _DebtStatusBar(
            leftLabel: 'Saldo pendiente',
            leftValue: FinanceFormat.money(
              loan.remainingBalance,
              symbol: sym,
              hide: hide,
            ),
            leftColor: colors.onSurface,
            rightLabel: 'Cuota mensual',
            rightValue: FinanceFormat.money(
              loan.monthlyPayment,
              symbol: sym,
              hide: hide,
            ),
            rightColor: palette.purple,
            progress: loan.paidProgress,
            barColor: palette.positive,
            barBg: palette.purple.withValues(alpha: 0.16),
          ),
          const SizedBox(height: 14),

          // Interest vs Principal breakdown of current payment
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.innerBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Desglose de tu cuota actual',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      'Intereses totales rest.: ${FinanceFormat.money(baseSim.totalInterestRemaining, symbol: sym, hide: hide)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: palette.warning,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        if (principalShare > 0)
                          Expanded(
                            flex: math.max(1, (principalShare * 1000).round()),
                            child: Container(color: palette.positive),
                          ),
                        if (interestShare > 0)
                          Expanded(
                            flex: math.max(1, (interestShare * 1000).round()),
                            child: Container(color: palette.warning),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _DotMetric(
                        color: palette.positive,
                        label: 'Capital (${(principalShare * 100).round()}%)',
                        value: FinanceFormat.money(
                          nextPrin,
                          symbol: sym,
                          hide: hide,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _DotMetric(
                        color: palette.warning,
                        label: 'Intereses (${(interestShare * 100).round()}%)',
                        value: FinanceFormat.money(
                          nextInt,
                          symbol: sym,
                          hide: hide,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Interest Reduction Simulator
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.innerBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Simular abono extra a capital / mes',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 96,
                      child: CupertinoTextField(
                        controller: _extraCtrl,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        prefix: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '+$sym',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: palette.positive,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: palette.border),
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        onChanged: (raw) {
                          final p =
                              double.tryParse(raw.trim().replaceAll(',', '.')) ??
                              0;
                          setState(() => _extraMonthly = math.max(0.0, p));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final amt in const [0.0, 20.0, 50.0, 100.0])
                      _QuickPresetChip(
                        label: amt == 0 ? 'Sin extra' : '+$sym${amt.round()}',
                        selected: (_extraMonthly - amt).abs() < 0.5,
                        accent: palette.positive,
                        onTap: () => _setExtra(amt),
                      ),
                  ],
                ),
                if (_extraMonthly > 0.01) ...[
                  const SizedBox(height: 12),
                  _ThreeMetricRow(
                    metrics: [
                      _MiniMetric(
                        label: 'Ahorras en intereses',
                        value: FinanceFormat.money(
                          interestSaved,
                          symbol: sym,
                          hide: hide,
                        ),
                        tint: palette.positive,
                      ),
                      _MiniMetric(
                        label: 'Ahorras en tiempo',
                        value:
                            '$monthsSaved ${monthsSaved == 1 ? 'mes' : 'meses'}',
                        tint: palette.accent,
                      ),
                      _MiniMetric(
                        label: 'Nuevo plazo',
                        value: '${extraSim.monthsRemaining} meses',
                        tint: colors.onSurface,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 9,
                ),
                minimumSize: Size.zero,
                borderRadius: BorderRadius.circular(10),
                onPressed: () => widget.onRecordPayment(_extraMonthly),
                child: Text(
                  _extraMonthly > 0
                      ? 'Registrar cuota (+$sym${_extraMonthly.round()} capital)'
                      : 'Registrar cuota del mes',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DotMetric extends StatelessWidget {
  const _DotMetric({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
      ],
    );
  }
}

class _DebtStatusBar extends StatelessWidget {
  const _DebtStatusBar({
    required this.leftLabel,
    required this.leftValue,
    required this.leftColor,
    required this.rightLabel,
    required this.rightValue,
    required this.rightColor,
    required this.progress,
    required this.barColor,
    required this.barBg,
  });

  final String leftLabel;
  final String leftValue;
  final Color leftColor;
  final String rightLabel;
  final String rightValue;
  final Color rightColor;
  final double progress;
  final Color barColor;
  final Color barBg;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.innerBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      leftLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      leftValue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: leftColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    rightLabel,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    rightValue,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: rightColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: barBg,
              color: barColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.tint,
    this.sub,
  });

  final String label;
  final String value;
  final Color tint;
  final String? sub;
}

class _ThreeMetricRow extends StatelessWidget {
  const _ThreeMetricRow({required this.metrics});

  final List<_MiniMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 500;
        final tiles = [
          for (final m in metrics)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: palette.innerBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    m.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: m.tint,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (m.sub != null)
                    Text(
                      m.sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
        ];

        if (wide) {
          return Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: tiles[i]),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              tiles[i],
            ],
          ],
        );
      },
    );
  }
}

class _PayoffPoint {
  const _PayoffPoint({
    required this.label,
    required this.amount,
    this.isCurrent = false,
    this.isZero = false,
  });

  final String label;
  final double amount;
  final bool isCurrent;
  final bool isZero;
}

List<_PayoffPoint> _buildPayoffPoints(double debt, double step) {
  final points = <_PayoffPoint>[
    _PayoffPoint(label: 'Hoy', amount: debt, isCurrent: true),
  ];
  if (debt <= 0.01 || step <= 0) return points;
  final totalMonths = (debt / step).ceil();
  if (totalMonths <= 8) {
    var rem = debt;
    for (var m = 1; m <= totalMonths; m++) {
      rem = math.max(0.0, rem - step);
      points.add(
        _PayoffPoint(
          label: rem <= 0.01 ? '¡Libre!' : 'M$m',
          amount: rem,
          isZero: rem <= 0.01,
        ),
      );
    }
  } else {
    // Sample evenly up to 8 bars, always ending on $0 milestone
    const slots = 7;
    for (var i = 1; i <= slots; i++) {
      final monthIdx = ((totalMonths * i) / slots).round().clamp(
        1,
        totalMonths,
      );
      final rem = math.max(0.0, debt - step * monthIdx);
      points.add(
        _PayoffPoint(
          label: rem <= 0.01 ? '¡Libre!' : 'M$monthIdx',
          amount: rem,
          isZero: rem <= 0.01,
        ),
      );
    }
  }
  return points;
}

/// Modern fintech interactive area & node paydown chart (Apple Stocks / Stripe style).
class _PayoffGradientChart extends StatefulWidget {
  const _PayoffGradientChart({
    required this.title,
    required this.points,
    required this.maxAmount,
    required this.startColor,
    required this.midColor,
    required this.zeroColor,
    required this.symbol,
    required this.hide,
  });

  final String title;
  final List<_PayoffPoint> points;
  final double maxAmount;
  final Color startColor;
  final Color midColor;
  final Color zeroColor;
  final String symbol;
  final bool hide;

  @override
  State<_PayoffGradientChart> createState() => _PayoffGradientChartState();
}

class _PayoffGradientChartState extends State<_PayoffGradientChart> {
  int? _hoveredIndex;

  void _updateHover(Offset localPos, double width) {
    if (widget.points.length <= 1) return;
    const leftPad = 48.0;
    const rightPad = 24.0;
    final usable = math.max(1.0, width - leftPad - rightPad);
    final t = ((localPos.dx - leftPad) / usable).clamp(0.0, 1.0);
    final idx = (t * (widget.points.length - 1)).round();
    if (idx != _hoveredIndex) {
      setState(() => _hoveredIndex = idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final activeIdx = _hoveredIndex != null &&
            _hoveredIndex! < widget.points.length
        ? _hoveredIndex
        : null;
    final activePt = activeIdx != null ? widget.points[activeIdx] : null;
    final paidSoFar = activePt != null
        ? math.max(0.0, widget.maxAmount - activePt.amount)
        : 0.0;
    final paidPct = widget.maxAmount > 0
        ? ((paidSoFar / widget.maxAmount) * 100).round().clamp(0, 100)
        : 100;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: palette.innerBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: Container(
                  key: ValueKey(activeIdx),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: palette.cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    activePt != null
                        ? (activePt.isZero
                              ? '${activePt.label} · ${widget.symbol}0 (100% pagado)'
                              : '${activePt.label} · Restan ${widget.hide ? '${widget.symbol}••' : '${widget.symbol}${activePt.amount.round()}'} ($paidPct%)')
                        : 'De ${widget.hide ? '${widget.symbol}••' : '${widget.symbol}${widget.maxAmount.round()}'} a ${widget.symbol}0',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: activePt?.isZero == true
                          ? palette.positive
                          : colors.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) => MouseRegion(
              cursor: SystemMouseCursors.precise,
              onHover: (e) => _updateHover(e.localPosition, constraints.maxWidth),
              onExit: (_) => setState(() => _hoveredIndex = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) =>
                    _updateHover(d.localPosition, constraints.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _updateHover(d.localPosition, constraints.maxWidth),
                child: SizedBox(
                  height: 176,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _PayoffChartPainter(
                      points: widget.points,
                      maxAmount: widget.maxAmount,
                      activeIndex: activeIdx,
                      lineColor: palette.negative,
                      zeroColor: palette.positive,
                      cardBg: palette.cardBg,
                      textColor: colors.onSurface,
                      mutedColor: colors.onSurfaceVariant,
                      gridColor: palette.border,
                      symbol: widget.symbol,
                      hide: widget.hide,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayoffChartPainter extends CustomPainter {
  const _PayoffChartPainter({
    required this.points,
    required this.maxAmount,
    required this.activeIndex,
    required this.lineColor,
    required this.zeroColor,
    required this.cardBg,
    required this.textColor,
    required this.mutedColor,
    required this.gridColor,
    required this.symbol,
    required this.hide,
  });

  final List<_PayoffPoint> points;
  final double maxAmount;
  final int? activeIndex;
  final Color lineColor;
  final Color zeroColor;
  final Color cardBg;
  final Color textColor;
  final Color mutedColor;
  final Color gridColor;
  final String symbol;
  final bool hide;

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 4.0;
    var x = a.dx;
    while (x < b.dx) {
      final end = math.min(x + dash, b.dx);
      canvas.drawLine(Offset(x, a.dy), Offset(end, b.dy), paint);
      x += dash + gap;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const leftPad = 48.0;
    const rightPad = 24.0;
    const topPad = 26.0;
    const bottomPad = 28.0;
    final chartW = math.max(40.0, size.width - leftPad - rightPad);
    final chartH = math.max(40.0, size.height - topPad - bottomPad);
    final baseY = topPad + chartH;

    // 1. Crisp horizontal dashed gridlines + left Y-axis ticks (100%, 50%, 0%)
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.75)
      ..strokeWidth = 1;
    for (final level in const [1.0, 0.5, 0.0]) {
      final y = baseY - level * chartH;
      if (level == 0.0) {
        canvas.drawLine(
          Offset(leftPad, y),
          Offset(size.width - rightPad, y),
          gridPaint,
        );
      } else {
        _drawDashedLine(
          canvas,
          Offset(leftPad, y),
          Offset(size.width - rightPad, y),
          Paint()
            ..color = gridColor.withValues(alpha: 0.55)
            ..strokeWidth = 1,
        );
      }
      final tickVal = maxAmount * level;
      final tickLabel = level == 0.0
          ? '${symbol}0'
          : (hide ? '$symbol••' : '$symbol${tickVal.round()}');
      final tp = TextPainter(
        text: TextSpan(
          text: tickLabel,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: mutedColor.withValues(alpha: 0.8),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: leftPad - 8);
      tp.paint(canvas, Offset(leftPad - tp.width - 10, y - tp.height / 2));
    }

    // 2. Compute smooth coordinates
    final coords = <Offset>[];
    final count = points.length;
    for (var i = 0; i < count; i++) {
      final pt = points[i];
      final t = count == 1 ? 0.5 : i / (count - 1);
      final x = leftPad + t * chartW;
      final ratio = maxAmount > 0 ? (pt.amount / maxAmount).clamp(0.0, 1.0) : 0.0;
      final y = baseY - ratio * chartH;
      coords.add(Offset(x, y));
    }

    // 3. Build smooth monotonic-feel Bezier curve + translucent area fill
    if (coords.length >= 2) {
      final curve = Path()..moveTo(coords.first.dx, coords.first.dy);
      for (var i = 1; i < coords.length; i++) {
        final prev = coords[i - 1];
        final curr = coords[i];
        final ctrlX = prev.dx + (curr.dx - prev.dx) * 0.45;
        curve.cubicTo(ctrlX, prev.dy, ctrlX, curr.dy, curr.dx, curr.dy);
      }

      final area = Path.from(curve)
        ..lineTo(coords.last.dx, baseY)
        ..lineTo(coords.first.dx, baseY)
        ..close();

      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              zeroColor.withValues(alpha: 0.16),
              zeroColor.withValues(alpha: 0.01),
            ],
          ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH)),
      );

      // Stroke smoothly transitioning from neutral/red start to green $0 finish
      canvas.drawPath(
        curve,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [lineColor, zeroColor],
            stops: const [0.0, 0.92],
          ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // 4. Active hover hairline guide
    if (activeIndex != null && activeIndex! < coords.length) {
      final activeCoord = coords[activeIndex!];
      canvas.drawLine(
        Offset(activeCoord.dx, topPad),
        Offset(activeCoord.dx, baseY),
        Paint()
          ..color = mutedColor.withValues(alpha: 0.35)
          ..strokeWidth = 1.2,
      );
    }

    // 5. Crisp data nodes + clean non-overlapping value & X-axis labels
    final showAllValues = count <= 8 && chartW / math.max(1, count) >= 54;
    for (var i = 0; i < count; i++) {
      final pt = points[i];
      final c = coords[i];
      final isHovered = i == activeIndex;
      final isFirst = i == 0;
      final isLast = i == count - 1;
      final nodeColor = pt.isZero
          ? zeroColor
          : Color.lerp(lineColor, zeroColor, i / math.max(1, count - 1))!;

      if (isHovered || pt.isZero) {
        canvas.drawCircle(
          c,
          isHovered ? 10 : 8.5,
          Paint()..color = nodeColor.withValues(alpha: 0.16),
        );
      }

      // Hollow core node (solid green on final $0 milestone)
      canvas.drawCircle(
        c,
        isHovered ? 5.2 : (pt.isZero ? 5.0 : 3.8),
        Paint()..color = pt.isZero ? zeroColor : cardBg,
      );
      canvas.drawCircle(
        c,
        isHovered ? 5.2 : (pt.isZero ? 5.0 : 3.8),
        Paint()
          ..color = nodeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHovered ? 2.6 : 2.0,
      );

      // Value label above node
      final showValue = isHovered ||
          isFirst ||
          isLast ||
          (showAllValues && activeIndex == null);
      if (showValue) {
        final valText = pt.isZero
            ? '${symbol}0'
            : (hide ? '$symbol••' : '$symbol${pt.amount.round()}');
        final valPainter = TextPainter(
          text: TextSpan(
            text: valText,
            style: TextStyle(
              fontSize: isHovered ? 11.5 : 10.5,
              fontWeight: isHovered || pt.isZero || isFirst
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: pt.isZero
                  ? zeroColor
                  : (isHovered ? textColor : mutedColor),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final labelX = (c.dx - valPainter.width / 2).clamp(
          leftPad,
          size.width - rightPad - valPainter.width,
        );
        final labelY = math.max(2.0, c.dy - (isHovered ? 24 : 20));
        valPainter.paint(canvas, Offset(labelX, labelY));
      }

      // Bottom month label
      final lblPainter = TextPainter(
        text: TextSpan(
          text: pt.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isHovered || pt.isZero || pt.isCurrent
                ? FontWeight.w700
                : FontWeight.w500,
            color: pt.isZero
                ? zeroColor
                : (isHovered ? textColor : mutedColor),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final lblX = (c.dx - lblPainter.width / 2).clamp(
        leftPad - 8,
        size.width - lblPainter.width - 4,
      );
      lblPainter.paint(canvas, Offset(lblX, baseY + 8));
    }
  }

  @override
  bool shouldRepaint(_PayoffChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.maxAmount != maxAmount ||
      oldDelegate.activeIndex != activeIndex ||
      oldDelegate.hide != hide ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.zeroColor != zeroColor;
}

class _DebtFreeBanner extends StatelessWidget {
  const _DebtFreeBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = FinancePalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.positive.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.positive.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.shieldCheck,
            color: palette.positive,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: palette.positive,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySectionCard extends StatelessWidget {
  const _EmptySectionCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 460;
          final iconBox = Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 22, color: accent),
          );
          final textCol = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          );
          final button = CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            minimumSize: Size.zero,
            borderRadius: BorderRadius.circular(10),
            onPressed: onAction,
            child: Text(
              actionLabel,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          );
          if (wide) {
            return Row(
              children: [
                iconBox,
                const SizedBox(width: 14),
                Expanded(child: textCol),
                const SizedBox(width: 12),
                button,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  iconBox,
                  const SizedBox(width: 12),
                  Expanded(child: textCol),
                ],
              ),
              const SizedBox(height: 14),
              button,
            ],
          );
        },
      ),
    );
  }
}
