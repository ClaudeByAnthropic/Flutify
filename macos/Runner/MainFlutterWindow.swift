import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var cacheDirectories: CacheDirectories?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    cacheDirectories = CacheDirectories(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

// NSOpenPanel grants access for this launch; bookmarks restore it next launch.
private class CacheDirectories {
  private let key = "FlutifyCacheDirectoryBookmarks"
  private var accessed: [String: URL] = [:]
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.flutify/cache_directories", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      do {
        switch call.method {
        case "restore":
          self.restore()
          result(nil)
        case "remember":
          guard let path = call.arguments as? String else {
            result(FlutterError(code: "invalid_path", message: "Missing directory path", details: nil))
            return
          }
          try self.remember(URL(fileURLWithPath: path, isDirectory: true))
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "directory_access", message: "Unable to retain directory access", details: nil))
      }
    }
  }

  private func remember(_ url: URL) throws {
    let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    var bookmarks = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
    bookmarks[url.path] = data
    UserDefaults.standard.set(bookmarks, forKey: key)
    if accessed[url.path] == nil && url.startAccessingSecurityScopedResource() {
      accessed[url.path] = url
    }
  }

  private func restore() {
    let bookmarks = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
    for (_, data) in bookmarks {
      do {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        if accessed[url.path] == nil && url.startAccessingSecurityScopedResource() {
          accessed[url.path] = url
        }
        if stale { try remember(url) }
      } catch {
        // CacheLocation falls back to AppData if the folder was removed/revoked.
      }
    }
  }

  deinit {
    for url in accessed.values { url.stopAccessingSecurityScopedResource() }
  }
}
