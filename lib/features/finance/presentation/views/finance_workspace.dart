import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/folio_dialogs.dart';
import '../../../cloud_sync/data/folio_cloud_sync_service.dart';
import '../../../onboarding/presentation/widgets/section_tour_card.dart';
import '../../../updates/data/patch_notes_service.dart';
import '../../../updates/presentation/patch_notes_dialog.dart';
import '../../domain/finance_models.dart';
import '../controllers/finance_controller.dart';
import '../widgets/finance_dialogs.dart';
import 'finance_accounts_view.dart';
import 'finance_budgets_view.dart';
import 'finance_debt_plan_view.dart';
import 'finance_lent_view.dart';
import 'finance_overview_view.dart';
import 'finance_recurring_view.dart';
import 'finance_transactions_view.dart';

enum _FinanceSection {
  overview,
  debtPlan,
  lent,
  transactions,
  budgets,
  accounts,
  recurring,
}

class FinanceWorkspace extends StatefulWidget {
  const FinanceWorkspace({
    super.key,
    required this.controller,
    this.onBudgetWarning,
    this.enableSectionTour = false,
    this.replayTourTrigger,
  });

  final FinanceController controller;
  final void Function(String message)? onBudgetWarning;
  final bool enableSectionTour;
  final ValueListenable<int>? replayTourTrigger;

  @override
  State<FinanceWorkspace> createState() => _FinanceWorkspaceState();
}

class _FinanceWorkspaceState extends State<FinanceWorkspace> {
  static const _tourDoneKey = 'folio_tour_finance_done_v1';

  // Spotlight GlobalKeys pointing to real interactive elements
  final GlobalKey _keySalaryCard = GlobalKey();
  final GlobalKey _keyHeroCard = GlobalKey();
  final GlobalKey _keyChartCard = GlobalKey();
  final GlobalKey _keyDebtRadarCard = GlobalKey();
  final GlobalKey _keyQuickAddFab = GlobalKey();
  final GlobalKey _keyNavDebtPlan = GlobalKey();
  final GlobalKey _keyNavTransactions = GlobalKey();
  final GlobalKey _keyNavBudgets = GlobalKey();
  final GlobalKey _keyNavRecurring = GlobalKey();

  bool get _needsSalarySetup =>
      _ctrl.primaryBudgetIncome <= 0 && _ctrl.monthIncome <= 0;

