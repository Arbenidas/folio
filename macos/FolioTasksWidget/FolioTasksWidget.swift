import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Interactive Intent (macOS 14+)

@available(macOS 14.0, *)
struct CompleteFolioTaskIntent: AppIntent {
  static var title: LocalizedStringResource = "Completar tarea de Folio"
  static var description = IntentDescription("Marca una tarea de Folio como hecha desde el escritorio.")

  @Parameter(title: "ID de tarea")
  var taskId: String

  init() {
    self.taskId = ""
  }

  init(taskId: String) {
    self.taskId = taskId
  }

  func perform() async throws -> some IntentResult {
    if !taskId.isEmpty {
      FolioWidgetStore.markTaskDoneFromWidget(id: taskId)
    }
    return .result()
  }
}

// MARK: - Timeline Provider

struct FolioTasksEntry: TimelineEntry {
  let date: Date
  let snapshot: FolioWidgetSnapshot
}

struct FolioTasksProvider: TimelineProvider {
  func placeholder(in context: Context) -> FolioTasksEntry {
    FolioTasksEntry(
      date: Date(),
      snapshot: FolioWidgetSnapshot(
        updatedAt: Date().timeIntervalSince1970,
        theme: .fallback,
        doneCount: 2,
        totalCount: 5,
        inProgressCount: 2,
        tasks: [
          FolioWidgetTask(
            id: "preview-1",
            title: "Pulir borrador de artículo",
            phase: "inProgress",
            priority: "urgentImportant",
            noteTitle: "Blog"
          ),
          FolioWidgetTask(
            id: "preview-2",
            title: "Planificar prioridades de la semana",
            phase: "inProgress",
            priority: "important",
            noteTitle: "Diario"
          ),
          FolioWidgetTask(
            id: "preview-3",
            title: "Revisar notas de arquitectura",
            phase: "pending",
            priority: "later",
            noteTitle: nil
          ),
        ],
        finance: FolioWidgetFinance(
          currencySymbol: "$",
          currencyCode: "USD",
          hideBalances: false,
          monthLabel: "Noviembre 2026",
          totalBalance: 1840.50,
          monthIncome: 1200.00,
          monthExpense: 420.75,
          monthBudget: 800.00,
          recent: [
            FolioWidgetFinanceTx(id: "p1", title: "Café y almuerzo", amount: 14.50, kind: "expense", dateLabel: "Hoy"),
            FolioWidgetFinanceTx(id: "p2", title: "Supermercado", amount: 68.25, kind: "expense", dateLabel: "Ayer"),
          ]
        ),
        daily: FolioWidgetDaily(
          dateTitle: "Hoy",
          noteExists: true,
          items: [
            FolioWidgetDailyItem(id: "d1", text: "Cerrar entrega principal", done: true),
            FolioWidgetDailyItem(id: "d2", text: "Revisar gastos del mes", done: false),
            FolioWidgetDailyItem(id: "d3", text: "Escribir notas de aprendizaje", done: false),
          ]
        )
      )
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (FolioTasksEntry) -> Void) {
    if context.isPreview {
      completion(placeholder(in: context))
    } else {
      completion(FolioTasksEntry(date: Date(), snapshot: FolioWidgetStore.loadSnapshot()))
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<FolioTasksEntry>) -> Void) {
    let entry = FolioTasksEntry(date: Date(), snapshot: FolioWidgetStore.loadSnapshot())
    let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
    completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
  }
}

// MARK: - Color Helpers

private extension Color {
  init(hex: String) {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&int)
    let r = Double((int >> 16) & 0xFF) / 255.0
    let g = Double((int >> 8) & 0xFF) / 255.0
    let b = Double(int & 0xFF) / 255.0
    self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
  }
}

private struct Palette {
  let surface: Color
  let card: Color
  let ink: Color
  let muted: Color
  let primary: Color
  let onPrimary: Color
  let error: Color
  let tertiary: Color
  let outline: Color

  init(_ theme: FolioWidgetTheme) {
    self.surface = Color(hex: theme.surface)
    self.card = Color(hex: theme.card)
    self.ink = Color(hex: theme.ink)
    self.muted = Color(hex: theme.muted)
    self.primary = Color(hex: theme.primary)
    self.onPrimary = Color(hex: theme.onPrimary)
    self.error = Color(hex: theme.error)
    self.tertiary = Color(hex: theme.tertiary)
    self.outline = Color(hex: theme.outline)
  }

  func priorityColor(_ priority: String) -> Color {
    switch priority {
    case "urgentImportant": return error
    case "important": return primary
    case "urgent": return tertiary
    case "later": return muted
    default: return outline
    }
  }
}

