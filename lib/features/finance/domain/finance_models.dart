import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum TransactionKind { expense, income, transfer }

enum AccountKind { cash, debit, credit, savings, salaryAdvance }

/// Theme-adaptive semantic colors for Finanzas so contrast stays crisp on
/// every Folio palette (Claro, Crema, Papel, Oscuro, Noche, etc.).
class FinancePalette {
  const FinancePalette({
    required this.isDark,
    required this.positive,
    required this.warning,
    required this.negative,
    required this.accent,
    required this.purple,
    required this.cardBg,
    required this.innerBg,
    required this.border,
  });

  final bool isDark;
  final Color positive;
  final Color warning;
  final Color negative;
  final Color accent;
  final Color purple;
  final Color cardBg;
  final Color innerBg;
  final Color border;

  factory FinancePalette.of(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = colors.brightness == Brightness.dark;
    // Strict 3-color system across all themes:
    // 1) Neutro (surfaces, borders, ink, slate)
    // 2) Verde (positive / inflows / available / healthy progress)
    // 3) Rojo (negative / outflows / debt / alerts)
    final pos = isDark ? const Color(0xFF34D399) : const Color(0xFF15803D);
    final neg = isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
    final softNeg = isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48);
    final neutralStrong = colors.onSurface;
    final neutralMid = colors.onSurfaceVariant;

    return FinancePalette(
      isDark: isDark,
      positive: pos,
      warning: softNeg,
      negative: neg,
      accent: neutralStrong,
      purple: neutralMid,
      cardBg: isDark
          ? colors.surfaceContainerLow
          : colors.surfaceContainerLowest,
      innerBg: isDark
          ? colors.surfaceContainer.withValues(alpha: 0.75)
          : colors.surface.withValues(alpha: 0.72),
      border: colors.outline.withValues(alpha: isDark ? 0.65 : 0.60),
    );
  }

  /// Maps any legacy category/account hex color into the 3-family system
  /// (Neutral, Green, or Red variants) so no stray rainbow hues appear.
  Color adaptiveHex(String hex) {
    final raw = FinanceFormat.colorFromHex(hex);
    final hsl = HSLColor.fromColor(raw);
    final h = hsl.hue;
    // Green family (90°..185°)
    if (h >= 90 && h <= 185) {
      return positive;
    }
    // Red / Coral family (0°..35° or 330°..360°)
    if (h <= 35 || h >= 330) {
      return negative;
    }
    // Everything else maps cleanly to neutral ink/slate variants
    return purple;
  }
}

class CurrencyOption {
  const CurrencyOption({
    required this.code,
    required this.symbol,
    required this.label,
  });

  final String code;
  final String symbol;
  final String label;

  static const supported = <CurrencyOption>[
    CurrencyOption(code: 'USD', symbol: r'$', label: 'Dólar (USD)'),
    CurrencyOption(code: 'EUR', symbol: '€', label: 'Euro (EUR)'),
    CurrencyOption(code: 'MXN', symbol: r'$', label: 'Peso mexicano (MXN)'),
    CurrencyOption(code: 'GTQ', symbol: 'Q', label: 'Quetzal (GTQ)'),
    CurrencyOption(code: 'COP', symbol: r'$', label: 'Peso colombiano (COP)'),
    CurrencyOption(code: 'CRC', symbol: '₡', label: 'Colón (CRC)'),
  ];
}

class FinanceAccount {
  const FinanceAccount({
    required this.id,
    required this.name,
    required this.kind,
    required this.initialBalance,
    required this.colorHex,
    this.archived = false,
    this.creditLimit,
    this.statementDay,
    this.paymentDueDay,
    this.transactionFeePercent,
    this.linkedAccountId,
  });

  final String id;
  final String name;
  final AccountKind kind;
  final double initialBalance;
  final String colorHex;
  final bool archived;
  final double? creditLimit;
  final int? statementDay;
  final int? paymentDueDay;
  final double? transactionFeePercent;
  final String? linkedAccountId;

  bool get isDebtAccount =>
      kind == AccountKind.credit || kind == AccountKind.salaryAdvance;

  bool get hasTransactionFee =>
      transactionFeePercent != null && transactionFeePercent! > 0;

