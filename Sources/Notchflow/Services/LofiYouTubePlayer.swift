import Combine
import Foundation
import WebKit

enum LofiPlaybackState: Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case buffering
    case ended
    case failed

    var isPlaying: Bool { self == .playing }

    var isActivelyPlaying: Bool {
        self == .playing || self == .buffering
    }

    var hasControllableSession: Bool {
        switch self {
        case .playing, .paused, .buffering:
            true
        case .idle, .loading, .ready, .ended, .failed:
            false
        }
    }
}

/// Observable control surface for the visible YouTube player.
///
/// The controller retains one web view for the lifetime of the app. SwiftUI can
/// temporarily remove that view when the notch collapses or changes tabs while
/// the official YouTube embed and its audio continue uninterrupted.
@MainActor
final class LofiYouTubePlayer: ObservableObject {
    static let defaultSlug = "lofi-hip-hop"

    /// How long a resolved set of broadcast IDs is trusted before the channel
    /// is consulted again. Streams run for months, so this only needs to be
    /// short enough to repair a dead station within a session or two.
    static let resolutionLifetime: TimeInterval = 6 * 60 * 60

    @Published private(set) var stations: [LofiStation]
    @Published private(set) var selectedStation: LofiStation
    @Published private(set) var playbackState: LofiPlaybackState = .idle
    @Published private(set) var isPlayerVisible = false
    @Published private(set) var lastError: String?
    @Published private(set) var isMuted = false
    @Published private(set) var volume: Double

    private enum Keys {
        static let selectedVideoID = "youtube.lofi.selectedVideoID"
        static let selectedSlug = "youtube.lofi.selectedSlug"
        static let volume = "youtube.lofi.volume"
        static let resolvedVideoIDs = "youtube.lofi.resolvedVideoIDs"
        static let resolvedAt = "youtube.lofi.resolvedAt"
    }

    private let defaults: UserDefaults
    private let directory: LofiStreamDirectory
    private let now: () -> Date
    private var refreshTask: Task<Void, Never>?
    private var hasAttemptedInitialAutoplay = false
    private(set) var webView: WKWebView?

    init(
        stations: [LofiStation] = .lofiGirlLiveStations,
        defaults: UserDefaults = .standard,
        directory: LofiStreamDirectory = LofiStreamDirectory(),
        now: @escaping () -> Date = { Date() }
    ) {
        let uniqueStations = stations.reduce(into: [LofiStation]()) { result, station in
            guard !result.contains(where: { $0.slug == station.slug }) else { return }
            result.append(station)
        }
        let bundled = uniqueStations.isEmpty ? .lofiGirlLiveStations : uniqueStations
        // Broadcast IDs resolved on an earlier run are applied before anything
        // is shown, so a repaired station survives a relaunch and works offline.
        let cached = defaults.dictionary(forKey: Keys.resolvedVideoIDs) as? [String: String] ?? [:]
        let catalog = bundled.map { station in
            cached[station.slug].map { station.withVideoID($0) } ?? station
        }
        self.stations = catalog
        self.defaults = defaults
        self.directory = directory
        self.now = now

        // Selections used to be stored as a video ID. Migrate one to its slug
        // so an upgrade past a rotation does not silently reset the station.
        let persistedSlug = defaults.string(forKey: Keys.selectedSlug)
            ?? defaults.string(forKey: Keys.selectedVideoID).flatMap { videoID in
                bundled.first(where: { $0.videoID == videoID })?.slug
            }
        selectedStation = catalog.first(where: { $0.slug == persistedSlug })
            ?? catalog.first(where: { $0.slug == Self.defaultSlug })
            ?? catalog[0]

        if let persistedVolume = defaults.object(forKey: Keys.volume) as? NSNumber {
            volume = min(max(persistedVolume.doubleValue, 0), 1)
        } else {
            volume = 0.55
        }
    }

    var isPlaying: Bool { playbackState.isPlaying }

    /// True only after a station has reached an active or paused playback
    /// state and its retained web player is still available.
    var hasControllablePlaybackSession: Bool {
        webView != nil && playbackState.hasControllableSession
    }