// MARK: - Views

struct FolioTasksWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: FolioTasksEntry

  private var palette: Palette { Palette(entry.snapshot.theme) }
  private var snapshot: FolioWidgetSnapshot { entry.snapshot }

  private var progress: Double {
    guard snapshot.totalCount > 0 else { return 0 }
    return Double(snapshot.doneCount) / Double(snapshot.totalCount)
  }

  var body: some View {
    Group {
      switch family {
      case .systemSmall:
        smallLayout
      case .systemMedium:
        mediumLayout
      default:
        largeLayout
      }
    }
    .widgetURL(URL(string: "com.folio.app://tasks"))
  }

  // MARK: Small

  private var smallLayout: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center) {
        HStack(spacing: 5) {
          Image(systemName: "checkmark.rectangle.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.primary)
          Text("Folio")
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(palette.ink)
        }
        Spacer()
        progressBadge
      }

      progressBar

      if snapshot.tasks.isEmpty {
        emptyState(compact: true)
      } else {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(snapshot.tasks.prefix(3)) { task in
            taskRow(task, compact: true)
          }
        }
        Spacer(minLength: 0)
      }
    }
    .padding(13)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: Medium

  private var mediumLayout: some View {
    HStack(spacing: 12) {
      // Left summary column
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 5) {
          Image(systemName: "checkmark.rectangle.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.primary)
          Text("Folio")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(palette.ink)
        }

        Spacer(minLength: 2)

        Text("\(snapshot.tasks.count)")
          .font(.system(size: 28, weight: .bold, design: .rounded))
          .foregroundStyle(palette.ink)
          .monospacedDigit()
        Text(snapshot.tasks.count == 1 ? "tarea activa" : "tareas activas")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(palette.muted)

        progressBar

        HStack(spacing: 4) {
          Circle()
            .fill(palette.primary)
            .frame(width: 6, height: 6)
          Text("\(snapshot.inProgressCount) en curso")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.muted)
        }
      }
      .frame(width: 108, alignment: .leading)
      .padding(11)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(palette.card)
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(palette.outline.opacity(0.65), lineWidth: 1)
          )
      )

      // Right interactive task list
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("PRÓXIMAS TAREAS")
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(palette.muted)
          Spacer()
          progressBadge
        }

        if snapshot.tasks.isEmpty {
          emptyState(compact: false)
        } else {
          VStack(alignment: .leading, spacing: 5) {
            ForEach(snapshot.tasks.prefix(4)) { task in
              taskRow(task, compact: false)
            }
          }
          Spacer(minLength: 0)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .padding(13)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: Large

  private var largeLayout: some View {
    let inProgress = snapshot.tasks.filter { $0.phase == "inProgress" }
    let pending = snapshot.tasks.filter { $0.phase != "inProgress" }

    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        HStack(spacing: 6) {
          Image(systemName: "checkmark.rectangle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(palette.primary)
          Text("Folio · Tareas")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(palette.ink)
        }
        Spacer()
        progressBadge
      }

      progressBar

      if snapshot.tasks.isEmpty {
        emptyState(compact: false)
      } else {
        if !inProgress.isEmpty {
          sectionHeader("EN CURSO", count: inProgress.count, dot: palette.primary)
          VStack(alignment: .leading, spacing: 6) {
            ForEach(inProgress.prefix(3)) { task in
              taskCard(task)
            }
          }
        }

        if !pending.isEmpty {
          sectionHeader("PENDIENTES", count: pending.count, dot: palette.muted)
          let remainingSlots = max(2, 6 - min(inProgress.count, 3))
          VStack(alignment: .leading, spacing: 6) {
            ForEach(pending.prefix(remainingSlots)) { task in
              taskCard(task)
            }
          }
        }
        Spacer(minLength: 0)
      }
    }
    .padding(15)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: Reusable Pieces

  private var progressBadge: some View {
    Text("\(snapshot.doneCount)/\(snapshot.totalCount)")
      .font(.system(size: 10, weight: .bold, design: .monospaced))
      .foregroundStyle(palette.primary)
      .padding(.horizontal, 7)
      .padding(.vertical, 2.5)
      .background(
        Capsule().fill(palette.primary.opacity(0.14))
      )
  }

  private var progressBar: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(palette.outline.opacity(0.45))
          .frame(height: 4)
        Capsule()
          .fill(palette.primary)
          .frame(width: max(0, geo.size.width * progress), height: 4)
      }
    }
    .frame(height: 4)
  }

  private func sectionHeader(_ title: String, count: Int, dot: Color) -> some View {
    HStack(spacing: 6) {
      Circle()
        .fill(dot)
        .frame(width: 6, height: 6)
      Text(title)
        .font(.system(size: 10, weight: .bold))
        .tracking(0.8)
        .foregroundStyle(palette.muted)
      Text("\(count)")
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundStyle(palette.muted.opacity(0.85))
    }
    .padding(.top, 2)
  }

  private func taskRow(_ task: FolioWidgetTask, compact: Bool) -> some View {
    HStack(spacing: 7) {
      checkButton(for: task, size: compact ? 13 : 14)

      Link(destination: taskURL(task.id)) {
        HStack(spacing: 6) {
          Text(task.title)
            .font(.system(size: compact ? 11.5 : 12, weight: task.phase == "inProgress" ? .semibold : .medium))
            .foregroundStyle(palette.ink)
            .lineLimit(1)
          Spacer(minLength: 2)
          if !compact, let note = task.noteTitle, !note.isEmpty {
            Text(note)
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(palette.muted)
              .lineLimit(1)
              .padding(.horizontal, 5)
              .padding(.vertical, 1.5)
              .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                  .fill(palette.outline.opacity(0.28))
              )
          }
          Circle()
            .fill(palette.priorityColor(task.priority))
            .frame(width: 5.5, height: 5.5)
        }
      }
    }
    .padding(.horizontal, compact ? 6 : 8)
    .padding(.vertical, compact ? 4.5 : 5.5)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(palette.card)
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(palette.outline.opacity(0.55), lineWidth: 0.8)
        )
    )
  }

  private func taskCard(_ task: FolioWidgetTask) -> some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 2)
        .fill(palette.priorityColor(task.priority))
        .frame(width: 3, height: 22)

      checkButton(for: task, size: 15)

      Link(destination: taskURL(task.id)) {
        HStack(spacing: 6) {
          Text(task.title)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(palette.ink)
            .lineLimit(1)
          Spacer(minLength: 4)
          if let note = task.noteTitle, !note.isEmpty {
            HStack(spacing: 3) {
              Image(systemName: "doc.text")
                .font(.system(size: 9))
              Text(note)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            }
            .foregroundStyle(palette.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
              RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(palette.surface)
            )
          }
        }
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(palette.card)
        .overlay(
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(palette.outline.opacity(0.6), lineWidth: 0.8)
        )
    )
  }

  @ViewBuilder
  private func checkButton(for task: FolioWidgetTask, size: CGFloat) -> some View {
    if #available(macOS 14.0, *) {
      Button(intent: CompleteFolioTaskIntent(taskId: task.id)) {
        Image(systemName: "circle")
          .font(.system(size: size, weight: .medium))
          .foregroundStyle(task.phase == "inProgress" ? palette.primary : palette.muted)
      }
      .buttonStyle(.plain)
    } else {
      Image(systemName: "circle")
        .font(.system(size: size, weight: .medium))
        .foregroundStyle(task.phase == "inProgress" ? palette.primary : palette.muted)
    }
  }

  private func emptyState(compact: Bool) -> some View {
    VStack(spacing: 5) {
      Spacer(minLength: 4)
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: compact ? 20 : 24))
        .foregroundStyle(palette.primary.opacity(0.85))
      Text("Todo al día")
        .font(.system(size: compact ? 12 : 13, weight: .bold))
        .foregroundStyle(palette.ink)
      if !compact {
        Text("Abre Folio para añadir nuevas tareas.")
          .font(.system(size: 11))
          .foregroundStyle(palette.muted)
          .multilineTextAlignment(.center)
      }
      Spacer(minLength: 4)
    }
    .frame(maxWidth: .infinity)
  }

  private func taskURL(_ id: String) -> URL {
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    return URL(string: "com.folio.app://task/\(encoded)") ?? URL(string: "com.folio.app://tasks")!
  }
}

