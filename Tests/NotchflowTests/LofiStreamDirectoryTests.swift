import Foundation
import Testing
@testable import Notchflow

/// Builds a page in the shape YouTube actually serves: a `ytInitialData` blob
/// of nested `lockupViewModel` entries, where the only signal that a broadcast
/// is live is a "N watching" metadata row.
private func channelPage(_ entries: [(videoID: String, title: String, live: Bool)]) -> String {
    let items = entries.map { entry in
        let status = entry.live ? "\(Int.random(in: 1...40))K watching" : "1.2M views"
        return """
        {"richItemRenderer":{"content":{"lockupViewModel":{
          "contentId":"\(entry.videoID)",
          "contentType":"LOCKUP_CONTENT_TYPE_VIDEO",
          "metadata":{"lockupMetadataViewModel":{
            "title":{"content":"\(entry.title)"},
            "metadata":{"contentMetadataViewModel":{"metadataRows":[
              {"metadataParts":[{"text":{"content":"\(status)"}}]}
            ]}}
          }}
        }}}}
        """
    }.joined(separator: ",")

    return """
    <!doctype html><html><body><script nonce="x">var ytInitialData = \
    {"contents":{"tabs":[{"tabRenderer":{"content":{"richGridRenderer":{"contents":[\(items)]}}}}]}};\
    </script></body></html>
    """
}

private struct StubChannel: LofiChannelSource {
    let page: String?
    func channelStreamsPage() async throws -> String {
        guard let page else { throw URLError(.notConnectedToInternet) }
        return page
    }
}

private let lofiGirlSample: [(videoID: String, title: String, live: Bool)] = [
    ("NEWhiphop11", "lofi hip hop radio 📚 beats to relax/study to", true),
    ("sleepEdit01", "lofi hip hop radio 💤 beats to sleep/chill to", true),
    ("NEWjazz1234", "jazz lofi radio 🎷 beats to chill/study to", true),
    ("NEWambient1", "synth ambient radio 🌌 deep space music to sleep to", true),
    ("deepsleep11", "24/7 deep sleep music 🌌 calm ambient to sleep & dream to", true),
    ("darkambien1", "dark ambient radio 🌃 music to escape/dream to", true),
    ("endedStrea1", "lofi hip hop radio - beats to relax/study to", false),
]

struct LofiStreamDirectoryTests {
    @Test
    func parserReadsLiveBroadcastsAndSkipsEndedOnes() {
        let streams = LofiStreamsPageParser.liveStreams(inPageSource: channelPage(lofiGirlSample))

        #expect(streams.count == 6)
        #expect(streams.contains(LofiLiveStream(videoID: "NEWhiphop11", title: "lofi hip hop radio 📚 beats to relax/study to")))
        // The ended rerun of the same show must not be offered.
        #expect(!streams.contains(where: { $0.videoID == "endedStrea1" }))
    }

    @Test
    func parserReturnsNothingForUnrecognisablePages() {
        #expect(LofiStreamsPageParser.liveStreams(inPageSource: "").isEmpty)
        #expect(LofiStreamsPageParser.liveStreams(inPageSource: "<html>no data here</html>").isEmpty)
        #expect(LofiStreamsPageParser.liveStreams(
            inPageSource: "<script>var ytInitialData = {not json;</script>"
        ).isEmpty)
    }

    @Test
    func matcherDistinguishesShowsThatShareWords() {
        let live = LofiStreamsPageParser.liveStreams(inPageSource: channelPage(lofiGirlSample))
        let resolved = LofiStreamMatcher.resolveVideoIDs(
            for: .lofiGirlLiveStations,
            among: live
        )

        // "lofi hip hop radio" alone also matches the sleep edition, and
        // "ambient" alone matches two other shows on the channel.
        #expect(resolved["lofi-hip-hop"] == "NEWhiphop11")
        #expect(resolved["synth-ambient"] == "NEWambient1")
        #expect(resolved["jazz-lofi"] == "NEWjazz1234")
        // Shows absent from this sample keep their bundled IDs.
        #expect(resolved["synthwave"] == nil)
    }

    @Test
    func ambiguousTitlesAreLeftAloneRatherThanGuessed() {
        let duplicated = channelPage([
            ("firstJazz11", "jazz lofi radio 🎷 beats to chill/study to", true),
            ("secondJazz1", "jazz lofi radio 🎷 beats to chill/study to", true),
        ])
        let resolved = LofiStreamMatcher.resolveVideoIDs(
            for: .lofiGirlLiveStations,
            among: LofiStreamsPageParser.liveStreams(inPageSource: duplicated)
        )

        #expect(resolved["jazz-lofi"] == nil)
    }

    @Test
    func directoryDegradesToNoUpdateWhenOffline() async {
        let directory = LofiStreamDirectory(source: StubChannel(page: nil))
        let resolved = await directory.resolveVideoIDs(for: .lofiGirlLiveStations)

        #expect(resolved.isEmpty)
    }

    @Test
    func directoryResolvesLiveIDsEndToEnd() async {
        let directory = LofiStreamDirectory(source: StubChannel(page: channelPage(lofiGirlSample)))
        let resolved = await directory.resolveVideoIDs(for: .lofiGirlLiveStations)

        #expect(resolved["lofi-hip-hop"] == "NEWhiphop11")
        #expect(resolved["jazz-lofi"] == "NEWjazz1234")
    }
}

/// Counts how many times the channel was actually consulted.
private final class CountingChannel: LofiChannelSource, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let page: String

    init(page: String) { self.page = page }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func channelStreamsPage() async throws -> String {
        lock.lock(); count += 1; lock.unlock()
        return page
    }
}

