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
}
