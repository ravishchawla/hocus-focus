import Foundation
import Testing
@testable import Notchflow

private struct FakeDisplay: DisplayCandidate {
    let displayIdentifier: String
    let displayFrame: CGRect
}

struct DisplayPreferenceTests {
    private let builtin = FakeDisplay(
        displayIdentifier: "builtin",
        displayFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
    )
    private let external = FakeDisplay(
        displayIdentifier: "display-1-2-3",
        displayFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1440)
    )

    @Test
    func followMouseTracksThePointerAcrossDisplays() {
        let screens = [builtin, external]

        let onBuiltin = DisplayResolver.screen(
            for: .followMouse,
            among: screens,
            mouseLocation: CGPoint(x: 100, y: 100),
            lastResolved: nil,
            systemDefault: builtin
        )
        let onExternal = DisplayResolver.screen(
            for: .followMouse,
            among: screens,
            mouseLocation: CGPoint(x: 2000, y: 700),
            lastResolved: nil,
            systemDefault: builtin
        )

        #expect(onBuiltin?.displayIdentifier == "builtin")
        #expect(onExternal?.displayIdentifier == "display-1-2-3")
    }

    @Test
    func pinnedDisplayIgnoresThePointer() {
        let screens = [builtin, external]

        for mouse in [CGPoint(x: 10, y: 10), CGPoint(x: 3000, y: 900)] {
            let resolved = DisplayResolver.screen(
                for: .pinned(displayID: "display-1-2-3"),
                among: screens,
                mouseLocation: mouse,
                lastResolved: builtin,
                systemDefault: builtin
            )
            #expect(resolved?.displayIdentifier == "display-1-2-3")
        }
    }

    @Test
    func pinnedDisplayFallsBackWhileUnpluggedAndReturnsOnReconnect() {
        let pinned = DisplayPreference.pinned(displayID: "display-1-2-3")

        let whileUnplugged = DisplayResolver.screen(
            for: pinned,
            among: [builtin],
            mouseLocation: CGPoint(x: 100, y: 100),
            lastResolved: nil,
            systemDefault: builtin
        )
        #expect(whileUnplugged?.displayIdentifier == "builtin")

        let afterReconnect = DisplayResolver.screen(
            for: pinned,
            among: [builtin, external],
            mouseLocation: CGPoint(x: 100, y: 100),
            lastResolved: builtin,
            systemDefault: builtin
        )
        #expect(afterReconnect?.displayIdentifier == "display-1-2-3")
    }

    @Test
    func followMouseDropsARememberedScreenThatWasUnplugged() {
        let offScreenMouse = CGPoint(x: 9_000, y: 9_000)

        let resolved = DisplayResolver.screen(
            for: .followMouse,
            among: [builtin],
            mouseLocation: offScreenMouse,
            lastResolved: external,
            systemDefault: builtin
        )

        #expect(resolved?.displayIdentifier == "builtin")
    }

    @Test
    func identicalMonitorsGetDistinctIdentifiers() {
        let twin = FakeDisplay(
            displayIdentifier: "display-1-2-3",
            displayFrame: CGRect(x: 2560, y: 0, width: 2560, height: 1440)
        )
        let screens = [builtin, external, twin]

        let identifiers = DisplayResolver.uniqueIdentifiers(for: screens)
        #expect(identifiers == ["builtin", "display-1-2-3", "display-1-2-3#2"])

        let resolved = DisplayResolver.screen(
            for: .pinned(displayID: "display-1-2-3#2"),
            among: screens,
            mouseLocation: CGPoint(x: 10, y: 10),
            lastResolved: nil,
            systemDefault: builtin
        )
        #expect(resolved?.displayFrame.minX == 2560)
    }

    @Test
    func preferenceRoundTripsThroughStorage() {
        #expect(DisplayPreference(storageValue: nil) == .followMouse)
        #expect(DisplayPreference(storageValue: "") == .followMouse)
        #expect(DisplayPreference(storageValue: "auto") == .followMouse)
        #expect(DisplayPreference.followMouse.storageValue == "auto")

        let pinned = DisplayPreference.pinned(displayID: "display-1-2-3")
        #expect(DisplayPreference(storageValue: pinned.storageValue) == pinned)
    }

    @Test @MainActor
    func selectedDisplaySurvivesRelaunch() throws {
        let suiteName = "NotchflowTests.Display.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(defaults: defaults)
        #expect(model.displayPreference == .followMouse)

        model.selectDisplay(.pinned(displayID: "display-1-2-3"), name: "LG HDR 4K")

        let relaunched = AppModel(defaults: defaults)
        #expect(relaunched.displayPreference == .pinned(displayID: "display-1-2-3"))
        #expect(relaunched.pinnedDisplayName == "LG HDR 4K")

        relaunched.selectDisplay(.followMouse, name: nil)
        let afterReset = AppModel(defaults: defaults)
        #expect(afterReset.displayPreference == .followMouse)
        #expect(afterReset.pinnedDisplayName == nil)
    }
}
