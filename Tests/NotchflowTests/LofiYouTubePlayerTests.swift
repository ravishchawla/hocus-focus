import Foundation
import Testing
import WebKit
@testable import Notchflow

struct LofiYouTubePlayerTests {
    @Test @MainActor
    func catalogUsesRequestedMainStreamByDefault() throws {
        let station = try #require([LofiStation].lofiGirlLiveStations.first)

        #expect(station.slug == LofiYouTubePlayer.defaultSlug)
        #expect(station.videoID == "rFZHOHl-L8A")
        #expect([LofiStation].lofiGirlLiveStations.count == 8)
        // Slugs are the persisted identity, so duplicates would silently merge
        // two stations into one saved selection.
        let slugs = [LofiStation].lofiGirlLiveStations.map(\.slug)
        #expect(Set(slugs).count == slugs.count)
        // Every catalog entry must stay re-resolvable.
        #expect([LofiStation].lofiGirlLiveStations.allSatisfy { !$0.matchPhrases.isEmpty })
    }

    @Test
    func parsesSupportedYouTubeLinkShapes() throws {
        let watch = try #require(URL(string: "https://www.youtube.com/watch?v=aaaaBBBB_-1"))
        let short = try #require(URL(string: "https://youtu.be/aaaaBBBB_-1"))
        let live = try #require(URL(string: "https://www.youtube.com/live/aaaaBBBB_-1"))
        let unrelated = try #require(URL(string: "https://example.com/watch?v=aaaaBBBB_-1"))

        #expect(LofiStation.from(youtubeURL: watch)?.videoID == "aaaaBBBB_-1")
        #expect(LofiStation.from(youtubeURL: short)?.videoID == "aaaaBBBB_-1")
        #expect(LofiStation.from(youtubeURL: live)?.videoID == "aaaaBBBB_-1")
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
    func pausingWhileLoadingCancelsDelayedInitialAutoplay() {
        let player = LofiYouTubePlayer()
        let webView = WKWebView()

        player.attach(to: webView)
        #expect(player.playbackState == .loading)

        player.pause()
        #expect(!player.autoplayOnceIfNeeded())

        player.detach(from: webView)
        player.attach(to: webView)
        #expect(!player.autoplayOnceIfNeeded())
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