    var hasRetainedPlayer: Bool { webView != nil }

    var isActivelyPlaying: Bool { playbackState.isActivelyPlaying }

    func togglePlayPause() {
        isActivelyPlaying ? pause() : play()
    }

    /// Controls a station that has already started, even while its retained
    /// web view is detached from the visible notch. This deliberately cannot
    /// create a new session, which keeps first-time playback user initiated on
    /// the Music page and prevents notch hover from triggering autoplay.
    @discardableResult
    func toggleExistingPlayback() -> Bool {
        guard hasControllablePlaybackSession else { return false }

        if isActivelyPlaying {
            pause()
        } else {
            resumeExistingPlayback()
        }
        return true
    }

    /// Starts playback automatically once during this player's lifetime.
    /// Subsequent view appearances preserve the user's current play/pause state.
    @discardableResult
    func autoplayOnceIfNeeded() -> Bool {
        guard !hasAttemptedInitialAutoplay, isPlayerVisible, webView != nil else {
            return false
        }
        play()
        return true
    }

    /// A new playback session starts from the expanded player. Once started,
    /// the retained web view can continue through notch and tab changes.
    func play() {
        guard isPlayerVisible, webView != nil else {
            lastError = "Open the Lofi Girl player before starting playback."
            return
        }
        hasAttemptedInitialAutoplay = true
        lastError = nil
        evaluate("window.notchflowPlayer.play();")
    }

    func pause() {
        if webView != nil {
            hasAttemptedInitialAutoplay = true
        }
        evaluate("window.notchflowPlayer.pause();", reportErrors: false)
        if playbackState == .playing || playbackState == .buffering {
            playbackState = .paused
        }
    }

    func select(_ station: LofiStation, autoplay: Bool = true) {
        guard stations.contains(station), station != selectedStation else { return }
        selectedStation = stations.first(where: { $0.slug == station.slug }) ?? station
        defaults.set(station.slug, forKey: Keys.selectedSlug)
        lastError = nil

        guard isPlayerVisible else {
            playbackState = .idle
            return
        }

        if autoplay { hasAttemptedInitialAutoplay = true }
        playbackState = .loading
        let videoID = Self.javaScriptString(selectedStation.videoID)
        evaluate("window.notchflowPlayer.load(\(videoID), \(autoplay));")
    }

    func selectNext(autoplay: Bool = true) {
        selectStation(offset: 1, autoplay: autoplay)
    }

    func selectPrevious(autoplay: Bool = true) {
        selectStation(offset: -1, autoplay: autoplay)
    }

    func setVolume(_ newVolume: Double) {
        volume = min(max(newVolume, 0), 1)
        defaults.set(volume, forKey: Keys.volume)
        isMuted = false
        evaluate("window.notchflowPlayer.setVolume(\(Int((volume * 100).rounded())));")
    }

    func toggleMute() {
        isMuted.toggle()
        evaluate(isMuted ? "window.notchflowPlayer.mute();" : "window.notchflowPlayer.unmute();")
    }

