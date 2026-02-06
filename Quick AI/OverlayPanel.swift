import AppKit
import SwiftUI

final class OverlayPanel: NSPanel, NSWindowDelegate {
    private enum Layout {
        static let width: CGFloat = 600
        static let compactHeight: CGFloat = 80
        static let expandedHeight: CGFloat = 420
    }

    private enum DefaultsKey {
        static let originX = "overlay-origin-x"
        static let originY = "overlay-origin-y"
    }

    private let appState: AppState
    private var clickMonitor: Any?
    private var escMonitor: Any?

    init(appState: AppState) {
        self.appState = appState

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.compactHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        delegate = self
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow

        let overlayView = OverlayView(
            appState: appState,
            onDismiss: { [weak self] in
                self?.hideOverlay()
            },
            onResponseVisibilityChanged: { [weak self] isVisible in
                self?.setExpandedState(isVisible)
            }
        )

        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func showOverlay() {
        appState.reset()
        setExpandedState(false, animated: false)
        positionAtScreenBottom()

        var startFrame = frame
        startFrame.origin.y -= 8
        setFrame(startFrame, display: false)

        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        var endFrame = frame
        endFrame.origin.y += 8

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(endFrame, display: true)
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hideOverlay()
        }

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.hideOverlay()
                return nil // swallow the event
            }
            return event
        }
    }

    func hideOverlay() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }

        var endFrame = frame
        endFrame.origin.y -= 8

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.11
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
            animator().setFrame(endFrame, display: true)
        } completionHandler: {
            Task { @MainActor in
                self.orderOut(nil)
                self.setExpandedState(false, animated: false)
                self.appState.reset()
            }
        }
    }

    func windowDidMove(_ notification: Notification) {
        AppDefaults.shared.set(frame.origin.x, forKey: DefaultsKey.originX)
        AppDefaults.shared.set(frame.origin.y, forKey: DefaultsKey.originY)
    }

    private func setExpandedState(_ isExpanded: Bool, animated: Bool = true) {
        let targetHeight = isExpanded ? Layout.expandedHeight : Layout.compactHeight
        guard abs(frame.height - targetHeight) > .ulpOfOne else { return }

        var newFrame = frame
        newFrame.origin.y -= (targetHeight - frame.height)
        newFrame.size.height = targetHeight

        if animated, isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true)
        }
    }

    private func positionAtScreenBottom() {
        let fallbackScreen = NSScreen.main
        let fallbackFrame = fallbackScreen?.visibleFrame ?? .zero

        if let savedOrigin = savedOrigin() {
            let clamped = clamp(origin: savedOrigin, in: fallbackFrame)
            setFrameOrigin(clamped)
            return
        }

        let x = fallbackFrame.midX - frame.width / 2
        let y = fallbackFrame.minY + fallbackFrame.height * 0.25
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func savedOrigin() -> NSPoint? {
        let defaults = AppDefaults.shared
        guard defaults.object(forKey: DefaultsKey.originX) != nil,
              defaults.object(forKey: DefaultsKey.originY) != nil
        else {
            return nil
        }

        return NSPoint(
            x: defaults.double(forKey: DefaultsKey.originX),
            y: defaults.double(forKey: DefaultsKey.originY)
        )
    }

    private func clamp(origin: NSPoint, in visibleFrame: NSRect) -> NSPoint {
        let clampedX = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        let clampedY = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
        return NSPoint(x: clampedX, y: clampedY)
    }
}
