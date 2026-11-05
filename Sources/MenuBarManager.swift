import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Accessibility inventory

enum MenuBarItemVisibility {
    case visible
    case behindNotch
    case offscreen

    var localizedTitle: String {
        switch self {
        case .visible: return tr("manager.visibility.visible")
        case .behindNotch: return tr("manager.visibility.behind_notch")
        case .offscreen: return tr("manager.visibility.offscreen")
        }
    }
}

struct MenuBarRecord: Identifiable {
    let id: String
    let pid: pid_t
    let appName: String
    let bundleIdentifier: String?
    let detail: String
    let frame: CGRect
    let visibility: MenuBarItemVisibility
    let appIcon: NSImage?
    let element: AXUIElement
}

enum MenuBarAccessibilityScanner {
    private struct AppSnapshot {
        let pid: pid_t
        let name: String
        let bundleIdentifier: String?
        let icon: NSImage?
    }

    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func scan(completion: @escaping ([MenuBarRecord]) -> Void) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && $0.bundleURL?.pathExtension == "app" }
            .map { AppSnapshot(pid: $0.processIdentifier, name: $0.localizedName ?? $0.bundleIdentifier ?? tr("manager.unknown_app"), bundleIdentifier: $0.bundleIdentifier, icon: $0.icon) }
        let notch = notchRange()
        let screenMaxX = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })?.frame.maxX
            ?? NSScreen.main?.frame.maxX ?? 0
        DispatchQueue.global(qos: .userInitiated).async {
            let result = scanNow(apps: apps, notch: notch, screenMaxX: screenMaxX)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func scanNow(apps: [AppSnapshot], notch: ClosedRange<CGFloat>?, screenMaxX: CGFloat) -> [MenuBarRecord] {
        guard AXIsProcessTrusted() else { return [] }
        var records: [MenuBarRecord] = []
        var seen = Set<String>()

        for app in apps {
            let pid = app.pid
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 0.18)

            guard let extras = copyAttribute(appElement, "AXExtrasMenuBar"),
                  CFGetTypeID(extras) == AXUIElementGetTypeID() else { continue }
            let extrasBar = extras as! AXUIElement
            guard let childrenValue = copyAttribute(extrasBar, kAXChildrenAttribute),
                  let children = childrenValue as? [AXUIElement] else { continue }

            for (index, child) in children.enumerated() {
                AXUIElementSetMessagingTimeout(child, 0.18)
                guard let position = pointValue(copyAttribute(child, kAXPositionAttribute)),
                      let size = sizeValue(copyAttribute(child, kAXSizeAttribute)),
                      size.width > 0, size.width < 400, size.height > 0, size.height < 100 else { continue }

                let identityHash = CFHash(child)
                let identity = identityHash == 0 ? String(index) : String(identityHash)
                let identifier = "\(pid)-\(identity)"
                guard seen.insert(identifier).inserted else { continue }
                let frame = CGRect(origin: position, size: size)
                let visibility: MenuBarItemVisibility
                if let notch, frame.maxX > notch.lowerBound, frame.minX < notch.upperBound {
                    visibility = .behindNotch
                } else if frame.minX < 0 || (screenMaxX > 0 && frame.maxX > screenMaxX) {
                    visibility = .offscreen
                } else {
                    visibility = .visible
                }

                let detail = (stringValue(copyAttribute(child, kAXDescriptionAttribute)))
                    ?? (stringValue(copyAttribute(child, kAXTitleAttribute)))
                    ?? (stringValue(copyAttribute(child, kAXIdentifierAttribute)))
                    ?? ""
                records.append(MenuBarRecord(
                    id: identifier,
                    pid: pid,
                    appName: app.name,
                    bundleIdentifier: app.bundleIdentifier,
                    detail: detail,
                    frame: frame,
                    visibility: visibility,
                    appIcon: app.icon,
                    element: child
                ))
            }
        }
        return records.sorted {
            if $0.frame.minX == $1.frame.minX { return $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
            return $0.frame.minX < $1.frame.minX
        }
    }

    static func press(_ item: MenuBarRecord) -> AXError {
        AXUIElementSetMessagingTimeout(item.element, 0.35)
        return AXUIElementPerformAction(item.element, kAXPressAction as CFString)
    }

    static func isPhysicallyVisible(_ frame: CGRect) -> Bool {
        guard frame.minX >= 0 else { return false }
        if let notch = notchRange(), frame.maxX > notch.lowerBound, frame.minX < notch.upperBound { return false }
        let maxX = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })?.frame.maxX
            ?? NSScreen.main?.frame.maxX ?? 0
        return maxX <= 0 || frame.maxX <= maxX
    }

    private static func notchRange() -> ClosedRange<CGFloat>? {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              left.maxX < right.minX else { return nil }
        return left.maxX...right.minX
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func pointValue(_ value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeValue(_ value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func stringValue(_ value: CFTypeRef?) -> String? {
        guard let value, let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}

// MARK: - Explicit, recoverable Command-drag

enum MenuBarItemMover {
    private static let dragInFlightKey = "menuBarPocketDragInFlight"

    static func recoverInterruptedDrag() {
        guard UserDefaults.standard.bool(forKey: dragInFlightKey) else { return }
        releaseMouseButton()
    }

    private static func releaseMouseButton() {
        let source = CGEventSource(stateID: .hidSystemState)
        let location = CGEvent(source: nil)?.location ?? .zero
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        UserDefaults.standard.removeObject(forKey: dragInFlightKey)
    }

    static func commandDrag(from: CGPoint, to: CGPoint) async {
        let originalCursor = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ type: CGEventType, _ point: CGPoint) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }

        post(.mouseMoved, from)
        try? await Task.sleep(nanoseconds: 80_000_000)
        UserDefaults.standard.set(true, forKey: dragInFlightKey)
        do {
            post(.leftMouseDown, from)
            defer {
                post(.leftMouseUp, to)
                UserDefaults.standard.removeObject(forKey: dragInFlightKey)
            }
            let steps = 14
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y))
                try? await Task.sleep(nanoseconds: 22_000_000)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if let originalCursor {
            post(.mouseMoved, originalCursor)
        }
    }
}