    /// Brings the catalog in line with what Lofi Girl is broadcasting now.
    ///
    /// Safe to call on every launch: it is a no-op while a previous resolution
    /// is still fresh, it never blocks the caller, and any failure leaves the
    /// existing IDs untouched.
    func refreshStations(force: Bool = false) {
        guard force || needsResolution else { return }
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            await self?.refreshStationsNow(force: force)
            self?.refreshTask = nil
        }
    }

    /// The awaitable half of ``refreshStations(force:)``.
    func refreshStationsNow(force: Bool = false) async {
        guard force || needsResolution else { return }
        let resolved = await directory.resolveVideoIDs(for: stations)
        guard !Task.isCancelled else { return }
        applyResolvedVideoIDs(resolved)
    }

    private var needsResolution: Bool {
        guard defaults.dictionary(forKey: Keys.resolvedVideoIDs) != nil else { return true }
        let resolvedAt = defaults.double(forKey: Keys.resolvedAt)
        guard resolvedAt > 0 else { return true }
        let age = now().timeIntervalSince1970 - resolvedAt
        // A clock that moved backwards should retry rather than trust the cache.
        return age < 0 || age >= Self.resolutionLifetime
    }

    func applyResolvedVideoIDs(_ resolved: [String: String]) {
        guard !resolved.isEmpty else { return }

        // Merge rather than replace. A later sweep that recognises fewer shows
        // must not discard a good address and drop that station back to the
        // build-time ID, which is by definition older.
        var cache = defaults.dictionary(forKey: Keys.resolvedVideoIDs) as? [String: String] ?? [:]
        cache.merge(resolved) { _, fresh in fresh }
        defaults.set(cache, forKey: Keys.resolvedVideoIDs)
        defaults.set(now().timeIntervalSince1970, forKey: Keys.resolvedAt)

        let previousVideoID = selectedStation.videoID
        stations = stations.map { station in
            resolved[station.slug].map { station.withVideoID($0) } ?? station
        }
        guard let current = stations.first(where: { $0.slug == selectedStation.slug }) else { return }
        selectedStation = current

        guard current.videoID != previousVideoID else { return }
        // Audio that is still running proves the old broadcast is alive, so it
        // is left alone; only a dead or idle player is moved to the new one.
        switch playbackState {
        case .playing, .buffering, .paused:
            return
        case .idle, .loading, .ready, .ended, .failed:
            lastError = nil
            guard isPlayerVisible else {
                playbackState = .idle
                return
            }
            playbackState = .loading
            let videoID = Self.javaScriptString(current.videoID)
            evaluate("window.notchflowPlayer.load(\(videoID), false);")
        }
    }

    /// Codes YouTube reports when a video ID no longer names a playable stream.
    static func indicatesRetiredBroadcast(_ code: Int?) -> Bool {
        guard let code else { return false }
        return [100, 101, 150].contains(code)
    }

    func shutdown() {
        refreshTask?.cancel()
        refreshTask = nil
        pause()
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: "notchflowYouTube"
        )
        webView?.loadHTMLString("", baseURL: nil)
        webView?.navigationDelegate = nil
        webView = nil
        isPlayerVisible = false
        playbackState = .idle
        hasAttemptedInitialAutoplay = false
    }
}

