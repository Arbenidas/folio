import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/widgets/folio_dialogs.dart';
import '../../domain/finance_models.dart';
import '../controllers/finance_controller.dart';
import '../widgets/finance_dialogs.dart';
import '../widgets/finance_shared_widgets.dart';

class FinanceBudgetsView extends StatefulWidget {
  const FinanceBudgetsView({
    super.key,
    required this.controller,
    required this.onOpenRecurring,
    required this.onOpenDebtPlan,
  });

  final FinanceController controller;
  final VoidCallback onOpenRecurring;
  final VoidCallback onOpenDebtPlan;

  @override
  State<FinanceBudgetsView> createState() => _FinanceBudgetsViewState();
}

class _FinanceBudgetsViewState extends State<FinanceBudgetsView> {
  bool _planningMode = false;
  final Map<String, TextEditingController> _draftCtrls = {};
  final Map<String, double> _draftValues = {};

  FinanceController get _ctrl => widget.controller;

  @override
  void dispose() {
    for (final c in _draftCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _enterPlannerMode({bool autoSuggest = false}) {
    final cats = _ctrl.categoriesFor(TransactionKind.expense);
    for (final cat in cats) {
      final initial = cat.monthlyBudget ?? 0.0;
      _draftValues[cat.id] = initial;
      final ctrl = _draftCtrls.putIfAbsent(
        cat.id,
        () => TextEditingController(),
      );
      ctrl.text = initial > 0 ? _fmtInput(initial) : '';
    }
    setState(() => _planningMode = true);
    if (autoSuggest) {
      _applySmartAutoDistribute();
    }
  }

  void _exitPlannerMode() {
    setState(() => _planningMode = false);
  }

  String _fmtInput(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

  void _setDraft(String catId, double value, {bool syncText = true}) {
    final clean = math.max(0.0, value);
    setState(() {
      _draftValues[catId] = clean;
      if (syncText) {
        final ctrl = _draftCtrls[catId];
        if (ctrl != null) {
          final formatted = clean > 0 ? _fmtInput(clean) : '';
          if (ctrl.text != formatted) {
            ctrl.text = formatted;
            ctrl.selection = TextSelection.collapsed(offset: formatted.length);
          }
        }
      }
    });
  }

  void _applySmartAutoDistribute() {
    final guide = _ctrl.recommendedLivingGuide;
    if (guide.isEmpty) return;
    setState(() {
      for (final entry in guide.entries) {
        _draftValues[entry.key] = entry.value.recommendedAmount;
        final ctrl = _draftCtrls.putIfAbsent(
          entry.key,
          () => TextEditingController(),
        );
        ctrl.text = entry.value.recommendedAmount > 0
            ? _fmtInput(entry.value.recommendedAmount)
            : '';
      }
    });
  }

  void _clearAllDrafts() {
    setState(() {
      for (final key in _draftValues.keys) {
        _draftValues[key] = 0.0;
        _draftCtrls[key]?.clear();
      }
    });
  }

  void _saveAllDrafts() {
    final cats = _ctrl.categoriesFor(TransactionKind.expense);
    for (final cat in cats) {
      final v = _draftValues[cat.id] ?? 0.0;
      _ctrl.setCategoryBudget(cat.id, v > 0 ? v : null);
    }
    setState(() => _planningMode = false);
  }

  double get _availablePoolForCategories => _ctrl.availableForLivingCategories;

  double get _activeCategoryTotal {
    if (_planningMode) {
      return _draftValues.values.fold<double>(0.0, (a, b) => a + b);
    }
    return _ctrl.totalMonthlyBudget;
  }

  Future<void> _editPrimaryIncome(BuildContext context) async {
    final raw = await showFolioPromptDialog(
      context,
      title: 'Ingreso principal del mes',
      initial: _ctrl.primaryBudgetIncome > 0
          ? _ctrl.primaryBudgetIncome.toStringAsFixed(2)
          : '',
      hint: 'Ej. 683.53 (vacío para usar tu salario recurrente)',
      confirmLabel: 'Guardar',
      icon: LucideIcons.banknote,
    );
    if (raw == null) return;
    final trimmed = raw.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) {
      _ctrl.setBudgetIncomeOverride(null);
      return;
    }
    final parsed = double.tryParse(trimmed);
    if (parsed != null && parsed > 0) {
      _ctrl.setBudgetIncomeOverride(parsed);
    }
  }

  Future<void> _editCustomSavingsDialog(BuildContext context) async {
    final sym = _ctrl.currencySymbol;
    final suggested = _ctrl.suggestedMonthlySavings;
    final raw = await showFolioPromptDialog(
      context,
      title: 'Ahorro del mes',
      initial: _ctrl.activeMonthlySavings > 0
          ? _ctrl.activeMonthlySavings.toStringAsFixed(2)
          : '0',
      hint:
          'Monto ($sym) o % (ej. 10%). Pon 0 si este mes no ahorrarás, o vacío para usar el sugerido.',
      confirmLabel: 'Guardar',
      icon: LucideIcons.piggyBank,
    );
    if (raw == null) return;
    final trimmed = raw.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) {
      _ctrl.setCustomSavingsAmount(null);
      return;
    }
    if (trimmed.endsWith('%')) {
      final pct = double.tryParse(
        trimmed.substring(0, trimmed.length - 1).trim(),
      );
      if (pct != null && pct >= 0) {
        final amt =
            ((_ctrl.primaryBudgetIncome * (pct / 100.0)) * 100)
                .roundToDouble() /
            100;
        _ctrl.setCustomSavingsAmount(amt);
      }
      return;
    }
    final parsed = double.tryParse(trimmed);
    if (parsed != null) {
      if ((parsed - suggested).abs() < 0.01) {
        _ctrl.setCustomSavingsAmount(null);
      } else {
        _ctrl.setCustomSavingsAmount(math.max(0.0, parsed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final expenseCats = _ctrl.categoriesFor(TransactionKind.expense);
    final hide = _ctrl.hideBalances;
    final sym = _ctrl.currencySymbol;

    final income = _ctrl.primaryBudgetIncome;
    final fixedNonLoan = _ctrl.nonLoanRecurringExpenses;
    final loanPayments = _ctrl.totalLoanMonthlyPayments;
    final debtPlan = _ctrl.effectiveDebtPlanForBudget;
    final activeSavings = _ctrl.activeMonthlySavings;
    final catBudgets = _activeCategoryTotal;
    final pool = _availablePoolForCategories;
    final remainingToAssign = pool - catBudgets;

    final barBase = math.max(
      income,
      fixedNonLoan + loanPayments + debtPlan + activeSavings + catBudgets,
    );
    final fixedShare = barBase > 0
        ? ((fixedNonLoan + loanPayments) / barBase).clamp(0.0, 1.0)
        : 0.0;
    final debtShare = barBase > 0 ? (debtPlan / barBase).clamp(0.0, 1.0) : 0.0;
    final savingsShare = barBase > 0
        ? (activeSavings / barBase).clamp(0.0, 1.0)
        : 0.0;
    final catShare = barBase > 0 ? (catBudgets / barBase).clamp(0.0, 1.0) : 0.0;
    final freeShare = math.max(
      0.0,
      1.0 - fixedShare - debtShare - savingsShare - catShare,
    );

    final budgetedCount = expenseCats
        .where((c) => (c.monthlyBudget ?? 0) > 0)
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 64),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. TOP ASYMMETRIC BENTO HERO (7:5 on desktop)
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 820;

                  final incomeHeroCard = FolioInteractiveBento(
                    enableHover: false,
                    padding: const EdgeInsets.all(20),
                    borderRadius: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            FolioIconBadge(
                              icon: LucideIcons.banknote,
                              tint: palette.positive,
                              size: 40,
                              iconSize: 19,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Ingreso principal del mes',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    FinanceFormat.money(
                                      income,
                                      symbol: sym,
                                      hide: hide,
                                    ),
                                    style: TextStyle(
                                      fontSize: 27,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.6,
                                      color: colors.onSurface,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              minimumSize: Size.zero,
                              color: palette.innerBg,
                              borderRadius: BorderRadius.circular(9),
                              onPressed: () =>
                                  unawaited(_editPrimaryIncome(context)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    LucideIcons.pencil,
                                    size: 13,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Editar',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: colors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Sleek segmented allocation bar (Compromisos · Ahorro · Libre)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: SizedBox(
                            height: 8,
                            child: Row(
                              children: [
                                if ((fixedShare + debtShare) > 0)
                                  Expanded(
                                    flex: ((fixedShare + debtShare) * 1000)
                                        .round()
                                        .clamp(1, 1000),
                                    child: Container(
                                      color: remainingToAssign < 0
                                          ? palette.negative
                                          : colors.onSurface.withValues(
                                              alpha: 0.72,
                                            ),
                                    ),
                                  ),
                                if (savingsShare > 0) ...[
                                  const SizedBox(width: 2),
                                  Expanded(
                                    flex: (savingsShare * 1000)
                                        .round()
                                        .clamp(1, 1000),
                                    child: Container(color: palette.positive),
                                  ),
                                ],
                                if (catShare > 0) ...[
                                  const SizedBox(width: 2),
                                  Expanded(
                                    flex: (catShare * 1000)
                                        .round()
                                        .clamp(1, 1000),
                                    child: Container(
                                      color: colors.onSurfaceVariant.withValues(
                                        alpha: 0.45,
                                      ),
                                    ),
                                  ),
                                ],
                                if (freeShare > 0) ...[
                                  const SizedBox(width: 2),
                                  Expanded(
                                    flex: (freeShare * 1000)
                                        .round()
                                        .clamp(1, 1000),
                                    child: Container(
                                      color: colors.surfaceContainerHighest,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Clean 2x2 breakdown grid (zero label truncation)
                        Builder(
                          builder: (_) {
                            final items = [
                              _DeductionMiniTile(
                                icon: LucideIcons.calendarClock,
                                label: 'Pagos fijos',
                                amount: FinanceFormat.money(
                                  fixedNonLoan,
                                  symbol: sym,
                                  hide: hide,
                                ),
                                tint: palette.accent,
                                onTap: widget.onOpenRecurring,
                              ),
                              _DeductionMiniTile(
                                icon: LucideIcons.landmark,
                                label: 'Préstamos',
                                amount: FinanceFormat.money(
                                  loanPayments,
                                  symbol: sym,
                                  hide: hide,
                                ),
                                tint: palette.purple,
                                onTap: widget.onOpenDebtPlan,
                              ),
                              _DeductionMiniTile(
                                icon: LucideIcons.route,
                                label: 'Plan deudas',
                                amount: FinanceFormat.money(
                                  debtPlan,
                                  symbol: sym,
                                  hide: hide,
                                ),
                                tint: palette.warning,
                                onTap: widget.onOpenDebtPlan,
                              ),
                              _DeductionMiniTile(
                                icon: LucideIcons.piggyBank,
                                label: 'Ahorro sugerido',
                                amount: FinanceFormat.money(
                                  activeSavings,
                                  symbol: sym,
                                  hide: hide,
                                ),
                                tint: palette.positive,
                                highlighted: activeSavings > 0,
                                onTap: () => unawaited(
                                  _editCustomSavingsDialog(context),
                                ),
                              ),
                            ];
                            return Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: items[0]),
                                    const SizedBox(width: 10),
                                    Expanded(child: items[1]),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(child: items[2]),
                                    const SizedBox(width: 10),
                                    Expanded(child: items[3]),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  );

                  final plannerPoolCard = FolioInteractiveBento(
                    enableHover: false,
                    padding: const EdgeInsets.all(20),
                    borderRadius: 20,
                    backgroundColor: remainingToAssign < 0
                        ? palette.negative.withValues(alpha: 0.08)
                        : palette.cardBg,
                    borderColor: remainingToAssign < 0
                        ? palette.negative.withValues(alpha: 0.5)
                        : palette.border,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              remainingToAssign < 0
                                  ? 'Excedido del disponible'
                                  : 'Libre para categorías',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              FinanceFormat.money(
                                remainingToAssign,
                                symbol: sym,
                                hide: hide,
                                showSign: remainingToAssign < 0,
                              ),
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.7,
                                color: remainingToAssign < 0
                                    ? palette.negative
                                    : palette.positive,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Asignado: ${FinanceFormat.money(catBudgets, symbol: sym, hide: hide)} de ${FinanceFormat.money(pool, symbol: sym, hide: hide)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (!_planningMode) ...[
                              CupertinoButton.filled(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8.5,
                                ),
                                minimumSize: Size.zero,
                                borderRadius: BorderRadius.circular(10),
                                onPressed: () => _enterPlannerMode(),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      LucideIcons.slidersHorizontal,
                                      size: 14,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Planificar todas',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (pool > 0)
                                CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8.5,
                                  ),
                                  minimumSize: Size.zero,
                                  color: palette.innerBg,
                                  borderRadius: BorderRadius.circular(10),
                                  onPressed: () =>
                                      _enterPlannerMode(autoSuggest: true),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        LucideIcons.compass,
                                        size: 14,
                                        color: colors.primary,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Auto-repartir',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: colors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (budgetedCount > 0)
                                CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 8.5,
                                  ),
                                  minimumSize: Size.zero,
                                  color: palette.innerBg,
                                  borderRadius: BorderRadius.circular(10),
                                  onPressed: _ctrl.clearAllCategoryBudgets,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        LucideIcons.rotateCcw,
                                        size: 13.5,
                                        color: colors.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Quitar límites',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ] else ...[
                              CupertinoButton.filled(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8.5,
                                ),
                                minimumSize: Size.zero,
                                borderRadius: BorderRadius.circular(10),
                                onPressed: _saveAllDrafts,
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.check, size: 14),
                                    SizedBox(width: 5),
                                    Text(
                                      'Guardar todo',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 8.5,
                                ),
                                minimumSize: Size.zero,
                                color: palette.innerBg,
                                borderRadius: BorderRadius.circular(10),
                                onPressed: _applySmartAutoDistribute,
                                child: Text(
                                  'Sugerir',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8.5,
                                ),
                                minimumSize: Size.zero,
                                color: palette.innerBg,
                                borderRadius: BorderRadius.circular(10),
                                onPressed: _exitPlannerMode,
                                child: Text(
                                  'Cancelar',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: incomeHeroCard),
                        const SizedBox(width: 14),
                        Expanded(flex: 5, child: plannerPoolCard),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      incomeHeroCard,
                      const SizedBox(height: 12),
                      plannerPoolCard,
                    ],
                  );
                },
              ),

              const SizedBox(height: 22),

              // 2. CATEGORY BUDGETS HEADER
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _planningMode
                              ? 'Planificador rápido de categorías'
                              : 'Presupuestos por categoría',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _planningMode
                              ? 'Ajusta todas tus categorías aquí mismo y pulsa «Guardar todo».'
                              : '$budgetedCount de ${expenseCats.length} categorías con límite definido',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_planningMode)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      onPressed: _clearAllDrafts,
                      child: Text(
                        'Limpiar todo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  else ...[
                    if (budgetedCount > 0) ...[
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        color: palette.cardBg,
                        borderRadius: BorderRadius.circular(9),
                        onPressed: _ctrl.clearAllCategoryBudgets,
                        child: Text(
                          'Quitar límites',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      color: palette.cardBg,
                      borderRadius: BorderRadius.circular(9),
                      onPressed: () => _enterPlannerMode(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.slidersHorizontal,
                            size: 13,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Definir todas',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 12),

              // 3. BODY: INLINE MULTI-CATEGORY PLANNER OR CLEAN 2-COL BENTO GRID
              if (_planningMode)
                _buildInlinePlanner(
                  context,
                  expenseCats: expenseCats,
                  pool: pool,
                  colors: colors,
                  palette: palette,
                  sym: sym,
                  hide: hide,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth >= 900
                        ? 3
                        : (constraints.maxWidth >= 600 ? 2 : 1);
                    const gap = 14.0;
                    final cardWidth =
                        (constraints.maxWidth - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final cat in expenseCats)
                          SizedBox(
                            width: cardWidth,
                            child: _buildCategoryCard(
                              context,
                              cat,
                              colors,
                              palette,
                              sym,
                              hide,
                            ),
                          ),
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

  Widget _buildInlinePlanner(
    BuildContext context, {
    required List<FinanceCategory> expenseCats,
    required double pool,
    required ColorScheme colors,
    required FinancePalette palette,
    required String sym,
    required bool hide,
  }) {
    final sliderCap = math.max(100.0, (pool > 0 ? pool : 400.0));

    return FolioInteractiveBento(
      enableHover: false,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      borderRadius: 18,
      child: Column(
        children: [
          for (var i = 0; i < expenseCats.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: palette.border.withValues(alpha: 0.55)),
            _buildPlannerRow(
              expenseCats[i],
              sliderCap: sliderCap,
              colors: colors,
              palette: palette,
              sym: sym,
              hide: hide,
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total presupuestado: ${FinanceFormat.money(_activeCategoryTotal, symbol: sym, hide: hide)}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                onPressed: _exitPlannerMode,
                child: Text(
                  'Cancelar',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                minimumSize: Size.zero,
                borderRadius: BorderRadius.circular(10),
                onPressed: _saveAllDrafts,
                child: const Text(
                  'Guardar presupuestos',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlannerRow(
    FinanceCategory cat, {
    required double sliderCap,
    required ColorScheme colors,
    required FinancePalette palette,
    required String sym,
    required bool hide,
  }) {
    final spent = _ctrl.spentInCategoryForMonth(cat.id, _ctrl.selectedMonth);
    final tint = palette.adaptiveHex(cat.colorHex);
    final val = _draftValues[cat.id] ?? 0.0;
    final ctrl = _draftCtrls.putIfAbsent(
      cat.id,
      () => TextEditingController(text: val > 0 ? _fmtInput(val) : ''),
    );
    final maxSlider = math.max(sliderCap, math.max(val, spent * 1.4));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 600;
          final labelBlock = Row(
            children: [
              FolioIconBadge(
                icon: FinanceFormat.categoryIcon(cat.iconKey),
                tint: tint,
                size: 34,
                iconSize: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cat.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      'Gastado: ${FinanceFormat.money(spent, symbol: sym, hide: hide)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final slider = SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: tint,
              inactiveTrackColor: colors.surfaceContainerHighest,
              thumbColor: tint,
              overlayColor: tint.withValues(alpha: 0.14),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: val.clamp(0.0, maxSlider),
              min: 0,
              max: maxSlider,
              onChanged: (v) {
                final snapped = maxSlider >= 100
                    ? (v / 5).round() * 5.0
                    : v.roundToDouble();
                _setDraft(cat.id, snapped);
              },
            ),
          );

          final inputRow = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spent > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 5,
                    ),
                    minimumSize: Size.zero,
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(7),
                    onPressed: () => _setDraft(cat.id, spent.ceilToDouble()),
                    child: Text(
                      '= Gasto',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              SizedBox(
                width: 108,
                child: CupertinoTextField(
                  controller: ctrl,
                  placeholder: '0.00',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      sym,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: palette.innerBg,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: val > 0
                          ? tint.withValues(alpha: 0.5)
                          : palette.border,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  onChanged: (raw) {
                    final parsed = double.tryParse(
                      raw.trim().replaceAll(',', '.'),
                    );
                    _setDraft(cat.id, parsed ?? 0.0, syncText: false);
                  },
                ),
              ),
            ],
          );

          if (wide) {
            return Row(
              children: [
                SizedBox(width: 185, child: labelBlock),
                const SizedBox(width: 10),
                Expanded(child: slider),
                const SizedBox(width: 10),
                inputRow,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: labelBlock),
                  const SizedBox(width: 8),
                  inputRow,
                ],
              ),
              slider,
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context,
    FinanceCategory cat,
    ColorScheme colors,
    FinancePalette palette,
    String sym,
    bool hide,
  ) {
    final spent = _ctrl.spentInCategoryForMonth(cat.id, _ctrl.selectedMonth);
    final limit = cat.monthlyBudget;
    final hasLimit = limit != null && limit > 0;
    final ratio = hasLimit ? (spent / limit) : 0.0;
    final tint = palette.adaptiveHex(cat.colorHex);
    final monthTotal = _ctrl.monthExpense;
    final spentShare = (!hasLimit && monthTotal > 0 && spent > 0)
        ? (spent / monthTotal).clamp(0.0, 1.0)
        : 0.0;
    final remaining = hasLimit ? (limit - spent) : null;

    final pctBadge = hasLimit
        ? '${(ratio * 100).round()}%'
        : (spentShare > 0 ? '${(spentShare * 100).round()}%' : null);

    return FolioInteractiveBento(
      hoverAccent: tint,
      padding: const EdgeInsets.all(18),
      borderRadius: 18,
      borderColor: ratio > 1
          ? palette.negative.withValues(alpha: 0.6)
          : palette.border,
      onTap: () => unawaited(
        showFinanceBudgetDialog(context, controller: _ctrl, category: cat),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FolioIconBadge(
                icon: FinanceFormat.categoryIcon(cat.iconKey),
                tint: tint,
                size: 36,
                iconSize: 17,
                borderRadius: 10,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  cat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              if (pctBadge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7.5,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: palette.innerBg,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    pctBadge,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ratio > 1
                          ? palette.negative
                          : colors.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                FinanceFormat.money(spent, symbol: sym, hide: hide),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: ratio > 1 ? palette.negative : colors.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasLimit
                      ? '/ ${FinanceFormat.money(limit, symbol: sym, hide: hide)}'
                      : 'Sin límite',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: hasLimit ? ratio.clamp(0.0, 1.0) : spentShare,
              minHeight: 5,
              backgroundColor: colors.surfaceContainerHighest,
              color: ratio > 1
                  ? palette.negative
                  : (hasLimit
                        ? palette.positive
                        : colors.onSurfaceVariant.withValues(alpha: 0.45)),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            hasLimit
                ? (remaining! >= 0
                      ? 'Quedan ${FinanceFormat.money(remaining, symbol: sym, hide: hide)}'
                      : 'Excedido por ${FinanceFormat.money(-remaining, symbol: sym, hide: hide)}')
                : (spentShare > 0
                      ? '${(spentShare * 100).round()}% del gasto del mes'
                      : 'Sin gasto este mes'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: hasLimit && remaining! < 0
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: hasLimit && remaining! < 0
                  ? palette.negative
                  : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeductionMiniTile extends StatelessWidget {
  const _DeductionMiniTile({
    required this.icon,
    required this.label,
    required this.amount,
    required this.tint,
    this.highlighted = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String amount;
  final Color tint;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);

    return FolioInteractiveBento(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      borderRadius: 14,
      backgroundColor: palette.innerBg,
      borderColor: palette.border,
      child: Row(
        children: [
          Icon(icon, size: 15, color: colors.onSurfaceVariant),
          const SizedBox(width: 9),
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
                const SizedBox(height: 2),
                Text(
                  amount,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: highlighted ? palette.positive : colors.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              LucideIcons.chevronRight,
              size: 14,
              color: colors.onSurfaceVariant.withValues(alpha: 0.65),
            ),
        ],
      ),
    );
  }
}