  FinanceAccount copyWith({
    String? name,
    AccountKind? kind,
    double? initialBalance,
    String? colorHex,
    bool? archived,
    double? creditLimit,
    int? statementDay,
    int? paymentDueDay,
    double? transactionFeePercent,
    String? linkedAccountId,
    bool clearCreditLimit = false,
    bool clearStatementDay = false,
    bool clearPaymentDueDay = false,
    bool clearTransactionFee = false,
    bool clearLinkedAccount = false,
  }) => FinanceAccount(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    initialBalance: initialBalance ?? this.initialBalance,
    colorHex: colorHex ?? this.colorHex,
    archived: archived ?? this.archived,
    creditLimit: clearCreditLimit ? null : (creditLimit ?? this.creditLimit),
    statementDay: clearStatementDay ? null : (statementDay ?? this.statementDay),
    paymentDueDay: clearPaymentDueDay
        ? null
        : (paymentDueDay ?? this.paymentDueDay),
    transactionFeePercent: clearTransactionFee
        ? null
        : (transactionFeePercent ?? this.transactionFeePercent),
    linkedAccountId: clearLinkedAccount
        ? null
        : (linkedAccountId ?? this.linkedAccountId),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'initialBalance': initialBalance,
    'colorHex': colorHex,
    'archived': archived,
    'creditLimit': ?creditLimit,
    'statementDay': ?statementDay,
    'paymentDueDay': ?paymentDueDay,
    'transactionFeePercent': ?transactionFeePercent,
    'linkedAccountId': ?linkedAccountId,
  };

  factory FinanceAccount.fromJson(Object? raw) {
    final map = raw as Map<String, dynamic>;
    return FinanceAccount(
      id: map['id'] as String,
      name: map['name'] as String,
      kind: AccountKind.values.firstWhere(
        (v) => v.name == map['kind'],
        orElse: () => AccountKind.debit,
      ),
      initialBalance: (map['initialBalance'] as num?)?.toDouble() ?? 0,
      colorHex: map['colorHex'] as String? ?? '#286863',
      archived: map['archived'] as bool? ?? false,
      creditLimit: (map['creditLimit'] as num?)?.toDouble(),
      statementDay: (map['statementDay'] as num?)?.toInt(),
      paymentDueDay: (map['paymentDueDay'] as num?)?.toInt(),
      transactionFeePercent: (map['transactionFeePercent'] as num?)?.toDouble(),
      linkedAccountId: map['linkedAccountId'] as String?,
    );
  }
}

class LoanSimulation {
  const LoanSimulation({
    required this.monthsRemaining,
    required this.totalInterestRemaining,
    required this.totalPaidRemaining,
  });

  final int monthsRemaining;
  final double totalInterestRemaining;
  final double totalPaidRemaining;
}

class FinanceLoan {
  const FinanceLoan({
    required this.id,
    required this.name,
    required this.principal,
    required this.remainingBalance,
    required this.annualInterestRate,
    required this.termMonths,
    required this.paidMonths,
    required this.monthlyPayment,
    required this.paymentDay,
    this.linkedAccountId,
    this.notes = '',
  });

  final String id;
  final String name;
  final double principal;
  final double remainingBalance;
  final double annualInterestRate; // e.g. 11.0 for 11% APR
  final int termMonths; // e.g. 60 for 5 years
  final int paidMonths;
  final double monthlyPayment; // e.g. 108.86
  final int paymentDay; // e.g. 15
  final String? linkedAccountId;
  final String notes;

  double get monthlyRate => (annualInterestRate / 100.0) / 12.0;

  double get nextInterestPortion => remainingBalance > 0
      ? double.parse((remainingBalance * monthlyRate).toStringAsFixed(2))
      : 0;

  double get nextPrincipalPortion => remainingBalance > 0
      ? math.max(0, math.min(remainingBalance, monthlyPayment - nextInterestPortion))
      : 0;

  double get paidProgress => principal > 0
      ? ((principal - remainingBalance) / principal).clamp(0.0, 1.0)
      : 0;

