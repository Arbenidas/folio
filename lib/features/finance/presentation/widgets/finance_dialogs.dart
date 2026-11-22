import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/folio_dialogs.dart';
import '../../domain/finance_models.dart';
import '../controllers/finance_controller.dart';

const _swatchColors = [
  '#286863',
  '#315F91',
  '#2E7D5B',
  '#C96A3B',
  '#B45B3E',
  '#6F58A8',
  '#C48B28',
  '#B94A48',
];

/// Native macOS-style select menu pill (never produces Material DropdownButton's
/// gray full-width focus highlight bar inside Wrap/Row layouts).
class FolioSelectOption<T> {
  const FolioSelectOption({
    required this.value,
    required this.label,
    this.icon,
    this.tint,
    this.subtitle,
  });

  final T value;
  final String label;
  final IconData? icon;
  final Color? tint;
  final String? subtitle;
}

class FolioSelectPill<T> extends StatefulWidget {
  const FolioSelectPill({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.expand = false,
    this.height = 36,
    this.placeholder = 'Elegir…',
  });

  final T? value;
  final List<FolioSelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final bool expand;
  final double height;
  final String placeholder;

  @override
  State<FolioSelectPill<T>> createState() => _FolioSelectPillState<T>();
}

class _FolioSelectPillState<T> extends State<FolioSelectPill<T>> {
  bool _hovered = false;

