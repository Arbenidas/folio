import Cocoa
import Darwin
import FlutterMacOS
import AVFoundation
import Sparkle
import Security
import UserNotifications
import WebKit

class MainFlutterWindow: NSWindow {
  // Matches FolioWindowChrome.toolbarHeight in Flutter.
  private let folioToolbarHeight: CGFloat = 40
  private var updaterController: SPUStandardUpdaterController?
  private var companionStatusItem: NSStatusItem?
  private var pomodoroTime = "25:00"
  private var pomodoroDeadline: Date?
  private var pomodoroTicker: Timer?
  private var pomodoroActivity: NSObjectProtocol?
  private var pomodoroRunning = false
  private var activePdfExporter: FolioPdfExporter?
  private var widgetChannel: FlutterMethodChannel?

  func openTasksFromDeepLink(taskId: String?) {
    restoreFolioWindow(nil)
    widgetChannel?.invokeMethod("openTasks", arguments: taskId)
  }

  func openFinanceFromDeepLink(openNew: Bool) {
    restoreFolioWindow(nil)
    widgetChannel?.invokeMethod("openFinance", arguments: openNew)
  }

  func openDailyFromDeepLink() {
    restoreFolioWindow(nil)
    widgetChannel?.invokeMethod("openDaily", arguments: nil)
  }