  /// Simulates paying off the current [remainingBalance] with [extraMonthly]
  /// added directly to principal each month.
  LoanSimulation simulatePayoff({double extraMonthly = 0}) {
    if (remainingBalance <= 0.01) {
      return const LoanSimulation(
        monthsRemaining: 0,
        totalInterestRemaining: 0,
        totalPaidRemaining: 0,
      );
    }
    var bal = remainingBalance;
    final r = monthlyRate;
    final payment = math.max(1.0, monthlyPayment + math.max(0, extraMonthly));
    var months = 0;
    var totalInterest = 0.0;
    var totalPaid = 0.0;

    // Guard against non-amortizing payment (< monthly interest)
    if (r > 0 && payment <= bal * r + 0.01) {
      final fallbackMonths = math.max(1, termMonths - paidMonths);
      return LoanSimulation(
        monthsRemaining: fallbackMonths,
        totalInterestRemaining: bal * r * fallbackMonths,
        totalPaidRemaining: payment * fallbackMonths,
      );
    }

    while (bal > 0.01 && months < 600) {
      final interest = bal * r;
      final due = bal + interest;
      final actualPay = math.min(payment, due);
      bal = math.max(0.0, due - actualPay);
      totalInterest += interest;
      totalPaid += actualPay;
      months++;
    }
    return LoanSimulation(
      monthsRemaining: months,
      totalInterestRemaining: totalInterest,
      totalPaidRemaining: totalPaid,
    );
  }

  /// Solves implied APR (%) from [principal], [monthlyPayment], and [termMonths]
  /// via binary search when the user hasn't entered an exact rate yet.
  static double estimateAnnualRate({
    required double principal,
    required double monthlyPayment,
    required int termMonths,
  }) {
    if (principal <= 0 || monthlyPayment <= 0 || termMonths <= 0) return 0;
    if (monthlyPayment * termMonths <= principal) return 0;
    var low = 0.0;
    var high = 1.0; // up to 100% APR
    for (var i = 0; i < 40; i++) {
      final mid = (low + high) / 2;
      final r = mid / 12.0;
      final powVal = math.pow(1 + r, termMonths).toDouble();
      final pmt = r == 0
          ? principal / termMonths
          : principal * (r * powVal) / (powVal - 1);
      if (pmt < monthlyPayment) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return double.parse((((low + high) / 2) * 100).toStringAsFixed(2));
  }

  FinanceLoan copyWith({
    String? name,
    double? principal,
    double? remainingBalance,
    double? annualInterestRate,
    int? termMonths,
    int? paidMonths,
    double? monthlyPayment,
    int? paymentDay,
    String? linkedAccountId,
    String? notes,
  }) => FinanceLoan(
    id: id,
    name: name ?? this.name,
    principal: principal ?? this.principal,
    remainingBalance: remainingBalance ?? this.remainingBalance,
    annualInterestRate: annualInterestRate ?? this.annualInterestRate,
    termMonths: termMonths ?? this.termMonths,
    paidMonths: paidMonths ?? this.paidMonths,
    monthlyPayment: monthlyPayment ?? this.monthlyPayment,
    paymentDay: paymentDay ?? this.paymentDay,
    linkedAccountId: linkedAccountId ?? this.linkedAccountId,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'principal': principal,
    'remainingBalance': remainingBalance,
    'annualInterestRate': annualInterestRate,
    'termMonths': termMonths,
    'paidMonths': paidMonths,
    'monthlyPayment': monthlyPayment,
    'paymentDay': paymentDay,
    'linkedAccountId': ?linkedAccountId,
    if (notes.isNotEmpty) 'notes': notes,
  };

  factory FinanceLoan.fromJson(Object? raw) {
    final map = raw as Map<String, dynamic>;
    return FinanceLoan(
      id: map['id'] as String,
      name: map['name'] as String,
      principal: (map['principal'] as num?)?.toDouble() ?? 0,
      remainingBalance: (map['remainingBalance'] as num?)?.toDouble() ?? 0,
      annualInterestRate: (map['annualInterestRate'] as num?)?.toDouble() ?? 0,
      termMonths: (map['termMonths'] as num?)?.toInt() ?? 60,
      paidMonths: (map['paidMonths'] as num?)?.toInt() ?? 0,
      monthlyPayment: (map['monthlyPayment'] as num?)?.toDouble() ?? 0,
      paymentDay: ((map['paymentDay'] as num?)?.toInt() ?? 15).clamp(1, 31),
      linkedAccountId: map['linkedAccountId'] as String?,
      notes: map['notes'] as String? ?? '',
    );
  }
}

class FinanceCategory {
  const FinanceCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.iconKey,
    required this.colorHex,
    this.monthlyBudget,
  });

  final String id;
  final String name;
  final TransactionKind kind;
  final String iconKey;
  final String colorHex;
  final double? monthlyBudget;

  FinanceCategory copyWith({
    String? name,
    String? iconKey,
    String? colorHex,
    double? monthlyBudget,
    bool clearBudget = false,
  }) => FinanceCategory(
    id: id,
    name: name ?? this.name,
    kind: kind,
    iconKey: iconKey ?? this.iconKey,
    colorHex: colorHex ?? this.colorHex,
    monthlyBudget: clearBudget ? null : (monthlyBudget ?? this.monthlyBudget),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'iconKey': iconKey,
    'colorHex': colorHex,
    'monthlyBudget': ?monthlyBudget,
  };

  factory FinanceCategory.fromJson(Object? raw) {
    final map = raw as Map<String, dynamic>;
    return FinanceCategory(
      id: map['id'] as String,
      name: map['name'] as String,
      kind: map['kind'] == 'income'
          ? TransactionKind.income
          : TransactionKind.expense,
      iconKey: map['iconKey'] as String? ?? 'tag',
      colorHex: map['colorHex'] as String? ?? '#315F91',
      monthlyBudget: (map['monthlyBudget'] as num?)?.toDouble(),
    );
  }
}

