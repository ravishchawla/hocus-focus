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

    @Test @MainActor
    func reopeningPausedPlayerDoesNotAutoplayAgain() {
        let player = LofiYouTubePlayer()
        let webView = WKWebView()

        player.attach(to: webView)
        #expect(player.autoplayOnceIfNeeded())
        player.receive(message: ["event": "state", "value": NSNumber(value: 1)])
        player.pause()
        #expect(player.playbackState == .paused)

        player.detach(from: webView)
        player.attach(to: webView)

        #expect(!player.autoplayOnceIfNeeded())
        #expect(player.playbackState == .paused)
    }

    @Test @MainActor
    func retainedPausedPlayerCanResumeWhileHidden() {
        let player = LofiYouTubePlayer()
        let webView = WKWebView()

        #expect(!player.toggleExistingPlayback())

        player.attach(to: webView)
        player.receive(message: ["event": "state", "value": NSNumber(value: 1)])
        player.pause()
        player.detach(from: webView)

        #expect(player.hasControllablePlaybackSession)
        #expect(player.toggleExistingPlayback())
        #expect(player.playbackState == .buffering)
        #expect(player.webView === webView)
        #expect(!player.isPlayerVisible)
    }

    @Test @MainActor
    func existingBufferingSessionCanBePaused() {
        let player = LofiYouTubePlayer()
        let webView = WKWebView()

        player.attach(to: webView)
        player.receive(message: ["event": "state", "value": NSNumber(value: 3)])

        #expect(player.hasControllablePlaybackSession)
        #expect(player.isActivelyPlaying)
        #expect(player.toggleExistingPlayback())
        #expect(player.playbackState == .paused)
    }

    @Test @MainActor
    func playerCommandsEndWithAWebKitBridgeableValue() {
        let command = "window.notchflowPlayer.play();"
        let script = LofiYouTubePlayer.bridgeableCommand(command)

        #expect(script.contains(command))
        #expect(script.contains("return true;"))
        #expect(script.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("})();"))
    }

    @Test @MainActor
    func compactPlayerUsesHalfTheOriginalAreaWithoutViolatingYouTubeMinimums() {
        let size = LofiYouTubePlayerView.displaySize
        let player = LofiYouTubePlayer()
        let originalArea: CGFloat = 400 * 225

        #expect(size.width * size.height == originalArea / 2)
        #expect(size.width >= 200)
        #expect(size.height >= 200)
        #expect(player.htmlDocument.contains("controls: 0"))
    }
}
