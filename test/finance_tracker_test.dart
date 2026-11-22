import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/core/theme.dart';
import 'package:folio/features/editor/data/desktop_notes_cloud_sync.dart';
import 'package:folio/features/editor/domain/markdown_document.dart';
import 'package:folio/features/editor/presentation/widgets/markdown_preview.dart';
import 'package:folio/features/editor/presentation/widgets/preview_mermaid_diagram.dart';
import 'package:folio/features/finance/data/finance_repository.dart';
import 'package:folio/features/finance/domain/finance_models.dart';
import 'package:folio/features/finance/presentation/controllers/finance_controller.dart';
import 'package:folio/features/finance/presentation/views/finance_workspace.dart';
import 'package:folio/features/mobile/cross_platform_notes_workspace.dart';
import 'package:folio/features/onboarding/presentation/views/welcome_onboarding_screen.dart';
import 'package:folio/features/updates/data/patch_notes_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'FinanceController handles credit cards, salary advance 4% fee, transfers, budgets & persistence',
    () async {
      final tmp = await Directory.systemTemp.createTemp('folio-fin-test-');
      addTearDown(() => tmp.delete(recursive: true));

      final repo = FinanceRepository(directory: tmp);
      final ctrl = FinanceController(repository: repo);
      await ctrl.load();

      expect(ctrl.currencyCode, 'USD');
      expect(ctrl.accounts.length, 4);

      // Update credit card with $335 initial debt + statement/due dates
      final credit = ctrl.accountById('acc-credit')!;
      ctrl.updateAccount(
        credit.copyWith(
          initialBalance: -335,
          creditLimit: 1000,
          statementDay: 15,
          paymentDueDay: 25,
          linkedAccountId: 'acc-debit',
        ),
      );
      expect(ctrl.debtOfAccount('acc-credit'), 335);
      expect(ctrl.availableLimitOf(ctrl.accountById('acc-credit')!), 665);

      // Add Salary Advance account ($450 cap, 4% fee per transaction)
      ctrl.addAccount(
        name: 'Adelanto salarial',
        kind: AccountKind.salaryAdvance,
        initialBalance: 0,
        colorHex: '#C48B28',
        creditLimit: 450,
        paymentDueDay: 30,
        transactionFeePercent: 4,
        linkedAccountId: 'acc-debit',
      );
      final advance = ctrl.accounts.firstWhere(
        (a) => a.kind == AccountKind.salaryAdvance,
      );

      // Salary income into Debit
      ctrl.addTransaction(
        kind: TransactionKind.income,
        amount: 1000,
        accountId: 'acc-debit',
        categoryId: 'cat-salary',
        date: DateTime.now(),
        note: 'Salario',
      );
      expect(ctrl.balanceOfAccount('acc-debit'), 1000);

      // Withdraw $100 from Salary Advance -> Debit: 4% fee ($4) charged on Advance
      ctrl.addTransaction(
        kind: TransactionKind.transfer,
        amount: 100,
        accountId: advance.id,
        toAccountId: 'acc-debit',
        date: DateTime.now(),
        note: 'Retiro adelanto',
      );
      expect(ctrl.balanceOfAccount('acc-debit'), 1100);
      expect(ctrl.debtOfAccount(advance.id), 104);
      expect(ctrl.monthFees, 4);
      expect(ctrl.monthExpense, 4);

      // Pay off credit card ($335) from Debit -> brings credit card debt to $0
      ctrl.addTransaction(
        kind: TransactionKind.transfer,
        amount: 335,
        accountId: 'acc-debit',
        toAccountId: 'acc-credit',
        date: DateTime.now(),
        note: 'Pago tarjeta',
      );
      expect(ctrl.debtOfAccount('acc-credit'), 0);
      expect(ctrl.balanceOfAccount('acc-debit'), 765);

      // Budget warning test
      ctrl.setCategoryBudget('cat-food', 100);
      final warn = ctrl.addTransaction(
        kind: TransactionKind.expense,
        amount: 120,
        accountId: 'acc-debit',
        categoryId: 'cat-food',
        date: DateTime.now(),
        note: 'Supermercado',
      );
      expect(warn, isNotNull);
      expect(ctrl.monthExpense, 124); // $120 food + $4 fee

      // Test initialBalanceForTargetCurrent (non-financial "Deuda real hoy" adjustment)
      final adjustedInit = ctrl.initialBalanceForTargetCurrent(
        'acc-credit',
        -298.07,
      );
      ctrl.updateAccount(
        ctrl.accountById('acc-credit')!.copyWith(initialBalance: adjustedInit),
      );
      expect(ctrl.debtOfAccount('acc-credit'), closeTo(298.07, 0.01));

      // Test convertTransactionToRecurring & updateRecurring account sync
      final foodTx = ctrl.transactions.firstWhere((t) => t.note == 'Supermercado');
      final debitBefore = ctrl.balanceOfAccount('acc-debit');
      ctrl.convertTransactionToRecurring(foodTx);
      expect(ctrl.balanceOfAccount('acc-debit'), debitBefore);
      final convertedRec = ctrl.recurring.firstWhere((r) => r.title == 'Supermercado');
      expect(convertedRec.accountId, 'acc-debit');

      // Moving recurring from acc-debit -> acc-cash updates current month's tx and restores acc-debit
      ctrl.updateRecurring(convertedRec.copyWith(accountId: 'acc-cash'));
      expect(ctrl.balanceOfAccount('acc-debit'), closeTo(debitBefore + 120, 0.01));
      expect(ctrl.balanceOfAccount('acc-cash'), closeTo(-120, 0.01));

      // Deleting a recurring-linked transaction clears lastAppliedMonth cleanly
      final linkedTx = ctrl.transactions.firstWhere((t) => t.recurringId == convertedRec.id);
      ctrl.deleteTransaction(linkedTx.id);
      expect(ctrl.balanceOfAccount('acc-cash'), closeTo(0, 0.01));
      expect(
        ctrl.recurring.firstWhere((r) => r.id == convertedRec.id).lastAppliedMonth,
        isNull,
      );

      // Test Loans (APR estimation, amortization, extra principal savings & persistence)
      final estApr = FinanceLoan.estimateAnnualRate(
        principal: 5000,
        monthlyPayment: 108.86,
        termMonths: 60,
      );
      expect(estApr, closeTo(11.0, 0.25));

      ctrl.addLoan(
        name: 'Préstamo bancario',
        principal: 5000,
        remainingBalance: 5000,
        annualInterestRate: 0, // auto-estimate
        termMonths: 60,
        paidMonths: 0,
        monthlyPayment: 108.86,
        paymentDay: 15,
        linkedAccountId: 'acc-debit',
      );
      final loan = ctrl.loans.single;
      expect(loan.annualInterestRate, closeTo(11.0, 0.25));
      expect(loan.nextInterestPortion, greaterThan(40));
      expect(loan.nextPrincipalPortion, greaterThan(55));

      final baseSim = loan.simulatePayoff();
      final extraSim = loan.simulatePayoff(extraMonthly: 50);
      expect(extraSim.monthsRemaining, lessThan(baseSim.monthsRemaining));
      expect(
        extraSim.totalInterestRemaining,
        lessThan(baseSim.totalInterestRemaining),
      );

      // Test credit card payoff step & income-based savings suggestion
      ctrl.setDebtPlanSettings(
        advanceReductionStep: 45,
        creditCardPayoffStep: 60,
      );
      ctrl.setBudgetIncomeOverride(683.53);
      expect(ctrl.activeAdvanceReductionStep, 45);
      expect(ctrl.activeCreditCardPayoffStep, 60);
      expect(ctrl.primaryBudgetIncome, 683.53);
      expect(ctrl.suggestedMonthlySavings, greaterThan(0));

      // Verify persistence in isolated JSON file
      await ctrl.flush();
      final reloaded = FinanceController(
        repository: FinanceRepository(directory: tmp),
      );
      await reloaded.load();
      expect(reloaded.debtOfAccount('acc-credit'), closeTo(298.07, 0.01));
      expect(reloaded.debtOfAccount(advance.id), 104);
      expect(reloaded.monthFees, 4);
      expect(reloaded.loans.length, 1);
      expect(reloaded.activeCreditCardPayoffStep, 60);
      expect(reloaded.primaryBudgetIncome, 683.53);
    },
  );

  testWidgets(
    'FinanceWorkspace Bento renders Cascada, Pastel, Diario & all redesigned tabs without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ctrl = FinanceController();
      final credit = ctrl.accountById('acc-credit')!;
      ctrl.updateAccount(
        credit.copyWith(
          initialBalance: -298.07,
          creditLimit: 335,
          statementDay: 22,
          paymentDueDay: 16,
        ),
      );
      ctrl.addAccount(
        name: 'Adelanto salarial 1831',
        kind: AccountKind.salaryAdvance,
        initialBalance: -365.82,
        colorHex: '#286863',
        creditLimit: 439,
        paymentDueDay: 15,
        transactionFeePercent: 4,
        linkedAccountId: 'acc-debit',
      );
      ctrl.addLoan(
        name: 'Préstamo 5 años',
        principal: 5000,
        remainingBalance: 4500,
        annualInterestRate: 11.0,
        termMonths: 60,
        paidMonths: 6,
        monthlyPayment: 108.86,
        paymentDay: 15,
        linkedAccountId: 'acc-debit',
      );
      ctrl.addRecurring(
        title: 'Internet residencial',
        amount: 20,
        kind: TransactionKind.expense,
        categoryId: 'cat-home',
        accountId: 'acc-credit',
        dayOfMonth: 15,
      );
      ctrl.addTransaction(
        kind: TransactionKind.income,
        amount: 720,
        accountId: 'acc-debit',
        categoryId: 'cat-salary',
        date: DateTime.now(),
        note: 'Salario SW',
      );
      ctrl.addTransaction(
        kind: TransactionKind.expense,
        amount: 42.5,
        accountId: 'acc-credit',
        categoryId: 'cat-food',
        date: DateTime.now(),
        note: 'Almuerzo',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildEditorTheme(AppTheme.noche, AppStyle.clasico),
          home: Scaffold(body: FinanceWorkspace(controller: ctrl)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FINANZAS'), findsOneWidget);
      expect(find.text('Cascada de flujo'), findsOneWidget);
      expect(find.text('Crédito y adelanto'), findsOneWidget);
      expect(find.text('Gasto rápido'), findsOneWidget);

      // Tap interactive Bento KPI tile ('Disponible hoy') -> opens interactive modal
      await tester.tap(find.text('Disponible hoy').last);
      await tester.pumpAndSettle();
      expect(find.text('Detalle de disponible hoy'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Detalle de disponible hoy'), findsNothing);

      // Open & close floating quick-add popover
      await tester.tap(find.text('Gasto rápido'));
      await tester.pumpAndSettle();
      expect(find.text('Registro rápido'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      // Switch chart to Pastel (Pie/Donut)
      await tester.tap(find.text('Pastel'));
      await tester.pumpAndSettle();
      expect(find.text('Distribución por categoría'), findsOneWidget);

      // Switch chart to Diario
      await tester.tap(find.text('Diario'));
      await tester.pumpAndSettle();
      expect(find.text('Gasto diario'), findsOneWidget);

      // Switch to Plan de deudas & verify all 3 sub-tabs (Adelanto, Tarjeta, Préstamos)
      await tester.tap(find.text('Plan de deudas'));
      await tester.pumpAndSettle();
      expect(find.text('Plan para salir de deudas'), findsOneWidget);
      expect(find.text('Así baja tu adelanto hasta \$0'), findsOneWidget);

      await tester.tap(find.text('Tarjeta'));
      await tester.pumpAndSettle();
      expect(
        find.text('Así queda tu tarjeta en \$0 para usarla normal'),
        findsOneWidget,
      );

      await tester.tap(find.text('Préstamos (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Préstamo 5 años'), findsOneWidget);
      expect(find.text('Desglose de tu cuota actual'), findsOneWidget);
      // Test 1-click loan -> fixed expense suggestion
      expect(find.text('Agregar a gastos fijos'), findsOneWidget);
      await tester.tap(find.text('Agregar a gastos fijos'));
      await tester.pumpAndSettle();
      expect(ctrl.isLoanInRecurring(ctrl.loans.single), isTrue);

      // Switch to redesigned Movimientos (summary strip + grouped day cards)
      await tester.tap(find.text('Movimientos'));
      await tester.pumpAndSettle();
      expect(find.text('Almuerzo'), findsOneWidget);
      expect(find.text('Entradas'), findsOneWidget);
      expect(find.text('Salidas'), findsOneWidget);

      // Switch to redesigned Presupuestos (2-Card Bento Hero + Inline Multi-Category Planner)
      await tester.tap(find.text('Presupuestos'));
      await tester.pumpAndSettle();
      expect(find.text('Ingreso principal del mes'), findsOneWidget);
      expect(find.text('Ahorro sugerido'), findsOneWidget);
      expect(find.text('Planificar todas'), findsOneWidget);

      // Test 1-click Auto-repartir + Guardar todo in inline planner mode, then Quitar límites
      await tester.tap(find.text('Auto-repartir'));
      await tester.pumpAndSettle();
      expect(find.text('Planificador rápido de categorías'), findsOneWidget);
      await tester.tap(find.text('Guardar todo'));
      await tester.pumpAndSettle();
      expect(ctrl.totalMonthlyBudget, greaterThan(0));
      await tester.tap(find.text('Quitar límites').first);
      await tester.pumpAndSettle();
      expect(ctrl.totalMonthlyBudget, equals(0));

      await tester.tap(find.text('Cuentas'));
      await tester.pumpAndSettle();
      expect(find.text('Tarjeta Crédito'), findsOneWidget);

      // Switch to new 'Me deben' (Lent money to people) section & test empty -> create -> repay flow
      await tester.tap(find.text('Me deben'));
      await tester.pumpAndSettle();
      expect(find.text('Préstamos a personas (Me deben)'), findsOneWidget);
      expect(find.text('Prestar dinero'), findsOneWidget);

      ctrl.addLentMoney(
        borrowerName: 'Carlos',
        amount: 30,
        accountId: 'acc-debit',
        dueDate: DateTime.now().add(const Duration(days: 5)),
        note: 'Almuerzo',
      );
      await tester.pumpAndSettle();
      expect(find.text('Carlos'), findsOneWidget);
      expect(ctrl.totalLentOutstanding, closeTo(30, 0.01));

      // Partial repayment
      ctrl.recordLentRepayment(
        id: ctrl.lentMoney.single.id,
        amount: 10,
        toAccountId: 'acc-debit',
      );
      await tester.pumpAndSettle();
      expect(ctrl.totalLentOutstanding, closeTo(20, 0.01));

      // Full settle via button
      await tester.tap(find.text('Marcar pagado'));
      await tester.pumpAndSettle();
      expect(ctrl.totalLentOutstanding, closeTo(0, 0.01));
      expect(find.text('Ya devueltos'), findsOneWidget);

      await tester.tap(find.text('Recurrentes'));
      await tester.pumpAndSettle();
      expect(find.text('+ Nuevo recurrente'), findsOneWidget);
    },
  );

  test(
    'FinanceRepository recovers from automatic .bak backup and RemoteUpdateManifest detects newer builds',
    () async {
      final tmp = await Directory.systemTemp.createTemp('folio-bak-test-');
      addTearDown(() => tmp.delete(recursive: true));

      final repo = FinanceRepository(directory: tmp);
      final ctrl = FinanceController(repository: repo);
      await ctrl.load();
      ctrl.setBudgetIncomeOverride(750);
      await ctrl.flush();
      ctrl.setBudgetIncomeOverride(800);
      await ctrl.flush();

      // Corrupt primary JSON to verify automatic `.bak` fallback
      final primary = File('${tmp.path}/folio_finances.json');
      await primary.writeAsString('{corrupted json');
      final recovered = await repo.load();
      expect(recovered.budgetIncomeOverride, 750);

      // Verify remote update manifest version detection
      final manifest = RemoteUpdateManifest.fromJson({
        'version': '0.1.0-alpha.6',
        'build': AppVersionInfo.currentBuild + 1,
        'publishedAt': '2026-11-21T00:00:00Z',
        'commitSha': 'abc1234',
        'summary': 'Nuevo parche de prueba',
      });
      expect(manifest.isNewerThanCurrent, isTrue);
    },
  );

  testWidgets(
    'FinanceWorkspace adapts cleanly to compact mobile viewport (390x844) without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final ctrl = FinanceController();
      ctrl.addTransaction(
        kind: TransactionKind.income,
        amount: 683.53,
        accountId: 'acc-debit',
        categoryId: 'cat-salary',
        date: DateTime.now(),
        note: 'Salario',
      );
      ctrl.addTransaction(
        kind: TransactionKind.expense,
        amount: 15.0,
        accountId: 'acc-debit',
        categoryId: 'cat-food',
        date: DateTime.now(),
        note: 'Café',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildEditorTheme(AppTheme.noche, AppStyle.clasico),
          home: Scaffold(body: FinanceWorkspace(controller: ctrl)),
        ),
      );
      await tester.pumpAndSettle();

      // Bottom navigation bar renders cleanly on mobile width
      expect(find.text('Deudas'), findsOneWidget);
      expect(find.text('Movs'), findsOneWidget);
      expect(find.text('Presup.'), findsOneWidget);

      await tester.tap(find.text('Deudas'));
      await tester.pumpAndSettle();
      expect(find.text('Plan de deudas'), findsOneWidget);

      await tester.tap(find.text('Movs'));
      await tester.pumpAndSettle();
      expect(find.text('Café'), findsOneWidget);

      await tester.tap(find.text('Presup.'));
      await tester.pumpAndSettle();
      expect(find.text('Ingreso principal del mes'), findsOneWidget);
    },
  );

  testWidgets(
    'WelcomeOnboardingScreen flows through all 3 steps with live theme & Google Sign-In cleanly',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var selectedTheme = AppTheme.noche;
      var completed = false;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            theme: buildEditorTheme(selectedTheme, AppStyle.clasico),
            home: WelcomeOnboardingScreen(
              selectedTheme: selectedTheme,
              onSelectTheme: (t) => setState(() => selectedTheme = t),
              onComplete: () => completed = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Welcome
      expect(find.text('Paso 1 de 3'), findsOneWidget);
      expect(find.text('Plan de deudas y préstamos'), findsOneWidget);

      // Step 2: Theme selection
      await tester.ensureVisible(find.text('Siguiente'));
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Elige tu estilo visual'), findsOneWidget);
      await tester.ensureVisible(find.text('Crema'));
      await tester.tap(find.text('Crema'));
      await tester.pumpAndSettle();
      expect(selectedTheme, AppTheme.crema);

      // Step 3: Google Sign-In + optional skip
      await tester.ensureVisible(find.text('Siguiente'));
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Continuar con Google'), findsOneWidget);
      await tester.ensureVisible(find.text('Seguir sin cuenta'));
      await tester.tap(find.text('Seguir sin cuenta'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
    },
  );

  testWidgets(
    'FinanceWorkspace spotlight tour, first-time salary starter card, and CrossPlatformNotesWorkspace 4-step spotlight tour work cleanly',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 1. Verify Finance 9-step spotlight tour starts on Salary Starter Card when income is $0
      final ctrl = FinanceController();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEditorTheme(AppTheme.noche, AppStyle.clasico),
          home: Scaffold(
            body: FinanceWorkspace(controller: ctrl, enableSectionTour: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Salary starter card spotlight
      expect(find.text('Empieza con tu ingreso mensual'), findsOneWidget);
      expect(
        find.text('Configura tu salario o ingreso mensual'),
        findsOneWidget,
      );

      final expectedFinanceSteps = [
        'Tu dinero disponible hoy',
        'Cascada, Pastel y Diario',
        'Cupo libre y próximas fechas',
        'Botón de gasto rápido',
        'Plan para salir de deudas',
        'Movimientos agrupados por día',
        'Presupuesto según tu ingreso',
        'Pagos e ingresos fijos',
      ];
      for (final title in expectedFinanceSteps) {
        await tester.tap(find.text('Siguiente'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsWidgets);
      }

      await tester.tap(find.text('¡Entendido!'));
      await tester.pumpAndSettle();
      expect(find.text('Pagos e ingresos fijos'), findsNothing);

      // 2. Return to Resumen and configure monthly salary via the dedicated starter card
      await tester.tap(find.text('Resumen'));
      await tester.pumpAndSettle();
      expect(
        find.text('Configura tu salario o ingreso mensual'),
        findsOneWidget,
      );

      final salaryField = find.widgetWithText(
        CupertinoTextField,
        'Monto mensual',
      );
      expect(salaryField, findsOneWidget);
      await tester.enterText(salaryField, '683.53');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar salario'));
      await tester.pumpAndSettle();

      expect(ctrl.monthlyRecurringIncome, closeTo(683.53, 0.01));
      expect(ctrl.monthIncome, closeTo(683.53, 0.01));
      // Starter card disappears once income is configured
      expect(find.text('Configura tu salario o ingreso mensual'), findsNothing);

      // 3. Verify CrossPlatformNotesWorkspace folders + 4-step spotlight tour
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEditorTheme(AppTheme.noche, AppStyle.clasico),
          home: const Scaffold(
            body: CrossPlatformNotesWorkspace(enableSectionTour: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Personal'), findsWidgets);
      expect(find.text('Proyectos'), findsWidgets);
      expect(find.text('Crea carpetas para organizarte'), findsOneWidget);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Filtra por carpeta o busca'), findsOneWidget);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Agrega notas en 1 clic'), findsOneWidget);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Alterna entre Editar y Vista'), findsOneWidget);

      await tester.tap(find.text('¡Entendido!'));
      await tester.pumpAndSettle();
      expect(find.text('Alterna entre Editar y Vista'), findsNothing);
    },
  );

  test(
    'FolioNotebookCloudCodec round-trips desktop folders/notes with Web folio_notebook_v1 format',
    () {
      final desktopNotes = [
        const MarkdownDocument(
          id: 'DART/Nueva nota.md',
          title: 'Nueva nota',
          folder: 'DART',
          content: '# ¿Que es folio?',
        ),
        const MarkdownDocument(
          id: 'Sin carpeta.md',
          title: 'Sin carpeta',
          content: 'Hola mundo',
        ),
      ];
      final encoded = FolioNotebookCloudCodec.encodeDesktop(
        notes: desktopNotes,
        folderPaths: {'DART', 'Vacía'},
        nowMs: 1763700000000,
      );
      final decoded = FolioNotebookCloudCodec.decode(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.isDefaultStarterOnly, isFalse);
      expect(decoded.folders, containsAll(['DART', 'Vacía']));
      expect(decoded.notes.length, 2);
      expect(decoded.notes.first.folder, 'DART');
      expect(decoded.notes.first.title, 'Nueva nota');
      expect(decoded.notes.first.content, '# ¿Que es folio?');

      // Signatures match between desktop and decoded cloud payload (no echo loop)
      expect(
        FolioNotebookCloudCodec.signatureFor(
          notes: desktopNotes,
          folderPaths: {'DART', 'Vacía'},
        ),
        FolioNotebookCloudCodec.signatureForDecoded(decoded),
      );

      // Untouched Web starter notebook is detected so it never clobbers real desktop notes
      const webStarter = '''
      {
        "format": "folio_notebook_v1",
        "folders": [
          {"id": "fld-personal", "name": "Personal"},
          {"id": "fld-work", "name": "Proyectos"}
        ],
        "notes": [
          {"id": "note-welcome", "title": "Bienvenida", "content": "...", "updatedAtMs": 1, "folderId": "fld-personal"},
          {"id": "note-ideas", "title": "Ideas", "content": "...", "updatedAtMs": 1, "folderId": "fld-work"}
        ]
      }
      ''';
      final decodedStarter = FolioNotebookCloudCodec.decode(webStarter);
      expect(decodedStarter, isNotNull);
      expect(decodedStarter!.isDefaultStarterOnly, isTrue);
    },
  );

  testWidgets(
    'MarkdownPreview renders Mermaid code blocks with ASCII-safe URL, native fallback, and code toggle',
    (tester) async {
      const mermaidSource = '''
flowchart TD
  M1["1. Principios y Bases de Diseño"] --> M2["2. Dart, UI en Flutter y Estado"]
  M1 --> M3["3. Patrones de Diseño Aplicados"]
  M2 --> M3
''';

      // Verify URL encoding escapes UTF-8 accents to pure ASCII so mermaid.ink never 400s
      final url = buildMermaidInkUrl(
        mermaidSource,
        isDark: false,
        backgroundColor: const Color(0xFFF8F6F1),
      );
      expect(url, startsWith('https://mermaid.ink/img/'));
      expect(url, endsWith('?type=png&bgColor=!F8F6F1'));
      expect(detectMermaidKindLabel(mermaidSource), 'Diagrama de flujo');

      final scrollCtrl = ScrollController();
      addTearDown(scrollCtrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildEditorTheme(AppTheme.crema, AppStyle.clasico),
          home: Scaffold(
            body: MarkdownPreview(
              content: '```mermaid\n$mermaidSource```',
              controller: scrollCtrl,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(PreviewMermaidDiagram), findsOneWidget);
      expect(find.text('Mermaid · Diagrama de flujo'), findsOneWidget);
      expect(find.text('Código'), findsOneWidget);

      // Toggle to raw source code and back to diagram
      await tester.tap(find.text('Código'));
      await tester.pump();
      expect(find.text('Diagrama'), findsOneWidget);
      expect(find.textContaining('flowchart TD'), findsOneWidget);

      await tester.tap(find.text('Diagrama'));
      await tester.pump();
      expect(find.text('Código'), findsOneWidget);
    },
  );
}
