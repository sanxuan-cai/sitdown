import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var engine: Engine!
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var reminder: NSPanel!
    private var menu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent two copies from writing to the same local statistics store.
        if let identifier = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let other = others.first {
                other.activate(options: [.activateIgnoringOtherApps])
                NSApp.terminate(nil)
                return
            }
        }
        engine = Engine()
        setupMenuBar()
        setupWindows()
        setupAppMenu()
        engine.onReminder = { [weak self] visible in
            if visible { self?.showReminder() } else { self?.reminder.orderOut(nil) }
        }
        engine.onChange = { [weak self] in self?.refreshStatus() }
        engine.tick()
        // The settings are discoverable on first launch; subsequent launches stay in the menu bar.
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            openSettings()
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "SitStandAssistant.StatusItem"
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshStatus()
    }

    private func setupWindows() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "坐站助手"
        window.contentView = NSHostingView(rootView: MainView(engine: engine))
        window.minSize = NSSize(width: 620, height: 640)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SitStandAssistant.Settings")
        window.center()

        reminder = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 440),
                           styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        reminder.title = "该换姿势了"
        reminder.contentView = NSHostingView(rootView: ReminderView(engine: engine))
        reminder.level = .floating
        reminder.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        reminder.hidesOnDeactivate = false
        reminder.isFloatingPanel = true
        reminder.isReleasedWhenClosed = false
        reminder.delegate = self
    }

    private func setupAppMenu() {
        let main = NSMenu()
        let application = NSMenuItem()
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "坐站助手设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出坐站助手", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.submenu = appMenu
        main.addItem(application)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
    }

    private func refreshStatus() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: engine.session == nil ? "figure.stand" : engine.posture.symbol, accessibilityDescription: "坐站助手")
        button.imagePosition = .imageLeading
        button.title = engine.session == nil ? "" : engine.isDue ? " 该换姿势了" : " \(engine.posture.title) \(engine.countdown)"
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.toolTip = engine.session == nil ? "坐站助手 · 点击开始" : "坐站助手 · \(engine.posture.title)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        engine.tick()
        menu.removeAllItems()
        add(engine.session == nil ? "坐站助手 · 尚未开始" : "\(engine.posture.title) · \(engine.isDue ? "等待确认" : engine.countdown)")
        add("今日坐姿  \(DayTotal.formatted(engine.today.sitting))")
        add("今日站姿  \(DayTotal.formatted(engine.today.standing))")
        menu.addItem(.separator())
        if engine.session == nil {
            add("开始提醒（\(engine.posture.title)）", #selector(start))
        } else {
            add(engine.posture.confirmation, #selector(confirm))
            if engine.isDue { add("延后 \(engine.settings.snoozeMinutes) 分钟", #selector(snooze)) }
            add("结束提醒", #selector(stop))
        }
        menu.addItem(.separator())
        add("打开设置…", #selector(openSettings), key: ",")
        add("退出坐站助手", #selector(quit), key: "q")
    }

    private func add(_ title: String, _ action: Selector? = nil, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = action != nil
        menu.addItem(item)
    }

    @objc private func start() { engine.start() }
    @objc private func confirm() { engine.confirm() }
    @objc private func snooze() { engine.snooze() }
    @objc private func stop() { engine.stop() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func showReminder() {
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            reminder.setFrameOrigin(NSPoint(x: frame.midX - reminder.frame.width / 2, y: frame.midY - reminder.frame.height / 2))
        }
        reminder.orderFrontRegardless()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { sender !== reminder }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { engine?.shutdown() }
}
