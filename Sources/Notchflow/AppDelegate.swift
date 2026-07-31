import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel.shared
    private var panelCoordinator: PanelCoordinator?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelCoordinator = PanelCoordinator(model: model)
        panelCoordinator?.show()
        configureStatusItem()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.persistTimerState()
        model.focusAudio.stop()
        model.music.stopPolling()
        model.lofiYouTube.shutdown()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "timer",
            accessibilityDescription: "Hocus Focus"
        )

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Hocus Focus", action: #selector(showNotch), keyEquivalent: "")
        menu.addItem(withTitle: "Start or Pause Timer", action: #selector(toggleTimer), keyEquivalent: " ")
        menu.addItem(withTitle: "Coffee Break", action: #selector(startCoffeeBreak), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Hocus Focus", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func showNotch() {
        model.expand(pin: true)
        panelCoordinator?.show()
    }

    @objc private func toggleTimer() {
        model.timer.toggle()
    }

    @objc private func startCoffeeBreak() {
        model.timer.startCoffeeBreak()
        model.selectedTab = .timer
        model.expand(pin: true)
    }

    @objc private func showSettings() {
        model.showSettings()
        panelCoordinator?.show()
    }

    @objc private func handleWake() {
        model.applicationDidWake()
        panelCoordinator?.reposition()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