extension LofiYouTubePlayer {
    var htmlDocument: String {
        let videoID = Self.javaScriptString(selectedStation.videoID)
        let initialVolume = Int((volume * 100).rounded())

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
          <meta name="referrer" content="strict-origin-when-cross-origin">
          <style>
            html, body, #player { width: 100%; height: 100%; margin: 0; overflow: hidden; background: #050505; }
          </style>
        </head>
        <body>
          <div id="player"></div>
          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            (() => {
              let player = null;
              const waiting = [];
              const send = payload => window.webkit.messageHandlers.notchflowYouTube.postMessage(payload);
              const run = operation => player && typeof player[operation.name] === 'function'
                ? player[operation.name](...(operation.arguments || []))
                : waiting.push(operation);
              const drain = () => { while (waiting.length) run(waiting.shift()); };

              window.notchflowPlayer = {
                play: () => run({ name: 'playVideo' }),
                pause: () => run({ name: 'pauseVideo' }),
                load: (videoID, autoplay) => run({
                  name: autoplay ? 'loadVideoById' : 'cueVideoById',
                  arguments: [videoID]
                }),
                setVolume: value => run({ name: 'setVolume', arguments: [value] }),
                mute: () => run({ name: 'mute' }),
                unmute: () => run({ name: 'unMute' })
              };

              window.onYouTubeIframeAPIReady = () => {
                player = new YT.Player('player', {
                  width: '100%',
                  height: '100%',
                  videoId: \(videoID),
                  playerVars: {
                    autoplay: 0,
                    controls: 0,
                    enablejsapi: 1,
                    playsinline: 1,
                    origin: 'https://app.notchflow.localclone'
                  },
                  events: {
                    onReady: event => {
                      event.target.setVolume(\(initialVolume));
                      send({ event: 'ready', volume: event.target.getVolume() });
                      drain();
                    },
                    onStateChange: event => send({ event: 'state', value: event.data }),
                    onError: event => send({ event: 'error', value: event.data }),
                    onAutoplayBlocked: () => send({ event: 'autoplayBlocked' })
                  }
                });
              };
            })();
          </script>
        </body>
        </html>
        """
    }

    func attach(to webView: WKWebView) {
        let isFirstAttachment = self.webView == nil
        self.webView = webView
        isPlayerVisible = true
        if isFirstAttachment {
            playbackState = .loading
            lastError = nil
        }
    }

    func detach(from webView: WKWebView) {
        guard self.webView === webView else { return }
        isPlayerVisible = false
    }

    func receive(message: [String: Any]) {
        guard let event = message["event"] as? String else { return }

        switch event {
        case "ready":
            playbackState = .ready
            lastError = nil
            if let reportedVolume = message["volume"] as? NSNumber {
                volume = min(max(reportedVolume.doubleValue / 100, 0), 1)
            }
        case "state":
            guard let value = message["value"] as? NSNumber else { return }
            playbackState = switch value.intValue {
            case -1: .ready
            case 0: .ended
            case 1: .playing
            case 2: .paused
            case 3: .buffering
            case 5: .ready
            default: playbackState
            }
            lastError = nil
        case "error":
            let code = (message["value"] as? NSNumber)?.intValue
            playbackState = .failed
            lastError = Self.errorMessage(for: code)
            // A station that has gone dark is the one case worth spending a
            // network round trip on immediately.
            if Self.indicatesRetiredBroadcast(code) { refreshStations(force: true) }
        case "autoplayBlocked":
            playbackState = .ready
            lastError = "YouTube blocked autoplay. Press Play to start this station."
        case "navigationError":
            playbackState = .failed
            lastError = (message["message"] as? String)
                .map { "The YouTube player could not load: \($0)" }
                ?? "The YouTube player could not load."
        default:
            break
        }
    }

    /// WebKit tries to bridge the value of the final JavaScript expression
    /// back to Swift. YouTube player methods may return `undefined` or host
    /// objects, neither of which is a supported `evaluateJavaScript` result.
    /// Explicitly returning a Boolean keeps successful commands bridgeable;
    /// JavaScript exceptions still escape the wrapper and reach the callback.
    static func bridgeableCommand(_ javaScript: String) -> String {
        """
        (() => {
          \(javaScript)
          return true;
        })();
        """
    }
}

private extension LofiYouTubePlayer {
    func resumeExistingPlayback() {
        guard webView != nil else { return }
        hasAttemptedInitialAutoplay = true
        lastError = nil
        playbackState = .buffering
        evaluate(
            "window.notchflowPlayer.play();",
            playbackStateOnError: .paused
        )
    }

    func selectStation(offset: Int, autoplay: Bool) {
        guard let currentIndex = stations.firstIndex(of: selectedStation), !stations.isEmpty else { return }
        let nextIndex = (currentIndex + offset + stations.count) % stations.count
        select(stations[nextIndex], autoplay: autoplay)
    }

    func evaluate(
        _ javaScript: String,
        reportErrors: Bool = true,
        playbackStateOnError: LofiPlaybackState? = nil
    ) {
        guard let webView else { return }
        webView.evaluateJavaScript(Self.bridgeableCommand(javaScript)) { [weak self] _, error in
            guard reportErrors, let error else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lastError = "The YouTube player could not be controlled: \(error.localizedDescription)"
                if let playbackStateOnError, self.playbackState == .buffering {
                    self.playbackState = playbackStateOnError
                }
            }
        }
    }

    static func javaScriptString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded.replacingOccurrences(of: "/", with: "\\/")
    }

    static func errorMessage(for code: Int?) -> String {
        switch code {
        case 2:
            "YouTube rejected this video ID."
        case 5:
            "This stream could not be played in the embedded player."
        case 100:
            "This Lofi Girl stream is no longer available. Choose another station."
        case 101, 150:
            "The owner does not allow this stream to play inside apps."
        case 153:
            "YouTube could not verify the embedded player."
        default:
            "The YouTube stream could not be played."
        }
    }
}
