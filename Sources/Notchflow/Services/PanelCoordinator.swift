import AppKit
import Combine
import QuartzCore
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchHostingView: NSHostingView<NotchRootView> {
    var onHoverChange: ((Bool) -> Void)?
    var onPrimaryClick: ((CGPoint, CGRect) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onPrimaryClick?(point, bounds)
        super.mouseDown(with: event)
    }
}

@MainActor
final class PanelCoordinator {
    private let model: AppModel
    private let panel: NotchPanel
    private var cancellables = Set<AnyCancellable>()
    private var activeScreen: NSScreen?

    init(model: AppModel) {
        self.model = model
        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        let hostingView = NotchHostingView(rootView: NotchRootView(model: model))
        hostingView.onHoverChange = { [weak model] hovering in
            guard let model else { return }
            if hovering {
                model.cancelScheduledCollapse()
                if !model.isExpanded { model.expand() }
            } else {
                model.scheduleCollapse()
            }
        }
        hostingView.onPrimaryClick = { [weak model] point, bounds in
            guard let model else { return }
            // Leave the right-side pin/settings/collapse controls to their own
            // actions. A click anywhere else keeps the glance surface open.
            if point.x < bounds.width - 112, !model.isPinned {
                model.expand(pin: true)
            }
        }
        panel.contentView = hostingView

        let layoutUpdates: [AnyPublisher<Void, Never>] = [
            model.$isExpanded.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$simulateNotch.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$selectedTab.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$surface.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            model.$musicSource.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                .map { _ in () }
                .prepend(())
                .eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(layoutUpdates)
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.reposition(animated: true) }
        .store(in: &cancellables)
    }

    func show() {
        reposition(animated: false)
        panel.orderFrontRegardless()
    }

    func reposition() {
        reposition(animated: false)
    }

    private func reposition(animated: Bool) {
        guard let screen = targetScreen() else { return }
        activeScreen = screen

        let physicalNotch = screen.safeAreaInsets.top >= 8 && !model.simulateNotch
        // Match the camera housing exactly. Adding padding below the reported
        // safe area creates a visible black lip beneath the physical notch.
        model.compactHeight = physicalNotch ? screen.safeAreaInsets.top : 36
        // Reserve real, readable wings around the physical camera housing.
        // The collapsed surface prioritizes timer context on the left and the
        // remaining countdown on the right instead of decorative media icons.
        model.compactWidth = physicalNotch ? 356 : 220
        model.expandedWidth = min(720, screen.visibleFrame.width - 32)
        let showsLofiPlayer = model.selectedTab == .music
            && model.surface == .main
            && model.musicSource == .lofiGirl
        model.expandedHeight = showsLofiPlayer ? 310 : 204

        let width = model.isExpanded ? model.expandedWidth : model.compactWidth
        let height = model.isExpanded ? model.expandedHeight : model.compactHeight
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        let frame = NSRect(x: x, y: y, width: width, height: height)

        guard animated, panel.isVisible else {
            panel.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = model.isExpanded ? 0.28 : 0.22
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: model.isExpanded ? 0.2 : 0.4,
                0.8,
                0.2,
                1.0
            )
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? activeScreen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
