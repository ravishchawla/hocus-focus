import AppKit
import Combine
import Foundation

struct NowPlayingTrack: Equatable {
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?

    static let empty = NowPlayingTrack(
        title: "",
        artist: "",
        album: "",
        artworkURL: nil
    )
}

/// Apple Music's native macOS playback bridge.
@MainActor
final class MusicBridge: ObservableObject {
    @Published private(set) var track = NowPlayingTrack.empty
    @Published private(set) var isPlaying = false
    @Published private(set) var shuffleEnabled = false
    @Published private(set) var volume = 0.5
    @Published private(set) var isAvailable = false
    @Published private(set) var lastError: String?

    private static let pollingInterval: TimeInterval = 1
    private static let bundleIdentifier = "com.apple.Music"
    private static let displayName = "Apple Music"
    private static let notRunningMessage = "Apple Music is not running."

    private var pollingTimer: Timer?
    private var commandRefreshTask: Task<Void, Never>?

    func startPolling() {
        guard pollingTimer == nil else { return }

        refresh()

        let timer = Timer(timeInterval: Self.pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func refresh() {
        guard isRunning else {
            setUnavailable(message: Self.notRunningMessage)
            return
        }

        do {
            apply(try query())
        } catch {
            setUnavailable(message: error.localizedDescription)
        }
    }

    func togglePlayPause() {
        perform(.togglePlayPause)
    }

    func pause() {
        perform(.pause)
    }

    func previous() {
        perform(.previous)
    }

    func next() {
        perform(.next)
    }

    func toggleShuffle() {
        perform(.toggleShuffle)
    }

    func setVolume(_ newVolume: Double) {
        let clampedVolume = min(max(newVolume, 0), 1)
        perform(.setVolume(Int((clampedVolume * 100).rounded())))
    }

    /// Opening Music is the only bridge operation that launches or foregrounds
    /// another application. Polling and controls require it to already run.
    func openProvider() {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.bundleIdentifier
        ) else {
            lastError = "Apple Music is not installed."
            return
        }

        if NSWorkspace.shared.open(applicationURL) {
            lastError = nil
        } else {
            lastError = "Apple Music could not be opened."
        }
    }
}

// Internal so Apple-event parsing and command construction can be tested
// without launching or automating the Music app.
extension MusicBridge {
    struct PlaybackSnapshot {
        let track: NowPlayingTrack?
        let isPlaying: Bool
        let shuffleEnabled: Bool
        let volume: Double
    }

    struct ScriptFailure: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    enum ControlCommand {
        case togglePlayPause
        case pause
        case previous
        case next
        case toggleShuffle
        case setVolume(Int)
    }

    func apply(_ snapshot: PlaybackSnapshot) {
        track = snapshot.track ?? .empty
        isPlaying = snapshot.isPlaying
        shuffleEnabled = snapshot.shuffleEnabled
        volume = min(max(snapshot.volume, 0), 1)
        isAvailable = true
        lastError = nil
    }

    func setUnavailable(message: String) {
        track = .empty
        isPlaying = false
        shuffleEnabled = false
        isAvailable = false
        lastError = message
    }

    var isRunning: Bool {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier
        ).contains(where: { !$0.isTerminated })
    }

    func query() throws -> PlaybackSnapshot {
        try parsePlaybackRecord(runAppleScript(Self.appleMusicQuery))
    }

    /// AppleScript returns an AppleEvent list rather than delimiter-joined text,
    /// so metadata remains intact even when it contains tabs or newlines.
    func parsePlaybackRecord(
        _ descriptor: NSAppleEventDescriptor
    ) throws -> PlaybackSnapshot {
        guard descriptor.numberOfItems >= 4 else {
            throw ScriptFailure(message: "Apple Music returned an invalid playback record.")
        }

        let status = descriptor.atIndex(1)?.stringValue ?? ""
        if status == "not-running" {
            throw ScriptFailure(message: Self.notRunningMessage)
        }

        guard status == "ok" || status == "no-track" else {
            throw ScriptFailure(message: "Apple Music returned an unknown playback state.")
        }

        let playerState = descriptor.atIndex(2)?.stringValue?.lowercased() ?? ""
        let shuffle = Self.parseBoolean(descriptor.atIndex(3)?.stringValue)
        let rawVolume = Double(descriptor.atIndex(4)?.stringValue ?? "") ?? 50

        let parsedTrack: NowPlayingTrack?
        if status == "ok", descriptor.numberOfItems >= 7 {
            let title = Self.normalizedMetadata(descriptor.atIndex(5)?.stringValue)
            let artist = Self.normalizedMetadata(descriptor.atIndex(6)?.stringValue)
            let album = Self.normalizedMetadata(descriptor.atIndex(7)?.stringValue)
            let artworkURLString = descriptor.numberOfItems >= 8
                ? descriptor.atIndex(8)?.stringValue
                : nil
            let streamTitle = descriptor.numberOfItems >= 9
                ? Self.normalizedMetadata(descriptor.atIndex(9)?.stringValue)
                : ""

            // Music exposes the actual programme/song name for live radio via
            // `current stream title`, while current track can remain the station.
            parsedTrack = NowPlayingTrack(
                title: streamTitle.isEmpty ? title : streamTitle,
                artist: artist,
                album: album,
                artworkURL: Self.validArtworkURL(artworkURLString)
            )
        } else {
            parsedTrack = nil
        }

        return PlaybackSnapshot(
            track: parsedTrack,
            isPlaying: playerState == "playing",
            shuffleEnabled: shuffle,
            volume: min(max(rawVolume / 100, 0), 1)
        )
    }

