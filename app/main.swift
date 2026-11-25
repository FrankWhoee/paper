// Paper — a minimalist writing app.
// A thin native macOS shell around web/index.html using the system WebKit.
// Documents are plain Markdown files in ~/Documents/Paper.

import Cocoa
import WebKit

// MARK: - Document store

let docsDir: URL = {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("Paper", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

func fileURL(for id: String) -> URL? {
    guard !id.isEmpty, id.count < 240, !id.contains("/"), !id.contains(":"), !id.hasPrefix(".") else { return nil }
    return docsDir.appendingPathComponent(id).appendingPathExtension("md")
}

func title(of text: String) -> String {
    for raw in text.split(separator: "\n", maxSplits: 200, omittingEmptySubsequences: true) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        while let c = s.first, "#>-*+".contains(c) { s.removeFirst() }
        s = s.replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { return String(s.prefix(80)) }
    }
    return "untitled"
}

func listDocuments() -> [[String: Any]] {
    let fm = FileManager.default
    let urls = (try? fm.contentsOfDirectory(at: docsDir,
                                            includingPropertiesForKeys: [.contentModificationDateKey],
                                            options: [.skipsHiddenFiles])) ?? []
    var out: [[String: Any]] = []
    for url in urls where url.pathExtension.lowercased() == "md" {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        out.append([
            "id": url.deletingPathExtension().lastPathComponent,
            "title": title(of: text),
            "modified": modified.timeIntervalSince1970 * 1000,
        ])
    }
    return out
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         WKNavigationDelegate, WKScriptMessageHandlerWithReply {
    var window: NSWindow!
    var web: WKWebView!
    var flushed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let config = WKWebViewConfiguration()
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "paper")
        web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = self

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Paper"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 420, height: 320)
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.086, green: 0.086, blue: 0.078, alpha: 1)
                : NSColor(srgbRed: 0.984, green: 0.980, blue: 0.969, alpha: 1)
        }
        window.contentView = web
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("PaperMainWindow")

        if let html = Bundle.main.url(forResource: "index", withExtension: "html") {
            web.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Save before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if flushed || web == nil { return .terminateNow }
        web.callAsyncJavaScript("if (window.paperFlush) { await window.paperFlush(); } return true;",
                                arguments: [:], in: nil, in: .page) { _ in
            self.flushed = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        window.makeFirstResponder(webView)
    }

    // Links in rendered markdown open in the default browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated, let url = action.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: Bridge (JS -> native)

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else {
            replyHandler(nil, "bad message"); return
        }
        let id = body["id"] as? String ?? ""
        switch op {
        case "list":
            replyHandler(listDocuments(), nil)
        case "read":
            guard let url = fileURL(for: id), let text = try? String(contentsOf: url, encoding: .utf8) else {
                replyHandler(nil, nil); return
            }
            replyHandler(text, nil)
        case "write":
            guard let url = fileURL(for: id), let text = body["text"] as? String else {
                replyHandler(nil, "bad id"); return
            }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                replyHandler(true, nil)
            } catch {
                replyHandler(nil, error.localizedDescription)
            }
        case "trash":
            guard let url = fileURL(for: id), FileManager.default.fileExists(atPath: url.path) else {
                replyHandler(false, nil); return
            }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                replyHandler(true, nil)
            } catch {
                replyHandler(nil, error.localizedDescription)
            }
        case "getPref":
            replyHandler(UserDefaults.standard.string(forKey: "pref." + (body["key"] as? String ?? "")), nil)
        case "setPref":
            UserDefaults.standard.set(body["value"] as? String, forKey: "pref." + (body["key"] as? String ?? ""))
            replyHandler(true, nil)
        default:
            replyHandler(nil, "unknown op")
        }
    }

    // MARK: Menu

    @objc func showFolder(_ sender: Any?) {
        NSWorkspace.shared.open(docsDir)
    }

    func buildMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Paper", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Paper", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Paper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Paper", action: nil, keyEquivalent: "").submenu = appMenu

        // ⌘N / ⌘O / ⌘S / ⌘E / ⌘. are handled by the page, so they are not menu shortcuts here.
        let fileMenu = NSMenu(title: "File")
        let show = fileMenu.addItem(withTitle: "Show Documents Folder", action: #selector(showFolder(_:)), keyEquivalent: "")
        show.target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = fileMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let viewMenu = NSMenu(title: "View")
        let fs = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        main.addItem(withTitle: "View", action: nil, keyEquivalent: "").submenu = viewMenu

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }
}

// MARK: - Entry point

// Top-level code runs on the main thread.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