  List<(_FinanceSection, SectionTourStep)> _buildTourPlan() => [
    if (_needsSalarySetup)
      (
        _FinanceSection.overview,
        SectionTourStep(
          badge: 'PASO INICIAL · SALARIO',
          title: 'Empieza con tu ingreso mensual',
          description:
              'Ingresa aquí tu salario o ingreso mensual y día de pago. Folio lo guardará como ingreso recurrente y calculará todo automáticamente (no uses Gasto rápido para esto).',
          icon: LucideIcons.banknote,
          targetKey: _keySalaryCard,
          borderRadius: 18,
        ),
      ),
    (
      _FinanceSection.overview,
      SectionTourStep(
        badge: 'FINANZAS · RESUMEN',
        title: 'Tu dinero disponible hoy',
        description:
            'Aquí ves exactamente cuánto tienes libre para gastar hoy, separado de tus tarjetas y adelanto para evitar confusiones.',
        icon: LucideIcons.wallet,
        targetKey: _keyHeroCard,
        borderRadius: 18,
      ),
    ),
    (
      _FinanceSection.overview,
      SectionTourStep(
        badge: 'FINANZAS · GRÁFICAS',
        title: 'Cascada, Pastel y Diario',
        description:
            'Cambia el tipo de gráfica aquí para entender de un vistazo cómo se distribuyó tu dinero durante el mes.',
        icon: LucideIcons.chartColumn,
        targetKey: _keyChartCard,
        borderRadius: 18,
      ),
    ),
    (
      _FinanceSection.overview,
      SectionTourStep(
        badge: 'FINANZAS · CRÉDITO Y ADELANTO',
        title: 'Cupo libre y próximas fechas',
        description:
            'Monitorea tu cupo disponible hoy, fechas de corte/pago y liquida tu tarjeta o adelanto en un clic.',
        icon: LucideIcons.creditCard,
        targetKey: _keyDebtRadarCard,
        borderRadius: 18,
      ),
    ),
    (
      _FinanceSection.overview,
      SectionTourStep(
        badge: 'FINANZAS · GASTOS DIARIOS',
        title: 'Botón de gasto rápido',
        description:
            'Úsalo para anotar gastos del día a día (comida, gasolina, café) en 3 segundos sin salir de tu pantalla.',
        icon: LucideIcons.circlePlus,
        targetKey: _keyQuickAddFab,
        borderRadius: 24,
      ),
    ),
    (
      _FinanceSection.debtPlan,
      SectionTourStep(
        badge: 'FINANZAS · DEUDAS',
        title: 'Plan para salir de deudas',
        description:
            'Define tu propio ritmo para bajar el adelanto y la tarjeta a \$0, y simula abonos extra a capital en tus préstamos.',
        icon: LucideIcons.route,
        targetKey: _keyNavDebtPlan,
        borderRadius: 12,
      ),
    ),
    (
      _FinanceSection.transactions,
      SectionTourStep(
        badge: 'FINANZAS · MOVIMIENTOS',
        title: 'Movimientos agrupados por día',
        description:
            'Busca, filtra por cuenta y revisa tu balance de entradas y salidas organizado por fecha.',
        icon: LucideIcons.receiptText,
        targetKey: _keyNavTransactions,
        borderRadius: 12,
      ),
    ),
    (
      _FinanceSection.budgets,
      SectionTourStep(
        badge: 'FINANZAS · PRESUPUESTOS',
        title: 'Presupuesto según tu ingreso',
        description:
            'Parte de tu sueldo principal, descuenta fijos, préstamos y plan de deudas, y recibe una sugerencia real de ahorro.',
        icon: LucideIcons.chartPie,
        targetKey: _keyNavBudgets,
        borderRadius: 12,
      ),
    ),
    (
      _FinanceSection.recurring,
      SectionTourStep(
        badge: 'FINANZAS · RECURRENTES',
        title: 'Pagos e ingresos fijos',
        description:
            'Guarda tu salario, internet, suscripciones y cuotas para registrarlos cada mes en un solo toque.',
        icon: LucideIcons.calendarClock,
        targetKey: _keyNavRecurring,
        borderRadius: 12,
      ),
    ),
  ];

  _FinanceSection _section = _FinanceSection.overview;
  bool _hasUpdateAvailable = false;
  bool _hasUnreadNotes = false;
  bool _showSectionTour = false;
  int _tourStep = 0;

  // Floating quick-add state
  bool _quickAddOpen = false;
  TransactionKind _quickKind = TransactionKind.expense;
  final _quickAmountCtrl = TextEditingController();
  final _quickNoteCtrl = TextEditingController();
  String? _quickCategoryId;
  String? _quickAccountId;

  @override
  void initState() {
    super.initState();
    _quickAmountCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _ctrl.attachCloudSync(FolioCloudSyncService.instance);
    unawaited(FolioCloudSyncService.instance.ensureInitialized());
    unawaited(_checkPatchUpdatesSilently());
    widget.replayTourTrigger?.addListener(_restartSectionTour);
    if (widget.enableSectionTour) {
      unawaited(_maybeStartSectionTour());
    }
  }