    static func parseBoolean(_ value: String?) -> Bool {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1":
            true
        default:
            false
        }
    }

    static func normalizedMetadata(_ value: String?) -> String {
        guard let value else { return "" }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.caseInsensitiveCompare("missing value") != .orderedSame else {
            return ""
        }
        return normalized
    }

    static func validArtworkURL(_ value: String?) -> URL? {
        guard let value,
              !value.isEmpty,
              value.caseInsensitiveCompare("missing value") != .orderedSame,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    func perform(_ command: ControlCommand) {
        guard isRunning else {
            setUnavailable(message: Self.notRunningMessage)
            return
        }

        do {
            let descriptor = try runAppleScript(controlScript(command))
            if descriptor.stringValue == "not-running" {
                setUnavailable(message: Self.notRunningMessage)
                return
            }

            lastError = nil
            refresh()
            scheduleCommandRefresh()
        } catch {
            setUnavailable(message: error.localizedDescription)
        }
    }

    /// Music updates AppleScript state asynchronously after transport commands.
    /// A follow-up refresh prevents stale playback state or metadata.
    func scheduleCommandRefresh() {
        commandRefreshTask?.cancel()
        commandRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func controlScript(_ command: ControlCommand) -> String {
        let commandSource: String
        switch command {
        case .togglePlayPause:
            commandSource = "playpause"
        case .pause:
            commandSource = "if player state is playing then pause"
        case .previous:
            commandSource = "previous track"
        case .next:
            commandSource = "next track"
        case .toggleShuffle:
            commandSource = "set shuffle enabled to not (shuffle enabled)"
        case .setVolume(let percent):
            commandSource = "set sound volume to \(min(max(percent, 0), 100))"
        }

        return """
        if application id "com.apple.Music" is not running then return "not-running"
        using terms from application "Music"
            tell application id "com.apple.Music"
                \(commandSource)
            end tell
        end using terms from
        return "ok"
        """
    }

    func runAppleScript(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw ScriptFailure(message: "The Apple Music command could not be created.")
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            throw ScriptFailure(message: friendlyScriptError(errorInfo))
        }

        return result
    }

    func friendlyScriptError(_ errorInfo: NSDictionary) -> String {
        let errorNumber = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue

        switch errorNumber {
        case -1743:
            return "Allow Hocus Focus to control Apple Music in System Settings → Privacy & Security → Automation."
        case -600:
            return Self.notRunningMessage
        case -1712:
            return "Apple Music did not respond."
        default:
            let message = errorInfo[NSAppleScript.errorBriefMessage] as? String
                ?? errorInfo[NSAppleScript.errorMessage] as? String
            return message.map { "Apple Music: \($0)" }
                ?? "Apple Music could not be controlled."
        }
    }

    static let appleMusicQuery = """
    if application id "com.apple.Music" is not running then return {"not-running", "", "false", "50"}
    using terms from application "Music"
        tell application id "com.apple.Music"
            set playbackState to player state as text
            set shuffleState to shuffle enabled as text
            set outputVolume to sound volume as text
            set trackName to ""
            set trackArtist to ""
            set trackAlbum to ""
            set streamTitle to ""

            try
                set trackName to name of current track as text
            end try
            try
                set trackArtist to artist of current track as text
            end try
            try
                set trackAlbum to album of current track as text
            end try
            try
                set streamTitleValue to current stream title
                if streamTitleValue is not missing value then set streamTitle to streamTitleValue as text
            end try

            if trackName is "" and streamTitle is "" then
                return {"no-track", playbackState, shuffleState, outputVolume}
            end if
            return {"ok", playbackState, shuffleState, outputVolume, trackName, trackArtist, trackAlbum, "", streamTitle}
        end tell
    end using terms from
    """
}
