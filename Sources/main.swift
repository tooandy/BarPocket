import AppKit
import Foundation
import ServiceManagement

// BarPocket v0.3.1: offline menu-bar pocket, Accessibility inventory, and notch blackout.
// Cross-app discovery is opt-in; actions are only performed after an explicit user click.

enum PocketLayout {
    static let expandedLength: CGFloat = 16
    static func collapsedLength(screens: [CGFloat]) -> CGFloat {
        let widest = screens.max() ?? 1440
        return max(500, min(widest * 2, 10_000))
    }
    static func duration(_ value: Int) -> TimeInterval { TimeInterval(max(0, value)) }
}

final class PocketController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let bar = NSStatusBar.system
    private var toggle: NSStatusItem!
    private var divider: NSStatusItem!
    private var isCollapsed = false
    private var timer: Timer?
    private var launchTimer: Timer?
    private var hasInteracted = false
    private var managerOperationInProgress = false
    private var managerWindowController: MenuBarManagerWindowController?
    private let notchBlackoutController = NotchBlackoutController()
    private let prefs = UserDefaults.standard
    private let lastCollapsedKey = "lastCollapsed"
    private let autoCollapseKey = "autoCollapseSeconds"
    private let everLaunchedKey = "everLaunched"
    private let notchBlackoutKey = "notchBlackoutEnabled"
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarItemMover.recoverInterruptedDrag()
        // macOS 26 can park newly created status items thousands of points offscreen
        // when the menu bar is already full. Seed only OUR OWN preferred positions
        // on first use. Never overwrite a position chosen later by Command-drag.
        let initialPositions: [(String, Int)] = [
            ("NSStatusItem Preferred Position MenuBarPocket.Toggle", 0),
            ("NSStatusItem Preferred Position MenuBarPocket.Divider", 48)
        ]
        for (key, value) in initialPositions where prefs.object(forKey: key) == nil {
            prefs.set(value, forKey: key)
        }
        // Inserting the toggle first and divider second puts the divider LEFT of the toggle.
        toggle = bar.statusItem(withLength: 27)
        toggle.autosaveName = "MenuBarPocket.Toggle"
        toggle.isVisible = true
        toggle.button?.target = self
        toggle.button?.action = #selector(toggleClick(_:))
        toggle.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        divider = bar.statusItem(withLength: PocketLayout.expandedLength)
        divider.autosaveName = "MenuBarPocket.Divider"
        divider.isVisible = true
        divider.button?.title = "│"
        divider.button?.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .light)
        divider.button?.toolTip = "收纳分隔线：按住 ⌘ 拖动，左边的图标将被收纳"

        menu.delegate = self
        notchBlackoutController.setEnabled(prefs.bool(forKey: notchBlackoutKey))
        updateVisuals()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensChanged(_:)), name: NSWorkspace.didWakeNotification, object: nil)

        let hasLaunched = prefs.bool(forKey: everLaunchedKey)
        prefs.set(true, forKey: everLaunchedKey)
        // Never collapse at first launch. On subsequent launches, wait for the
        // menu bar layout to settle (macOS 26 is sensitive to early collapsing).
        if hasLaunched && prefs.bool(forKey: lastCollapsedKey) {
            launchTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
                guard let self = self, !self.hasInteracted else { return }
                self.setCollapsed(true, remember: false)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        launchTimer?.invalidate()
        // Restore the original visibility of other applications as we exit.
        // Their status item positions and user defaults are not changed.
        divider?.length = PocketLayout.expandedLength
    }

    @objc private func toggleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(from: sender)
        } else {
            recordInteraction()
            setCollapsed(!isCollapsed, remember: true)
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        recordInteraction()
        rebuildMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 2), in: button)
    }

    private func recordInteraction() {
        hasInteracted = true
        launchTimer?.invalidate()
    }

    private func setCollapsed(_ collapsed: Bool, remember: Bool) {
        guard divider != nil else { return }
        isCollapsed = collapsed
        divider.length = collapsed
          ? PocketLayout.collapsedLength(screens: NSScreen.screens.map { $0.frame.width })
          : PocketLayout.expandedLength
        if remember { prefs.set(collapsed, forKey: lastCollapsedKey) }
        updateVisuals()
        scheduleCollapseIfNeeded()
    }

    private func updateVisuals() {
        let symbol = isCollapsed ? "chevron.right" : "chevron.left"
        let hint = isCollapsed ? "展开已收纳图标" : "收纳分隔线左侧的图标"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: hint) {
            image.isTemplate = true
            toggle.button?.image = image
            toggle.button?.imagePosition = .imageOnly
        } else {
            toggle.button?.title = isCollapsed ? "›" : "‹"
        }
        toggle.button?.toolTip = "\(hint)；右键打开设置"
        divider.button?.toolTip = "分隔线：按住 ⌘ 拖到常驻图标的左侧"
    }

    private func scheduleCollapseIfNeeded() {
        timer?.invalidate()
        timer = nil
        let seconds = prefs.integer(forKey: autoCollapseKey)
        guard !isCollapsed, seconds > 0, !managerOperationInProgress else { return }
        timer = Timer.scheduledTimer(withTimeInterval: PocketLayout.duration(seconds), repeats: false) { [weak self] _ in
            guard let self = self, !self.isCollapsed else { return }
            // Never auto-hide while the pointer is inside the menu bar region.
            let point = NSEvent.mouseLocation
            let insideMenuBar = NSScreen.screens.contains { screen in
                screen.frame.contains(point) && point.y >= screen.visibleFrame.maxY - 2
            }
            if insideMenuBar {
                self.scheduleCollapseIfNeeded()
            } else {
                self.setCollapsed(true, remember: true)
            }
        }
    }

    @objc private func screensChanged(_ notification: Notification) {
        // Keep the widened divider and optional notch backing valid after display changes.
        if isCollapsed { setCollapsed(true, remember: false) }
        notchBlackoutController.refreshForDisplayChanges()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let state = NSMenuItem(title: isCollapsed ? "展开全部图标" : "收起左侧图标", action: #selector(menuToggle(_:)), keyEquivalent: "")
        state.target = self
        menu.addItem(state)
        menu.addItem(.separator())

        let blackout = NSMenuItem(title: "刘海隐身模式（顶部黑色）", action: #selector(toggleNotchBlackout(_:)), keyEquivalent: "")
        blackout.target = self
        blackout.state = notchBlackoutController.isEnabled ? .on : .off
        blackout.isEnabled = notchBlackoutController.supportsCurrentDisplay
        menu.addItem(blackout)
        menu.addItem(.separator())

        let tip = NSMenuItem(title: "⌘ 拖动图标到分隔线左侧进行收纳", action: nil, keyEquivalent: "")
        tip.isEnabled = false
        menu.addItem(tip)

        let collapseMenu = NSMenu()
        for seconds in [0, 5, 15, 30] {
            let title = seconds == 0 ? "关闭" : "\(seconds) 秒"
            let option = NSMenuItem(title: title, action: #selector(changeDelay(_:)), keyEquivalent: "")
            option.target = self
            option.tag = seconds
            option.state = prefs.integer(forKey: autoCollapseKey) == seconds ? .on : .off
            collapseMenu.addItem(option)
        }
        let collapseItem = NSMenuItem(title: "展开后自动收起", action: nil, keyEquivalent: "")
        collapseItem.submenu = collapseMenu
        menu.addItem(collapseItem)

        let login = NSMenuItem(title: "登录时启动", action: #selector(changeLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let manager = NSMenuItem(title: "打开菜单栏管理器…", action: #selector(openManager(_:)), keyEquivalent: "m")
        manager.target = self
        menu.addItem(manager)
        let help = NSMenuItem(title: "使用说明与权限", action: #selector(showHelp(_:)), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
        let quit = NSMenuItem(title: "退出 BarPocket", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleNotchBlackout(_ sender: NSMenuItem) {
        recordInteraction()
        let enabled = !notchBlackoutController.isEnabled
        notchBlackoutController.setEnabled(enabled)
        prefs.set(enabled, forKey: notchBlackoutKey)
    }

    @objc private func menuToggle(_ sender: NSMenuItem) {
        recordInteraction()
        setCollapsed(!isCollapsed, remember: true)
    }

    @objc private func changeDelay(_ sender: NSMenuItem) {
        recordInteraction()
        prefs.set(sender.tag, forKey: autoCollapseKey)
        scheduleCollapseIfNeeded()
    }

    @objc private func changeLogin(_ sender: NSMenuItem) {
        recordInteraction()
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(title: "未能更改登录启动", message: "系统返回：\(error.localizedDescription)\n\n你也可以在「系统设置 → 通用 → 登录项」里检查。")
        }
    }

    @objc private func openManager(_ sender: NSMenuItem) {
        recordInteraction()
        if managerWindowController == nil {
            managerWindowController = MenuBarManagerWindowController(
                isPocketCollapsed: { [weak self] in self?.isCollapsed ?? false },
                setPocketCollapsed: { [weak self] collapsed in self?.setCollapsed(collapsed, remember: false) },
                dividerFrame: { [weak self] in self?.divider.button?.window?.frame },
                setOperationInProgress: { [weak self] active in
                    guard let self else { return }
                    self.managerOperationInProgress = active
                    if active { self.timer?.invalidate(); self.timer = nil }
                    else { self.scheduleCollapseIfNeeded() }
                }
            )
        }
        managerWindowController?.showAndRefresh()
    }

    @objc private func showHelp(_ sender: NSMenuItem) {
        recordInteraction()
        showAlert(title: "BarPocket · 使用说明", message: "1. 点击箭头展开或收起收纳区。\n2. 右键箭头 → 可开启「刘海隐身模式」，将刘海屏最顶部整行背景变为黑色，同时保留菜单栏图标和点击操作。\n3. 按住 ⌘ 拖动图标可调整其相对分隔线的位置。\n4. 打开菜单栏管理器，可扫描刘海遮挡和屏幕外图标。\n\n管理器需要你主动授予辅助功能权限，只读取菜单栏项目名称、所属应用和位置；点击按钮时才会尝试打开菜单或模拟 ⌘ 拖动。\n\n不申请屏幕录制、输入监控或管理员权限，不联网。macOS 和个别 App 可能不支持移动或 AXPress。")
    }

    @objc private func quit(_ sender: NSMenuItem) { NSApp.terminate(nil) }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}

func selfTest() -> Bool {
    let cases: [(input: [CGFloat], result: CGFloat)] = [
        ([1440], 2880), ([2880, 1920], 5760), ([200], 500), ([9000], 10000), ([], 2880)
    ]
    var passed = 0
    for (index, test) in cases.enumerated() {
        if PocketLayout.collapsedLength(screens: test.input) == test.result {
            passed += 1
        } else {
            fputs("FAILED CASE \(index)\n", stderr)
        }
    }
    guard passed == cases.count, PocketLayout.duration(-8) == 0 else { return false }
    print("PASS: layout self-tests (\(passed + 1) cases)")
    return true
}

if CommandLine.arguments.contains("--self-test") {
    exit(selfTest() ? 0 : 1)
} else {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let controller = PocketController()
    application.delegate = controller
    application.run()
}
