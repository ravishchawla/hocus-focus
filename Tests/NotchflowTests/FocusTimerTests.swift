import Foundation
import Testing
@testable import Notchflow

struct FocusTimerTests {
    @Test @MainActor
    func pausePreservesFractionalRemainingTime() {
        var now = Date(timeIntervalSince1970: 1_000)
        let timer = FocusTimer(focusSeconds: 60, now: { now })

        timer.start()
        now.addTimeInterval(3.4)
        timer.pause()

        #expect(timer.state == .paused)
        #expect(timer.remainingSeconds == 57)

        now.addTimeInterval(120)
        timer.refresh()
        #expect(timer.remainingSeconds == 57)

        timer.start()
        now.addTimeInterval(0.7)
        timer.refresh()

        #expect(timer.remainingSeconds == 56)
    }

    @Test @MainActor
    func focusCompletionEntersAndAutoStartsShortBreak() {
        var now = Date(timeIntervalSince1970: 2_000)
        let timer = FocusTimer(
            focusSeconds: 10,
            shortBreakSeconds: 5,
            now: { now }
        )
        var completedModes: [TimerMode] = []
        timer.onCompletion = { completedModes.append($0) }
        timer.autoStartBreaks = true

        timer.start()
        now.addTimeInterval(10)
        timer.refresh()

        #expect(timer.mode == .shortBreak)
        #expect(timer.state == .running)
        #expect(timer.remainingSeconds == 5)
        #expect(timer.totalSeconds == 5)
        #expect(timer.completedFocusSessions == 1)
        #expect(completedModes == [.focus])
    }

    @Test @MainActor
    func shortBreakCompletionReturnsToIdleFocus() {
        var now = Date(timeIntervalSince1970: 3_000)
        let timer = FocusTimer(
            focusSeconds: 10,
            shortBreakSeconds: 5,
            now: { now }
        )

        timer.skip()
        timer.start()
        now.addTimeInterval(5)
        timer.refresh()

        #expect(timer.mode == .focus)
        #expect(timer.state == .idle)
        #expect(timer.remainingSeconds == 10)
        #expect(timer.completedFocusSessions == 0)
    }

    @Test @MainActor
    func endingCoffeeBreakReturnsToFreshFocusSession() {
        var now = Date(timeIntervalSince1970: 4_000)
        let timer = FocusTimer(
            focusSeconds: 10,
            coffeeSeconds: 4,
            now: { now }
        )

        timer.startCoffeeBreak()
        now.addTimeInterval(1.25)
        timer.refresh()
        #expect(timer.mode == .coffee)
        #expect(timer.remainingSeconds == 3)

        timer.endCoffeeBreak()

        #expect(timer.mode == .focus)
        #expect(timer.state == .idle)
        #expect(timer.remainingSeconds == 10)
        #expect(timer.totalSeconds == 10)
    }

    @Test @MainActor
    func resetRestoresCurrentModeDuration() {
        var now = Date(timeIntervalSince1970: 5_000)
        let timer = FocusTimer(shortBreakSeconds: 8, now: { now })

        timer.skip()
        timer.start()
        now.addTimeInterval(3)
        timer.refresh()
        #expect(timer.remainingSeconds == 5)

        timer.reset()

        #expect(timer.mode == .shortBreak)
        #expect(timer.state == .idle)
        #expect(timer.remainingSeconds == 8)
        #expect(abs(timer.progress) < 0.000_001)
        #expect(timer.displayTime == "00:08")
    }

    @Test @MainActor
    func skipAdvancesWithoutCountingACompletedFocus() {
        var now = Date(timeIntervalSince1970: 6_000)
        let timer = FocusTimer(
            focusSeconds: 10,
            shortBreakSeconds: 5,
            now: { now }
        )

        timer.start()
        now.addTimeInterval(2)
        timer.skip()

        #expect(timer.mode == .shortBreak)
        #expect(timer.state == .idle)
        #expect(timer.remainingSeconds == 5)
        #expect(timer.completedFocusSessions == 0)

        timer.skip()

        #expect(timer.mode == .focus)
        #expect(timer.state == .idle)
        #expect(timer.remainingSeconds == 10)
    }

    @Test @MainActor
    func runningTimerRestoresFromItsWallClockDeadline() throws {
        var now = Date(timeIntervalSince1970: 7_000)
        let original = FocusTimer(
            focusSeconds: 10,
            shortBreakSeconds: 5,
            now: { now }
        )
        original.start()
        now.addTimeInterval(3.2)

        let data = try #require(original.encodedState())
        let restored = FocusTimer(now: { now })
        restored.restoreState(from: data)

        #expect(restored.mode == .focus)
        #expect(restored.state == .running)
        #expect(restored.remainingSeconds == 7)

        now.addTimeInterval(6.8)
        restored.refresh()
        #expect(restored.mode == .shortBreak)
        #expect(restored.state == .idle)
        #expect(restored.completedFocusSessions == 1)
    }
}