class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.kind,
    required this.amount,
    required this.accountId,
    required this.date,
    this.categoryId,
    this.toAccountId,
    this.note = '',
    this.recurringId,
    this.feeAmount = 0,
  });

  final String id;
  final TransactionKind kind;
  final double amount;
  final String accountId;
  final DateTime date;
  final String? categoryId;
  final String? toAccountId;
  final String note;
  final String? recurringId;
  final double feeAmount;

  FinanceTransaction copyWith({
    TransactionKind? kind,
    double? amount,
    String? accountId,
    DateTime? date,
    String? categoryId,
    String? toAccountId,
    String? note,
    String? recurringId,
    double? feeAmount,
    bool clearCategory = false,
    bool clearToAccount = false,
  }) => FinanceTransaction(
    id: id,
    kind: kind ?? this.kind,
    amount: amount ?? this.amount,
    accountId: accountId ?? this.accountId,
    date: date ?? this.date,
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    toAccountId: clearToAccount ? null : (toAccountId ?? this.toAccountId),
    note: note ?? this.note,
    recurringId: recurringId ?? this.recurringId,
    feeAmount: feeAmount ?? this.feeAmount,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'amount': amount,
    'accountId': accountId,
    'date': date.toIso8601String(),
    'categoryId': ?categoryId,
    'toAccountId': ?toAccountId,
    'note': note,
    'recurringId': ?recurringId,
    if (feeAmount > 0) 'feeAmount': feeAmount,
  };

  factory FinanceTransaction.fromJson(Object? raw) {
    final map = raw as Map<String, dynamic>;
    return FinanceTransaction(
      id: map['id'] as String,
      kind: TransactionKind.values.firstWhere(
        (v) => v.name == map['kind'],
        orElse: () => TransactionKind.expense,
      ),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      accountId: map['accountId'] as String,
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      categoryId: map['categoryId'] as String?,
      toAccountId: map['toAccountId'] as String?,
      note: map['note'] as String? ?? '',
      recurringId: map['recurringId'] as String?,
      feeAmount: (map['feeAmount'] as num?)?.toDouble() ?? 0,
    );
  }
}

class RecurringPayment {
  const RecurringPayment({
    required this.id,
    required this.title,
    required this.amount,
    required this.kind,
    required this.categoryId,
    required this.accountId,
    required this.dayOfMonth,
    this.active = true,
    this.lastAppliedMonth,
  });