struct LofiStationResolutionTests {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "NotchflowTests.Resolve.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    @Test @MainActor
    func aRotatedBroadcastIsPickedUpAndKeepsTheSavedStation() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let channel = CountingChannel(page: channelPage(lofiGirlSample))
        let player = LofiYouTubePlayer(
            defaults: defaults,
            directory: LofiStreamDirectory(source: channel),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        let jazz = try #require(player.stations.first(where: { $0.slug == "jazz-lofi" }))
        player.select(jazz, autoplay: false)
        #expect(player.selectedStation.videoID == "E2vONfzoyRI")

        await player.refreshStationsNow()

        #expect(channel.callCount == 1)
        // Same station, new address.
        #expect(player.selectedStation.slug == "jazz-lofi")
        #expect(player.selectedStation.videoID == "NEWjazz1234")
    }

    @Test @MainActor
    func resolvedIDsSurviveRelaunchWithoutTouchingTheNetwork() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let launch = Date(timeIntervalSince1970: 1_000_000)
        let channel = CountingChannel(page: channelPage(lofiGirlSample))
        let first = LofiYouTubePlayer(
            defaults: defaults,
            directory: LofiStreamDirectory(source: channel),
            now: { launch }
        )
        await first.refreshStationsNow()
        #expect(channel.callCount == 1)

        // Relaunch an hour later: the cached resolution is still fresh.
        let restarted = LofiYouTubePlayer(
            defaults: defaults,
            directory: LofiStreamDirectory(source: channel),
            now: { launch.addingTimeInterval(3600) }
        )
        #expect(restarted.stations.first(where: { $0.slug == "lofi-hip-hop" })?.videoID == "NEWhiphop11")

        await restarted.refreshStationsNow()
        #expect(channel.callCount == 1)

        // A day later it is stale and the channel is consulted again.
        let later = LofiYouTubePlayer(
            defaults: defaults,
            directory: LofiStreamDirectory(source: channel),
            now: { launch.addingTimeInterval(24 * 3600) }
        )
        await later.refreshStationsNow()
        #expect(channel.callCount == 2)
    }

    @Test @MainActor
    func anOfflineLaunchStillPlaysTheBundledStations() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let player = LofiYouTubePlayer(
            defaults: defaults,
            directory: LofiStreamDirectory(source: StubChannel(page: nil))
        )
        await player.refreshStationsNow()

        #expect(player.stations.count == 8)
        #expect(player.selectedStation.videoID == "rFZHOHl-L8A")
        #expect(defaults.dictionary(forKey: "youtube.lofi.resolvedVideoIDs") == nil)
    }

    @Test @MainActor
    func playingAudioIsNotInterruptedByAResolution() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let player = LofiYouTubePlayer(
            defaults: defaults,
            directory: LofiStreamDirectory(source: StubChannel(page: channelPage(lofiGirlSample)))
        )
        player.receive(message: ["event": "state", "value": NSNumber(value: 1)])
        #expect(player.playbackState == .playing)

        await player.refreshStationsNow()

        // The catalog moved on, but a stream that is audibly alive is left be.
        #expect(player.stations.first(where: { $0.slug == "lofi-hip-hop" })?.videoID == "NEWhiphop11")
        #expect(player.playbackState == .playing)
    }

    @Test @MainActor
    func aSelectionSavedByVideoIDMigratesToItsSlug() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Written by a build that keyed selections on the video ID.
        defaults.set("E2vONfzoyRI", forKey: "youtube.lofi.selectedVideoID")

        let player = LofiYouTubePlayer(defaults: defaults)
        #expect(player.selectedStation.slug == "jazz-lofi")
    }

    @Test @MainActor
    func retiredBroadcastCodesTriggerARefresh() {
        #expect(LofiYouTubePlayer.indicatesRetiredBroadcast(100))
        #expect(LofiYouTubePlayer.indicatesRetiredBroadcast(101))
        #expect(LofiYouTubePlayer.indicatesRetiredBroadcast(150))
        #expect(!LofiYouTubePlayer.indicatesRetiredBroadcast(2))
        #expect(!LofiYouTubePlayer.indicatesRetiredBroadcast(nil))
    }
}

extension LofiStationResolutionTests {
    @Test @MainActor
    func aLaterPartialSweepKeepsEarlierResolvedAddresses() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let full = LofiYouTubePlayer(
            defaults: defaults,
            directory: LofiStreamDirectory(source: StubChannel(page: channelPage(lofiGirlSample)))
        )
        await full.refreshStationsNow()
        #expect(full.stations.first(where: { $0.slug == "jazz-lofi" })?.videoID == "NEWjazz1234")

        // YouTube renames the jazz show; only the hip hop station still matches.
        let narrowed = channelPage([
            ("NEWhiphop22", "lofi hip hop radio 📚 beats to relax/study to", true),
            ("NEWjazz9999", "jazz radio 🎷 now called something else", true),
        ])
        let second = LofiYouTubePlayer(
            defaults: defaults,
            directory: LofiStreamDirectory(source: StubChannel(page: narrowed))
        )
        await second.refreshStationsNow(force: true)

        #expect(second.stations.first(where: { $0.slug == "lofi-hip-hop" })?.videoID == "NEWhiphop22")
        // Jazz keeps the address that last worked instead of reverting.
        #expect(second.stations.first(where: { $0.slug == "jazz-lofi" })?.videoID == "NEWjazz1234")
    }
}
