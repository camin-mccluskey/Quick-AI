import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayPanel: OverlayPanel?
    private var hotkeyManager: HotkeyManager?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayPanel = OverlayPanel(appState: appState)
        hotkeyManager = HotkeyManager { [weak self] in
            self?.toggleOverlay()
        }
    }

    func toggleOverlay() {
        guard let panel = overlayPanel else { return }
        if panel.isVisible {
            panel.hideOverlay()
        } else {
            panel.showOverlay()
        }
    }
}
