import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../cloud_sync/data/folio_cloud_sync_service.dart';
import '../../data/finance_repository.dart';
import '../../domain/finance_models.dart';

class CategorySpending {
  const CategorySpending({
    required this.category,
    required this.spent,
    required this.share,
  });

  final FinanceCategory category;
  final double spent;
  final double share;

  double? get budgetRatio {
    final budget = category.monthlyBudget;
    if (budget == null || budget <= 0) return null;
    return spent / budget;
  }
}

class FinanceController extends ChangeNotifier {
  FinanceController({FinanceRepository? repository})
    : _repository = repository ?? FinanceRepository();

  final FinanceRepository _repository;
  final Random _random = Random.secure();

  FinanceSnapshot _snapshot = FinanceSnapshot.starter();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loaded = false;
  Future<void> _saveQueue = Future<void>.value();

  FolioCloudSyncService? _cloudSync;
  StreamSubscription<RemoteFinancePayload?>? _cloudSub;
  Timer? _cloudUploadDebounce;
  int _lastLocalChangeMs = 0;
  bool _applyingRemote = false;

  bool get loaded => _loaded;
  String get currencyCode => _snapshot.currencyCode;
  String get currencySymbol => _snapshot.currencySymbol;
  bool get hideBalances => _snapshot.hideBalances;
  DateTime get selectedMonth => _selectedMonth;
  double? get monthlyEssentialBudget => _snapshot.monthlyEssentialBudget;
  double? get advanceReductionStep => _snapshot.advanceReductionStep;
  double? get creditCardPayoffStep => _snapshot.creditCardPayoffStep;
  double? get budgetIncomeOverride => _snapshot.budgetIncomeOverride;
  double? get customSavingsAmount => _snapshot.customSavingsAmount;
  bool get includeDebtPlanInBudget => _snapshot.includeDebtPlanInBudget;
  bool get includeExtraIncomeInBudget => _snapshot.includeExtraIncomeInBudget;

  List<FinanceLoan> get loans => List.unmodifiable(_snapshot.loans);

  List<FinanceAccount> get accounts =>
      _snapshot.accounts.where((a) => !a.archived).toList(growable: false);

  List<FinanceAccount> get allAccounts =>
      List.unmodifiable(_snapshot.accounts);

  List<FinanceAccount> get debtAccounts =>
      accounts.where((a) => a.isDebtAccount).toList(growable: false);

  List<FinanceAccount> get liquidAccounts =>
      accounts.where((a) => !a.isDebtAccount).toList(growable: false);

  List<FinanceCategory> get categories =>
      List.unmodifiable(_snapshot.categories);

  List<FinanceCategory> categoriesFor(TransactionKind kind) => _snapshot
      .categories
      .where((c) => c.kind == kind)
      .toList(growable: false);

  List<FinanceTransaction> get transactions =>
      List.unmodifiable(_snapshot.transactions);

  List<RecurringPayment> get recurring =>
      List.unmodifiable(_snapshot.recurring);

  List<LentMoneyRecord> get lentMoney =>
      List.unmodifiable(_snapshot.lentMoney);

  List<LentMoneyRecord> get activeLentMoney {
    final list = _snapshot.lentMoney.where((e) => !e.isSettled).toList();
    list.sort((a, b) {
      if (a.dueDate == null && b.dueDate == null) {
        return b.lentDate.compareTo(a.lentDate);
      }
      if (a.dueDate == null) return 1;
      if (b.dueDate == null) return -1;
      return a.dueDate!.compareTo(b.dueDate!);
    });
    return list;
  }

  List<LentMoneyRecord> get settledLentMoney =>
      _snapshot.lentMoney.where((e) => e.isSettled).toList()
        ..sort((a, b) => b.lentDate.compareTo(a.lentDate));

  double get totalLentOutstanding =>
      _snapshot.lentMoney.fold(0.0, (sum, item) => sum + item.remaining);

