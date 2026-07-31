import Foundation
import Testing
@testable import Notchflow

struct MusicBridgeTests {
    @Test
    func productExposesOnlyAppleMusicAndLofiGirl() {
        #expect(MusicSource.allCases == [.appleMusic, .lofiGirl])
    }

    @Test @MainActor
    func appleMusicRecordPrefersLiveStreamTitleAndNormalizesMetadata() throws {
        let bridge = MusicBridge()
        let record = makeRecord([
            "ok",
            "playing",
            "true",
            "72",
            "Lofi radio station",
            "missing value",
            "  Live radio  ",
            "",
            "  Current song — Current artist  ",
        ])

        let snapshot = try bridge.parsePlaybackRecord(record)

        #expect(snapshot.track?.title == "Current song — Current artist")
        #expect(snapshot.track?.artist == "")
        #expect(snapshot.track?.album == "Live radio")
        #expect(snapshot.isPlaying)
        #expect(snapshot.shuffleEnabled)
        #expect(abs(snapshot.volume - 0.72) < 0.000_001)
    }

    @Test @MainActor
    func noTrackRecordStillReportsPlayerStateAndVolume() throws {
        let bridge = MusicBridge()
        let record = makeRecord(["no-track", "stopped", "false", "110"])

        let snapshot = try bridge.parsePlaybackRecord(record)

        #expect(snapshot.track == nil)
        #expect(!snapshot.isPlaying)
        #expect(snapshot.volume == 1)
    }

    @Test @MainActor
    func appleMusicTransportScriptsUseSupportedCommands() {
        let bridge = MusicBridge()

        #expect(bridge.controlScript(.togglePlayPause).contains("playpause"))
        #expect(bridge.controlScript(.previous).contains("previous track"))
        #expect(bridge.controlScript(.next).contains("next track"))
        #expect(bridge.controlScript(.setVolume(120)).contains("set sound volume to 100"))
    }

    private func makeRecord(_ values: [String]) -> NSAppleEventDescriptor {
        let descriptor = NSAppleEventDescriptor.list()
        for (offset, value) in values.enumerated() {
            descriptor.insert(NSAppleEventDescriptor(string: value), at: offset + 1)
        }
        return descriptor
    }
}