  final String id;
  final String title;
  final double amount;
  final TransactionKind kind;
  final String categoryId;
  final String accountId;
  final int dayOfMonth;
  final bool active;
  final String? lastAppliedMonth;

  RecurringPayment copyWith({
    String? title,
    double? amount,
    TransactionKind? kind,
    String? categoryId,
    String? accountId,
    int? dayOfMonth,
    bool? active,
    String? lastAppliedMonth,
    bool clearLastAppliedMonth = false,
  }) => RecurringPayment(
    id: id,
    title: title ?? this.title,
    amount: amount ?? this.amount,
    kind: kind ?? this.kind,
    categoryId: categoryId ?? this.categoryId,
    accountId: accountId ?? this.accountId,
    dayOfMonth: dayOfMonth ?? this.dayOfMonth,
    active: active ?? this.active,
    lastAppliedMonth: clearLastAppliedMonth
        ? null
        : (lastAppliedMonth ?? this.lastAppliedMonth),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'kind': kind.name,
    'categoryId': categoryId,
    'accountId': accountId,
    'dayOfMonth': dayOfMonth,
    'active': active,
    'lastAppliedMonth': ?lastAppliedMonth,
  };

  factory RecurringPayment.fromJson(Object? raw) {
    final map = raw as Map<String, dynamic>;
    return RecurringPayment(
      id: map['id'] as String,
      title: map['title'] as String,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      kind: map['kind'] == 'income'
          ? TransactionKind.income
          : TransactionKind.expense,
      categoryId: map['categoryId'] as String? ?? 'cat-subs',
      accountId: map['accountId'] as String? ?? 'acc-debit',
      dayOfMonth: ((map['dayOfMonth'] as num?)?.toInt() ?? 1).clamp(1, 28),
      active: map['active'] as bool? ?? true,
      lastAppliedMonth: map['lastAppliedMonth'] as String?,
    );
  }
}

/// Tracks money the user lent to another person (friend, family, coworker),
/// including when they promised to pay it back and partial/full repayments.
class LentMoneyRecord {
  const LentMoneyRecord({
    required this.id,
    required this.borrowerName,
    required this.amount,
    required this.lentDate,
    required this.accountId,
    this.repaidAmount = 0,
    this.dueDate,
    this.note = '',
  });

  final String id;
  final String borrowerName;
  final double amount;
  final double repaidAmount;
  final DateTime lentDate;
  final DateTime? dueDate;
  final String accountId;
  final String note;

  double get remaining => math.max(0.0, amount - repaidAmount);
  bool get isSettled => remaining <= 0.009;
  double get progress =>
      amount > 0 ? (repaidAmount / amount).clamp(0.0, 1.0) : 1.0;

  int? get daysUntilDue {
    final due = dueDate;
    if (due == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(due.year, due.month, due.day);
    return target.difference(today).inDays;
  }

  bool get isOverdue {
    if (isSettled) return false;
    final d = daysUntilDue;
    return d != null && d < 0;
  }

  String get dueStatusLabel {
    if (isSettled) return 'Pagado';
    final d = daysUntilDue;
    if (d == null) return 'Sin fecha acordada';
    if (d < 0) {
      final abs = -d;
      return abs == 1 ? 'Vencido ayer' : 'Vencido hace $abs días';
    }
    if (d == 0) return 'Devuelven hoy';
    if (d == 1) return 'Devuelven mañana';
    return 'En $d días (${FinanceFormat.shortDate(dueDate!)})';
  }

  LentMoneyRecord copyWith({
    String? borrowerName,
    double? amount,
    double? repaidAmount,
    DateTime? lentDate,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? accountId,
    String? note,
  }) => LentMoneyRecord(
    id: id,
    borrowerName: borrowerName ?? this.borrowerName,
    amount: amount ?? this.amount,
    repaidAmount: repaidAmount ?? this.repaidAmount,
    lentDate: lentDate ?? this.lentDate,
    dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
    accountId: accountId ?? this.accountId,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'borrowerName': borrowerName,
    'amount': amount,
    'repaidAmount': repaidAmount,
    'lentDate': lentDate.toIso8601String(),
    if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
    'accountId': accountId,
    'note': note,
  };

  factory LentMoneyRecord.fromJson(Object? raw) {
    final map = raw as Map<String, dynamic>;
    return LentMoneyRecord(
      id: map['id'] as String,
      borrowerName: map['borrowerName'] as String? ?? 'Persona',
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      repaidAmount: (map['repaidAmount'] as num?)?.toDouble() ?? 0,
      lentDate:
          DateTime.tryParse(map['lentDate'] as String? ?? '') ?? DateTime.now(),
      dueDate: map['dueDate'] != null
          ? DateTime.tryParse(map['dueDate'] as String)
          : null,
      accountId: map['accountId'] as String? ?? 'acc-debit',
      note: map['note'] as String? ?? '',
    );
  }
}

class FinanceSnapshot {
  const FinanceSnapshot({
    required this.currencyCode,
    required this.currencySymbol,
    required this.hideBalances,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.recurring,
    this.loans = const [],
    this.lentMoney = const [],
    this.monthlyEssentialBudget,
    this.advanceReductionStep,
    this.creditCardPayoffStep,
    this.budgetIncomeOverride,
    this.customSavingsAmount,
    this.includeDebtPlanInBudget = true,
    this.includeExtraIncomeInBudget = false,
  });

