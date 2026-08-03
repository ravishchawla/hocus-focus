import Foundation
import Testing
import WebKit
@testable import Notchflow

struct AppModelMediaRoutingTests {
    @Test @MainActor
    func timerTransportResumesOnlyTheSelectedRetainedLofiSession() throws {
        let suiteName = "NotchflowTests.TimerMedia.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(MusicSource.lofiGirl.rawValue, forKey: "music.source")

        let model = AppModel(defaults: defaults)
        let webView = WKWebView()

        #expect(!model.timerMediaUsesLofi)
        #expect(model.timerMediaSourceName == "Apple Music")

        model.lofiYouTube.attach(to: webView)
        model.lofiYouTube.receive(
            message: ["event": "state", "value": NSNumber(value: 2)]
        )
        model.lofiYouTube.detach(from: webView)

        #expect(model.timerMediaUsesLofi)
        #expect(model.timerMediaSourceName == "Lofi Girl")

        model.toggleTimerMediaPlayback()
        #expect(model.lofiYouTube.playbackState == .buffering)

        model.musicSource = .appleMusic
        #expect(!model.timerMediaUsesLofi)
        #expect(model.timerMediaSourceName == "Apple Music")
    }

    @Test @MainActor
    func onlyFocusCompletionPausesRetainedLofiPlayback() throws {
        let suiteName = "NotchflowTests.FocusCompletionMedia.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(MusicSource.lofiGirl.rawValue, forKey: "music.source")
        defaults.set(false, forKey: "app.notificationsEnabled")
        defaults.set(10, forKey: "timer.focusSeconds")
        defaults.set(5, forKey: "timer.breakSeconds")
        defaults.set(4, forKey: "timer.coffeeSeconds")

        var now = Date(timeIntervalSince1970: 10_000)
        let model = AppModel(defaults: defaults, now: { now })
        let webView = WKWebView()
        model.lofiYouTube.attach(to: webView)
        model.lofiYouTube.receive(
            message: ["event": "state", "value": NSNumber(value: 1)]
        )
        model.lofiYouTube.detach(from: webView)

        model.timer.start()
        now.addTimeInterval(10)
        model.timer.refresh()
        #expect(model.lofiYouTube.playbackState == .paused)

        model.lofiYouTube.receive(
            message: ["event": "state", "value": NSNumber(value: 1)]
        )
        model.timer.start()
        now.addTimeInterval(5)
        model.timer.refresh()
        #expect(model.lofiYouTube.playbackState == .playing)

        model.timer.startCoffeeBreak()
        now.addTimeInterval(4)
        model.timer.refresh()
        #expect(model.lofiYouTube.playbackState == .playing)
    }
}
