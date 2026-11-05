import AppKit
import CoreGraphics

/// Draws an opaque black backing immediately below the system menu bar.
/// Mouse events pass through to the real menu bar and its status items.
final class NotchBlackoutController {
    private var windows: [NSWindow] = []
    private(set) var isEnabled = false

    var supportsCurrentDisplay: Bool {
        NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            rebuildWindows()
        } else {
            removeWindows()
        }
    }

    func refreshForDisplayChanges() {
        guard isEnabled else { return }
        rebuildWindows()
    }

    private func rebuildWindows() {
        removeWindows()

        for screen in NSScreen.screens where screen.safeAreaInsets.top > 0 {
            // Include the complete system menu-bar row. On the built-in Retina
            // display this is 34 pt; the notch safe-area itself is 33 pt.
            let menuBarHeight = max(
                screen.safeAreaInsets.top,
                screen.frame.maxY - screen.visibleFrame.maxY
            )
            guard menuBarHeight > 0 else { continue }

            let frame = NSRect(
                x: screen.frame.minX,
                y: screen.frame.maxY - menuBarHeight,
                width: screen.frame.width,
                height: menuBarHeight
            )

            // Use the non-screen initializer: AppKit's screen-aware initializer
            // and normal window levels can shift windows below the notch safe area.
            let window = NSWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.setFrame(frame, display: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.alphaValue = 1
            window.ignoresMouseEvents = true
            window.isMovable = false
            window.isMovableByWindowBackground = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

            // Level 23 is clamped below the notch safe area by macOS. At the
            // main-menu level the window can occupy the actual menu-bar row.
            // Keep it immediately BELOW Window Server's Menubar window so the
            // native menu titles and status items remain in front and clickable.
            let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
            window.level = NSWindow.Level(rawValue: menuBarLevel)
            let menuBarInfo = (CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
            ) as? [[String: Any]] ?? []).first { info in
                let owner = info[kCGWindowOwnerName as String] as? String
                let name = info[kCGWindowName as String] as? String
                let level = info[kCGWindowLayer as String] as? Int
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
                return owner == "Window Server"
                    && name == "Menubar"
                    && level == menuBarLevel
                    && abs((bounds["Width"] ?? 0) - screen.frame.width) < 1
            }
            if let menuBarWindowNumber = menuBarInfo?[kCGWindowNumber as String] as? Int {
                window.order(.below, relativeTo: menuBarWindowNumber)
            } else {
                window.orderBack(nil)
            }
            windows.append(window)
        }
    }

    private func removeWindows() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }
}