  final String currencyCode;
  final String currencySymbol;
  final bool hideBalances;
  final List<FinanceAccount> accounts;
  final List<FinanceCategory> categories;
  final List<FinanceTransaction> transactions;
  final List<RecurringPayment> recurring;
  final List<FinanceLoan> loans;
  final List<LentMoneyRecord> lentMoney;
  final double? monthlyEssentialBudget;
  final double? advanceReductionStep;
  final double? creditCardPayoffStep;
  final double? budgetIncomeOverride;
  final double? customSavingsAmount;
  final bool includeDebtPlanInBudget;
  final bool includeExtraIncomeInBudget;

  factory FinanceSnapshot.starter() => const FinanceSnapshot(
    currencyCode: 'USD',
    currencySymbol: r'$',
    hideBalances: false,
    accounts: [
      FinanceAccount(
        id: 'acc-cash',
        name: 'Efectivo',
        kind: AccountKind.cash,
        initialBalance: 0,
        colorHex: '#2E7D5B',
      ),
      FinanceAccount(
        id: 'acc-debit',
        name: 'Cuenta Débito',
        kind: AccountKind.debit,
        initialBalance: 0,
        colorHex: '#315F91',
      ),
      FinanceAccount(
        id: 'acc-credit',
        name: 'Tarjeta Crédito',
        kind: AccountKind.credit,
        initialBalance: 0,
        colorHex: '#B45B3E',
        statementDay: 15,
        paymentDueDay: 25,
        linkedAccountId: 'acc-debit',
      ),
      FinanceAccount(
        id: 'acc-savings',
        name: 'Ahorro',
        kind: AccountKind.savings,
        initialBalance: 0,
        colorHex: '#6F58A8',
      ),
    ],
    categories: [
      FinanceCategory(
        id: 'cat-food',
        name: 'Comida',
        kind: TransactionKind.expense,
        iconKey: 'cart',
        colorHex: '#C96A3B',
      ),
      FinanceCategory(
        id: 'cat-transport',
        name: 'Transporte',
        kind: TransactionKind.expense,
        iconKey: 'car',
        colorHex: '#315F91',
      ),
      FinanceCategory(
        id: 'cat-home',
        name: 'Hogar',
        kind: TransactionKind.expense,
        iconKey: 'house',
        colorHex: '#286863',
      ),
      FinanceCategory(
        id: 'cat-subs',
        name: 'Suscripciones',
        kind: TransactionKind.expense,
        iconKey: 'repeat',
        colorHex: '#6F58A8',
      ),
      FinanceCategory(
        id: 'cat-health',
        name: 'Salud',
        kind: TransactionKind.expense,
        iconKey: 'heart',
        colorHex: '#B94A48',
      ),
      FinanceCategory(
        id: 'cat-leisure',
        name: 'Ocio',
        kind: TransactionKind.expense,
        iconKey: 'sparkles',
        colorHex: '#C48B28',
      ),
      FinanceCategory(
        id: 'cat-shopping',
        name: 'Compras',
        kind: TransactionKind.expense,
        iconKey: 'bag',
        colorHex: '#3B7A8C',
      ),
      FinanceCategory(
        id: 'cat-other-exp',
        name: 'Otros gastos',
        kind: TransactionKind.expense,
        iconKey: 'tag',
        colorHex: '#706B60',
      ),
      FinanceCategory(
        id: 'cat-salary',
        name: 'Salario',
        kind: TransactionKind.income,
        iconKey: 'briefcase',
        colorHex: '#2E7D5B',
      ),
      FinanceCategory(
        id: 'cat-freelance',
        name: 'Freelance',
        kind: TransactionKind.income,
        iconKey: 'laptop',
        colorHex: '#286863',
      ),
      FinanceCategory(
        id: 'cat-invest',
        name: 'Inversiones',
        kind: TransactionKind.income,
        iconKey: 'chart',
        colorHex: '#315F91',
      ),
      FinanceCategory(
        id: 'cat-other-inc',
        name: 'Otros ingresos',
        kind: TransactionKind.income,
        iconKey: 'plus',
        colorHex: '#6F58A8',
      ),
    ],
    transactions: [],
    recurring: [],
    loans: [],
  );

