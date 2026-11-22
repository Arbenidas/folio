import Foundation
import WidgetKit

struct FolioWidgetTheme: Codable {
  let surface: String
  let card: String
  let ink: String
  let muted: String
  let primary: String
  let onPrimary: String
  let error: String
  let tertiary: String
  let outline: String
  let isDark: Bool

  static let fallback = FolioWidgetTheme(
    surface: "#F6F0E2",
    card: "#FCF8EE",
    ink: "#292722",
    muted: "#706B60",
    primary: "#286863",
    onPrimary: "#FFF9EB",
    error: "#AF3C36",
    tertiary: "#9C573D",
    outline: "#D5CBB9",
    isDark: false
  )
}

struct FolioWidgetTask: Codable, Identifiable {
  let id: String
  let title: String
  let phase: String
  let priority: String
  let noteTitle: String?
}

struct FolioWidgetFinanceTx: Codable, Identifiable {
  let id: String
  let title: String
  let amount: Double
  let kind: String
  let dateLabel: String
}

struct FolioWidgetFinance: Codable {
  let currencySymbol: String
  let currencyCode: String
  let hideBalances: Bool
  let monthLabel: String
  let totalBalance: Double
  let monthIncome: Double
  let monthExpense: Double
  let monthBudget: Double
  let recent: [FolioWidgetFinanceTx]
}

struct FolioWidgetDailyItem: Codable, Identifiable {
  let id: String
  let text: String
  let done: Bool
}

struct FolioWidgetDaily: Codable {
  let dateTitle: String
  let noteExists: Bool
  let items: [FolioWidgetDailyItem]
}

struct FolioWidgetSnapshot: Codable {
  let updatedAt: Double
  let theme: FolioWidgetTheme
  var doneCount: Int
  var totalCount: Int
  var inProgressCount: Int
  var tasks: [FolioWidgetTask]
  var finance: FolioWidgetFinance?
  var daily: FolioWidgetDaily?

  static let empty = FolioWidgetSnapshot(
    updatedAt: 0,
    theme: .fallback,
    doneCount: 0,
    totalCount: 0,
    inProgressCount: 0,
    tasks: [],
    finance: nil,
    daily: nil
  )
}

enum FolioWidgetStore {
  static let appGroupId = "LS5RBP28M2.com.folio.app.shared"
  static let toggleNotificationName = "LS5RBP28M2.com.folio.app.widget-toggle"

  private static var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
  }

  private static var snapshotURL: URL? {
    containerURL?.appendingPathComponent("widget_snapshot.json")
  }

  private static var pendingTogglesURL: URL? {
    containerURL?.appendingPathComponent("pending_toggles.json")
  }

  static func saveSnapshotJSON(_ jsonString: String) {
    guard let url = snapshotURL, let data = jsonString.data(using: .utf8) else { return }
    try? data.write(to: url, options: .atomic)
    WidgetCenter.shared.reloadAllTimelines()
  }

  static func loadSnapshot() -> FolioWidgetSnapshot {
    guard let url = snapshotURL,
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode(FolioWidgetSnapshot.self, from: data) else {
      return .empty
    }
    return decoded
  }

  static func markTaskDoneFromWidget(id: String) {
    var snapshot = loadSnapshot()
    if let idx = snapshot.tasks.firstIndex(where: { $0.id == id }) {
      let removed = snapshot.tasks.remove(at: idx)
      snapshot.doneCount = min(snapshot.totalCount, snapshot.doneCount + 1)
      if removed.phase == "inProgress" {
        snapshot.inProgressCount = max(0, snapshot.inProgressCount - 1)
      }
      if let url = snapshotURL, let encoded = try? JSONEncoder().encode(snapshot) {
        try? encoded.write(to: url, options: .atomic)
      }
    }

    var pending = readPendingToggles()
    if !pending.contains(id) {
      pending.append(id)
      if let url = pendingTogglesURL, let encoded = try? JSONEncoder().encode(pending) {
        try? encoded.write(to: url, options: .atomic)
      }
    }

    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(toggleNotificationName as CFString),
      nil,
      nil,
      true
    )
    WidgetCenter.shared.reloadAllTimelines()
  }

  static func readPendingToggles() -> [String] {
    guard let url = pendingTogglesURL,
          let data = try? Data(contentsOf: url),
          let decoded = try? JSONDecoder().decode([String].self, from: data) else {
      return []
    }
    return decoded
  }

  static func consumePendingToggles() -> [String] {
    let items = readPendingToggles()
    guard !items.isEmpty else { return [] }
    if let url = pendingTogglesURL {
      try? FileManager.default.removeItem(at: url)
    }
    return items
  }
}