// MARK: - Finance Widget View

private func formatWidgetMoney(_ amount: Double, symbol: String, hide: Bool, showSign: Bool = false) -> String {
  if hide { return "\(symbol)••••" }
  let formatter = NumberFormatter()
  formatter.numberStyle = .decimal
  formatter.minimumFractionDigits = 2
  formatter.maximumFractionDigits = 2
  formatter.groupingSeparator = ","
  formatter.decimalSeparator = "."
  let absStr = formatter.string(from: NSNumber(value: abs(amount))) ?? String(format: "%.2f", abs(amount))
  if amount < 0 { return "-\(symbol)\(absStr)" }
  if showSign && amount > 0 { return "+\(symbol)\(absStr)" }
  return "\(symbol)\(absStr)"
}

struct FolioFinanceWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: FolioTasksEntry

  private var palette: Palette { Palette(entry.snapshot.theme) }
  private var finance: FolioWidgetFinance {
    entry.snapshot.finance ?? FolioWidgetFinance(
      currencySymbol: "$",
      currencyCode: "USD",
      hideBalances: false,
      monthLabel: "Este mes",
      totalBalance: 0,
      monthIncome: 0,
      monthExpense: 0,
      monthBudget: 0,
      recent: []
    )
  }

  private var budgetRatio: Double {
    guard finance.monthBudget > 0 else { return 0 }
    return min(1.0, max(0.0, finance.monthExpense / finance.monthBudget))
  }

  var body: some View {
    Group {
      if family == .systemSmall {
        smallFinance
      } else {
        mediumFinance
      }
    }
    .widgetURL(URL(string: "com.folio.app://finance"))
  }

  private var smallFinance: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        HStack(spacing: 5) {
          Image(systemName: "chart.pie.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.primary)
          Text("Finanzas")
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(palette.ink)
        }
        Spacer()
        Link(destination: URL(string: "com.folio.app://finance/new")!) {
          Image(systemName: "plus.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(palette.primary)
        }
      }

      Spacer(minLength: 2)

      Text("BALANCE TOTAL")
        .font(.system(size: 9, weight: .bold))
        .tracking(0.6)
        .foregroundStyle(palette.muted)

      Text(formatWidgetMoney(finance.totalBalance, symbol: finance.currencySymbol, hide: finance.hideBalances))
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .foregroundStyle(palette.ink)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)

      if finance.monthBudget > 0 {
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(palette.outline.opacity(0.45))
              .frame(height: 5)
            Capsule()
              .fill(finance.monthExpense > finance.monthBudget ? palette.error : palette.primary)
              .frame(width: max(0, geo.size.width * budgetRatio), height: 5)
          }
        }
        .frame(height: 5)
      }

      HStack {
        Text("Gastos")
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(palette.muted)
        Spacer()
        Text(formatWidgetMoney(finance.monthExpense, symbol: finance.currencySymbol, hide: finance.hideBalances))
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(palette.error)
          .monospacedDigit()
      }
    }
    .padding(13)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var mediumFinance: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 5) {
          Image(systemName: "chart.pie.fill")
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(palette.primary)
          Text("Finanzas")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(palette.ink)
        }

        Spacer(minLength: 2)

        Text(formatWidgetMoney(finance.totalBalance, symbol: finance.currencySymbol, hide: finance.hideBalances))
          .font(.system(size: 21, weight: .bold, design: .rounded))
          .foregroundStyle(palette.ink)
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.7)

        Text(finance.monthLabel)
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(palette.muted)

        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 1) {
            Text("Ingresos")
              .font(.system(size: 9))
              .foregroundStyle(palette.muted)
            Text(formatWidgetMoney(finance.monthIncome, symbol: finance.currencySymbol, hide: finance.hideBalances))
              .font(.system(size: 10.5, weight: .bold))
              .foregroundStyle(palette.primary)
              .lineLimit(1)
          }
          Spacer(minLength: 2)
          VStack(alignment: .leading, spacing: 1) {
            Text("Gastos")
              .font(.system(size: 9))
              .foregroundStyle(palette.muted)
            Text(formatWidgetMoney(finance.monthExpense, symbol: finance.currencySymbol, hide: finance.hideBalances))
              .font(.system(size: 10.5, weight: .bold))
              .foregroundStyle(palette.error)
              .lineLimit(1)
          }
        }
      }
      .frame(width: 148, alignment: .leading)
      .padding(11)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(palette.card)
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(palette.outline.opacity(0.65), lineWidth: 1)
          )
      )

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("RECIENTES")
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(palette.muted)
          Spacer()
          Link(destination: URL(string: "com.folio.app://finance/new")!) {
            HStack(spacing: 3) {
              Image(systemName: "plus")
                .font(.system(size: 9.5, weight: .bold))
              Text("Gasto")
                .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(palette.onPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(palette.primary))
          }
        }

        if finance.recent.isEmpty {
          Spacer()
          Text("Sin movimientos recientes")
            .font(.system(size: 11.5))
            .foregroundStyle(palette.muted)
          Spacer()
        } else {
          VStack(alignment: .leading, spacing: 5) {
            ForEach(finance.recent.prefix(3)) { tx in
              HStack(spacing: 6) {
                Circle()
                  .fill(tx.kind == "income" ? palette.primary : palette.error)
                  .frame(width: 6, height: 6)
                Text(tx.title)
                  .font(.system(size: 11.5, weight: .medium))
                  .foregroundStyle(palette.ink)
                  .lineLimit(1)
                Spacer(minLength: 4)
                Text(
                  formatWidgetMoney(
                    tx.kind == "expense" ? -tx.amount : tx.amount,
                    symbol: finance.currencySymbol,
                    hide: finance.hideBalances,
                    showSign: true
                  )
                )
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tx.kind == "income" ? palette.primary : palette.ink)
                .monospacedDigit()
              }
              .padding(.horizontal, 7)
              .padding(.vertical, 5)
              .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                  .fill(palette.card)
              )
            }
          }
          Spacer(minLength: 0)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .padding(13)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