  Map<String, dynamic> toJson() => {
    'version': 1,
    'currencyCode': currencyCode,
    'currencySymbol': currencySymbol,
    'hideBalances': hideBalances,
    'accounts': accounts.map((a) => a.toJson()).toList(),
    'categories': categories.map((c) => c.toJson()).toList(),
    'transactions': transactions.map((t) => t.toJson()).toList(),
    'recurring': recurring.map((r) => r.toJson()).toList(),
    if (loans.isNotEmpty) 'loans': loans.map((l) => l.toJson()).toList(),
    if (lentMoney.isNotEmpty)
      'lentMoney': lentMoney.map((l) => l.toJson()).toList(),
    'monthlyEssentialBudget': ?monthlyEssentialBudget,
    'advanceReductionStep': ?advanceReductionStep,
    'creditCardPayoffStep': ?creditCardPayoffStep,
    'budgetIncomeOverride': ?budgetIncomeOverride,
    'customSavingsAmount': ?customSavingsAmount,
    if (!includeDebtPlanInBudget) 'includeDebtPlanInBudget': false,
    if (includeExtraIncomeInBudget) 'includeExtraIncomeInBudget': true,
  };

  factory FinanceSnapshot.fromJson(Map<String, dynamic> map) {
    final starter = FinanceSnapshot.starter();
    final accounts = (map['accounts'] as List?)
            ?.map(FinanceAccount.fromJson)
            .toList() ??
        starter.accounts;
    final categories = (map['categories'] as List?)
            ?.map(FinanceCategory.fromJson)
            .toList() ??
        starter.categories;
    final transactions = (map['transactions'] as List?)
            ?.map(FinanceTransaction.fromJson)
            .toList() ??
        const <FinanceTransaction>[];
    final recurring = (map['recurring'] as List?)
            ?.map(RecurringPayment.fromJson)
            .toList() ??
        const <RecurringPayment>[];
    final loans = (map['loans'] as List?)
            ?.map(FinanceLoan.fromJson)
            .toList() ??
        const <FinanceLoan>[];
    final lentMoney = (map['lentMoney'] as List?)
            ?.map(LentMoneyRecord.fromJson)
            .toList() ??
        const <LentMoneyRecord>[];
    return FinanceSnapshot(
      currencyCode: map['currencyCode'] as String? ?? 'USD',
      currencySymbol: map['currencySymbol'] as String? ?? r'$',
      hideBalances: map['hideBalances'] as bool? ?? false,
      accounts: accounts.isEmpty ? starter.accounts : accounts,
      categories: categories.isEmpty ? starter.categories : categories,
      transactions: transactions,
      recurring: recurring,
      loans: loans,
      lentMoney: lentMoney,
      monthlyEssentialBudget: (map['monthlyEssentialBudget'] as num?)
          ?.toDouble(),
      advanceReductionStep: (map['advanceReductionStep'] as num?)?.toDouble(),
      creditCardPayoffStep: (map['creditCardPayoffStep'] as num?)?.toDouble(),
      budgetIncomeOverride: (map['budgetIncomeOverride'] as num?)?.toDouble(),
      customSavingsAmount: (map['customSavingsAmount'] as num?)?.toDouble(),
      includeDebtPlanInBudget: map['includeDebtPlanInBudget'] as bool? ?? true,
      includeExtraIncomeInBudget:
          map['includeExtraIncomeInBudget'] as bool? ?? false,
    );
  }
}

abstract final class FinanceFormat {
  static const _months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  static String monthKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}';

