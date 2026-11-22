import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var retainedFolioWindow: MainFlutterWindow?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      if let window = resolveMainWindow(in: sender) {
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
      }
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    var unhandled: [URL] = []
    for url in urls {
      if url.scheme == "com.folio.app" {
        switch url.host {
        case "tasks", "task":
          let rawId = url.host == "task" ? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) : nil
          let taskId = (rawId?.isEmpty == false) ? rawId : nil
          if let window = resolveMainWindow(in: application) {
            window.openTasksFromDeepLink(taskId: taskId)
          }
        case "finance":
          let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
          if let window = resolveMainWindow(in: application) {
            window.openFinanceFromDeepLink(openNew: path == "new")
          }
        case "daily":
          if let window = resolveMainWindow(in: application) {
            window.openDailyFromDeepLink()
          }
        default:
          unhandled.append(url)
        }
      } else {
        unhandled.append(url)
      }
    }
    if !unhandled.isEmpty {
      super.application(application, open: unhandled)
    }
  }

  private func resolveMainWindow(in app: NSApplication) -> MainFlutterWindow? {
    let window = retainedFolioWindow
      ?? mainFlutterWindow as? MainFlutterWindow
      ?? app.windows.compactMap { $0 as? MainFlutterWindow }.first
    if let window {
      retainedFolioWindow = window
      mainFlutterWindow = window
    }
    return window
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    retainedFolioWindow = NSApp.windows.compactMap { $0 as? MainFlutterWindow }.first
    mainFlutterWindow = retainedFolioWindow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