  private func sendNativeNotification(title: String, body: String) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: "folio-\(UUID().uuidString)",
        content: content,
        trigger: nil
      )
      center.add(request, withCompletionHandler: nil)
    }
  }

  private func notifyFlutterOfWidgetToggles() {
    let ids = FolioWidgetStore.consumePendingToggles()
    guard !ids.isEmpty else { return }
    DispatchQueue.main.async { [weak self] in
      self?.widgetChannel?.invokeMethod("applyToggles", arguments: ids)
    }
  }

  override func sendEvent(_ event: NSEvent) {
    guard event.type == .leftMouseDown,
          isKeyWindow,
          isMovable,
          !styleMask.contains(.fullScreen) else {
      super.sendEvent(event)
      return
    }
    let point = event.locationInWindow
    let distanceFromTop = frame.height - point.y
    if distanceFromTop >= 2,
       distanceFromTop < folioToolbarHeight,
       point.x >= 355,
       point.x <= frame.width - 430 {
      if event.clickCount == 2 {
        performZoom(nil)
        return
      }
      if event.clickCount == 1 {
        performDrag(with: event)
        return
      }
    }
    super.sendEvent(event)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.styleMask.insert(.fullSizeContentView)
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    if #available(macOS 11.0, *) {
      self.titlebarSeparatorStyle = .none
    }
    self.setFrame(NSRect(origin: windowFrame.origin, size: NSSize(width: 1180, height: 780)), display: true)
    self.minSize = NSSize(width: 800, height: 620)
    self.center()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(folioWindowDidMiniaturize(_:)),
      name: NSWindow.didMiniaturizeNotification,
      object: self
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(folioWindowDidDeminiaturize(_:)),
      name: NSWindow.didDeminiaturizeNotification,
      object: self
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(folioWindowDidBecomeKey(_:)),
      name: NSWindow.didBecomeKeyNotification,
      object: self
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(folioWindowDidResignKey(_:)),
      name: NSWindow.didResignKeyNotification,
      object: self
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(folioWindowDidClose(_:)),
      name: NSWindow.willCloseNotification,
      object: self
    )

    let keyboardChannel = FlutterMethodChannel(
      name: "apuntes/keyboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    let clipboardChannel = FlutterMethodChannel(
      name: "folio/clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    let blogKeychain = FlutterMethodChannel(
      name: "folio/blog-keychain",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    blogKeychain.setMethodCallHandler(Self.handleBlogKeychain)
    let widgetChannel = FlutterMethodChannel(
      name: "folio/widget",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    self.widgetChannel = widgetChannel
    widgetChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "sync":
        if let json = call.arguments as? String {
          FolioWidgetStore.saveSnapshotJSON(json)
          DispatchQueue.main.async {
            self?.rebuildCompanionMenu()
          }
        }
        result(nil)
      case "consumePendingToggles":
        result(FolioWidgetStore.consumePendingToggles())
      case "notify":
        if let args = call.arguments as? [String: Any],
           let title = args["title"] as? String,
           let body = args["body"] as? String {
          self?.sendNativeNotification(title: title, body: body)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let observerPtr = Unmanaged.passUnretained(self).toOpaque()
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      observerPtr,
      { _, observer, _, _, _ in
        guard let observer else { return }
        let window = Unmanaged<MainFlutterWindow>.fromOpaque(observer).takeUnretainedValue()
        window.notifyFlutterOfWidgetToggles()
      },
      FolioWidgetStore.toggleNotificationName as CFString,
      nil,
      .deliverImmediately
    )
    let exportChannel = FlutterMethodChannel(
      name: "folio/export",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    exportChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "export", message: "Ventana no disponible.", details: nil))
        return
      }
      guard call.method == "renderPdf", let html = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let exporter = FolioPdfExporter()
      self.activePdfExporter = exporter
      exporter.render(html: html) { [weak self] output in
        self?.activePdfExporter = nil
        switch output {
        case .success(let data):
          result(FlutterStandardTypedData(bytes: data))
        case .failure(let error):
          result(FlutterError(code: "pdf_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
    let pomodoroChannel = FlutterMethodChannel(
      name: "folio/pomodoro",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    pomodoroChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "update":
        if let values = call.arguments as? [String: Any] {
          if let time = values["display"] as? String {
            self.pomodoroTime = time
          }
          self.pomodoroRunning = values["running"] as? Bool ?? false
          if let timestamp = values["deadline"] as? Double {
            self.pomodoroDeadline = Date(timeIntervalSince1970: timestamp / 1000)
          } else {
            self.pomodoroDeadline = nil
          }
          self.updatePomodoroTicker()
          self.refreshCompanionStatusItem()
        } else if let time = call.arguments as? String {
          self.pomodoroTime = time
          self.refreshCompanionStatusItem()
        }
        result(nil)
      case "stop":
        self.pomodoroRunning = false
        self.pomodoroDeadline = nil
        self.pomodoroTicker?.invalidate()
        self.pomodoroTicker = nil
        self.endPomodoroActivity()
        self.refreshCompanionStatusItem()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    clipboardChannel.setMethodCallHandler { call, result in
      guard call.method == "readPng" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let pasteboard = NSPasteboard.general
      if let text = pasteboard.string(forType: .string), !text.isEmpty {
        result(nil)
        return
      }
      let limit = 20 * 1024 * 1024
      let tooLarge = FlutterError(
        code: "imageTooLarge", message: "Pega una captura de hasta 20 MB.", details: nil
      )
      var png = pasteboard.data(forType: .png)
      if png == nil, let tiff = pasteboard.data(forType: .tiff) {
        guard tiff.count <= limit else {
          result(tooLarge)
          return
        }
        png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
      }
      guard let png else {
        result(nil)
        return
      }
      guard png.count <= limit else {
        result(tooLarge)
        return
      }
      result(FlutterStandardTypedData(bytes: png))
    }
    var keySoundPlayers: [AVAudioPlayer] = []
    var nextKeySound = 0
    let keySoundQueue = DispatchQueue(label: "folio.keyboard.audio", qos: .userInteractive)
    var lastKeySoundTimestamp: CFTimeInterval = 0
    var scopedNotesDirectoryURL: URL?
    var pendingNotesDirectoryURL: URL?
    var pendingNotesDirectoryBookmark: Data?
    let defaults = UserDefaults.standard
    var cachedKeyVolume = Float(defaults.object(forKey: "typingKeyVolume") as? Double ?? 0.68)
    let updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    self.updaterController = updaterController

    if let appMenu = NSApp.mainMenu?.items.first?.submenu {
      appMenu.addItem(.separator())
      let updateItem = NSMenuItem(
        title: "Buscar actualizaciones…",
        action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
        keyEquivalent: ""
      )
      updateItem.target = updaterController
      appMenu.addItem(updateItem)
    }

    if let bookmark = defaults.data(forKey: "folioNotesDirectoryBookmark") {
      do {
        var isStale = false
        let url = try URL(
          resolvingBookmarkData: bookmark,
          options: [.withSecurityScope],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )
        if url.startAccessingSecurityScopedResource() {
          scopedNotesDirectoryURL = url
          defaults.set(url.path, forKey: "folioNotesDirectory")
          if isStale,
             let refreshedBookmark = try? url.bookmarkData(
               options: [.withSecurityScope],
               includingResourceValuesForKeys: nil,
               relativeTo: nil
             ) {
            defaults.set(refreshedBookmark, forKey: "folioNotesDirectoryBookmark")
          }
        }
      } catch {
        defaults.removeObject(forKey: "folioNotesDirectoryBookmark")
        defaults.removeObject(forKey: "folioNotesDirectory")
      }
    }

    keyboardChannel.setMethodCallHandler { call, result in
      if call.method == "checkForUpdates" {
        updaterController.checkForUpdates(nil)
        result(nil)
        return
      }
      if call.method == "loadInitialSetup" {
        result([
          "isComplete": defaults.bool(forKey: "folioInitialSetupComplete"),
          "notesDirectory": defaults.string(forKey: "folioNotesDirectory") as Any? ?? NSNull(),
          "homeDirectory": NSHomeDirectory()
        ])
        return
      }
      if call.method == "chooseNotesDirectory" {
        let panel = NSOpenPanel()
        panel.title = "Elige dónde guardar tus notas"
        panel.message = "Folio mantendrá tus apuntes en esta carpeta local."
        panel.prompt = "Usar esta carpeta"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let path = call.arguments as? String, !path.isEmpty {
          panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        } else if let user = getpwuid(getuid()) {
          let home = String(cString: user.pointee.pw_dir)
          panel.directoryURL = URL(fileURLWithPath: home, isDirectory: true)
        }
        panel.begin { response in
          guard response == .OK, let url = panel.url else {
            pendingNotesDirectoryURL?.stopAccessingSecurityScopedResource()
            pendingNotesDirectoryURL = nil
            pendingNotesDirectoryBookmark = nil
            result(nil)
            return
          }
          do {
            let isLocal = try url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal
            guard isLocal == true else {
              result(FlutterError(
                code: "unsupported_remote_volume",
                message: "Folio solo admite carpetas en volúmenes locales.",
                details: nil
              ))
              return
            }
            let bookmark = try url.bookmarkData(
              options: [.withSecurityScope],
              includingResourceValuesForKeys: nil,
              relativeTo: nil
            )
            guard url.startAccessingSecurityScopedResource() else {
              result(FlutterError(
                code: "folder_access_denied",
                message: "macOS no permitió acceso persistente a esa carpeta.",
                details: nil
              ))
              return
            }
            pendingNotesDirectoryURL?.stopAccessingSecurityScopedResource()
            pendingNotesDirectoryURL = url
            pendingNotesDirectoryBookmark = bookmark
            result(url.path)
          } catch {
            result(FlutterError(
              code: "folder_bookmark_failed",
              message: "No se pudo guardar el permiso de acceso a la carpeta.",
              details: error.localizedDescription
            ))
          }
        }
        return
      }
      if call.method == "completeInitialSetup", let path = call.arguments as? String {
        if let pendingURL = pendingNotesDirectoryURL,
           pendingURL.path == path,
           let pendingBookmark = pendingNotesDirectoryBookmark {
          scopedNotesDirectoryURL?.stopAccessingSecurityScopedResource()
          scopedNotesDirectoryURL = pendingURL
          pendingNotesDirectoryURL = nil
          pendingNotesDirectoryBookmark = nil
          defaults.set(pendingBookmark, forKey: "folioNotesDirectoryBookmark")
        } else if scopedNotesDirectoryURL?.path != path {
          scopedNotesDirectoryURL?.stopAccessingSecurityScopedResource()
          scopedNotesDirectoryURL = nil
          defaults.removeObject(forKey: "folioNotesDirectoryBookmark")
        }
        defaults.set(path, forKey: "folioNotesDirectory")
        defaults.set(true, forKey: "folioInitialSetupComplete")
        result(nil)
        return
      }
      if call.method == "getAppearance" {
        let appearance = defaults.dictionary(forKey: "folioAppearance")
          ?? ["theme": defaults.string(forKey: "apuntesTheme") ?? "claro"]
        result(appearance)
        return
      }
      if call.method == "setAppearance", let appearance = call.arguments as? [String: String],
         let theme = appearance["theme"], let style = appearance["style"] {
        var stored: [String: String] = ["theme": theme, "style": style]
        if let typography = appearance["editorTypography"] {
          stored["editorTypography"] = typography
        }
        if let fontSize = appearance["editorFontSize"] {
          stored["editorFontSize"] = fontSize
        }
        if let focusMode = appearance["focusMode"] {
          stored["focusMode"] = focusMode
        }
        defaults.set(stored, forKey: "folioAppearance")
        result(nil)
        return
      }
      if call.method == "getUiScale" {
        result(defaults.object(forKey: "folioUiScale") as? Double ?? 1.0)
        return
      }
      if call.method == "setUiScale", let scale = call.arguments as? Double,
         (0.8...1.2).contains(scale) {
        defaults.set(scale, forKey: "folioUiScale")
        result(nil)
        return
      }
      if call.method == "getVolume" {
        result(Double(cachedKeyVolume))
        return
      }
      if call.method == "setVolume", let volume = call.arguments as? Double {
        cachedKeyVolume = Float(volume)
        defaults.set(volume, forKey: "typingKeyVolume")
        result(nil)
        return
      }
      if call.method == "configure", let bytes = call.arguments as? FlutterStandardTypedData {
        let soundData = bytes.data
        keySoundQueue.async {
          // 4 pre-warmed voices are plenty for natural typing without muddy overlap.
          keySoundPlayers = (0..<4).compactMap { _ in
            guard let player = try? AVAudioPlayer(data: soundData) else { return nil }
            player.enableRate = true
            player.prepareToPlay()
            return player
          }
          nextKeySound = 0
          lastKeySoundTimestamp = 0
        }
        result(nil)
        return
      }
      guard call.method == "click" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let baseVolume = cachedKeyVolume
      guard baseVolume > 0 else {
        result(nil)
        return
      }
      let args = call.arguments as? [String: Any]
      let kind = args?["kind"] as? String ?? "char"
      let isRepeat = args?["repeat"] as? Bool ?? false
      keySoundQueue.async {
        guard !keySoundPlayers.isEmpty else { return }
        let now = CACurrentMediaTime()
        // Smooth anti-overlap cadence: crisper for real typing, gentle spaced cadence for held keys.
        let minInterval: CFTimeInterval = isRepeat ? 0.078 : 0.026
        if now - lastKeySoundTimestamp < minInterval {
          return
        }
        lastKeySoundTimestamp = now

        // Keep at most 2 overlapping voices so keys stay crisp and never buzz/clip.
        let playing = keySoundPlayers.filter { $0.isPlaying }
        let player: AVAudioPlayer
        if playing.count >= 2 {
          player = keySoundPlayers[nextKeySound]
          nextKeySound = (nextKeySound + 1) % keySoundPlayers.count
          player.stop()
        } else if let idle = keySoundPlayers.first(where: { !$0.isPlaying }) {
          player = idle
        } else {
          player = keySoundPlayers[nextKeySound]
          nextKeySound = (nextKeySound + 1) % keySoundPlayers.count
          player.stop()
        }

        // Natural per-key acoustic shaping (like a tuned mechanical keyboard).
        let (rateRange, gainMultiplier): (ClosedRange<Float>, Float) = switch kind {
        case "space":
          (0.80...0.85, 1.06)
        case "enter":
          (0.84...0.90, 1.10)
        case "backspace":
          (1.08...1.15, 0.78)
        default:
          (0.96...1.06, Float.random(in: 0.90...1.00))
        }
        let repeatAttenuation: Float = isRepeat ? 0.50 : 1.0
        player.currentTime = 0
        player.volume = min(1.0, baseVolume * gainMultiplier * repeatAttenuation)
        player.rate = Float.random(in: rateRange)
        player.play()
      }
      result(nil)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupCompanionStatusItem()

    super.awakeFromNib()
  }

  @objc private func folioWindowDidMiniaturize(_ notification: Notification) {
    refreshCompanionStatusItem()
  }

  @objc private func folioWindowDidDeminiaturize(_ notification: Notification) {
    refreshCompanionStatusItem()
  }

  @objc private func folioWindowDidBecomeKey(_ notification: Notification) {
    refreshCompanionStatusItem()
  }

  @objc private func folioWindowDidResignKey(_ notification: Notification) {
    refreshCompanionStatusItem()
  }

  @objc private func folioWindowDidClose(_ notification: Notification) {
    DispatchQueue.main.async { [weak self] in
      self?.refreshCompanionStatusItem()
    }
  }

  private func setupCompanionStatusItem() {
    guard companionStatusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    companionStatusItem = item
    refreshCompanionStatusItem()
    rebuildCompanionMenu()
  }

  private func refreshCompanionStatusItem() {
    guard let button = companionStatusItem?.button else { return }
    if #available(macOS 11.0, *) {
      let symbolName = pomodoroRunning ? "timer" : "book.pages"
      let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Folio")
      img?.isTemplate = true
      button.image = img
      button.imagePosition = pomodoroRunning ? .imageLeading : .imageOnly
    }
    button.title = pomodoroRunning ? " \(pomodoroTime)" : ""
    button.toolTip = pomodoroRunning ? "Folio · Pomodoro \(pomodoroTime)" : "Folio"
  }

  private func rebuildCompanionMenu() {
    guard let item = companionStatusItem else { return }
    let snapshot = FolioWidgetStore.loadSnapshot()
    let menu = NSMenu()

    let openItem = NSMenuItem(title: "Abrir Folio", action: #selector(restoreFolioWindow(_:)), keyEquivalent: "")
    openItem.target = self
    menu.addItem(openItem)

    menu.addItem(.separator())

    let newExpense = NSMenuItem(title: "Nuevo gasto rápido…", action: #selector(menuNewExpense(_:)), keyEquivalent: "")
    newExpense.target = self
    menu.addItem(newExpense)

    let dailyNote = NSMenuItem(title: "Abrir nota de hoy", action: #selector(menuOpenDaily(_:)), keyEquivalent: "")
    dailyNote.target = self
    menu.addItem(dailyNote)

    let pendingCount = snapshot.tasks.count
    let tasksTitle = pendingCount > 0 ? "Ver tareas (\(pendingCount) pendientes)" : "Ver tareas"
    let tasksItem = NSMenuItem(title: tasksTitle, action: #selector(menuOpenTasks(_:)), keyEquivalent: "")
    tasksItem.target = self
    menu.addItem(tasksItem)

    if let fin = snapshot.finance {
      menu.addItem(.separator())
      let balStr = fin.hideBalances
        ? "\(fin.currencySymbol)••••"
        : String(format: "%@%.2f", fin.currencySymbol, fin.totalBalance)
      let expStr = fin.hideBalances
        ? "\(fin.currencySymbol)••••"
        : String(format: "%@%.2f", fin.currencySymbol, fin.monthExpense)
      let summary = NSMenuItem(title: "Finanzas · Bal: \(balStr) · Mes: -\(expStr)", action: #selector(menuOpenFinance(_:)), keyEquivalent: "")
      summary.target = self
      menu.addItem(summary)
    }

    item.menu = menu
  }

  @objc private func menuNewExpense(_ sender: Any?) {
    openFinanceFromDeepLink(openNew: true)
  }

  @objc private func menuOpenFinance(_ sender: Any?) {
    openFinanceFromDeepLink(openNew: false)
  }

  @objc private func menuOpenDaily(_ sender: Any?) {
    openDailyFromDeepLink()
  }

  @objc private func menuOpenTasks(_ sender: Any?) {
    openTasksFromDeepLink(taskId: nil)
  }

  private func updatePomodoroTicker() {
    if pomodoroRunning {
      if pomodoroActivity == nil {
        pomodoroActivity = ProcessInfo.processInfo.beginActivity(
          options: [.userInitiated],
          reason: "Keeping the Folio Pomodoro timer current in the menu bar"
        )
      }
      if pomodoroTicker == nil {
        pomodoroTicker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
          self?.refreshPomodoroStatusTitle()
        }
      }
      refreshPomodoroStatusTitle()
      return
    }
    pomodoroTicker?.invalidate()
    pomodoroTicker = nil
    endPomodoroActivity()
  }

  private func endPomodoroActivity() {
    guard let activity = pomodoroActivity else { return }
    ProcessInfo.processInfo.endActivity(activity)
    pomodoroActivity = nil
  }

  private func refreshPomodoroStatusTitle() {
    if let deadline = pomodoroDeadline {
      let seconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
      pomodoroTime = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    refreshCompanionStatusItem()
  }

  @objc private func restoreFolioWindow(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    deminiaturize(nil)
    makeKeyAndOrderFront(nil)
  }

  private static func handleBlogKeychain(_ call: FlutterMethodCall, result: FlutterResult) {
    guard let arguments = call.arguments as? [String: String],
          let key = arguments["key"], key.hasPrefix("folio-blog-"), key.count <= 250 else {
      result(FlutterError(code: "keychain", message: "Clave de sesión inválida.", details: nil))
      return
    }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.folio.app.blog-auth",
      kSecAttrAccount as String: key,
    ]
    let status: OSStatus
    switch call.method {
    case "read":
      var item: CFTypeRef?
      var request = query
      request[kSecReturnData as String] = true
      request[kSecMatchLimit as String] = kSecMatchLimitOne
      status = SecItemCopyMatching(request as CFDictionary, &item)
      if status == errSecSuccess || status == errSecItemNotFound {
        result((item as? Data).flatMap { String(data: $0, encoding: .utf8) })
        return
      }
    case "write":
      guard let value = arguments["value"] else {
        result(FlutterError(code: "keychain", message: "Falta el valor de sesión.", details: nil))
        return
      }
      let data = Data(value.utf8)
      let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
      if update == errSecItemNotFound {
        var item = query
        item[kSecValueData as String] = data
        status = SecItemAdd(item as CFDictionary, nil)
      } else {
        status = update
      }
    case "remove":
      status = SecItemDelete(query as CFDictionary)
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    if status == errSecSuccess || (call.method == "remove" && status == errSecItemNotFound) {
      result(nil)
    } else {
      result(FlutterError(code: "keychain", message: "No se pudo acceder al Llavero.", details: status))
    }
  }
}

private final class FolioPdfExporter: NSObject, WKNavigationDelegate {
  private var webView: WKWebView?
  private var completion: ((Result<Data, Error>) -> Void)?

  func render(html: String, completion: @escaping (Result<Data, Error>) -> Void) {
    self.completion = completion
    let config = WKWebViewConfiguration()
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 820, height: 1120), configuration: config)
    view.navigationDelegate = self
    self.webView = view
    view.loadHTMLString(html, baseURL: nil)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    if #available(macOS 11.0, *) {
      let pdfConfig = WKPDFConfiguration()
      webView.createPDF(configuration: pdfConfig) { [weak self] result in
        DispatchQueue.main.async {
          self?.finish(result)
        }
      }
    } else {
      finish(.failure(NSError(
        domain: "FolioPdfExporter",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "La exportación a PDF requiere macOS 11 o superior."]
      )))
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    finish(.failure(error))
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    finish(.failure(error))
  }

  private func finish(_ result: Result<Data, Error>) {
    let cb = completion
    completion = nil
    webView?.navigationDelegate = nil
    webView = nil
    cb?(result)
  }
}
