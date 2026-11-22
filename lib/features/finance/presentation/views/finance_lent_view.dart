import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/finance_models.dart';
import '../controllers/finance_controller.dart';
import '../widgets/finance_dialogs.dart';
import '../widgets/finance_shared_widgets.dart';

class FinanceLentView extends StatelessWidget {
  const FinanceLentView({super.key, required this.controller});

  final FinanceController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    final hide = controller.hideBalances;
    final sym = controller.currencySymbol;

    final active = controller.activeLentMoney;
    final settled = controller.settledLentMoney;
    final totalOutstanding = controller.totalLentOutstanding;
    final nextDueRecord = active.where((r) => r.dueDate != null).firstOrNull;
    final overdueCount = active.where((r) => r.isOverdue).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 64),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Top 3 Bento KPI Cards
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  final kpis = [
                    _LentKpiTile(
                      icon: LucideIcons.handCoins,
                      label: 'Total por cobrar',
                      value: FinanceFormat.money(
                        totalOutstanding,
                        symbol: sym,
                        hide: hide,
                      ),
                      sub: active.isEmpty
                          ? 'Nadie te debe dinero'
                          : '${active.length} ${active.length == 1 ? 'préstamo activo' : 'préstamos activos'}',
                      tint: totalOutstanding > 0
                          ? palette.accent
                          : palette.positive,
                    ),
                    _LentKpiTile(
                      icon: LucideIcons.calendarCheck,
                      label: 'Próximo cobro',
                      value: nextDueRecord != null
                          ? nextDueRecord.dueStatusLabel
                          : 'Sin fecha',
                      sub: nextDueRecord != null
                          ? '${nextDueRecord.borrowerName} · ${FinanceFormat.money(nextDueRecord.remaining, symbol: sym, hide: hide)}'
                          : 'Agrega una fecha esperada',
                      tint: overdueCount > 0
                          ? palette.negative
                          : palette.warning,
                    ),
                    _LentKpiTile(
                      icon: LucideIcons.userCheck,
                      label: 'Ya cobrados',
                      value: '${settled.length}',
                      sub: settled.isEmpty
                          ? 'Historial vacío'
                          : 'Completados al 100%',
                      tint: palette.positive,
                    ),
                  ];

                  if (wide) {
                    return Row(
                      children: [
                        for (var i = 0; i < kpis.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Expanded(child: kpis[i]),
                        ],
                      ],
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < kpis.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        kpis[i],
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
                      'Registra a quién le prestaste dinero y cuándo prometieron devolvértelo',
                      maxLines: 2,
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
                      vertical: 8.5,
                    ),
                    minimumSize: Size.zero,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: () => unawaited(
                      showFinanceLentMoneyDialog(
                        context,
                        controller: controller,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.plus, size: 15),
                        SizedBox(width: 5),
                        Text(
                          'Prestar dinero',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 3. Empty State or Active Loans Grid
              if (active.isEmpty && settled.isEmpty)
                FolioInteractiveBento(
                  enableHover: false,
                  padding: const EdgeInsets.all(36),
                  child: Column(
                    children: [
                      FolioIconBadge(
                        icon: LucideIcons.handCoins,
                        tint: palette.accent,
                        size: 52,
                        iconSize: 24,
                        borderRadius: 15,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Aún no has registrado dinero prestado',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Cuando le prestes a un amigo, familiar o compañero, anótalo aquí con su fecha de devolución para que nunca se te olvide cobrarlo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        minimumSize: Size.zero,
                        borderRadius: BorderRadius.circular(10),
                        onPressed: () => unawaited(
                          showFinanceLentMoneyDialog(
                            context,
                            controller: controller,
                          ),
                        ),
                        child: const Text(
                          '+ Registrar primer préstamo',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                if (active.isNotEmpty) ...[
                  _LentSectionHeader(
                    title: 'Pendientes por cobrar',
                    count: '${active.length}',
                    tint: overdueCount > 0 ? palette.negative : palette.accent,
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth >= 740 ? 2 : 1;
                      const gap = 14.0;
                      final cardW =
                          (constraints.maxWidth - gap * (cols - 1)) / cols;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final rec in active)
                            SizedBox(
                              width: cardW,
                              child: _buildActiveLentCard(
                                context,
                                rec: rec,
                                colors: colors,
                                palette: palette,
                                sym: sym,
                                hide: hide,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
                if (settled.isNotEmpty) ...[
                  SizedBox(height: active.isNotEmpty ? 24 : 0),
                  _LentSectionHeader(
                    title: 'Ya devueltos',
                    count: '${settled.length}',
                    tint: palette.positive,
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth >= 740 ? 2 : 1;
                      const gap = 12.0;
                      final cardW =
                          (constraints.maxWidth - gap * (cols - 1)) / cols;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final rec in settled)
                            SizedBox(
                              width: cardW,
                              child: _buildSettledCard(
                                context,
                                rec: rec,
                                colors: colors,
                                palette: palette,
                                sym: sym,
                                hide: hide,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveLentCard(
    BuildContext context, {
    required LentMoneyRecord rec,
    required ColorScheme colors,
    required FinancePalette palette,
    required String sym,
    required bool hide,
  }) {
    final acc = controller.accountById(rec.accountId);
    final days = rec.daysUntilDue;
    final urgent = rec.isOverdue || (days != null && days <= 2);
    final tint = rec.isOverdue
        ? palette.negative
        : urgent
        ? palette.warning
        : palette.accent;

    return FolioInteractiveBento(
      hoverAccent: tint,
      padding: const EdgeInsets.all(18),
      borderRadius: 17,
      borderColor: rec.isOverdue
          ? palette.negative.withValues(alpha: 0.45)
          : palette.border,
      onTap: () => unawaited(
        showFinanceLentMoneyDialog(
          context,
          controller: controller,
          existing: rec,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FolioIconBadge(
                icon: LucideIcons.user,
                tint: tint,
                size: 38,
                iconSize: 18,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rec.borrowerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    Text(
                      rec.note.isNotEmpty
                          ? rec.note
                          : 'Prestado el ${FinanceFormat.shortDate(rec.lentDate)}',
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
              Icon(
                LucideIcons.pencil,
                size: 14.5,
                color: colors.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rec.repaidAmount > 0 ? 'Falta por cobrar' : 'Te debe',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      FinanceFormat.money(
                        rec.remaining,
                        symbol: sym,
                        hide: hide,
                      ),
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: colors.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (rec.repaidAmount > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Ya devolvió',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${FinanceFormat.money(rec.repaidAmount, symbol: sym, hide: hide)} / ${FinanceFormat.money(rec.amount, symbol: sym, hide: hide)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: palette.positive,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (rec.repaidAmount > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: rec.progress,
                minHeight: 5.5,
                backgroundColor: colors.surfaceContainerHighest,
                color: palette.positive,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: urgent
                      ? tint.withValues(alpha: 0.14)
                      : colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.calendarDays,
                      size: 12,
                      color: urgent ? tint : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      rec.dueStatusLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: urgent ? tint : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (acc != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    'Desde: ${acc.name}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: Size.zero,
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(9),
                  onPressed: () => unawaited(
                    showFinanceLentRepaymentDialog(
                      context,
                      controller: controller,
                      record: rec,
                    ),
                  ),
                  child: Text(
                    'Registrar abono',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: Size.zero,
                  color: palette.positive.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                  onPressed: () => controller.recordLentRepayment(
                    id: rec.id,
                    amount: rec.remaining,
                    toAccountId: rec.accountId,
                  ),
                  child: Text(
                    'Marcar pagado',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: palette.positive,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettledCard(
    BuildContext context, {
    required LentMoneyRecord rec,
    required ColorScheme colors,
    required FinancePalette palette,
    required String sym,
    required bool hide,
  }) {
    return FolioInteractiveBento(
      hoverAccent: palette.positive,
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      child: Row(
        children: [
          FolioIconBadge(
            icon: LucideIcons.userCheck,
            tint: palette.positive,
            size: 34,
            iconSize: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rec.borrowerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                Text(
                  '${FinanceFormat.money(rec.amount, symbol: sym, hide: hide)} · ${FinanceFormat.shortDate(rec.lentDate)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
            decoration: BoxDecoration(
              color: palette.positive.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              'Pagado',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: palette.positive,
              ),
            ),
          ),
          const SizedBox(width: 4),
          CupertinoButton(
            padding: const EdgeInsets.all(4),
            minimumSize: Size.zero,
            onPressed: () => controller.deleteLentMoney(rec.id),
            child: Icon(
              LucideIcons.trash2,
              size: 14.5,
              color: colors.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _LentKpiTile extends StatelessWidget {
  const _LentKpiTile({
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
          FolioIconBadge(icon: icon, tint: tint, size: 36, iconSize: 17),
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
                    fontSize: 18,
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

class _LentSectionHeader extends StatelessWidget {
  const _LentSectionHeader({
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

// ---------------------------------------------------------------------------
// Dialogs: Lend Money & Record Repayment
// ---------------------------------------------------------------------------

Future<void> showFinanceLentMoneyDialog(
  BuildContext context, {
  required FinanceController controller,
  LentMoneyRecord? existing,
}) async {
  final nameCtrl = TextEditingController(text: existing?.borrowerName ?? '');
  final amountCtrl = TextEditingController(
    text: existing != null ? existing.amount.toStringAsFixed(2) : '',
  );
  final noteCtrl = TextEditingController(text: existing?.note ?? '');
  final liquid = controller.liquidAccounts.isNotEmpty
      ? controller.liquidAccounts
      : controller.accounts;
  var accountId =
      existing?.accountId ??
      liquid.where((a) => a.kind == AccountKind.debit).firstOrNull?.id ??
      liquid.first.id;
  var dueDate =
      existing?.dueDate ?? DateTime.now().add(const Duration(days: 7));
  var hasDueDate = existing == null ? true : existing.dueDate != null;
  var recordOutflow = true;

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setState) {
        final colors = Theme.of(context).colorScheme;
        final palette = FinancePalette.of(context);
        final sym = controller.currencySymbol;
        final accOptions = [
          for (final acc in controller.accounts)
            FolioSelectOption<String>(
              value: acc.id,
              label: acc.name,
              icon: FinanceFormat.accountIcon(acc.kind),
              tint: palette.adaptiveHex(acc.colorHex),
            ),
        ];

        void pickQuickDays(int days) {
          final now = DateTime.now();
          setState(() {
            hasDueDate = true;
            dueDate = DateTime(
              now.year,
              now.month,
              now.day,
            ).add(Duration(days: days));
          });
        }

        return Dialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: palette.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      FolioIconBadge(
                        icon: LucideIcons.handCoins,
                        tint: palette.accent,
                        size: 36,
                        iconSize: 17,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          existing == null
                              ? 'Prestar dinero'
                              : 'Editar préstamo a persona',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      if (existing != null)
                        IconButton(
                          icon: Icon(
                            LucideIcons.trash2,
                            size: 16,
                            color: palette.negative,
                          ),
                          tooltip: 'Eliminar',
                          onPressed: () {
                            controller.deleteLentMoney(existing.id);
                            Navigator.of(dialogCtx).pop();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '¿A quién le prestas?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 5),
                  CupertinoTextField(
                    controller: nameCtrl,
                    placeholder: 'Ej. Carlos, Mamá, Ana…',
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: palette.innerBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.border),
                    ),
                    style: TextStyle(color: colors.onSurface, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Monto',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 5),
                            CupertinoTextField(
                              controller: amountCtrl,
                              placeholder: '0.00',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'),
                                ),
                              ],
                              prefix: Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: Text(
                                  sym,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: palette.innerBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: palette.border),
                              ),
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
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
                            Text(
                              'Cuenta de origen',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 5),
                            FolioSelectPill<String>(
                              value: accountId,
                              options: accOptions,
                              height: 40,
                              onChanged: (v) => setState(() => accountId = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '¿Cuándo te lo van a devolver?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _QuickDateChip(
                        label: 'En 3 días',
                        onTap: () => pickQuickDays(3),
                      ),
                      _QuickDateChip(
                        label: 'En 1 semana',
                        onTap: () => pickQuickDays(7),
                      ),
                      _QuickDateChip(
                        label: 'En 15 días',
                        onTap: () => pickQuickDays(15),
                      ),
                      _QuickDateChip(
                        label: 'En 1 mes',
                        onTap: () => pickQuickDays(30),
                      ),
                      _QuickDateChip(
                        label: hasDueDate
                            ? 'Fecha: ${FinanceFormat.shortDate(dueDate)}'
                            : 'Elegir fecha…',
                        selected: hasDueDate,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: dueDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setState(() {
                              hasDueDate = true;
                              dueDate = picked;
                            });
                          }
                        },
                      ),
                      _QuickDateChip(
                        label: 'Sin fecha',
                        selected: !hasDueDate,
                        onTap: () => setState(() => hasDueDate = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nota (opcional)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 5),
                  CupertinoTextField(
                    controller: noteCtrl,
                    placeholder: 'Ej. Almuerzo, emergencia, pasaje…',
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: palette.innerBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.border),
                    ),
                    style: TextStyle(color: colors.onSurface, fontSize: 13.5),
                  ),
                  if (existing == null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Descontar este monto de mi cuenta hoy',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        CupertinoSwitch(
                          value: recordOutflow,
                          onChanged: (v) => setState(() => recordOutflow = v),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        child: Text(
                          'Cancelar',
                          style: TextStyle(color: colors.onSurfaceVariant),
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
                        onPressed: () {
                          final amount = double.tryParse(
                            amountCtrl.text.trim().replaceAll(',', '.'),
                          );
                          if (amount == null || amount <= 0) return;
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) return;
                          if (existing == null) {
                            controller.addLentMoney(
                              borrowerName: name,
                              amount: amount,
                              accountId: accountId,
                              dueDate: hasDueDate ? dueDate : null,
                              note: noteCtrl.text.trim(),
                              recordOutflowTransaction: recordOutflow,
                            );
                          } else {
                            controller.updateLentMoney(
                              existing.copyWith(
                                borrowerName: name,
                                amount: amount,
                                accountId: accountId,
                                dueDate: hasDueDate ? dueDate : null,
                                clearDueDate: !hasDueDate,
                                note: noteCtrl.text.trim(),
                              ),
                            );
                          }
                          Navigator.of(dialogCtx).pop();
                        },
                        child: Text(
                          existing == null ? 'Guardar préstamo' : 'Guardar',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
  nameCtrl.dispose();
  amountCtrl.dispose();
  noteCtrl.dispose();
}

Future<void> showFinanceLentRepaymentDialog(
  BuildContext context, {
  required FinanceController controller,
  required LentMoneyRecord record,
}) async {
  final amountCtrl = TextEditingController(
    text: record.remaining.toStringAsFixed(2),
  );
  var toAccountId = record.accountId;
  var recordInflow = true;

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setState) {
        final colors = Theme.of(context).colorScheme;
        final palette = FinancePalette.of(context);
        final sym = controller.currencySymbol;
        final accOptions = [
          for (final acc in controller.accounts)
            FolioSelectOption<String>(
              value: acc.id,
              label: acc.name,
              icon: FinanceFormat.accountIcon(acc.kind),
              tint: palette.adaptiveHex(acc.colorHex),
            ),
        ];

        return Dialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: palette.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 410),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      FolioIconBadge(
                        icon: LucideIcons.userCheck,
                        tint: palette.positive,
                        size: 36,
                        iconSize: 17,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Devolución de ${record.borrowerName}',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurface,
                              ),
                            ),
                            Text(
                              'Pendiente: ${FinanceFormat.money(record.remaining, symbol: sym)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Monto que te devuelven',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 5),
                  CupertinoTextField(
                    controller: amountCtrl,
                    placeholder: '0.00',
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
                          fontWeight: FontWeight.w800,
                          color: palette.positive,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: palette.innerBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.border),
                    ),
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Cuenta donde recibes el dinero',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 5),
                  FolioSelectPill<String>(
                    value: toAccountId,
                    options: accOptions,
                    height: 40,
                    onChanged: (v) => setState(() => toAccountId = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Sumar este dinero a mi cuenta',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      CupertinoSwitch(
                        value: recordInflow,
                        onChanged: (v) => setState(() => recordInflow = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        child: Text(
                          'Cancelar',
                          style: TextStyle(color: colors.onSurfaceVariant),
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
                        onPressed: () {
                          final amount = double.tryParse(
                            amountCtrl.text.trim().replaceAll(',', '.'),
                          );
                          if (amount == null || amount <= 0) return;
                          controller.recordLentRepayment(
                            id: record.id,
                            amount: amount,
                            toAccountId: toAccountId,
                            recordInflowTransaction: recordInflow,
                          );
                          Navigator.of(dialogCtx).pop();
                        },
                        child: const Text(
                          'Registrar devolución',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
  amountCtrl.dispose();
}

class _QuickDateChip extends StatelessWidget {
  const _QuickDateChip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = FinancePalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5.5),
        decoration: BoxDecoration(
          color: selected ? colors.primaryContainer : palette.innerBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colors.primary : palette.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
