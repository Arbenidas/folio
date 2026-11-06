import Cocoa
import Darwin
import FlutterMacOS
import AVFoundation
import Sparkle

class MainFlutterWindow: NSWindow {
  private var updaterController: SPUStandardUpdaterController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(origin: windowFrame.origin, size: NSSize(width: 1180, height: 780)), display: true)
    self.minSize = NSSize(width: 800, height: 620)
    self.center()

    let keyboardChannel = FlutterMethodChannel(
      name: "apuntes/keyboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    var keySoundPlayers: [AVAudioPlayer] = []
    var keySoundData: Data?
    var nextKeySound = 0
    var scopedNotesDirectoryURL: URL?
    var pendingNotesDirectoryURL: URL?
    var pendingNotesDirectoryBookmark: Data?
    let defaults = UserDefaults.standard
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
          "notesDirectory": defaults.string(forKey: "folioNotesDirectory") as Any? ?? NSNull()
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
      if call.method == "getTheme" {
        result(defaults.string(forKey: "apuntesTheme") ?? "claro")
        return
      }
      if call.method == "setTheme", let theme = call.arguments as? String {
        defaults.set(theme, forKey: "apuntesTheme")
        result(nil)
        return
      }
      if call.method == "getVolume" {
        result(defaults.object(forKey: "typingKeyVolume") as? Double ?? 0.68)
        return
      }
      if call.method == "setVolume", let volume = call.arguments as? Double {
        defaults.set(volume, forKey: "typingKeyVolume")
        result(nil)
        return
      }
      if call.method == "configure", let bytes = call.arguments as? FlutterStandardTypedData {
        keySoundData = bytes.data
        keySoundPlayers = (0..<8).compactMap { _ in
          guard let player = try? AVAudioPlayer(data: bytes.data) else { return nil }
          player.enableRate = true
          player.prepareToPlay()
          return player
        }
        nextKeySound = 0
        result(nil)
        return
      }
      guard call.method == "click" else {
        result(FlutterMethodNotImplemented)
        return
      }
      var player = keySoundPlayers.first(where: { !$0.isPlaying })
      if player == nil, keySoundPlayers.count < 16, let data = keySoundData,
         let extraPlayer = try? AVAudioPlayer(data: data) {
        extraPlayer.enableRate = true
        extraPlayer.prepareToPlay()
        keySoundPlayers.append(extraPlayer)
        player = extraPlayer
      }
      if player == nil, !keySoundPlayers.isEmpty {
        player = keySoundPlayers[nextKeySound]
        nextKeySound = (nextKeySound + 1) % keySoundPlayers.count
        player?.stop()
      }
      if let player {
        player.currentTime = 0
        player.volume = Float(defaults.object(forKey: "typingKeyVolume") as? Double ?? 0.68)
        player.rate = Float.random(in: 0.97...1.03)
        player.play()
      }
      result(nil)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