  FinanceAccount? accountById(String? id) {
    if (id == null) return null;
    for (final account in _snapshot.accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  FinanceCategory? categoryById(String? id) {
    if (id == null) return null;
    for (final category in _snapshot.categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  Future<void> load() async {
    _snapshot = await _repository.load();
    _loaded = true;
    notifyListeners();
    if (_cloudSync?.isSignedIn == true) {
      unawaited(syncNowWithCloud());
    }
  }

  /// Connects this controller to [FolioCloudSyncService] for real-time
  /// bidirectional Firestore sync across macOS, Android, iOS, and Web.
  void attachCloudSync(FolioCloudSyncService sync) {
    if (identical(_cloudSync, sync)) return;
    _cloudSync?.removeListener(_handleCloudAuthChanged);
    _cloudSync = sync;
    sync.addListener(_handleCloudAuthChanged);
    _handleCloudAuthChanged();
  }

  void _handleCloudAuthChanged() {
    final sync = _cloudSync;
    if (sync == null || !sync.isSignedIn) {
      _cloudSub?.cancel();
      _cloudSub = null;
      return;
    }
    if (_cloudSub == null) {
      _cloudSub = sync.watchFinanceSnapshot().listen(_onRemoteSnapshot);
      unawaited(syncNowWithCloud());
    }
  }

  void _onRemoteSnapshot(RemoteFinancePayload? remote) {
    if (remote == null) return;
    if (remote.updatedAtMs <= _lastLocalChangeMs) return;
    _applyingRemote = true;
    _lastLocalChangeMs = remote.updatedAtMs;
    _snapshot = remote.snapshot;
    notifyListeners();
    _saveQueue = _saveQueue
        .then((_) => _repository.save(remote.snapshot))
        .catchError((_) {});
    _applyingRemote = false;
  }

  /// Smart initial sync: if cloud has data and local is fresh/starter, pulls
  /// from cloud; if cloud is empty and local has real data, uploads local.
  Future<void> syncNowWithCloud() async {
    final sync = _cloudSync;
    if (sync == null || !sync.isSignedIn) return;
    final remote = await sync.fetchFinanceSnapshot();
    final localHasData =
        _snapshot.transactions.isNotEmpty ||
        _snapshot.recurring.isNotEmpty ||
        _snapshot.loans.isNotEmpty ||
        _snapshot.accounts.length > 4;
    if (remote == null) {
      if (localHasData) {
        await pushLocalToCloud();
      }
      return;
    }
    if (!localHasData || remote.updatedAtMs > _lastLocalChangeMs) {
      _onRemoteSnapshot(remote);
    } else if (_lastLocalChangeMs > remote.updatedAtMs) {
      await pushLocalToCloud();
    }
  }

  Future<bool> pushLocalToCloud() async {
    final sync = _cloudSync;
    if (sync == null || !sync.isSignedIn) return false;
    final ts = DateTime.now().millisecondsSinceEpoch;
    _lastLocalChangeMs = ts;
    return sync.uploadFinanceSnapshot(_snapshot, updatedAtMs: ts);
  }

  Future<bool> pullCloudToLocal() async {
    final sync = _cloudSync;
    if (sync == null || !sync.isSignedIn) return false;
    final remote = await sync.fetchFinanceSnapshot();
    if (remote == null) return false;
    _applyingRemote = true;
    _lastLocalChangeMs = remote.updatedAtMs;
    _snapshot = remote.snapshot;
    notifyListeners();
    _saveQueue = _saveQueue
        .then((_) => _repository.save(remote.snapshot))
        .catchError((_) {});
    _applyingRemote = false;
    return true;
  }

  void _commit(FinanceSnapshot next) {
    _snapshot = next;
    if (!_applyingRemote) {
      _lastLocalChangeMs = DateTime.now().millisecondsSinceEpoch;
    }
    notifyListeners();
    _saveQueue = _saveQueue.then((_) => _repository.save(next)).catchError((_) {});
    if (!_applyingRemote && _cloudSync?.isSignedIn == true) {
      final ts = _lastLocalChangeMs;
      _cloudUploadDebounce?.cancel();
      _cloudUploadDebounce = Timer(const Duration(milliseconds: 450), () {
        unawaited(_cloudSync!.uploadFinanceSnapshot(next, updatedAtMs: ts));
      });
    }
  }

  @override
  void dispose() {
    _cloudUploadDebounce?.cancel();
    _cloudSub?.cancel();
    _cloudSync?.removeListener(_handleCloudAuthChanged);
    super.dispose();
  }

  FinanceSnapshot _copySnapshot({
    String? currencyCode,
    String? currencySymbol,
    bool? hideBalances,
    List<FinanceAccount>? accounts,
    List<FinanceCategory>? categories,
    List<FinanceTransaction>? transactions,
    List<RecurringPayment>? recurring,
    List<FinanceLoan>? loans,
    List<LentMoneyRecord>? lentMoney,
    double? monthlyEssentialBudget,
    double? advanceReductionStep,
    double? creditCardPayoffStep,
    double? budgetIncomeOverride,
    bool clearBudgetIncomeOverride = false,
    double? customSavingsAmount,
    bool clearCustomSavingsAmount = false,
    bool? includeDebtPlanInBudget,
    bool? includeExtraIncomeInBudget,
  }) => FinanceSnapshot(
    currencyCode: currencyCode ?? _snapshot.currencyCode,
    currencySymbol: currencySymbol ?? _snapshot.currencySymbol,
    hideBalances: hideBalances ?? _snapshot.hideBalances,
    accounts: accounts ?? _snapshot.accounts,
    categories: categories ?? _snapshot.categories,
    transactions: transactions ?? _snapshot.transactions,
    recurring: recurring ?? _snapshot.recurring,
    loans: loans ?? _snapshot.loans,
    lentMoney: lentMoney ?? _snapshot.lentMoney,
    monthlyEssentialBudget:
        monthlyEssentialBudget ?? _snapshot.monthlyEssentialBudget,
    advanceReductionStep:
        advanceReductionStep ?? _snapshot.advanceReductionStep,
    creditCardPayoffStep:
        creditCardPayoffStep ?? _snapshot.creditCardPayoffStep,
    budgetIncomeOverride: clearBudgetIncomeOverride
        ? null
        : (budgetIncomeOverride ?? _snapshot.budgetIncomeOverride),
    customSavingsAmount: clearCustomSavingsAmount
        ? null
        : (customSavingsAmount ?? _snapshot.customSavingsAmount),
    includeDebtPlanInBudget:
        includeDebtPlanInBudget ?? _snapshot.includeDebtPlanInBudget,
    includeExtraIncomeInBudget:
        includeExtraIncomeInBudget ?? _snapshot.includeExtraIncomeInBudget,
  );

  void setDebtPlanSettings({
    double? monthlyEssentialBudget,
    double? advanceReductionStep,
    double? creditCardPayoffStep,
  }) {
    _commit(
      _copySnapshot(
        monthlyEssentialBudget: monthlyEssentialBudget,
        advanceReductionStep: advanceReductionStep,
        creditCardPayoffStep: creditCardPayoffStep,
      ),
    );
  }

  void setBudgetIncomeOverride(double? income) {
    if (income == null || income <= 0) {
      _commit(_copySnapshot(clearBudgetIncomeOverride: true));
    } else {
      _commit(_copySnapshot(budgetIncomeOverride: income));
    }
  }

  void setCustomSavingsAmount(double? amount) {
    if (amount == null) {
      _commit(_copySnapshot(clearCustomSavingsAmount: true));
    } else {
      _commit(_copySnapshot(customSavingsAmount: max(0.0, amount)));
    }
  }

  void setIncludeDebtPlanInBudget(bool include) {
    _commit(_copySnapshot(includeDebtPlanInBudget: include));
  }

  void setIncludeExtraIncomeInBudget(bool include) {
    _commit(_copySnapshot(includeExtraIncomeInBudget: include));
  }

  void addLoan({
    required String name,
    required double principal,
    required double remainingBalance,
    required double annualInterestRate,
    required int termMonths,
    required int paidMonths,
    required double monthlyPayment,
    required int paymentDay,
    String? linkedAccountId,
    String notes = '',
    bool addToRecurring = false,
  }) {
    final resolvedRate = annualInterestRate > 0
        ? annualInterestRate
        : FinanceLoan.estimateAnnualRate(
            principal: principal,
            monthlyPayment: monthlyPayment,
            termMonths: termMonths,
          );
    final loan = FinanceLoan(
      id: _nextId('loan'),
      name: name.trim(),
      principal: principal,
      remainingBalance: remainingBalance,
      annualInterestRate: resolvedRate,
      termMonths: termMonths,
      paidMonths: paidMonths,
      monthlyPayment: monthlyPayment,
      paymentDay: paymentDay.clamp(1, 31),
      linkedAccountId: linkedAccountId,
      notes: notes.trim(),
    );
    _commit(_copySnapshot(loans: [..._snapshot.loans, loan]));
    if (addToRecurring) {
      addLoanToRecurring(loan);
    }
  }

  /// Checks whether [loan] is already represented in monthly fixed expenses.
  bool isLoanInRecurring(FinanceLoan loan) {
    final loanLower = loan.name.toLowerCase();
    for (final rec in _snapshot.recurring) {
      if (rec.kind != TransactionKind.expense) continue;
      final closeAmount = (rec.amount - loan.monthlyPayment).abs() <= 2.0;
      final recLower = rec.title.toLowerCase();
      final nameMatch =
          recLower.contains('prestamo') ||
          recLower.contains('préstamo') ||
          recLower.contains('loan') ||
          (loanLower.length >= 4 && recLower.contains(loanLower));
      if (closeAmount && nameMatch) return true;
    }
    return false;
  }

  /// Adds [loan]'s monthly quota to fixed expenses (`Recurrentes`) in 1 click,
  /// and automatically links any existing matching transaction in the selected month.
  void addLoanToRecurring(FinanceLoan loan) {
    if (isLoanInRecurring(loan)) return;
    final recId = _nextId('rec');
    final targetAccountId =
        loan.linkedAccountId ??
        liquidAccounts.firstOrNull?.id ??
        accounts.first.id;
    final title = loan.name.toLowerCase().contains('préstamo') ||
            loan.name.toLowerCase().contains('prestamo')
        ? loan.name.trim()
        : 'Préstamo ${loan.name.trim()}';
    final monthKey = FinanceFormat.monthKey(_selectedMonth);

    // Check if there is already a matching expense transaction this month so we
    // don't double-charge when adding the recurring item.
    FinanceTransaction? matchingTx;
    for (final tx in monthTransactions) {
      if (tx.kind == TransactionKind.expense &&
          (tx.amount - loan.monthlyPayment).abs() <= 2.0 &&
          (tx.note.toLowerCase().contains('prestamo') ||
              tx.note.toLowerCase().contains('préstamo') ||
              tx.note.toLowerCase().contains(loan.name.toLowerCase()))) {
        matchingTx = tx;
        break;
      }
    }

    final item = RecurringPayment(
      id: recId,
      title: title,
      amount: loan.monthlyPayment,
      kind: TransactionKind.expense,
      categoryId: matchingTx?.categoryId ?? 'cat-other-exp',
      accountId: matchingTx?.accountId ?? targetAccountId,
      dayOfMonth: loan.paymentDay.clamp(1, 28),
      lastAppliedMonth: matchingTx != null ? monthKey : null,
    );

    final nextTxs = matchingTx == null
        ? _snapshot.transactions
        : [
            for (final tx in _snapshot.transactions)
              tx.id == matchingTx.id ? tx.copyWith(recurringId: recId) : tx,
          ];

    _commit(
      _copySnapshot(
        recurring: [..._snapshot.recurring, item],
        transactions: nextTxs,
      ),
    );
  }

  void updateLoan(FinanceLoan updated) {
    final next = [
      for (final item in _snapshot.loans)
        item.id == updated.id ? updated : item,
    ];
    _commit(_copySnapshot(loans: next));
  }

  void deleteLoan(String id) {
    final next = _snapshot.loans.where((l) => l.id != id).toList();
    _commit(_copySnapshot(loans: next));
  }

  /// Registers money lent to another person and optionally deducts it from
  /// [accountId] so liquid balances reflect the cash that left the wallet.
  void addLentMoney({
    required String borrowerName,
    required double amount,
    required String accountId,
    DateTime? lentDate,
    DateTime? dueDate,
    String note = '',
    bool recordOutflowTransaction = true,
  }) {
    if (amount <= 0) return;
    final cleanName = borrowerName.trim().isEmpty
        ? 'Persona'
        : borrowerName.trim();
    final when = lentDate ?? DateTime.now();
    final record = LentMoneyRecord(
      id: _nextId('lent'),
      borrowerName: cleanName,
      amount: amount,
      lentDate: when,
      dueDate: dueDate,
      accountId: accountId,
      note: note.trim(),
    );
    _commit(_copySnapshot(lentMoney: [..._snapshot.lentMoney, record]));
    if (recordOutflowTransaction) {
      addTransaction(
        kind: TransactionKind.expense,
        amount: amount,
        accountId: accountId,
        categoryId: 'cat-other-exp',
        date: when,
        note: note.trim().isEmpty
            ? 'Préstamo a $cleanName'
            : 'Préstamo a $cleanName · ${note.trim()}',
      );
    }
  }

  void updateLentMoney(LentMoneyRecord updated) {
    final next = [
      for (final item in _snapshot.lentMoney)
        item.id == updated.id ? updated : item,
    ];
    _commit(_copySnapshot(lentMoney: next));
  }

  /// Records a partial or full repayment received from a borrower and
  /// optionally credits [toAccountId].
  void recordLentRepayment({
    required String id,
    required double amount,
    required String toAccountId,
    bool recordInflowTransaction = true,
  }) {
    if (amount <= 0) return;
    LentMoneyRecord? target;
    for (final item in _snapshot.lentMoney) {
      if (item.id == id) {
        target = item;
        break;
      }
    }
    if (target == null) return;
    final applied = min(amount, target.remaining);
    if (applied <= 0) return;
    final nextRepaid = double.parse(
      (target.repaidAmount + applied).toStringAsFixed(2),
    );
    final updated = target.copyWith(repaidAmount: nextRepaid);
    updateLentMoney(updated);
    if (recordInflowTransaction) {
      addTransaction(
        kind: TransactionKind.income,
        amount: applied,
        accountId: toAccountId,
        categoryId: 'cat-other-inc',
        date: DateTime.now(),
        note: 'Devolución de ${target.borrowerName}',
      );
    }
  }

  void deleteLentMoney(String id) {
    final next = _snapshot.lentMoney.where((e) => e.id != id).toList();
    _commit(_copySnapshot(lentMoney: next));
  }

  /// Registers a monthly loan payment (optionally with extra principal payment).
  /// Updates remaining balance & paid months, and optionally records the expense.
  void recordLoanPayment(
    FinanceLoan loan, {
    double extraPrincipal = 0,
    bool recordTransaction = true,
  }) {
    final principalCut = loan.nextPrincipalPortion + max(0.0, extraPrincipal);
    final nextBalance = double.parse(
      max(0.0, loan.remainingBalance - principalCut).toStringAsFixed(2),
    );
    final updatedLoan = loan.copyWith(
      remainingBalance: nextBalance,
      paidMonths: loan.paidMonths + 1,
    );
    final nextLoans = [
      for (final item in _snapshot.loans)
        item.id == loan.id ? updatedLoan : item,
    ];
    _commit(_copySnapshot(loans: nextLoans));

    if (recordTransaction) {
      final totalPay = loan.monthlyPayment + max(0.0, extraPrincipal);
      final targetAccId =
          loan.linkedAccountId ??
          liquidAccounts.firstOrNull?.id ??
          accounts.first.id;
      final defaultCatId = categoriesFor(TransactionKind.expense).firstOrNull?.id;
      addTransaction(
        kind: TransactionKind.expense,
        amount: totalPay,
        accountId: targetAccId,
        categoryId: defaultCatId,
        date: DateTime.now(),
        note: extraPrincipal > 0
            ? '${loan.name} (cuota + abono capital)'
            : 'Cuota ${loan.name}',
      );
    }
  }

  /// Given a desired real balance today (negative for debt), computes the
  /// exact [initialBalance] needed so existing transactions stay intact.
  double initialBalanceForTargetCurrent(
    String accountId,
    double targetCurrentBalance,
  ) {
    final acc = accountById(accountId);
    if (acc == null) return targetCurrentBalance;
    final txDelta = balanceOfAccount(accountId) - acc.initialBalance;
    return double.parse((targetCurrentBalance - txDelta).toStringAsFixed(2));
  }

  /// Waits for all queued disk writes to finish.
  Future<void> flush() => _saveQueue;

  String _nextId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 16)}';

  void previousMonth() {
    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    notifyListeners();
  }

  void nextMonth() {
    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    notifyListeners();
  }

  void resetToCurrentMonth() {
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    notifyListeners();
  }

  void toggleHideBalances() {
    _commit(_copySnapshot(hideBalances: !_snapshot.hideBalances));
  }

  void setCurrency(CurrencyOption option) {
    _commit(
      _copySnapshot(currencyCode: option.code, currencySymbol: option.symbol),
    );
  }

  /// Computes the default transaction fee for an outgoing movement from [accountId].
  double computeFeeFor(String accountId, TransactionKind kind, double amount) {
    if (kind == TransactionKind.income || amount <= 0) return 0;
    final acc = accountById(accountId);
    final pct = acc?.transactionFeePercent;
    if (pct == null || pct <= 0) return 0;
    return double.parse((amount * pct / 100.0).toStringAsFixed(2));
  }

  /// Adds a transaction and returns a budget warning message if a category
  /// monthly budget was exceeded by this expense.
  String? addTransaction({
    required TransactionKind kind,
    required double amount,
    required String accountId,
    required DateTime date,
    String? categoryId,
    String? toAccountId,
    String note = '',
    String? recurringId,
    double? feeAmount,
  }) {
    if (amount <= 0) return null;
    final resolvedFee = feeAmount ?? computeFeeFor(accountId, kind, amount);
    final tx = FinanceTransaction(
      id: _nextId('tx'),
      kind: kind,
      amount: amount,
      accountId: accountId,
      date: date,
      categoryId: kind == TransactionKind.transfer ? null : categoryId,
      toAccountId: kind == TransactionKind.transfer ? toAccountId : null,
      note: note.trim(),
      recurringId: recurringId,
      feeAmount: resolvedFee > 0 ? resolvedFee : 0,
    );
    final updated = [tx, ..._snapshot.transactions]
      ..sort((a, b) => b.date.compareTo(a.date));
    _commit(_copySnapshot(transactions: updated));

    if (kind == TransactionKind.expense && categoryId != null) {
      final category = categoryById(categoryId);
      final limit = category?.monthlyBudget;
      if (category != null && limit != null && limit > 0) {
        final spent = spentInCategoryForMonth(categoryId, date);
        if (spent > limit) {
          return 'Superaste el presupuesto de ${category.name} '
              '(${FinanceFormat.money(spent, symbol: currencySymbol)} / '
              '${FinanceFormat.money(limit, symbol: currencySymbol)}).';
        }
      }
    }
    return null;
  }

  void updateTransaction(FinanceTransaction updatedTx) {
    final updated = [
      for (final item in _snapshot.transactions)
        item.id == updatedTx.id ? updatedTx : item,
    ]..sort((a, b) => b.date.compareTo(a.date));
    _commit(_copySnapshot(transactions: updated));
  }

  void deleteTransaction(String id) {
    FinanceTransaction? removed;
    for (final tx in _snapshot.transactions) {
      if (tx.id == id) {
        removed = tx;
        break;
      }
    }
    final updatedTxs = _snapshot.transactions.where((t) => t.id != id).toList();
    var updatedRec = _snapshot.recurring;
    if (removed?.recurringId != null) {
      final removedMonth = FinanceFormat.monthKey(removed!.date);
      updatedRec = [
        for (final rec in _snapshot.recurring)
          rec.id == removed.recurringId && rec.lastAppliedMonth == removedMonth
              ? rec.copyWith(clearLastAppliedMonth: true)
              : rec,
      ];
    }
    _commit(_copySnapshot(transactions: updatedTxs, recurring: updatedRec));
  }

  void addAccount({
    required String name,
    required AccountKind kind,
    required double initialBalance,
    required String colorHex,
    double? creditLimit,
    int? statementDay,
    int? paymentDueDay,
    double? transactionFeePercent,
    String? linkedAccountId,
  }) {
    final account = FinanceAccount(
      id: _nextId('acc'),
      name: name.trim(),
      kind: kind,
      initialBalance: initialBalance,
      colorHex: colorHex,
      creditLimit: creditLimit,
      statementDay: statementDay,
      paymentDueDay: paymentDueDay,
      transactionFeePercent: transactionFeePercent,
      linkedAccountId: linkedAccountId,
    );
    _commit(_copySnapshot(accounts: [..._snapshot.accounts, account]));
  }

  void updateAccount(FinanceAccount account) {
    final updated = [
      for (final item in _snapshot.accounts)
        item.id == account.id ? account : item,
    ];
    _commit(_copySnapshot(accounts: updated));
  }

  void archiveAccount(String id) {
    if (accounts.length <= 1) return;
    final updated = [
      for (final item in _snapshot.accounts)
        item.id == id ? item.copyWith(archived: true) : item,
    ];
    _commit(_copySnapshot(accounts: updated));
  }

  void setCategoryBudget(String categoryId, double? budget) {
    final updated = [
      for (final item in _snapshot.categories)
        item.id == categoryId
            ? item.copyWith(
                monthlyBudget: budget != null && budget > 0 ? budget : null,
                clearBudget: budget == null || budget <= 0,
              )
            : item,
    ];
    _commit(_copySnapshot(categories: updated));
  }

  /// Clears all monthly budget limits across expense categories in one atomic commit.
  void clearAllCategoryBudgets() {
    final updated = [
      for (final item in _snapshot.categories)
        item.kind == TransactionKind.expense
            ? item.copyWith(monthlyBudget: null, clearBudget: true)
            : item,
    ];
    _commit(_copySnapshot(categories: updated));
  }

  void addCategory({
    required String name,
    required TransactionKind kind,
    required String iconKey,
    required String colorHex,
    double? monthlyBudget,
  }) {
    final category = FinanceCategory(
      id: _nextId('cat'),
      name: name.trim(),
      kind: kind,
      iconKey: iconKey,
      colorHex: colorHex,
      monthlyBudget: monthlyBudget != null && monthlyBudget > 0
          ? monthlyBudget
          : null,
    );
    _commit(_copySnapshot(categories: [..._snapshot.categories, category]));
  }

  void addRecurring({
    required String title,
    required double amount,
    required TransactionKind kind,
    required String categoryId,
    required String accountId,
    required int dayOfMonth,
  }) {
    final item = RecurringPayment(
      id: _nextId('rec'),
      title: title.trim(),
      amount: amount,
      kind: kind,
      categoryId: categoryId,
      accountId: accountId,
      dayOfMonth: dayOfMonth.clamp(1, 28),
    );
    _commit(_copySnapshot(recurring: [..._snapshot.recurring, item]));
  }

  void updateRecurring(
    RecurringPayment updated, {
    bool syncCurrentMonthTx = true,
  }) {
    final nextRec = [
      for (final item in _snapshot.recurring)
        item.id == updated.id ? updated : item,
    ];
    var nextTxs = _snapshot.transactions;
    if (syncCurrentMonthTx) {
      final monthKey = FinanceFormat.monthKey(_selectedMonth);
      nextTxs = [
        for (final tx in _snapshot.transactions)
          tx.recurringId == updated.id &&
                  FinanceFormat.monthKey(tx.date) == monthKey
              ? tx.copyWith(
                  kind: updated.kind,
                  amount: updated.amount,
                  accountId: updated.accountId,
                  categoryId: updated.categoryId,
                  note: updated.title,
                  feeAmount: computeFeeFor(
                    updated.accountId,
                    updated.kind,
                    updated.amount,
                  ),
                )
              : tx,
      ];
    }
    _commit(_copySnapshot(recurring: nextRec, transactions: nextTxs));
  }

  /// Promotes an existing expense/income transaction into a monthly recurring
  /// item on the exact same account & category without duplicating or shifting
  /// account balances.
  void convertTransactionToRecurring(FinanceTransaction tx) {
    if (tx.kind == TransactionKind.transfer || tx.recurringId != null) return;
    final recId = _nextId('rec');
    final categoryId =
        tx.categoryId ?? categoriesFor(tx.kind).first.id;
    final title = tx.note.isNotEmpty
        ? tx.note
        : (categoryById(categoryId)?.name ?? 'Pago fijo');
    final monthKey = FinanceFormat.monthKey(tx.date);
    final rec = RecurringPayment(
      id: recId,
      title: title,
      amount: tx.amount,
      kind: tx.kind,
      categoryId: categoryId,
      accountId: tx.accountId,
      dayOfMonth: tx.date.day.clamp(1, 28),
      lastAppliedMonth: monthKey,
    );
    final nextTxs = [
      for (final item in _snapshot.transactions)
        item.id == tx.id ? item.copyWith(recurringId: recId) : item,
    ];
    _commit(
      _copySnapshot(
        recurring: [..._snapshot.recurring, rec],
        transactions: nextTxs,
      ),
    );
  }

  void toggleRecurringActive(String id) {
    final updated = [
      for (final item in _snapshot.recurring)
        item.id == id ? item.copyWith(active: !item.active) : item,
    ];
    _commit(_copySnapshot(recurring: updated));
  }

  void deleteRecurring(String id) {
    final updated = _snapshot.recurring.where((r) => r.id != id).toList();
    _commit(_copySnapshot(recurring: updated));
  }

  String? applyRecurringToSelectedMonth(RecurringPayment item) {
    final monthKey = FinanceFormat.monthKey(_selectedMonth);
    if (item.lastAppliedMonth == monthKey) return null;
    final txDate = DateTime(
      _selectedMonth.year,
      _selectedMonth.month,
      item.dayOfMonth.clamp(1, 28),
      12,
    );
    final warning = addTransaction(
      kind: item.kind,
      amount: item.amount,
      accountId: item.accountId,
      date: txDate,
      categoryId: item.categoryId,
      note: item.title,
      recurringId: item.id,
    );
    final updatedRec = [
      for (final r in _snapshot.recurring)
        r.id == item.id ? r.copyWith(lastAppliedMonth: monthKey) : r,
    ];
    _commit(_copySnapshot(recurring: updatedRec));
    return warning;
  }

  // ---- Computed analytics ----

  double balanceOfAccount(String accountId) {
    final account = accountById(accountId);
    if (account == null) return 0;
    var balance = account.initialBalance;
    for (final tx in _snapshot.transactions) {
      switch (tx.kind) {
        case TransactionKind.income:
          if (tx.accountId == accountId) balance += tx.amount;
        case TransactionKind.expense:
          if (tx.accountId == accountId) {
            balance -= (tx.amount + tx.feeAmount);
          }
        case TransactionKind.transfer:
          if (tx.accountId == accountId) {
            balance -= (tx.amount + tx.feeAmount);
          }
          if (tx.toAccountId == accountId) balance += tx.amount;
      }
    }
    return balance;
  }

  /// Positive debt owed on a credit card or salary advance account.
  double debtOfAccount(String accountId) {
    final bal = balanceOfAccount(accountId);
    return bal < 0 ? -bal : 0;
  }

  /// Remaining credit / advance capacity if [creditLimit] is configured.
  double? availableLimitOf(FinanceAccount account) {
    final limit = account.creditLimit;
    if (limit == null || limit <= 0) return null;
    return max(0, limit - debtOfAccount(account.id));
  }

  double get liquidBalance => liquidAccounts.fold<double>(
    0,
    (sum, account) => sum + balanceOfAccount(account.id),
  );

  double get totalDebt => debtAccounts.fold<double>(
    0,
    (sum, account) => sum + debtOfAccount(account.id),
  );

  double get totalAvailableCredit => debtAccounts.fold<double>(
    0,
    (sum, account) => sum + (availableLimitOf(account) ?? 0),
  );

  double get totalBalance => accounts.fold<double>(
    0,
    (sum, account) => sum + balanceOfAccount(account.id),
  );

  double get monthlyRecurringIncome => _snapshot.recurring
      .where((r) => r.active && r.kind == TransactionKind.income)
      .fold<double>(0, (sum, r) => sum + r.amount);

  double get estimatedMonthlyIncome =>
      monthlyRecurringIncome > 0 ? monthlyRecurringIncome : monthIncome;

  /// Fixed monthly salary/recurring income (excluding one-off freelance or extra income).
  double get fixedSalaryIncome =>
      _snapshot.budgetIncomeOverride ??
      (monthlyRecurringIncome > 0 ? monthlyRecurringIncome : monthIncome);

  /// Extra variable income received in the selected month beyond fixed salary.
  double get extraMonthIncome => max(0.0, monthIncome - fixedSalaryIncome);

  /// Info about the user's next recurring salary/income payday.
  ({String title, int dayOfMonth, int daysUntil, double amount})?
  get nextRecurringIncomeInfo {
    final incomes = _snapshot.recurring
        .where((r) => r.active && r.kind == TransactionKind.income)
        .toList();
    if (incomes.isEmpty) return null;
    incomes.sort(
      (a, b) => FinanceFormat.daysUntilDayOfMonth(
        a.dayOfMonth,
      ).compareTo(FinanceFormat.daysUntilDayOfMonth(b.dayOfMonth)),
    );
    final next = incomes.first;
    return (
      title: next.title,
      dayOfMonth: next.dayOfMonth,
      daysUntil: FinanceFormat.daysUntilDayOfMonth(next.dayOfMonth),
      amount: next.amount,
    );
  }

  List<RecurringPayment> get unpaidRecurringExpensesListThisMonth {
    final monthKey = FinanceFormat.monthKey(_selectedMonth);
    final list = _snapshot.recurring
        .where(
          (r) =>
              r.active &&
              r.kind == TransactionKind.expense &&
              r.lastAppliedMonth != monthKey,
        )
        .toList();
    list.sort((a, b) => a.dayOfMonth.compareTo(b.dayOfMonth));
    return list;
  }

  int get paidRecurringExpenseCountThisMonth {
    final monthKey = FinanceFormat.monthKey(_selectedMonth);
    return _snapshot.recurring
        .where(
          (r) =>
              r.active &&
              r.kind == TransactionKind.expense &&
              r.lastAppliedMonth == monthKey,
        )
        .length;
  }

  double get pendingRecurringExpensesThisMonth {
    final monthKey = FinanceFormat.monthKey(_selectedMonth);
    return _snapshot.recurring
        .where(
          (r) =>
              r.active &&
              r.kind == TransactionKind.expense &&
              r.lastAppliedMonth != monthKey,
        )
        .fold<double>(0, (sum, r) => sum + r.amount);
  }

  double get paidRecurringExpensesThisMonth {
    final monthKey = FinanceFormat.monthKey(_selectedMonth);
    return _snapshot.recurring
        .where(
          (r) =>
              r.active &&
              r.kind == TransactionKind.expense &&
              r.lastAppliedMonth == monthKey,
        )
        .fold<double>(0, (sum, r) => sum + r.amount);
  }

  /// Cash available today after reserving any unpaid fixed bills left this month.
  double get safeToSpendToday =>
      max(0, liquidBalance - pendingRecurringExpensesThisMonth);

  /// Primary monthly income used for budgeting and savings recommendations.
  /// By default uses fixed salary (safe baseline); if [includeExtraIncomeInBudget]
  /// is enabled, includes extra freelance/variable income from the month.
  double get primaryBudgetIncome => _snapshot.includeExtraIncomeInBudget
      ? max(fixedSalaryIncome, monthIncome)
      : fixedSalaryIncome;

  double get totalLoanDebt => _snapshot.loans.fold<double>(
    0,
    (sum, loan) => sum + max(0.0, loan.remainingBalance),
  );

  double get totalLoanMonthlyPayments => _snapshot.loans
      .where((l) => l.remainingBalance > 0.01)
      .fold<double>(0, (sum, loan) => sum + loan.monthlyPayment);

  bool _recurringMatchesAnyLoan(RecurringPayment rec) {
    if (_snapshot.loans.isEmpty) return false;
    final lower = rec.title.toLowerCase();
    for (final loan in _snapshot.loans) {
      final closeAmount = (rec.amount - loan.monthlyPayment).abs() <= 2.0;
      final loanName = loan.name.toLowerCase();
      final nameMatch =
          lower.contains('prestamo') ||
          lower.contains('préstamo') ||
          lower.contains('loan') ||
          (loanName.length >= 4 && lower.contains(loanName));
      if (closeAmount && nameMatch) return true;
    }
    return false;
  }

  /// Active recurring expenses excluding any recurring item already represented
  /// in [loans], preventing double-counting in the budget blueprint.
  double get nonLoanRecurringExpenses => _snapshot.recurring
      .where(
        (r) =>
            r.active &&
            r.kind == TransactionKind.expense &&
            !_recurringMatchesAnyLoan(r),
      )
      .fold<double>(0, (sum, r) => sum + r.amount);

  /// Total monthly fixed commitments (non-loan recurring + active loan quotas).
  double get totalFixedAndLoanCommitments =>
      nonLoanRecurringExpenses + totalLoanMonthlyPayments;

  /// Monthly fixed expenses come directly from active recurring expenses (plus
  /// any loans not already listed as recurring).
  double get effectiveMonthlyEssentials => totalFixedAndLoanCommitments;

  /// Count of active recurring expense items.
  int get activeRecurringExpenseCount => _snapshot.recurring
      .where((r) => r.active && r.kind == TransactionKind.expense)
      .length;

  /// Smart recommended monthly reduction step for breaking the Salary Advance loop
  /// without running out of living money.
  double get recommendedAdvanceReduction {
    final margin = max(0.0, primaryBudgetIncome - effectiveMonthlyEssentials);
    if (margin <= 0) return 35.0;
    final raw = (margin * 0.18 / 5).round() * 5.0;
    return raw.clamp(25.0, 120.0);
  }

  double get activeAdvanceReductionStep =>
      _snapshot.advanceReductionStep ?? recommendedAdvanceReduction;

  /// Recommended monthly payoff step to permanently clear credit card debt.
  double get recommendedCreditCardPayoffStep {
    final margin = max(0.0, primaryBudgetIncome - effectiveMonthlyEssentials);
    if (margin <= 0) return 50.0;
    final raw = (margin * 0.16 / 5).round() * 5.0;
    return raw.clamp(25.0, 150.0);
  }

  double get activeCreditCardPayoffStep =>
      _snapshot.creditCardPayoffStep ?? recommendedCreditCardPayoffStep;

  double get totalAdvanceDebt => accounts
      .where((a) => a.kind == AccountKind.salaryAdvance)
      .fold<double>(0, (sum, a) => sum + debtOfAccount(a.id));

  double get totalCreditCardDebt => accounts
      .where((a) => a.kind == AccountKind.credit)
      .fold<double>(0, (sum, a) => sum + debtOfAccount(a.id));

  /// Monthly amount allocated to exit Salary Advance + Credit Card debt.
  double get totalDebtPlanAllocation {
    var total = 0.0;
    if (totalAdvanceDebt > 0.01) {
      total += min(totalAdvanceDebt, activeAdvanceReductionStep);
    }
    if (totalCreditCardDebt > 0.01) {
      total += min(totalCreditCardDebt, activeCreditCardPayoffStep);
    }
    return total;
  }

  /// Debt plan allocation actually counted in this month's budget (0 if paused).
  double get effectiveDebtPlanForBudget =>
      _snapshot.includeDebtPlanInBudget ? totalDebtPlanAllocation : 0.0;

  /// Tailored monthly savings recommendation based on the user's income level.
  double get suggestedMonthlySavings {
    final income = primaryBudgetIncome;
    if (income <= 0) return 0;
    final capacity = max(
      0.0,
      income - totalFixedAndLoanCommitments - effectiveDebtPlanForBudget,
    );
    if (capacity <= 0) return 0;
    final hasActiveRevolvingDebt =
        totalAdvanceDebt > 0.01 || totalCreditCardDebt > 0.01;
    final targetPct = hasActiveRevolvingDebt ? 0.08 : 0.15;
    final capPct = hasActiveRevolvingDebt ? 0.25 : 0.45;
    final raw = min(income * targetPct, capacity * capPct);
    final rounded = (raw / 5).round() * 5.0;
    if (rounded <= 0 && capacity >= 10) return 5.0;
    return rounded;
  }

  /// Active monthly savings goal: either user's custom choice (including $0) or
  /// the suggested amount for their income level.
  double get activeMonthlySavings => _snapshot.customSavingsAmount != null
      ? max(0.0, _snapshot.customSavingsAmount!)
      : suggestedMonthlySavings;

  /// Money left from monthly income for daily living categories (food, transport,
  /// home, health, leisure) after fixed bills, loans, optional debt plan, and savings.
  double get availableForLivingCategories => max(
    0.0,
    primaryBudgetIncome -
        totalFixedAndLoanCommitments -
        effectiveDebtPlanForBudget -
        activeMonthlySavings,
  );

  /// Remaining income after fixed bills, loans, optional debt-exit plan, and category budgets.
  double get remainingUnallocatedIncome =>
      primaryBudgetIncome -
      totalFixedAndLoanCommitments -
      effectiveDebtPlanForBudget -
      activeMonthlySavings -
      totalMonthlyBudget;

  String get savingsSuggestionReason {
    if (primaryBudgetIncome <= 0) {
      return 'Define tu salario mensual para calcular una meta de ahorro.';
    }
    final suggestedText = FinanceFormat.money(
      suggestedMonthlySavings,
      symbol: currencySymbol,
    );
    if (_snapshot.customSavingsAmount != null &&
        _snapshot.customSavingsAmount! <= 0) {
      return 'Sin ahorro este mes (${currencySymbol}0) · Sugerido por tus ingresos: $suggestedText.';
    }
    if (_snapshot.customSavingsAmount != null) {
      return 'Ahorro elegido: ${FinanceFormat.money(_snapshot.customSavingsAmount!, symbol: currencySymbol)} · Sugerido por tus ingresos: $suggestedText.';
    }
    return 'Ahorro sugerido según tus ingresos: $suggestedText (toca «Ahorro sugerido» para cambiarlo o poner ${currencySymbol}0).';
  }

  /// Healthy recommended living distribution across categories based on the
  /// user's available salary pool ([availableForLivingCategories]), NOT past
  /// erratic spending.
  Map<String, ({double share, double recommendedAmount, String guideTip})>
  get recommendedLivingGuide {
    final expCats = categoriesFor(TransactionKind.expense);
    if (expCats.isEmpty) return const {};

    final pool = availableForLivingCategories > 0
        ? availableForLivingCategories
        : max(100.0, primaryBudgetIncome * 0.40);

    const baseWeights = <String, (double, String)>{
      'cat-food': (0.32, '32% · Supermercado, despensa y comidas del mes'),
      'cat-home': (0.18, '18% · Servicios básicos y artículos del hogar'),
      'cat-transport': (0.16, '16% · Gasolina, transporte y movilidad'),
      'cat-health': (0.10, '10% · Farmacia, consultas y cuidado personal'),
      'cat-fun': (0.10, '10% · Salidas, café y descanso sin culpa'),
      'cat-shopping': (0.06, '6% · Ropa o compras personales'),
      'cat-subs': (0.04, '4% · Apps y suscripciones digitales'),
      'cat-other-exp': (0.04, '4% · Margen para imprevistos pequeños'),
    };

    final rawWeights = <String, double>{};
    final tips = <String, String>{};
    var totalWeight = 0.0;

    for (final cat in expCats) {
      final preset = baseWeights[cat.id];
      final w = preset?.$1 ?? 0.06;
      rawWeights[cat.id] = w;
      tips[cat.id] =
          preset?.$2 ?? '${(w * 100).round()}% · Recomendado para vivir bien';
      totalWeight += w;
    }

    final result =
        <String, ({double share, double recommendedAmount, String guideTip})>{};
    for (final cat in expCats) {
      final share = totalWeight > 0 ? (rawWeights[cat.id]! / totalWeight) : 0.0;
      final rawAmt = pool * share;
      final rounded = rawAmt >= 15
          ? (rawAmt / 5).round() * 5.0
          : max(5.0, rawAmt.roundToDouble());
      result[cat.id] = (
        share: share,
        recommendedAmount: rounded,
        guideTip: tips[cat.id]!,
      );
    }
    return result;
  }

  /// Applies the healthy salary-based [recommendedLivingGuide] across all
  /// expense categories in one click.
  void applyRecommendedLivingGuide() {
    final guide = recommendedLivingGuide;
    if (guide.isEmpty) return;
    final updated = [
      for (final item in _snapshot.categories)
        if (item.kind == TransactionKind.expense && guide.containsKey(item.id))
          item.copyWith(monthlyBudget: guide[item.id]!.recommendedAmount)
        else
          item,
    ];
    _commit(_copySnapshot(categories: updated));
  }

  List<FinanceTransaction> transactionsForMonth(DateTime month) => _snapshot
      .transactions
      .where((t) => t.date.year == month.year && t.date.month == month.month)
      .toList(growable: false);

  List<FinanceTransaction> get monthTransactions =>
      transactionsForMonth(_selectedMonth);

  double get monthIncome => monthTransactions
      .where((t) => t.kind == TransactionKind.income)
      .fold<double>(0, (sum, t) => sum + t.amount);

  double get monthFees =>
      monthTransactions.fold<double>(0, (sum, t) => sum + t.feeAmount);

  double get monthExpense => monthTransactions.fold<double>(0, (sum, t) {
    if (t.kind == TransactionKind.expense) {
      return sum + t.amount + t.feeAmount;
    }
    if (t.kind == TransactionKind.transfer && t.feeAmount > 0) {
      return sum + t.feeAmount;
    }
    return sum;
  });

  double get monthNet => monthIncome - monthExpense;

  double get monthSavingsRate =>
      monthIncome > 0 ? ((monthIncome - monthExpense) / monthIncome) : 0;

  double get totalMonthlyBudget => _snapshot.categories
      .where((c) => c.kind == TransactionKind.expense && c.monthlyBudget != null)
      .fold<double>(0, (sum, c) => sum + c.monthlyBudget!);

  double get monthlyRecurringExpenses => _snapshot.recurring
      .where((r) => r.active && r.kind == TransactionKind.expense)
      .fold<double>(0, (sum, r) => sum + r.amount);

  double spentInCategoryForMonth(String categoryId, DateTime month) =>
      transactionsForMonth(month)
          .where(
            (t) =>
                t.kind == TransactionKind.expense && t.categoryId == categoryId,
          )
          .fold<double>(0, (sum, t) => sum + t.amount);

  List<CategorySpending> get monthExpenseBreakdown {
    final total = monthExpense;
    final expenseCategories = categoriesFor(TransactionKind.expense);
    final items = <CategorySpending>[];
    for (final cat in expenseCategories) {
      final spent = spentInCategoryForMonth(cat.id, _selectedMonth);
      if (spent > 0) {
        items.add(
          CategorySpending(
            category: cat,
            spent: spent,
            share: total > 0 ? spent / total : 0,
          ),
        );
      }
    }
    final fees = monthFees;
    if (fees > 0) {
      items.add(
        CategorySpending(
          category: const FinanceCategory(
            id: '_fees',
            name: 'Comisiones / Intereses',
            kind: TransactionKind.expense,
            iconKey: 'chart',
            colorHex: '#B94A48',
          ),
          spent: fees,
          share: total > 0 ? fees / total : 0,
        ),
      );
    }
    items.sort((a, b) => b.spent.compareTo(a.spent));
    return items;
  }

  List<double> get dailyMonthExpenses {
    final daysInMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
    ).day;
    final values = List<double>.filled(daysInMonth, 0);
    for (final tx in monthTransactions) {
      final cost = tx.kind == TransactionKind.expense
          ? tx.amount + tx.feeAmount
          : tx.feeAmount;
      if (cost > 0) {
        final idx = (tx.date.day - 1).clamp(0, daysInMonth - 1);
        values[idx] += cost;
      }
    }
    return values;
  }

  /// Snapshot payload specifically for the native macOS WidgetKit & Menu Bar.
  Map<String, dynamic> toWidgetPayload() {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final currentTxs = transactionsForMonth(currentMonth);
    final currentIncome = currentTxs
        .where((t) => t.kind == TransactionKind.income)
        .fold<double>(0, (sum, t) => sum + t.amount);
    final currentExpense = currentTxs.fold<double>(0, (sum, t) {
      if (t.kind == TransactionKind.expense) return sum + t.amount + t.feeAmount;
      if (t.kind == TransactionKind.transfer && t.feeAmount > 0) {
        return sum + t.feeAmount;
      }
      return sum;
    });
    return {
      'currencySymbol': currencySymbol,
      'currencyCode': currencyCode,
      'hideBalances': hideBalances,
      'monthLabel': FinanceFormat.monthTitle(currentMonth),
      'totalBalance': liquidBalance,
      'monthIncome': currentIncome,
      'monthExpense': currentExpense,
      'monthBudget': totalMonthlyBudget,
      'recent': [
        for (final tx in _snapshot.transactions.take(4))
          {
            'id': tx.id,
            'title': tx.note.isNotEmpty
                ? tx.note
                : (categoryById(tx.categoryId)?.name ??
                      (tx.kind == TransactionKind.transfer
                          ? 'Transferencia'
                          : 'Movimiento')),
            'amount': tx.amount + tx.feeAmount,
            'kind': tx.kind.name,
            'dateLabel': FinanceFormat.shortDate(tx.date),
          },
      ],
    };
  }

  Future<String?> exportCsv() async {
    final buf = StringBuffer(
      'Fecha,Tipo,Monto,Comisión,Moneda,Categoría,Cuenta,Cuenta destino,Nota\n',
    );
    String esc(String value) => '"${value.replaceAll('"', '""')}"';
    for (final tx in _snapshot.transactions) {
      final dateStr =
          '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}-${tx.date.day.toString().padLeft(2, '0')}';
      final kindLabel = switch (tx.kind) {
        TransactionKind.expense => 'Gasto',
        TransactionKind.income => 'Ingreso',
        TransactionKind.transfer => 'Transferencia',
      };
      final catName = categoryById(tx.categoryId)?.name ?? '';
      final accName = accountById(tx.accountId)?.name ?? '';
      final toAccName = accountById(tx.toAccountId)?.name ?? '';
      buf.writeln(
        '${esc(dateStr)},${esc(kindLabel)},${tx.amount.toStringAsFixed(2)},'
        '${tx.feeAmount.toStringAsFixed(2)},${esc(currencyCode)},'
        '${esc(catName)},${esc(accName)},${esc(toAccName)},${esc(tx.note)}',
      );
    }
    final bytes = Uint8List.fromList(utf8.encode(buf.toString()));
    final monthSlug = FinanceFormat.monthKey(_selectedMonth);
    final fileName = 'folio-finanzas-$monthSlug.csv';
    final savedUri = await FilePicker.saveFile(
      dialogTitle: 'Exportar finanzas a CSV',
      fileName: fileName,
      bytes: bytes,
    );
    if (savedUri == null) return null;
    return savedUri.path.isEmpty ? fileName : savedUri.path;
  }
}