  Future<void> _openMenu() async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlay == null) return;
    final offset = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = Rect.fromLTWH(
      offset.dx,
      offset.dy + renderBox.size.height + 4,
      renderBox.size.width,
      renderBox.size.height,
    );
    final colors = Theme.of(context).colorScheme;
    final selected = await showMenu<T>(
      context: context,
      color: colors.surface,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(color: colors.outlineVariant),
      ),
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        for (final opt in widget.options)
          PopupMenuItem<T>(
            value: opt.value,
            height: 36,
            child: Row(
              children: [
                if (opt.icon != null) ...[
                  Icon(
                    opt.icon,
                    size: 16,
                    color: opt.tint ?? colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        opt.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: opt.value == widget.value
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: colors.onSurface,
                        ),
                      ),
                      if (opt.subtitle != null)
                        Text(
                          opt.subtitle!,
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
                if (opt.value == widget.value) ...[
                  const SizedBox(width: 8),
                  Icon(
                    CupertinoIcons.checkmark,
                    size: 14,
                    color: colors.primary,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
    if (selected != null && mounted) {
      widget.onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    FolioSelectOption<T>? current;
    for (final opt in widget.options) {
      if (opt.value == widget.value) {
        current = opt;
        break;
      }
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.options.isEmpty ? null : _openMenu,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: _hovered
                ? colors.surfaceContainerHigh.withValues(alpha: 0.72)
                : colors.surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: _hovered
                  ? colors.primary.withValues(alpha: 0.55)
                  : colors.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (current?.icon != null) ...[
                Icon(
                  current!.icon,
                  size: 15,
                  color: current.tint ?? colors.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
              ],
              if (widget.expand)
                Expanded(
                  child: Text(
                    current?.label ?? widget.placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: current != null
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 165),
                  child: Text(
                    current?.label ?? widget.placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: current != null
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Icon(
                CupertinoIcons.chevron_up_chevron_down,
                size: 12,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showFinanceTransactionDialog(
  BuildContext context, {
  required FinanceController controller,
  FinanceTransaction? existing,
  TransactionKind initialKind = TransactionKind.expense,
  String? initialAccountId,
  String? initialToAccountId,
  double? initialAmount,
  String? initialNote,
  void Function(String warning)? onBudgetWarning,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _TransactionDialog(
      controller: controller,
      existing: existing,
      initialKind: initialKind,
      initialAccountId: initialAccountId,
      initialToAccountId: initialToAccountId,
      initialAmount: initialAmount,
      initialNote: initialNote,
      onBudgetWarning: onBudgetWarning,
    ),
  );
}

class _TransactionDialog extends StatefulWidget {
  const _TransactionDialog({
    required this.controller,
    required this.initialKind,
    this.existing,
    this.initialAccountId,
    this.initialToAccountId,
    this.initialAmount,
    this.initialNote,
    this.onBudgetWarning,
  });

  final FinanceController controller;
  final FinanceTransaction? existing;
  final TransactionKind initialKind;
  final String? initialAccountId;
  final String? initialToAccountId;
  final double? initialAmount;
  final String? initialNote;
  final void Function(String warning)? onBudgetWarning;

  @override
  State<_TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends State<_TransactionDialog> {
  late TransactionKind _kind;
  late TextEditingController _amountCtrl;
  late TextEditingController _noteCtrl;
  late String _accountId;
  String? _toAccountId;
  String? _categoryId;
  late DateTime _date;
  bool _applyAccountFee = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final tx = widget.existing;
    _kind = tx?.kind ?? widget.initialKind;
    _amountCtrl = TextEditingController(
      text: tx != null
          ? tx.amount.toStringAsFixed(2)
          : (widget.initialAmount != null && widget.initialAmount! > 0
                ? widget.initialAmount!.toStringAsFixed(2)
                : ''),
    );
    _noteCtrl = TextEditingController(
      text: tx?.note ?? widget.initialNote ?? '',
    );
    final accounts = widget.controller.accounts;
    _accountId = tx?.accountId ?? widget.initialAccountId ?? accounts.first.id;
    _toAccountId =
        tx?.toAccountId ??
        widget.initialToAccountId ??
        (accounts.length > 1
            ? accounts.firstWhere((a) => a.id != _accountId).id
            : accounts.first.id);
    _date = tx?.date ?? DateTime.now();
    _applyAccountFee = tx == null ? true : tx.feeAmount > 0;
    _syncDefaultCategory(tx?.categoryId);
    _amountCtrl.addListener(() => setState(() {}));
  }

  void _syncDefaultCategory([String? preferred]) {
    if (_kind == TransactionKind.transfer) {
      _categoryId = null;
      return;
    }
    final list = widget.controller.categoriesFor(_kind);
    if (preferred != null && list.any((c) => c.id == preferred)) {
      _categoryId = preferred;
    } else if (list.isNotEmpty) {
      _categoryId = list.first.id;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double get _parsedAmount =>
      double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.')) ?? 0;

  double get _calculatedFee {
    if (!_applyAccountFee || _kind == TransactionKind.income) return 0;
    return widget.controller.computeFeeFor(_accountId, _kind, _parsedAmount);
  }

  void _save() {
    final amount = _parsedAmount;
    if (amount <= 0) {
      setState(() => _error = 'Ingresa un monto válido mayor a 0.');
      return;
    }
    if (_kind == TransactionKind.transfer && _accountId == _toAccountId) {
      setState(() => _error = 'Elige dos cuentas distintas para transferir.');
      return;
    }
    final fee = _calculatedFee;

    if (widget.existing != null) {
      widget.controller.updateTransaction(
        widget.existing!.copyWith(
          kind: _kind,
          amount: amount,
          accountId: _accountId,
          toAccountId: _kind == TransactionKind.transfer ? _toAccountId : null,
          clearToAccount: _kind != TransactionKind.transfer,
          categoryId: _kind == TransactionKind.transfer ? null : _categoryId,
          clearCategory: _kind == TransactionKind.transfer,
          date: _date,
          note: _noteCtrl.text.trim(),
          feeAmount: fee,
        ),
      );
    } else {
      final warning = widget.controller.addTransaction(
        kind: _kind,
        amount: amount,
        accountId: _accountId,
        toAccountId: _toAccountId,
        categoryId: _categoryId,
        date: _date,
        note: _noteCtrl.text.trim(),
        feeAmount: fee,
      );
      if (warning != null) {
        widget.onBudgetWarning?.call(warning);
      }
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final style = FolioStyle.of(context);
    final accounts = widget.controller.accounts;
    final categories = _kind == TransactionKind.transfer
        ? const <FinanceCategory>[]
        : widget.controller.categoriesFor(_kind);
    final selectedAccount = widget.controller.accountById(_accountId);
    final hasFee =
        selectedAccount?.hasTransactionFee == true &&
        _kind != TransactionKind.income;
    final feePreview = _calculatedFee;

    final accountOptions = [
      for (final acc in accounts)
        FolioSelectOption<String>(
          value: acc.id,
          label: acc.name,
          subtitle: acc.hasTransactionFee
              ? '${acc.transactionFeePercent!.toStringAsFixed(acc.transactionFeePercent! % 1 == 0 ? 0 : 1)}% comisión por transacción'
              : FinanceFormat.accountKindLabel(acc.kind),
          icon: FinanceFormat.accountIcon(acc.kind),
          tint: palette.adaptiveHex(acc.colorHex),
        ),
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(style.isGraphic ? 14 : 16),
            border: Border.all(
              color: style.isGraphic ? style.ink : colors.outlineVariant,
              width: style.isGraphic ? style.lineWidth : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.money_dollar_circle,
                      size: 22,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.existing == null
                            ? 'Nuevo movimiento'
                            : 'Editar movimiento',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.all(4),
                      minimumSize: Size.zero,
                      onPressed: () => Navigator.of(context).pop(),
                      child: Icon(
                        CupertinoIcons.xmark,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CupertinoSlidingSegmentedControl<TransactionKind>(
                  groupValue: _kind,
                  onValueChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _kind = value;
                      _error = null;
                      _syncDefaultCategory();
                    });
                  },
                  children: const {
                    TransactionKind.expense: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Gasto', style: TextStyle(fontSize: 13)),
                    ),
                    TransactionKind.income: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Ingreso', style: TextStyle(fontSize: 13)),
                    ),
                    TransactionKind.transfer: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Transferencia',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FieldLabel('Monto (${widget.controller.currencyCode})'),
                          const SizedBox(height: 6),
                          CupertinoTextField(
                            controller: _amountCtrl,
                            autofocus: true,
                            placeholder: '0.00',
                            prefix: Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Text(
                                widget.controller.currencySymbol,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                            decoration: _inputDecoration(colors),
                            onSubmitted: (_) => _save(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _FieldLabel('Concepto / Nota'),
                          const SizedBox(height: 6),
                          CupertinoTextField(
                            controller: _noteCtrl,
                            placeholder: _kind == TransactionKind.expense
                                ? 'Café, supermercado, renta…'
                                : _kind == TransactionKind.income
                                ? 'Pago quincenal, proyecto…'
                                : 'Pago tarjeta de crédito…',
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.onSurface,
                            ),
                            decoration: _inputDecoration(colors),
                            onSubmitted: (_) => _save(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FieldLabel(
                            _kind == TransactionKind.transfer
                                ? 'Desde cuenta'
                                : 'Cuenta',
                          ),
                          const SizedBox(height: 6),
                          FolioSelectPill<String>(
                            value: _accountId,
                            options: accountOptions,
                            expand: true,
                            height: 38,
                            onChanged: (v) => setState(() => _accountId = v),
                          ),
                        ],
                      ),
                    ),
                    if (_kind == TransactionKind.transfer) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('Hacia cuenta'),
                            const SizedBox(height: 6),
                            FolioSelectPill<String>(
                              value: _toAccountId ?? accounts.first.id,
                              options: accountOptions,
                              expand: true,
                              height: 38,
                              onChanged: (v) =>
                                  setState(() => _toAccountId = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (hasFee) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: palette.warning.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: palette.warning.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.swap_horizontal_circle_rounded,
                          size: 18,
                          color: palette.warning,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Comisión ${selectedAccount!.transactionFeePercent!.toStringAsFixed(selectedAccount.transactionFeePercent! % 1 == 0 ? 0 : 1)}% por transacción',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                              ),
                              Text(
                                _applyAccountFee && _parsedAmount > 0
                                    ? 'Interés: +${FinanceFormat.money(feePreview, symbol: widget.controller.currencySymbol)} · Total cargado: ${FinanceFormat.money(_parsedAmount + feePreview, symbol: widget.controller.currencySymbol)}'
                                    : 'Se calculará automáticamente sobre el monto.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        CupertinoSwitch(
                          value: _applyAccountFee,
                          onChanged: (v) =>
                              setState(() => _applyAccountFee = v),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_kind != TransactionKind.transfer &&
                    categories.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const _FieldLabel('Categoría'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final cat in categories)
                        _CategoryChip(
                          category: cat,
                          selected: cat.id == _categoryId,
                          onTap: () => setState(() => _categoryId = cat.id),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const _FieldLabel('Fecha'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _QuickDateChip(
                      label: 'Hoy',
                      selected: _isSameDay(_date, DateTime.now()),
                      onTap: () => setState(() => _date = DateTime.now()),
                    ),
                    const SizedBox(width: 6),
                    _QuickDateChip(
                      label: 'Ayer',
                      selected: _isSameDay(
                        _date,
                        DateTime.now().subtract(const Duration(days: 1)),
                      ),
                      onTap: () => setState(
                        () => _date = DateTime.now().subtract(
                          const Duration(days: 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      color: colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null && mounted) {
                          setState(() => _date = picked);
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.calendar,
                            size: 14,
                            color: colors.onSurface,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_date.day}/${_date.month}/${_date.year}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (widget.existing != null) ...[
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        onPressed: () {
                          widget.controller.deleteTransaction(
                            widget.existing!.id,
                          );
                          Navigator.of(context).pop();
                        },
                        child: Text(
                          'Eliminar',
                          style: TextStyle(
                            color: colors.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (widget.existing!.recurringId == null &&
                          _kind != TransactionKind.transfer)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          onPressed: () {
                            widget.controller.convertTransactionToRecurring(
                              widget.existing!,
                            );
                            Navigator.of(context).pop();
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.repeat,
                                size: 13.5,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Hacer recurrente',
                                style: TextStyle(
                                  color: colors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const Spacer(),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancelar',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 9,
                      ),
                      minimumSize: Size.zero,
                      borderRadius: BorderRadius.circular(9),
                      onPressed: _save,
                      child: Text(
                        widget.existing == null ? 'Guardar' : 'Actualizar',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

Future<void> showFinanceAccountDialog(
  BuildContext context, {
  required FinanceController controller,
  FinanceAccount? existing,
  AccountKind? initialKind,
}) async {
  var kind = existing?.kind ?? initialKind ?? AccountKind.debit;
  final isDebt =
      kind == AccountKind.credit || kind == AccountKind.salaryAdvance;
  final nameCtrl = TextEditingController(
    text:
        existing?.name ??
        (initialKind == AccountKind.salaryAdvance
            ? 'Adelanto salarial'
            : initialKind == AccountKind.credit
            ? 'Tarjeta de crédito'
            : ''),
  );
  // When editing an existing account, show its LIVE real balance / debt today
  // so the user never has to do mental math with past transactions.
  final initialAmountDisplay = existing == null
      ? '0'
      : (isDebt
            ? controller.debtOfAccount(existing.id).toStringAsFixed(2)
            : controller.balanceOfAccount(existing.id).toStringAsFixed(2));
  final balanceCtrl = TextEditingController(text: initialAmountDisplay);
  final limitCtrl = TextEditingController(
    text: existing?.creditLimit != null
        ? existing!.creditLimit!.toStringAsFixed(2)
        : (initialKind == AccountKind.salaryAdvance ? '450' : ''),
  );
  final statementCtrl = TextEditingController(
    text: existing?.statementDay?.toString() ?? '',
  );
  final paymentDueCtrl = TextEditingController(
    text: existing?.paymentDueDay?.toString() ?? '',
  );
  final feeCtrl = TextEditingController(
    text: existing?.transactionFeePercent != null
        ? existing!.transactionFeePercent!.toStringAsFixed(
            existing.transactionFeePercent! % 1 == 0 ? 0 : 2,
          )
        : '',
  );
  var colorHex =
      existing?.colorHex ??
      (initialKind == AccountKind.salaryAdvance
          ? '#C48B28'
          : initialKind == AccountKind.credit
          ? '#B45B3E'
          : _swatchColors.first);
  final liquidAccounts = controller.liquidAccounts;
  String? linkedAccountId =
      existing?.linkedAccountId ??
      (liquidAccounts.isNotEmpty ? liquidAccounts.first.id : null);

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final colors = Theme.of(context).colorScheme;
        final isCredit = kind == AccountKind.credit;
        final isAdvance = kind == AccountKind.salaryAdvance;
        final isDebtKind = isCredit || isAdvance;

        final linkedOptions = [
          for (final acc in liquidAccounts)
            FolioSelectOption<String>(
              value: acc.id,
              label: acc.name,
              icon: FinanceFormat.accountIcon(acc.kind),
              tint: FinanceFormat.colorFromHex(acc.colorHex),
            ),
        ];

        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          FinanceFormat.accountIcon(kind),
                          size: 20,
                          color: FinanceFormat.colorFromHex(colorHex),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            existing == null ? 'Nueva cuenta' : 'Editar cuenta',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('Tipo de cuenta'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final k in AccountKind.values)
                          _QuickDateChip(
                            label: FinanceFormat.accountKindLabel(k),
                            selected: kind == k,
                            onTap: () => setState(() {
                              kind = k;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _FieldLabel('Nombre'),
                    const SizedBox(height: 6),
                    CupertinoTextField(
                      controller: nameCtrl,
                      autofocus: existing == null,
                      placeholder: isAdvance
                          ? 'Ej. Adelanto salarial nómina'
                          : isCredit
                          ? 'Ej. Visa Banco Agrícola'
                          : 'Ej. Cuenta corriente, Ahorro…',
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      style: TextStyle(fontSize: 14, color: colors.onSurface),
                      decoration: _inputDecoration(colors),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FieldLabel(
                                isDebtKind
                                    ? (existing == null
                                          ? 'Deuda actual hoy (${controller.currencyCode})'
                                          : 'Deuda real hoy (${controller.currencyCode})')
                                    : (existing == null
                                          ? 'Saldo actual hoy (${controller.currencyCode})'
                                          : 'Saldo real hoy (${controller.currencyCode})'),
                              ),
                              const SizedBox(height: 6),
                              CupertinoTextField(
                                controller: balanceCtrl,
                                placeholder: isDebtKind ? 'Ej. 335.00' : '0.00',
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.onSurface,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[-0-9.,]'),
                                  ),
                                ],
                                decoration: _inputDecoration(colors),
                              ),
                            ],
                          ),
                        ),
                        if (isDebtKind) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _FieldLabel(
                                  isAdvance
                                      ? 'Cupo adelanto (${controller.currencyCode})'
                                      : 'Límite crédito (${controller.currencyCode})',
                                ),
                                const SizedBox(height: 6),
                                CupertinoTextField(
                                  controller: limitCtrl,
                                  placeholder: isAdvance ? '450.00' : '1000.00',
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colors.onSurface,
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]'),
                                    ),
                                  ],
                                  decoration: _inputDecoration(colors),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (isCredit) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _FieldLabel('Día de corte (1–31)'),
                                const SizedBox(height: 6),
                                CupertinoTextField(
                                  controller: statementCtrl,
                                  placeholder: 'Ej. 15',
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colors.onSurface,
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: _inputDecoration(colors),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _FieldLabel('Día límite de pago (1–31)'),
                                const SizedBox(height: 6),
                                CupertinoTextField(
                                  controller: paymentDueCtrl,
                                  placeholder: 'Ej. 25',
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colors.onSurface,
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: _inputDecoration(colors),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (isAdvance) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _FieldLabel(
                                  'Comisión retiro % (opcional, según tu banco)',
                                ),
                                const SizedBox(height: 6),
                                CupertinoTextField(
                                  controller: feeCtrl,
                                  placeholder: 'Ej. 0, 3 o 4',
                                  suffix: Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: Text(
                                      '%',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colors.onSurface,
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]'),
                                    ),
                                  ],
                                  decoration: _inputDecoration(colors),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _FieldLabel('Día de descuento salarial'),
                                const SizedBox(height: 6),
                                CupertinoTextField(
                                  controller: paymentDueCtrl,
                                  placeholder: 'Ej. 15 ó 30',
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colors.onSurface,
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: _inputDecoration(colors),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (!isAdvance) ...[
                      const SizedBox(height: 12),
                      const _FieldLabel(
                        'Comisión por transacción % (opcional)',
                      ),
                      const SizedBox(height: 6),
                      CupertinoTextField(
                        controller: feeCtrl,
                        placeholder: '0 (déjalo vacío si no aplica)',
                        suffix: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            '%',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        style: TextStyle(fontSize: 13.5, color: colors.onSurface),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: _inputDecoration(colors),
                      ),
                    ],
                    if (isDebtKind && linkedOptions.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _FieldLabel(
                        isAdvance
                            ? 'Cuenta de débito / nómina vinculada'
                            : 'Cuenta desde donde pagas la tarjeta',
                      ),
                      const SizedBox(height: 6),
                      FolioSelectPill<String>(
                        value: linkedAccountId,
                        options: linkedOptions,
                        expand: true,
                        height: 38,
                        onChanged: (v) => setState(() => linkedAccountId = v),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const _FieldLabel('Color'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final hex in _swatchColors)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => setState(() => colorHex = hex),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: FinanceFormat.colorFromHex(hex),
                                  shape: BoxShape.circle,
                                  border: colorHex == hex
                                      ? Border.all(
                                          color: colors.onSurface,
                                          width: 2.5,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (existing != null && controller.accounts.length > 1)
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            onPressed: () {
                              controller.archiveAccount(existing.id);
                              Navigator.of(dialogContext).pop();
                            },
                            child: Text(
                              'Archivar',
                              style: TextStyle(
                                color: colors.error,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const Spacer(),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: Text(
                            'Cancelar',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 8),
                        CupertinoButton.filled(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 9,
                          ),
                          minimumSize: Size.zero,
                          borderRadius: BorderRadius.circular(9),
                          onPressed: () {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) return;
                            final rawBal =
                                double.tryParse(
                                  balanceCtrl.text.trim().replaceAll(',', '.'),
                                ) ??
                                0;
                            // Debt entered as positive (e.g. 298.07) is stored as negative balance.
                            final targetBalance = isDebtKind && rawBal > 0
                                ? -rawBal
                                : rawBal;
                            final initialBalance = existing != null
                                ? controller.initialBalanceForTargetCurrent(
                                    existing.id,
                                    targetBalance,
                                  )
                                : targetBalance;
                            final parsedLimit = double.tryParse(
                              limitCtrl.text.trim().replaceAll(',', '.'),
                            );
                            final parsedStatement = int.tryParse(
                              statementCtrl.text.trim(),
                            );
                            final parsedDue = int.tryParse(
                              paymentDueCtrl.text.trim(),
                            );
                            final parsedFee = double.tryParse(
                              feeCtrl.text.trim().replaceAll(',', '.'),
                            );

                            final limitVal =
                                parsedLimit != null && parsedLimit > 0
                                ? parsedLimit
                                : null;
                            final stmtVal =
                                isCredit &&
                                    parsedStatement != null &&
                                    parsedStatement >= 1 &&
                                    parsedStatement <= 31
                                ? parsedStatement
                                : null;
                            final dueVal =
                                isDebtKind &&
                                    parsedDue != null &&
                                    parsedDue >= 1 &&
                                    parsedDue <= 31
                                ? parsedDue
                                : null;
                            final feeVal = parsedFee != null && parsedFee > 0
                                ? parsedFee
                                : null;
                            final linkedVal = isDebtKind
                                ? linkedAccountId
                                : null;

                            if (existing != null) {
                              controller.updateAccount(
                                existing.copyWith(
                                  name: name,
                                  kind: kind,
                                  initialBalance: initialBalance,
                                  colorHex: colorHex,
                                  creditLimit: limitVal,
                                  clearCreditLimit: limitVal == null,
                                  statementDay: stmtVal,
                                  clearStatementDay: stmtVal == null,
                                  paymentDueDay: dueVal,
                                  clearPaymentDueDay: dueVal == null,
                                  transactionFeePercent: feeVal,
                                  clearTransactionFee: feeVal == null,
                                  linkedAccountId: linkedVal,
                                  clearLinkedAccount: linkedVal == null,
                                ),
                              );
                            } else {
                              controller.addAccount(
                                name: name,
                                kind: kind,
                                initialBalance: initialBalance,
                                colorHex: colorHex,
                                creditLimit: limitVal,
                                statementDay: stmtVal,
                                paymentDueDay: dueVal,
                                transactionFeePercent: feeVal,
                                linkedAccountId: linkedVal,
                              );
                            }
                            Navigator.of(dialogContext).pop();
                          },
                          child: const Text('Guardar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  nameCtrl.dispose();
  balanceCtrl.dispose();
  limitCtrl.dispose();
  statementCtrl.dispose();
  paymentDueCtrl.dispose();
  feeCtrl.dispose();
}

Future<void> showFinanceRecurringDialog(
  BuildContext context, {
  required FinanceController controller,
  RecurringPayment? existing,
}) async {
  final titleCtrl = TextEditingController(text: existing?.title ?? '');
  final amountCtrl = TextEditingController(
    text: existing != null ? existing.amount.toStringAsFixed(2) : '',
  );
  final dayCtrl = TextEditingController(
    text: existing != null ? '${existing.dayOfMonth}' : '15',
  );
  var kind = existing?.kind ?? TransactionKind.expense;
  // Default new recurring bills to Debit (not Cash!) so subscriptions don't
  // accidentally drain Efectivo into negative.
  final defaultAcc = controller.accounts.firstWhere(
    (a) => a.kind == AccountKind.debit,
    orElse: () => controller.accounts.first,
  );
  var accountId = existing?.accountId ?? defaultAcc.id;
  var categoryId =
      existing?.categoryId ??
      controller.categoriesFor(kind).first.id;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final colors = Theme.of(context).colorScheme;
        final categories = controller.categoriesFor(kind);
        if (!categories.any((c) => c.id == categoryId) &&
            categories.isNotEmpty) {
          categoryId = categories.first.id;
        }
        final accountOptions = [
          for (final acc in controller.accounts)
            FolioSelectOption<String>(
              value: acc.id,
              label: acc.name,
              subtitle: FinanceFormat.accountKindLabel(acc.kind),
              icon: FinanceFormat.accountIcon(acc.kind),
              tint: FinanceFormat.colorFromHex(acc.colorHex),
            ),
        ];
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    existing == null
                        ? 'Nuevo gasto fijo / recurrente'
                        : 'Editar pago recurrente',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),
                  CupertinoSlidingSegmentedControl<TransactionKind>(
                    groupValue: kind,
                    onValueChanged: (v) {
                      if (v == null) return;
                      setState(() => kind = v);
                    },
                    children: const {
                      TransactionKind.expense: Padding(
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Text('Gasto fijo'),
                      ),
                      TransactionKind.income: Padding(
                        padding: EdgeInsets.symmetric(vertical: 5),
                        child: Text('Ingreso fijo'),
                      ),
                    },
                  ),
                  const SizedBox(height: 14),
                  const _FieldLabel('Nombre'),
                  const SizedBox(height: 6),
                  CupertinoTextField(
                    controller: titleCtrl,
                    autofocus: existing == null,
                    placeholder: 'Ej. Internet, Alquiler, Spotify, Salario…',
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    style: TextStyle(fontSize: 14, color: colors.onSurface),
                    decoration: _inputDecoration(colors),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FieldLabel('Monto (${controller.currencyCode})'),
                            const SizedBox(height: 6),
                            CupertinoTextField(
                              controller: amountCtrl,
                              placeholder: '0.00',
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                color: colors.onSurface,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'),
                                ),
                              ],
                              decoration: _inputDecoration(colors),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _FieldLabel('Día (1–28)'),
                            const SizedBox(height: 6),
                            CupertinoTextField(
                              controller: dayCtrl,
                              placeholder: '15',
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                color: colors.onSurface,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: _inputDecoration(colors),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const _FieldLabel('Cuenta donde se cobra / deposita'),
                  const SizedBox(height: 6),
                  FolioSelectPill<String>(
                    value: accountId,
                    options: accountOptions,
                    expand: true,
                    height: 38,
                    onChanged: (v) => setState(() => accountId = v),
                  ),
                  const SizedBox(height: 12),
                  const _FieldLabel('Categoría'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final cat in categories)
                        _CategoryChip(
                          category: cat,
                          selected: cat.id == categoryId,
                          onTap: () => setState(() => categoryId = cat.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(
                          'Cancelar',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                        minimumSize: Size.zero,
                        borderRadius: BorderRadius.circular(9),
                        onPressed: () {
                          final title = titleCtrl.text.trim();
                          final amount = double.tryParse(
                            amountCtrl.text.trim().replaceAll(',', '.'),
                          );
                          final day =
                              (int.tryParse(dayCtrl.text.trim()) ?? 1).clamp(
                                1,
                                28,
                              );
                          if (title.isEmpty || amount == null || amount <= 0) {
                            return;
                          }
                          if (existing != null) {
                            controller.updateRecurring(
                              existing.copyWith(
                                title: title,
                                amount: amount,
                                kind: kind,
                                categoryId: categoryId,
                                accountId: accountId,
                                dayOfMonth: day,
                              ),
                            );
                          } else {
                            controller.addRecurring(
                              title: title,
                              amount: amount,
                              kind: kind,
                              categoryId: categoryId,
                              accountId: accountId,
                              dayOfMonth: day,
                            );
                          }
                          Navigator.of(dialogContext).pop();
                        },
                        child: Text(existing == null ? 'Guardar' : 'Actualizar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  titleCtrl.dispose();
  amountCtrl.dispose();
  dayCtrl.dispose();
}

Future<void> showFinanceLoanDialog(
  BuildContext context, {
  required FinanceController controller,
  FinanceLoan? existing,
}) async {
  final nameCtrl = TextEditingController(
    text: existing?.name ?? 'Préstamo personal',
  );
  final principalCtrl = TextEditingController(
    text: existing != null ? existing.principal.toStringAsFixed(2) : '5000',
  );
  final remainingCtrl = TextEditingController(
    text: existing != null
        ? existing.remainingBalance.toStringAsFixed(2)
        : '',
  );
  final paymentCtrl = TextEditingController(
    text: existing != null
        ? existing.monthlyPayment.toStringAsFixed(2)
        : '108.86',
  );
  final termCtrl = TextEditingController(
    text: (existing?.termMonths ?? 60).toString(),
  );
  final paidCtrl = TextEditingController(
    text: (existing?.paidMonths ?? 0).toString(),
  );
  final rateCtrl = TextEditingController(
    text: existing != null && existing.annualInterestRate > 0
        ? existing.annualInterestRate.toStringAsFixed(2)
        : '',
  );
  final dayCtrl = TextEditingController(
    text: (existing?.paymentDay ?? 15).toString(),
  );
  final liquidAccounts = controller.liquidAccounts;
  String? linkedAccountId =
      existing?.linkedAccountId ??
      (liquidAccounts.isNotEmpty ? liquidAccounts.first.id : null);
  final alreadyInRecurring =
      existing != null && controller.isLoanInRecurring(existing);
  var addToRecurring = existing == null ? true : alreadyInRecurring;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final colors = Theme.of(context).colorScheme;
        final palette = FinancePalette.of(context);
        final principalVal =
            double.tryParse(principalCtrl.text.trim().replaceAll(',', '.')) ??
            0;
        final paymentVal =
            double.tryParse(paymentCtrl.text.trim().replaceAll(',', '.')) ?? 0;
        final termVal = int.tryParse(termCtrl.text.trim()) ?? 60;
        final manualRate = double.tryParse(
          rateCtrl.text.trim().replaceAll(',', '.'),
        );
        final estimatedRate = (manualRate == null || manualRate <= 0)
            ? FinanceLoan.estimateAnnualRate(
                principal: principalVal,
                monthlyPayment: paymentVal,
                termMonths: termVal,
              )
            : manualRate;

        final accountOptions = [
          for (final acc in controller.accounts)
            FolioSelectOption<String>(
              value: acc.id,
              label: acc.name,
              icon: FinanceFormat.accountIcon(acc.kind),
              tint: palette.adaptiveHex(acc.colorHex),
            ),
        ];

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.border),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: palette.purple.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.account_balance_rounded,
                            size: 18,
                            color: palette.purple,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            existing == null
                                ? 'Agregar préstamo'
                                : 'Editar préstamo',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        if (existing != null)
                          CupertinoButton(
                            padding: const EdgeInsets.all(6),
                            minimumSize: Size.zero,
                            onPressed: () {
                              controller.deleteLoan(existing.id);
                              Navigator.of(dialogContext).pop();
                            },
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: palette.negative,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const _FieldLabel('Nombre del préstamo'),
                    const SizedBox(height: 6),
                    CupertinoTextField(
                      controller: nameCtrl,
                      placeholder: 'Ej. Préstamo bancario 5 años',
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: _inputDecoration(colors),
                      style: TextStyle(fontSize: 14, color: colors.onSurface),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _FieldLabel('Monto original'),
                              const SizedBox(height: 6),
                              CupertinoTextField(
                                controller: principalCtrl,
                                onChanged: (_) => setState(() {}),
                                placeholder: '5000',
                                prefix: Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: Text(
                                    controller.currencySymbol,
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                decoration: _inputDecoration(colors),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _FieldLabel('Saldo pendiente actual'),
                              const SizedBox(height: 6),
                              CupertinoTextField(
                                controller: remainingCtrl,
                                placeholder: 'Igual al original',
                                prefix: Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: Text(
                                    controller.currencySymbol,
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                decoration: _inputDecoration(colors),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _FieldLabel('Cuota mensual'),
                              const SizedBox(height: 6),
                              CupertinoTextField(
                                controller: paymentCtrl,
                                onChanged: (_) => setState(() {}),
                                placeholder: '108.86',
                                prefix: Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: Text(
                                    controller.currencySymbol,
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                decoration: _inputDecoration(colors),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _FieldLabel('Tasa anual % (opcional)'),
                              const SizedBox(height: 6),
                              CupertinoTextField(
                                controller: rateCtrl,
                                onChanged: (_) => setState(() {}),
                                placeholder: estimatedRate > 0
                                    ? '~${estimatedRate.toStringAsFixed(1)}% est.'
                                    : 'Ej. 11.0',
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                decoration: _inputDecoration(colors),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (estimatedRate > 0 &&
                        (manualRate == null || manualRate <= 0)) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Tasa estimada automáticamente: ${estimatedRate.toStringAsFixed(2)}% anual. Puedes ajustarla cuando tengas el documento del banco.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _FieldLabel('Plazo (meses)'),
                              const SizedBox(height: 6),
                              CupertinoTextField(
                                controller: termCtrl,
                                onChanged: (_) => setState(() {}),
                                placeholder: '60',
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                decoration: _inputDecoration(colors),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _FieldLabel('Cuotas pagadas'),
                              const SizedBox(height: 6),
                              CupertinoTextField(
                                controller: paidCtrl,
                                placeholder: '0',
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                decoration: _inputDecoration(colors),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _FieldLabel('Día de pago'),
                              const SizedBox(height: 6),
                              CupertinoTextField(
                                controller: dayCtrl,
                                placeholder: '15',
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                decoration: _inputDecoration(colors),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (accountOptions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const _FieldLabel('Cuenta desde donde se paga'),
                      const SizedBox(height: 6),
                      FolioSelectPill<String>(
                        value: linkedAccountId,
                        options: accountOptions,
                        expand: true,
                        height: 38,
                        onChanged: (v) => setState(() => linkedAccountId = v),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: palette.purple.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: palette.purple.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.calendar_badge_plus,
                            size: 18,
                            color: palette.purple,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Agregar cuota a gastos fijos (Recurrentes)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: colors.onSurface,
                                  ),
                                ),
                                Text(
                                  alreadyInRecurring
                                      ? 'Esta cuota ya forma parte de tus pagos fijos del mes.'
                                      : 'Recomendado: incluye la cuota mensual en tus pagos fijos.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          CupertinoSwitch(
                            value: addToRecurring,
                            onChanged: alreadyInRecurring
                                ? null
                                : (v) => setState(() => addToRecurring = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: Text(
                            'Cancelar',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 8),
                        CupertinoButton.filled(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 9,
                          ),
                          minimumSize: Size.zero,
                          borderRadius: BorderRadius.circular(9),
                          onPressed: () {
                            final name = nameCtrl.text.trim();
                            final principal =
                                double.tryParse(
                                  principalCtrl.text.trim().replaceAll(',', '.'),
                                ) ??
                                0;
                            final payment =
                                double.tryParse(
                                  paymentCtrl.text.trim().replaceAll(',', '.'),
                                ) ??
                                0;
                            if (name.isEmpty || principal <= 0 || payment <= 0) {
                              return;
                            }
                            final term = (int.tryParse(termCtrl.text.trim()) ??
                                    60)
                                .clamp(1, 480);
                            final paid = (int.tryParse(paidCtrl.text.trim()) ??
                                    0)
                                .clamp(0, term);
                            final day = (int.tryParse(dayCtrl.text.trim()) ??
                                    15)
                                .clamp(1, 31);
                            final remainingParsed = double.tryParse(
                              remainingCtrl.text.trim().replaceAll(',', '.'),
                            );
                            final remaining =
                                (remainingParsed != null && remainingParsed > 0)
                                ? remainingParsed
                                : principal;
                            final rate =
                                double.tryParse(
                                  rateCtrl.text.trim().replaceAll(',', '.'),
                                ) ??
                                0;

                            if (existing != null) {
                              final resolvedRate = rate > 0
                                  ? rate
                                  : FinanceLoan.estimateAnnualRate(
                                      principal: principal,
                                      monthlyPayment: payment,
                                      termMonths: term,
                                    );
                              final updatedLoan = existing.copyWith(
                                name: name,
                                principal: principal,
                                remainingBalance: remaining,
                                annualInterestRate: resolvedRate,
                                termMonths: term,
                                paidMonths: paid,
                                monthlyPayment: payment,
                                paymentDay: day,
                                linkedAccountId: linkedAccountId,
                              );
                              controller.updateLoan(updatedLoan);
                              if (addToRecurring && !alreadyInRecurring) {
                                controller.addLoanToRecurring(updatedLoan);
                              }
                            } else {
                              controller.addLoan(
                                name: name,
                                principal: principal,
                                remainingBalance: remaining,
                                annualInterestRate: rate,
                                termMonths: term,
                                paidMonths: paid,
                                monthlyPayment: payment,
                                paymentDay: day,
                                linkedAccountId: linkedAccountId,
                                addToRecurring: addToRecurring,
                              );
                            }
                            Navigator.of(dialogContext).pop();
                          },
                          child: Text(
                            existing == null ? 'Guardar préstamo' : 'Actualizar',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  nameCtrl.dispose();
  principalCtrl.dispose();
  remainingCtrl.dispose();
  paymentCtrl.dispose();
  termCtrl.dispose();
  paidCtrl.dispose();
  rateCtrl.dispose();
  dayCtrl.dispose();
}

Future<void> showFinanceBudgetDialog(
  BuildContext context, {
  required FinanceController controller,
  required FinanceCategory category,
}) async {
  final raw = await showFolioPromptDialog(
    context,
    title: 'Presupuesto mensual · ${category.name}',
    initial: category.monthlyBudget?.toStringAsFixed(0) ?? '',
    hint: 'Límite en ${controller.currencyCode} (vacío para quitar)',
    confirmLabel: 'Guardar',
    icon: CupertinoIcons.chart_pie,
  );
  if (raw == null) return;
  final trimmed = raw.trim().replaceAll(',', '.');
  if (trimmed.isEmpty) {
    controller.setCategoryBudget(category.id, null);
    return;
  }
  final parsed = double.tryParse(trimmed);
  if (parsed != null) {
    controller.setCategoryBudget(category.id, parsed > 0 ? parsed : null);
  }
}

BoxDecoration _inputDecoration(ColorScheme colors) => BoxDecoration(
  color: colors.surfaceContainerLow,
  borderRadius: BorderRadius.circular(9),
  border: Border.all(color: colors.outlineVariant),
);

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final FinanceCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final tint = palette.adaptiveHex(category.colorHex);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
        decoration: BoxDecoration(
          color: selected
              ? tint.withValues(alpha: 0.18)
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? tint : colors.outlineVariant.withValues(alpha: 0.7),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FinanceFormat.categoryIcon(category.iconKey),
              size: 14,
              color: selected ? tint : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              category.name,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? colors.onSurface : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickDateChip extends StatelessWidget {
  const _QuickDateChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
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