// MARK: - Daily Note Widget View

struct FolioDailyWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: FolioTasksEntry

  private var palette: Palette { Palette(entry.snapshot.theme) }
  private var daily: FolioWidgetDaily {
    entry.snapshot.daily ?? FolioWidgetDaily(dateTitle: "Nota de hoy", noteExists: false, items: [])
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        HStack(spacing: 5) {
          Image(systemName: "calendar")
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(palette.primary)
          Text(daily.dateTitle)
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(palette.ink)
            .lineLimit(1)
        }
        Spacer()
        Text("DIARIO")
          .font(.system(size: 9, weight: .bold))
          .tracking(0.8)
          .foregroundStyle(palette.primary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Capsule().fill(palette.primary.opacity(0.14)))
      }

      if daily.items.isEmpty {
        Spacer()
        VStack(alignment: .leading, spacing: 4) {
          Text(daily.noteExists ? "Sin prioridades marcadas" : "Abre tu nota de hoy")
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(palette.ink)
          Text("Toca para escribir tu Top 3 del día en Folio.")
            .font(.system(size: 11))
            .foregroundStyle(palette.muted)
        }
        Spacer()
      } else {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(daily.items.prefix(family == .systemSmall ? 3 : 4)) { item in
            HStack(spacing: 7) {
              Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(item.done ? palette.primary : palette.muted)
              Text(item.text)
                .font(.system(size: 12, weight: item.done ? .regular : .medium))
                .strikethrough(item.done)
                .foregroundStyle(item.done ? palette.muted : palette.ink)
                .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.card)
            )
          }
        }
        Spacer(minLength: 0)
      }
    }
    .padding(13)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .widgetURL(URL(string: "com.folio.app://daily"))
  }
}

