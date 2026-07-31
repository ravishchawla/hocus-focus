import Foundation
import Testing
import WebKit
@testable import Notchflow

struct LofiYouTubePlayerTests {
    @Test @MainActor
    func catalogUsesRequestedMainStreamByDefault() throws {
        let station = try #require([LofiStation].lofiGirlLiveStations.first)

        #expect(station.videoID == LofiYouTubePlayer.defaultVideoID)
        #expect(station.videoID == "X4VbdwhkE10")
        #expect([LofiStation].lofiGirlLiveStations.count == 8)
    }

    @Test
    func parsesSupportedYouTubeLinkShapes() throws {
        let watch = try #require(URL(string: "https://www.youtube.com/watch?v=X4VbdwhkE10"))
        let short = try #require(URL(string: "https://youtu.be/X4VbdwhkE10"))
        let live = try #require(URL(string: "https://www.youtube.com/live/X4VbdwhkE10"))
        let unrelated = try #require(URL(string: "https://example.com/watch?v=X4VbdwhkE10"))

        #expect(LofiStation.from(youtubeURL: watch)?.videoID == "X4VbdwhkE10")
        #expect(LofiStation.from(youtubeURL: short)?.videoID == "X4VbdwhkE10")
        #expect(LofiStation.from(youtubeURL: live)?.videoID == "X4VbdwhkE10")
        #expect(LofiStation.from(youtubeURL: unrelated) == nil)
    }

    @Test @MainActor
    func selectionAndVolumePersistLocally() throws {
        let suiteName = "NotchflowTests.Lofi.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstPlayer = LofiYouTubePlayer(defaults: defaults)
        let alternate = try #require(firstPlayer.stations.dropFirst().first)
        firstPlayer.select(alternate)
        firstPlayer.setVolume(0.73)

        let restored = LofiYouTubePlayer(defaults: defaults)
        #expect(restored.selectedStation == alternate)
        #expect(abs(restored.volume - 0.73) < 0.000_001)
    }

    @Test @MainActor
    func hidingPlayerRetainsPlaybackUntilShutdown() {
        let player = LofiYouTubePlayer()
        let webView = WKWebView()

        player.attach(to: webView)
        player.receive(message: ["event": "state", "value": NSNumber(value: 1)])
        player.detach(from: webView)

        #expect(!player.isPlayerVisible)
        #expect(player.isPlaying)
        #expect(player.webView === webView)

        player.shutdown()
        #expect(player.webView == nil)
        #expect(player.playbackState == .idle)
    }
}