// MARK: - Manager window

final class MenuBarManagerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let isPocketCollapsed: () -> Bool
    private let setPocketCollapsed: (Bool) -> Void
    private let dividerFrame: () -> CGRect?
    private let setOperationInProgress: (Bool) -> Void

    private var allItems: [MenuBarRecord] = []
    private var filteredItems: [MenuBarRecord] = []
    private var scanInProgress = false
    private var moveInProgress = false

    private let titleLabel = NSTextField(labelWithString: tr("manager.title"))
    private let countLabel = NSTextField(labelWithString: "")
    private let permissionLabel = NSTextField(wrappingLabelWithString: tr("manager.permission.description"))
    private let permissionButton = NSButton(title: tr("manager.permission.enable"), target: nil, action: nil)
    private let refreshButton = NSButton(title: tr("manager.refresh"), target: nil, action: nil)
    private let filterControl = NSSegmentedControl(labels: [tr("manager.filter.all"), tr("manager.filter.behind_notch"), tr("manager.filter.offscreen"), tr("manager.filter.visible")], trackingMode: .selectOne, target: nil, action: nil)
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let openButton = NSButton(title: tr("manager.button.open"), target: nil, action: nil)
    private let pocketButton = NSButton(title: tr("manager.button.pocket"), target: nil, action: nil)
    private let restoreButton = NSButton(title: tr("manager.button.restore"), target: nil, action: nil)
    private let footerLabel = NSTextField(wrappingLabelWithString: tr("manager.footer"))
    private let permissionRow = NSStackView()

    init(
        isPocketCollapsed: @escaping () -> Bool,
        setPocketCollapsed: @escaping (Bool) -> Void,
        dividerFrame: @escaping () -> CGRect?,
        setOperationInProgress: @escaping (Bool) -> Void
    ) {
        self.isPocketCollapsed = isPocketCollapsed
        self.setPocketCollapsed = setPocketCollapsed
        self.dividerFrame = dividerFrame
        self.setOperationInProgress = setOperationInProgress
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 610),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = tr("manager.window_title")
        window.minSize = NSSize(width: 780, height: 500)
        window.center()
        super.init(window: window)
        configureWindow()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showAndRefresh() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    private func configureWindow() {
        guard let content = window?.contentView else { return }
        titleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        countLabel.textColor = .secondaryLabelColor
        countLabel.font = .systemFont(ofSize: 12)
        permissionLabel.font = .systemFont(ofSize: 12)
        permissionLabel.textColor = .secondaryLabelColor
        permissionLabel.maximumNumberOfLines = 3
        permissionButton.bezelStyle = .rounded
        permissionButton.target = self
        permissionButton.action = #selector(requestPermission)
        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refreshAction)
        filterControl.selectedSegment = 0
        filterControl.target = self
        filterControl.action = #selector(filterChanged)
        searchField.placeholderString = tr("manager.search.placeholder")
        searchField.target = self
        searchField.action = #selector(filterChanged)
        searchField.sendsSearchStringImmediately = true

        setupTable()
        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(openSelected)
        pocketButton.bezelStyle = .rounded
        pocketButton.target = self
        pocketButton.action = #selector(moveSelectedToPocket)
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreSelected)
        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.maximumNumberOfLines = 3

        permissionRow.orientation = .horizontal
        permissionRow.alignment = .centerY
        permissionRow.spacing = 12
        permissionRow.addArrangedSubview(permissionLabel)
        permissionRow.addArrangedSubview(permissionButton)

        let header = NSStackView(views: [titleLabel, countLabel, NSView(), refreshButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        let filters = NSStackView(views: [filterControl, searchField])
        filters.orientation = .horizontal
        filters.alignment = .centerY
        filters.spacing = 12
        searchField.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let actions = NSStackView(views: [openButton, pocketButton, restoreButton, NSView()])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        let footer = NSStackView(views: [actions, footerLabel])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 8

        let root = NSStackView(views: [header, permissionRow, filters, scrollView, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 13
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            header.widthAnchor.constraint(equalTo: root.widthAnchor),
            permissionRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            filters.widthAnchor.constraint(equalTo: root.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: root.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
        updateActionButtons()
        updatePermissionState()
    }

    private func setupTable() {
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 42
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.delegate = self
        tableView.dataSource = self
        let columns: [(String, String, CGFloat)] = [
            ("app", tr("manager.column.app"), 175),
            ("detail", tr("manager.column.detail"), 205),
            ("visibility", tr("manager.column.visibility"), 115),
            ("x", tr("manager.column.position"), 100)
        ]
        for (identifier, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
    }

    @objc private func refreshAction() { refresh() }

    private func refresh() {
        guard !scanInProgress, !moveInProgress else { return }
        guard MenuBarAccessibilityScanner.isTrusted() else {
            allItems = []
            applyFilter()
            updatePermissionState()
            countLabel.stringValue = tr("manager.status.waiting_permission")
            return
        }
        scanInProgress = true
        refreshButton.isEnabled = false
        countLabel.stringValue = tr("manager.status.scanning")
        updatePermissionState()
        MenuBarAccessibilityScanner.scan { [weak self] records in
            guard let self else { return }
            self.scanInProgress = false
            self.refreshButton.isEnabled = true
            self.allItems = records
            self.applyFilter()
            let hidden = records.filter { $0.visibility != .visible }.count
            let notch = records.filter { $0.visibility == .behindNotch }.count
            self.countLabel.stringValue = trf("manager.status.count", records.count, hidden, notch)
        }
    }

    private func updatePermissionState() {
        let trusted = MenuBarAccessibilityScanner.isTrusted()
        permissionRow.isHidden = trusted
        refreshButton.isEnabled = trusted && !scanInProgress && !moveInProgress
        if !trusted {
            countLabel.stringValue = tr("manager.status.permission_required")
        }
    }

    @objc private func requestPermission() {
        MenuBarAccessibilityScanner.requestAccess()
        permissionLabel.stringValue = tr("manager.permission.instructions")
        countLabel.stringValue = tr("manager.status.waiting_system")
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func filterChanged() { applyFilter() }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        filteredItems = allItems.filter { item in
            let filterMatches: Bool
            switch filterControl.selectedSegment {
            case 1: filterMatches = item.visibility == .behindNotch
            case 2: filterMatches = item.visibility == .offscreen
            case 3: filterMatches = item.visibility == .visible
            default: filterMatches = true
            }
            let textMatches = query.isEmpty || item.appName.lowercased().contains(query)
                || item.detail.lowercased().contains(query)
                || (item.bundleIdentifier?.lowercased().contains(query) ?? false)
            return filterMatches && textMatches
        }
        tableView.reloadData()
        if !filteredItems.isEmpty { tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        updateActionButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filteredItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filteredItems.count, let column = tableColumn else { return nil }
        let item = filteredItems[row]
        let cell = NSTableCellView()
        let label: NSTextField
        if column.identifier.rawValue == "app" {
            let imageView = NSImageView()
            imageView.image = item.appIcon
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(imageView)
            label = NSTextField(labelWithString: item.appName)
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 5),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 24),
                imageView.heightAnchor.constraint(equalToConstant: 24),
                label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        } else {
            let text: String
            switch column.identifier.rawValue {
            case "detail": text = item.detail.isEmpty ? tr("manager.fallback_item") : item.detail
            case "visibility": text = item.visibility.localizedTitle
            case "x": text = String(format: "x = %.0f", item.frame.minX)
            default: text = ""
            }
            label = NSTextField(labelWithString: text)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            if column.identifier.rawValue == "visibility" && item.visibility != .visible {
                label.textColor = .systemOrange
            } else {
                label.textColor = .labelColor
            }
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField = label
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateActionButtons() }

    private var selectedItem: MenuBarRecord? {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredItems.count else { return nil }
        return filteredItems[row]
    }

    private func updateActionButtons() {
        let item = selectedItem
        let separator = dividerFrame()
        let isLeftOfDivider = item.map { record in
            guard let separator else { return false }
            return record.frame.maxX <= separator.minX
        } ?? false
        openButton.isEnabled = item != nil && !moveInProgress && MenuBarAccessibilityScanner.isTrusted()
        pocketButton.isEnabled = item?.visibility == .visible && !isLeftOfDivider && !moveInProgress
        restoreButton.isEnabled = item != nil && item?.visibility != .behindNotch
            && (item?.visibility == .offscreen || isLeftOfDivider) && !moveInProgress
        refreshButton.isEnabled = MenuBarAccessibilityScanner.isTrusted() && !scanInProgress && !moveInProgress
    }

    @objc private func openSelected() {
        guard let item = selectedItem else { return }
        let result = MenuBarAccessibilityScanner.press(item)
        if result != .success {
            showMessage(tr("manager.alert.open_failed.title"), trf("manager.alert.open_failed.message", item.appName as NSString, result.rawValue))
        }
    }

    @objc private func moveSelectedToPocket() { moveSelected(toPocket: true) }
    @objc private func restoreSelected() { moveSelected(toPocket: false) }

    private func moveSelected(toPocket: Bool) {
        guard let selected = selectedItem, !moveInProgress else { return }
        guard MenuBarAccessibilityScanner.isTrusted() else { updatePermissionState(); return }
        moveInProgress = true
        updateActionButtons()
        setOperationInProgress(true)
        let previousCollapsed = isPocketCollapsed()
        setPocketCollapsed(false) // temporarily reveal items managed by our divider

        // Restoring a hidden item may need a little more room. Keep our toggle
        // visible so the drop target remains a stable point beside the divider.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            MenuBarAccessibilityScanner.scan { [weak self] refreshed in
                guard let self else { return }
                guard let fresh = refreshed.first(where: { $0.id == selected.id }) else {
                    self.finishMove(previousCollapsed: previousCollapsed)
                    self.showMessage(tr("manager.alert.item_changed.title"), tr("manager.alert.item_changed.message"))
                    return
                }
                guard fresh.visibility == .visible,
                      MenuBarAccessibilityScanner.isPhysicallyVisible(fresh.frame) else {
                    self.finishMove(previousCollapsed: previousCollapsed)
                    self.showMessage(tr("manager.alert.cannot_drag.title"), tr("manager.alert.cannot_drag.message"))
                    return
                }
                guard let separator = self.dividerFrame(), separator.width < 200 else {
                    self.finishMove(previousCollapsed: previousCollapsed)
                    self.showMessage(tr("manager.alert.divider_unavailable.title"), tr("manager.alert.divider_unavailable.message"))
                    return
                }

                let isLeftOfDivider = fresh.frame.maxX <= separator.minX
                let isRightOfDivider = fresh.frame.minX >= separator.maxX
                if toPocket && isLeftOfDivider {
                    self.finishMove(previousCollapsed: previousCollapsed)
                    self.showMessage(tr("manager.alert.already_in_pocket.title"), tr("manager.alert.already_in_pocket.message"))
                    return
                }
                if !toPocket && isRightOfDivider {
                    self.finishMove(previousCollapsed: previousCollapsed)
                    self.showMessage(tr("manager.alert.already_in_persistent.title"), tr("manager.alert.already_in_persistent.message"))
                    return
                }

                let targetX = toPocket ? separator.minX - 24 : separator.maxX + 10
                let screenMaxX = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })?.frame.maxX
                    ?? NSScreen.main?.frame.maxX ?? 0
                guard targetX > 0, screenMaxX <= 0 || targetX < screenMaxX - 2 else {
                    self.finishMove(previousCollapsed: previousCollapsed)
                    self.showMessage(tr("manager.alert.no_space.title"), tr("manager.alert.no_space.message"))
                    return
                }

                let from = CGPoint(x: fresh.frame.midX, y: fresh.frame.midY)
                let to = CGPoint(x: targetX, y: fresh.frame.midY)
                Task { @MainActor in
                    await MenuBarItemMover.commandDrag(from: from, to: to)
                    self.finishMove(previousCollapsed: previousCollapsed)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.refresh() }
                }
            }
        }
    }

    private func finishMove(previousCollapsed: Bool) {
        setPocketCollapsed(previousCollapsed)
        setOperationInProgress(false)
        moveInProgress = false
        updateActionButtons()
        updatePermissionState()
    }

    private func showMessage(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: tr("alert.dismiss"))
        alert.beginSheetModal(for: window!)
    }
}