  @override
  void didUpdateWidget(covariant FinanceWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replayTourTrigger != widget.replayTourTrigger) {
      oldWidget.replayTourTrigger?.removeListener(_restartSectionTour);
      widget.replayTourTrigger?.addListener(_restartSectionTour);
    }
  }

  Future<void> _maybeStartSectionTour() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool(_tourDoneKey) ?? false;
      if (!done && mounted) {
        final plan = _buildTourPlan();
        setState(() {
          _showSectionTour = true;
          _tourStep = 0;
          _section = plan.first.$1;
        });
      }
    } catch (_) {}
  }

  void _restartSectionTour() {
    if (!mounted) return;
    final plan = _buildTourPlan();
    setState(() {
      _showSectionTour = true;
      _tourStep = 0;
      _section = plan.first.$1;
      _quickAddOpen = false;
    });
  }

  void _goToTourStep(int next) {
    final plan = _buildTourPlan();
    final idx = next.clamp(0, plan.length - 1);
    setState(() {
      _tourStep = idx;
      _section = plan[idx].$1;
      _quickAddOpen = false;
    });
  }

  Future<void> _finishSectionTour() async {
    setState(() {
      _showSectionTour = false;
      _section = _FinanceSection.overview;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_tourDoneKey, true);
    } catch (_) {}
  }

  Future<void> _checkPatchUpdatesSilently() async {
    try {
      final result = await PatchNotesService.instance.checkForUpdates();
      final latestBuild = result.notes.isNotEmpty
          ? result.notes.first.build
          : AppVersionInfo.currentBuild;
      final unread = await PatchNotesService.instance.hasUnreadPatchNotes(
        latestBuild,
      );
      if (mounted) {
        setState(() {
          _hasUpdateAvailable = result.hasUpdate;
          _hasUnreadNotes = unread;
        });
      }
    } catch (_) {}
  }

  Future<void> _openPatchNotes() async {
    await showPatchNotesDialog(context);
    if (mounted) {
      setState(() => _hasUnreadNotes = false);
    }
  }

  @override
  void dispose() {
    widget.replayTourTrigger?.removeListener(_restartSectionTour);
    _quickAmountCtrl.dispose();
    _quickNoteCtrl.dispose();
    super.dispose();
  }

  FinanceController get _ctrl => widget.controller;

  void _ensureQuickDefaults() {
    final cats = _ctrl.categoriesFor(_quickKind);
    if (cats.isNotEmpty &&
        (_quickCategoryId == null ||
            !cats.any((c) => c.id == _quickCategoryId))) {
      _quickCategoryId = cats.first.id;
    }
    final accs = _ctrl.accounts;
    if (accs.isNotEmpty &&
        (_quickAccountId == null ||
            !accs.any((a) => a.id == _quickAccountId))) {
      _quickAccountId = accs.first.id;
    }
  }

  void _submitQuickAdd() {
    final amount = double.tryParse(
      _quickAmountCtrl.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) return;
    _ensureQuickDefaults();
    final accId = _quickAccountId ?? _ctrl.accounts.first.id;
    final warning = _ctrl.addTransaction(
      kind: _quickKind,
      amount: amount,
      accountId: accId,
      categoryId: _quickCategoryId,
      date: DateTime.now(),
      note: _quickNoteCtrl.text.trim(),
    );
    _quickAmountCtrl.clear();
    _quickNoteCtrl.clear();
    setState(() => _quickAddOpen = false);
    FocusScope.of(context).unfocus();
    if (warning != null) {
      widget.onBudgetWarning?.call(warning);
    }
  }

  void _openPayOffDialog(FinanceAccount target) {
    final debt = _ctrl.debtOfAccount(target.id);
    final liquid = _ctrl.liquidAccounts;
    final fromId =
        target.linkedAccountId != null &&
            _ctrl.accounts.any((a) => a.id == target.linkedAccountId)
        ? target.linkedAccountId!
        : (liquid.isNotEmpty ? liquid.first.id : _ctrl.accounts.first.id);
    final defaultNote = target.kind == AccountKind.salaryAdvance
        ? 'Descuento salario · ${target.name}'
        : 'Pago ${target.name}';
    unawaited(
      showFinanceTransactionDialog(
        context,
        controller: _ctrl,
        initialKind: TransactionKind.transfer,
        initialAccountId: fromId,
        initialToAccountId: target.id,
        initialAmount: debt > 0 ? debt : null,
        initialNote: defaultNote,
        onBudgetWarning: widget.onBudgetWarning,
      ),
    );
  }

  Future<void> _exportCsv() async {
    try {
      final path = await _ctrl.exportCsv();
      if (path != null && mounted) {
        await showFolioMessageDialog(
          context,
          title: 'CSV exportado',
          message: 'Tus movimientos financieros se guardaron correctamente.',
          icon: CupertinoIcons.table,
        );
      }
    } catch (error) {
      if (mounted) {
        await showFolioMessageDialog(
          context,
          title: 'Error al exportar',
          message: '$error',
          icon: CupertinoIcons.exclamationmark_triangle,
        );
      }
    }
  }

  Future<void> _pickCurrency() async {
    final chosen = await showFolioPickerDialog<CurrencyOption>(
      context,
      title: 'Moneda principal',
      subtitle: 'Elige la divisa para tu tracker de dinero.',
      icon: CupertinoIcons.money_dollar_circle,
      searchable: false,
      items: [
        for (final opt in CurrencyOption.supported)
          FolioPickerItem(
            value: opt,
            title: opt.label,
            subtitle: '${opt.symbol} · ${opt.code}',
            icon: opt.code == _ctrl.currencyCode
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.circle,
          ),
      ],
    );
    if (chosen != null) {
      _ctrl.setCurrency(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_ctrl, FolioCloudSyncService.instance]),
      builder: (context, _) {
        _ensureQuickDefaults();
        final colors = Theme.of(context).colorScheme;
        final style = FolioStyle.of(context);
        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 760;
            final bodyStack = _buildBodyStack(
              colors,
              style,
              maxWidth: constraints.maxWidth,
            );
            final content = isCompact
                ? Container(
                    color: colors.surface,
                    child: Column(
                      children: [
                        _buildMobileTopHeader(colors),
                        Expanded(child: bodyStack),
                        _buildMobileBottomBar(colors),
                      ],
                    ),
                  )
                : Container(
                    color: colors.surface,
                    child: Row(
                      children: [
                        _buildLeftRail(colors, style),
                        VerticalDivider(
                          width: style.isGraphic ? style.lineWidth : 1,
                          thickness: style.isGraphic ? style.lineWidth : 1,
                          color: style.isGraphic
                              ? style.ink
                              : colors.outlineVariant,
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              _buildTopHeader(colors, style),
                              Expanded(child: bodyStack),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );

            if (!_showSectionTour) return content;
            final plan = _buildTourPlan();
            final steps = [for (final item in plan) item.$2];
            final safeStep = _tourStep.clamp(0, steps.length - 1);
            return Stack(
              children: [
                Positioned.fill(child: content),
                Positioned.fill(
                  child: SpotlightTourOverlay(
                    steps: steps,
                    currentIndex: safeStep,
                    onSkip: () => unawaited(_finishSectionTour()),
                    onBack: () {
                      if (safeStep > 0) _goToTourStep(safeStep - 1);
                    },
                    onNext: () {
                      if (safeStep + 1 < steps.length) {
                        _goToTourStep(safeStep + 1);
                      } else {
                        unawaited(_finishSectionTour());
                      }
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBodyStack(
    ColorScheme colors,
    FolioStyle style, {
    required double maxWidth,
  }) {
    return Stack(
      children: [
        Positioned.fill(
          child: switch (_section) {
            _FinanceSection.overview => FinanceOverviewView(
              controller: _ctrl,
              onPayOffAccount: _openPayOffDialog,
              onOpenDebtPlan: () =>
                  setState(() => _section = _FinanceSection.debtPlan),
              onOpenTransactions: () =>
                  setState(() => _section = _FinanceSection.transactions),
              onOpenAccounts: () =>
                  setState(() => _section = _FinanceSection.accounts),
              onOpenBudgets: () =>
                  setState(() => _section = _FinanceSection.budgets),
              onOpenRecurring: () =>
                  setState(() => _section = _FinanceSection.recurring),
              onBudgetWarning: widget.onBudgetWarning,
              salaryCardKey: _keySalaryCard,
              heroTileKey: _keyHeroCard,
              chartTileKey: _keyChartCard,
              debtRadarTileKey: _keyDebtRadarCard,
            ),
            _FinanceSection.debtPlan => FinanceDebtPlanView(
              controller: _ctrl,
              onPayOffAccount: _openPayOffDialog,
              onEditAccount: (acc) => unawaited(
                showFinanceAccountDialog(
                  context,
                  controller: _ctrl,
                  existing: acc,
                ),
              ),
              onAddAdvanceAccount: () => unawaited(
                showFinanceAccountDialog(
                  context,
                  controller: _ctrl,
                  initialKind: AccountKind.salaryAdvance,
                ),
              ),
              onAddLoan: () => unawaited(
                showFinanceLoanDialog(context, controller: _ctrl),
              ),
              onEditLoan: (loan) => unawaited(
                showFinanceLoanDialog(
                  context,
                  controller: _ctrl,
                  existing: loan,
                ),
              ),
              onOpenRecurring: () =>
                  setState(() => _section = _FinanceSection.recurring),
            ),
            _FinanceSection.lent => FinanceLentView(controller: _ctrl),
            _FinanceSection.transactions => FinanceTransactionsView(
              controller: _ctrl,
              onBudgetWarning: widget.onBudgetWarning,
            ),
            _FinanceSection.budgets => FinanceBudgetsView(
              controller: _ctrl,
              onOpenRecurring: () =>
                  setState(() => _section = _FinanceSection.recurring),
              onOpenDebtPlan: () =>
                  setState(() => _section = _FinanceSection.debtPlan),
            ),
            _FinanceSection.accounts => FinanceAccountsView(
              controller: _ctrl,
              onPayOffAccount: _openPayOffDialog,
            ),
            _FinanceSection.recurring => FinanceRecurringView(
              controller: _ctrl,
              onBudgetWarning: widget.onBudgetWarning,
            ),
          },
        ),
        if (_quickAddOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _quickAddOpen = false),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
        if (_section == _FinanceSection.overview ||
            _section == _FinanceSection.transactions)
          Positioned(
            right: 16,
            bottom: 16,
            child: _buildFloatingQuickAdd(colors, style, maxWidth: maxWidth),
          ),
      ],
    );
  }

  Widget _buildMobileTopHeader(ColorScheme colors) {
    final palette = FinancePalette.of(context);
    final title = switch (_section) {
      _FinanceSection.overview => 'Resumen',
      _FinanceSection.debtPlan => 'Plan de deudas',
      _FinanceSection.lent => 'Me deben',
      _FinanceSection.transactions => 'Movimientos',
      _FinanceSection.budgets => 'Presupuesto',
      _FinanceSection.accounts => 'Cuentas',
      _FinanceSection.recurring => 'Recurrentes',
    };
    return SafeArea(
      bottom: false,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(bottom: BorderSide(color: palette.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                  Text(
                    FinanceFormat.monthTitle(_ctrl.selectedMonth),
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.all(6),
              minimumSize: Size.zero,
              onPressed: _ctrl.previousMonth,
              child: Icon(
                CupertinoIcons.chevron_left,
                size: 16,
                color: colors.onSurface,
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.all(6),
              minimumSize: Size.zero,
              onPressed: _ctrl.nextMonth,
              child: Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: colors.onSurface,
              ),
            ),
            CupertinoButton(
              padding: const EdgeInsets.all(6),
              minimumSize: Size.zero,
              onPressed: () => unawaited(_openPatchNotes()),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.new_releases_rounded,
                    size: 19,
                    color: _hasUpdateAvailable
                        ? palette.accent
                        : colors.onSurfaceVariant,
                  ),
                  if (_hasUpdateAvailable || _hasUnreadNotes)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _hasUpdateAvailable
                              ? palette.positive
                              : palette.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            CupertinoButton.filled(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              borderRadius: BorderRadius.circular(9),
              onPressed: () => unawaited(
                showFinanceTransactionDialog(
                  context,
                  controller: _ctrl,
                  onBudgetWarning: widget.onBudgetWarning,
                ),
              ),
              child: const Icon(CupertinoIcons.add, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileBottomBar(ColorScheme colors) {
    final palette = FinancePalette.of(context);
    final items = [
      (_FinanceSection.overview, LucideIcons.layoutGrid, 'Resumen', null),
      (
        _FinanceSection.debtPlan,
        LucideIcons.route,
        'Deudas',
        _keyNavDebtPlan,
      ),
      (
        _FinanceSection.lent,
        LucideIcons.handCoins,
        'Prestar',
        null,
      ),
      (
        _FinanceSection.transactions,
        LucideIcons.receiptText,
        'Movs',
        _keyNavTransactions,
      ),
      (
        _FinanceSection.budgets,
        LucideIcons.chartPie,
        'Presup.',
        _keyNavBudgets,
      ),
      (
        _FinanceSection.accounts,
        LucideIcons.wallet,
        'Cuentas',
        null,
      ),
      (
        _FinanceSection.recurring,
        LucideIcons.calendarClock,
        'Fijos',
        _keyNavRecurring,
      ),
    ];
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border(top: BorderSide(color: palette.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            for (final item in items)
              Expanded(
                child: GestureDetector(
                  key: item.$4,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _section = item.$1),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.$2,
                        size: 20,
                        color: _section == item.$1
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: _section == item.$1
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _section == item.$1
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftRail(ColorScheme colors, FolioStyle style) {
    final palette = FinancePalette.of(context);
    final hide = _ctrl.hideBalances;
    final sym = _ctrl.currencySymbol;
    return Container(
      width: 252,
      color: colors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.wallet,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 9),
                Text(
                  'FINANZAS',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: style.isRetro ? 'Menlo' : null,
                    letterSpacing: 1.15,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: hide ? 'Mostrar montos' : 'Ocultar montos',
                  child: CupertinoButton(
                    padding: const EdgeInsets.all(6),
                    minimumSize: Size.zero,
                    onPressed: _ctrl.toggleHideBalances,
                    child: Icon(
                      hide
                          ? LucideIcons.eyeOff
                          : LucideIcons.eye,
                      size: 17,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: style.isGraphic
                      ? style.ink.withValues(alpha: 0.4)
                      : palette.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Disponible hoy',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    FinanceFormat.money(
                      _ctrl.safeToSpendToday,
                      symbol: sym,
                      hide: hide,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: palette.positive,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_ctrl.totalAvailableCredit > 0)
                    Text(
                      '+${FinanceFormat.money(_ctrl.totalAvailableCredit, symbol: sym, hide: hide)} disp. en líneas',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurfaceVariant,
                      ),
                    )
                  else
                    Text(
                      '${_ctrl.accounts.length} cuentas activas · ${_ctrl.currencyCode}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  if (_ctrl.totalDebt > 0 || _ctrl.totalLoanDebt > 0) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _section = _FinanceSection.debtPlan),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: palette.border),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.route,
                              size: 14,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Plan de pago · ${FinanceFormat.money(_ctrl.totalDebt, symbol: sym, hide: hide)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              children: [
                _RailNavItem(
                  icon: LucideIcons.layoutGrid,
                  label: 'Resumen',
                  selected: _section == _FinanceSection.overview,
                  onTap: () =>
                      setState(() => _section = _FinanceSection.overview),
                ),
                _RailNavItem(
                  key: _keyNavDebtPlan,
                  icon: LucideIcons.route,
                  label: 'Plan de deudas',
                  selected: _section == _FinanceSection.debtPlan,
                  onTap: () =>
                      setState(() => _section = _FinanceSection.debtPlan),
                ),
                _RailNavItem(
                  icon: LucideIcons.handCoins,
                  label: 'Me deben',
                  badge: _ctrl.activeLentMoney.isEmpty
                      ? null
                      : '${_ctrl.activeLentMoney.length}',
                  selected: _section == _FinanceSection.lent,
                  onTap: () => setState(() => _section = _FinanceSection.lent),
                ),
                _RailNavItem(
                  key: _keyNavTransactions,
                  icon: LucideIcons.receiptText,
                  label: 'Movimientos',
                  badge: '${_ctrl.monthTransactions.length}',
                  selected: _section == _FinanceSection.transactions,
                  onTap: () =>
                      setState(() => _section = _FinanceSection.transactions),
                ),
                _RailNavItem(
                  key: _keyNavBudgets,
                  icon: LucideIcons.chartPie,
                  label: 'Presupuestos',
                  selected: _section == _FinanceSection.budgets,
                  onTap: () =>
                      setState(() => _section = _FinanceSection.budgets),
                ),
                _RailNavItem(
                  icon: LucideIcons.wallet,
                  label: 'Cuentas',
                  badge: '${_ctrl.accounts.length}',
                  selected: _section == _FinanceSection.accounts,
                  onTap: () =>
                      setState(() => _section = _FinanceSection.accounts),
                ),
                _RailNavItem(
                  key: _keyNavRecurring,
                  icon: LucideIcons.calendarClock,
                  label: 'Recurrentes',
                  badge: _ctrl.recurring.isEmpty
                      ? null
                      : '${_ctrl.recurring.length}',
                  selected: _section == _FinanceSection.recurring,
                  onTap: () =>
                      setState(() => _section = _FinanceSection.recurring),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RailUtilityButton(
                  icon: Icons.new_releases_rounded,
                  label: _hasUpdateAvailable
                      ? 'Actualización disponible'
                      : 'Notas de parche',
                  highlightDot: _hasUpdateAvailable || _hasUnreadNotes,
                  onTap: () => unawaited(_openPatchNotes()),
                ),
                const SizedBox(height: 6),
                _RailUtilityButton(
                  icon: LucideIcons.banknote,
                  label:
                      'Moneda: ${_ctrl.currencyCode} (${_ctrl.currencySymbol})',
                  onTap: _pickCurrency,
                ),
                const SizedBox(height: 6),
                _RailUtilityButton(
                  icon: Icons.ios_share_rounded,
                  label: 'Exportar a CSV',
                  onTap: _exportCsv,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeader(ColorScheme colors, FolioStyle style) {
    final title = switch (_section) {
      _FinanceSection.overview => 'Resumen mensual',
      _FinanceSection.debtPlan => 'Plan para salir de deudas',
      _FinanceSection.lent => 'Préstamos a personas (Me deben)',
      _FinanceSection.transactions => 'Movimientos',
      _FinanceSection.budgets => 'Presupuesto mensual',
      _FinanceSection.accounts => 'Cuentas, tarjetas y adelanto',
      _FinanceSection.recurring => 'Gastos e ingresos recurrentes',
    };
    final now = DateTime.now();
    final isCurrentMonth =
        _ctrl.selectedMonth.year == now.year &&
        _ctrl.selectedMonth.month == now.month;

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(
            color: style.isGraphic ? style.ink : colors.outlineVariant,
            width: style.isGraphic ? style.lineWidth : 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.75),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: const EdgeInsets.all(5),
                  minimumSize: Size.zero,
                  onPressed: _ctrl.previousMonth,
                  child: Icon(
                    CupertinoIcons.chevron_left,
                    size: 15,
                    color: colors.onSurface,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    FinanceFormat.monthTitle(_ctrl.selectedMonth),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.all(5),
                  minimumSize: Size.zero,
                  onPressed: _ctrl.nextMonth,
                  child: Icon(
                    CupertinoIcons.chevron_right,
                    size: 15,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (!isCurrentMonth) ...[
            const SizedBox(width: 8),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              onPressed: _ctrl.resetToCurrentMonth,
              child: Text(
                'Hoy',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
            ),
          ],
          const SizedBox(width: 12),
          CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            minimumSize: Size.zero,
            borderRadius: BorderRadius.circular(9),
            onPressed: () => unawaited(
              showFinanceTransactionDialog(
                context,
                controller: _ctrl,
                onBudgetWarning: widget.onBudgetWarning,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.add, size: 15),
                SizedBox(width: 6),
                Text(
                  'Nuevo movimiento',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingQuickAdd(
    ColorScheme colors,
    FolioStyle style, {
    required double maxWidth,
  }) {
    final palette = FinancePalette.of(context);
    final cardWidth = math.min(392.0, math.max(280.0, maxWidth - 32.0));
    final cats = _ctrl.categoriesFor(_quickKind);
    final accs = _ctrl.accounts;
    final selectedAcc = _ctrl.accountById(_quickAccountId);
    final parsedAmt =
        double.tryParse(_quickAmountCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final feePreview = _quickAccountId != null
        ? _ctrl.computeFeeFor(_quickAccountId!, _quickKind, parsedAmt)
        : 0.0;

    final catOptions = [
      for (final c in cats)
        FolioSelectOption<String>(
          value: c.id,
          label: c.name,
          icon: FinanceFormat.categoryIcon(c.iconKey),
          tint: palette.adaptiveHex(c.colorHex),
        ),
    ];
    final accOptions = [
      for (final a in accs)
        FolioSelectOption<String>(
          value: a.id,
          label: a.name,
          subtitle: a.hasTransactionFee
              ? 'Comisión ${a.transactionFeePercent!.toStringAsFixed(a.transactionFeePercent! % 1 == 0 ? 0 : 1)}%'
              : FinanceFormat.accountKindLabel(a.kind),
          icon: FinanceFormat.accountIcon(a.kind),
          tint: palette.adaptiveHex(a.colorHex),
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 170),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: _quickAddOpen
              ? Container(
                  key: const ValueKey('floating-quick-add-card'),
                  width: cardWidth,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: style.isGraphic
                          ? style.ink
                          : colors.outlineVariant,
                      width: style.isGraphic ? style.lineWidth : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.24),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Registro rápido',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CupertinoSlidingSegmentedControl<TransactionKind>(
                            groupValue: _quickKind,
                            onValueChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _quickKind = v;
                                _quickCategoryId = null;
                                _ensureQuickDefaults();
                              });
                            },
                            children: const {
                              TransactionKind.expense: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                child: Text(
                                  'Gasto',
                                  style: TextStyle(fontSize: 11.5),
                                ),
                              ),
                              TransactionKind.income: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                child: Text(
                                  'Ingreso',
                                  style: TextStyle(fontSize: 11.5),
                                ),
                              ),
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 118,
                            child: CupertinoTextField(
                              controller: _quickAmountCtrl,
                              autofocus: true,
                              placeholder: '${_ctrl.currencySymbol} 0.00',
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 9,
                              ),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurface,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'),
                                ),
                              ],
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                              ),
                              onSubmitted: (_) => _submitQuickAdd(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CupertinoTextField(
                              controller: _quickNoteCtrl,
                              placeholder: 'Concepto…',
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              style: TextStyle(
                                fontSize: 13.5,
                                color: colors.onSurface,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                              ),
                              onSubmitted: (_) => _submitQuickAdd(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (catOptions.isNotEmpty)
                            Expanded(
                              child: FolioSelectPill<String>(
                                value: _quickCategoryId,
                                options: catOptions,
                                expand: true,
                                onChanged: (v) =>
                                    setState(() => _quickCategoryId = v),
                              ),
                            ),
                          if (catOptions.isNotEmpty && accOptions.isNotEmpty)
                            const SizedBox(width: 8),
                          if (accOptions.isNotEmpty)
                            Expanded(
                              child: FolioSelectPill<String>(
                                value: _quickAccountId,
                                options: accOptions,
                                expand: true,
                                onChanged: (v) =>
                                    setState(() => _quickAccountId = v),
                              ),
                            ),
                        ],
                      ),
                      if (selectedAcc?.hasTransactionFee == true &&
                          _quickKind == TransactionKind.expense) ...[
                        const SizedBox(height: 9),
                        Text(
                          parsedAmt > 0
                              ? 'Comisión ${selectedAcc!.transactionFeePercent!.toStringAsFixed(0)}%: +${FinanceFormat.money(feePreview, symbol: _ctrl.currencySymbol)} · Total ${FinanceFormat.money(parsedAmt + feePreview, symbol: _ctrl.currencySymbol)}'
                              : '${selectedAcc!.name} suma ${selectedAcc.transactionFeePercent!.toStringAsFixed(0)}% de comisión.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: palette.warning,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            onPressed: () {
                              setState(() => _quickAddOpen = false);
                              unawaited(
                                showFinanceTransactionDialog(
                                  context,
                                  controller: _ctrl,
                                  onBudgetWarning: widget.onBudgetWarning,
                                ),
                              );
                            },
                            child: Text(
                              'Más opciones…',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const Spacer(),
                          CupertinoButton.filled(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            borderRadius: BorderRadius.circular(9),
                            onPressed: _submitQuickAdd,
                            child: const Text(
                              'Registrar',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        DecoratedBox(
          key: _keyQuickAddFab,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            minimumSize: Size.zero,
            borderRadius: BorderRadius.circular(24),
            onPressed: () => setState(() => _quickAddOpen = !_quickAddOpen),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _quickAddOpen ? CupertinoIcons.xmark : CupertinoIcons.add,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Text(
                  _quickAddOpen ? 'Cerrar' : 'Gasto rápido',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RailNavItem extends StatelessWidget {
  const _RailNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9.5),
          decoration: BoxDecoration(
            color: selected ? colors.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? colors.onSecondaryContainer
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? colors.onSecondaryContainer
                        : colors.onSurface,
                  ),
                ),
              ),
              if (badge != null)
                Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? colors.onSecondaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailUtilityButton extends StatelessWidget {
  const _RailUtilityButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlightDot = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlightDot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8.5),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: highlightDot
                ? palette.accent.withValues(alpha: 0.5)
                : colors.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15.5,
              color: highlightDot ? palette.accent : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
            ),
            if (highlightDot)
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: palette.positive,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
