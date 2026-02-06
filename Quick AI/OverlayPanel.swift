import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    private enum Layout {
        static let width: CGFloat = 600
        static let compactHeight: CGFloat = 80
        static let expandedHeight: CGFloat = 420
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

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
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
        contentView = hostingView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func showOverlay() {
        appState.reset()
        setExpandedState(false, animated: false)
        positionAtScreenBottom()
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
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

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: {
            self.orderOut(nil)
            self.setExpandedState(false, animated: false)
            self.appState.reset()
        }
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
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.minY + screenFrame.height * 0.25
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