// MARK: - Widget Definitions

struct FolioTasksWidget: Widget {
  let kind: String = "FolioTasksWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FolioTasksProvider()) { entry in
      if #available(macOS 14.0, *) {
        FolioTasksWidgetView(entry: entry)
          .containerBackground(for: .widget) {
            Color(hex: entry.snapshot.theme.surface)
          }
      } else {
        FolioTasksWidgetView(entry: entry)
          .background(Color(hex: entry.snapshot.theme.surface))
      }
    }
    .configurationDisplayName("Tareas de Folio")
    .description("Consulta y completa tus tareas de Folio directamente desde el escritorio.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    .contentMarginsDisabled()
  }
}

struct FolioFinanceWidget: Widget {
  let kind: String = "FolioFinanceWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FolioTasksProvider()) { entry in
      if #available(macOS 14.0, *) {
        FolioFinanceWidgetView(entry: entry)
          .containerBackground(for: .widget) {
            Color(hex: entry.snapshot.theme.surface)
          }
      } else {
        FolioFinanceWidgetView(entry: entry)
          .background(Color(hex: entry.snapshot.theme.surface))
      }
    }
    .configurationDisplayName("Finanzas de Folio")
    .description("Ve tu balance, gastos del mes y registra nuevos movimientos al instante.")
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}

struct FolioDailyWidget: Widget {
  let kind: String = "FolioDailyWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: FolioTasksProvider()) { entry in
      if #available(macOS 14.0, *) {
        FolioDailyWidgetView(entry: entry)
          .containerBackground(for: .widget) {
            Color(hex: entry.snapshot.theme.surface)
          }
      } else {
        FolioDailyWidgetView(entry: entry)
          .background(Color(hex: entry.snapshot.theme.surface))
      }
    }
    .configurationDisplayName("Nota de hoy · Folio")
    .description("Mantén visibles tus prioridades de la nota diaria de Folio.")
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}

@main
struct FolioTasksWidgetBundle: WidgetBundle {
  var body: some Widget {
    FolioTasksWidget()
    FolioFinanceWidget()
    FolioDailyWidget()
  }
}