  static String monthTitle(DateTime dt) => '${_months[dt.month - 1]} ${dt.year}';

  static String shortDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Hoy';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day) {
      return 'Ayer';
    }
    final monthShort = _months[dt.month - 1].substring(0, 3).toLowerCase();
    return '${dt.day} $monthShort';
  }

  static DateTime nextDateForDayOfMonth(int dayOfMonth, [DateTime? reference]) {
    final now = reference ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int clampedDay(int year, int month) {
      final last = DateTime(year, month + 1, 0).day;
      return dayOfMonth.clamp(1, last);
    }

    final thisMonth = DateTime(
      today.year,
      today.month,
      clampedDay(today.year, today.month),
    );
    if (!thisMonth.isBefore(today)) return thisMonth;
    final nextMonthDate = DateTime(today.year, today.month + 1, 1);
    return DateTime(
      nextMonthDate.year,
      nextMonthDate.month,
      clampedDay(nextMonthDate.year, nextMonthDate.month),
    );
  }

  static int daysUntilDayOfMonth(int dayOfMonth, [DateTime? reference]) {
    final now = reference ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final next = nextDateForDayOfMonth(dayOfMonth, today);
    return next.difference(today).inDays;
  }

  static String countdownLabel(int dayOfMonth) {
    final days = daysUntilDayOfMonth(dayOfMonth);
    if (days == 0) return 'hoy';
    if (days == 1) return 'mañana';
    return 'en $days días';
  }

  static String money(
    double amount, {
    String symbol = r'$',
    bool hide = false,
    bool showSign = false,
  }) {
    if (hide) return '$symbol••••';
    final negative = amount < 0;
    final abs = amount.abs();
    final fixed = abs.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) {
        buf.write(',');
      }
      buf.write(intPart[i]);
    }
    final formatted = '$symbol$buf.${parts[1]}';
    if (negative) return '-$formatted';
    if (showSign && amount > 0) return '+$formatted';
    return formatted;
  }

  static Color colorFromHex(String hex) {
    final cleaned = hex.replaceFirst('#', '').trim();
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return const Color(0xFF315F91);
    if (cleaned.length <= 6) return Color(0xFF000000 | value);
    return Color(value);
  }

  /// Cohesive, refined rounded fintech icons.
  static IconData categoryIcon(String key) => switch (key) {
    'cart' => LucideIcons.utensils,
    'car' => LucideIcons.car,
    'house' => LucideIcons.house,
    'repeat' => LucideIcons.repeat,
    'heart' => LucideIcons.heartPulse,
    'sparkles' => LucideIcons.coffee,
    'bag' => LucideIcons.shoppingBag,
    'briefcase' => LucideIcons.banknote,
    'laptop' => LucideIcons.laptop,
    'chart' => LucideIcons.trendingUp,
    'plus' => LucideIcons.circlePlus,
    _ => LucideIcons.receiptText,
  };

  static IconData accountIcon(AccountKind kind) => switch (kind) {
    AccountKind.cash => LucideIcons.banknote,
    AccountKind.debit => LucideIcons.landmark,
    AccountKind.credit => LucideIcons.creditCard,
    AccountKind.savings => LucideIcons.piggyBank,
    AccountKind.salaryAdvance => LucideIcons.arrowLeftRight,
  };

  static String accountKindLabel(AccountKind kind) => switch (kind) {
    AccountKind.cash => 'Efectivo',
    AccountKind.debit => 'Débito',
    AccountKind.credit => 'Tarjeta de crédito',
    AccountKind.savings => 'Ahorro',
    AccountKind.salaryAdvance => 'Adelanto salarial',
  };
}
