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
}

/// Observable control surface for the visible YouTube player.
///
/// The controller retains one web view for the lifetime of the app. SwiftUI can
/// temporarily remove that view when the notch collapses or changes tabs while
/// the official YouTube embed and its audio continue uninterrupted.
@MainActor
final class LofiYouTubePlayer: ObservableObject {
    static let defaultVideoID = "X4VbdwhkE10"

    @Published private(set) var stations: [LofiStation]
    @Published private(set) var selectedStation: LofiStation
    @Published private(set) var playbackState: LofiPlaybackState = .idle
    @Published private(set) var isPlayerVisible = false
    @Published private(set) var lastError: String?
    @Published private(set) var isMuted = false
    @Published private(set) var volume: Double

    private enum Keys {
        static let selectedVideoID = "youtube.lofi.selectedVideoID"
        static let volume = "youtube.lofi.volume"
    }

    private let defaults: UserDefaults
    private(set) var webView: WKWebView?

    init(
        stations: [LofiStation] = .lofiGirlLiveStations,
        defaults: UserDefaults = .standard
    ) {
        let uniqueStations = stations.reduce(into: [LofiStation]()) { result, station in
            guard !result.contains(where: { $0.videoID == station.videoID }) else { return }
            result.append(station)
        }
        let catalog = uniqueStations.isEmpty ? .lofiGirlLiveStations : uniqueStations
        self.stations = catalog
        self.defaults = defaults

        let persistedID = defaults.string(forKey: Keys.selectedVideoID)
        selectedStation = catalog.first(where: { $0.videoID == persistedID })
            ?? catalog.first(where: { $0.videoID == Self.defaultVideoID })
            ?? catalog[0]

        if let persistedVolume = defaults.object(forKey: Keys.volume) as? NSNumber {
            volume = min(max(persistedVolume.doubleValue, 0), 1)
        } else {
            volume = 0.55
        }
    }

    var isPlaying: Bool { playbackState.isPlaying }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    /// A new playback session starts from the expanded player. Once started,
    /// the retained web view can continue through notch and tab changes.
    func play() {
        guard isPlayerVisible, webView != nil else {
            lastError = "Open the Lofi Girl player before starting playback."
            return
        }
        lastError = nil
        evaluate("window.notchflowPlayer.play();")
    }

    func pause() {
        evaluate("window.notchflowPlayer.pause();", reportErrors: false)
        if playbackState == .playing || playbackState == .buffering {
            playbackState = .paused
        }
    }

    func select(_ station: LofiStation, autoplay: Bool = true) {
        guard stations.contains(station), station != selectedStation else { return }
        selectedStation = station
        defaults.set(station.videoID, forKey: Keys.selectedVideoID)
        lastError = nil

        guard isPlayerVisible else {
            playbackState = .idle
            return
        }

        playbackState = .loading
        let videoID = Self.javaScriptString(station.videoID)
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

    func shutdown() {
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
                    controls: 1,
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
    func selectStation(offset: Int, autoplay: Bool) {
        guard let currentIndex = stations.firstIndex(of: selectedStation), !stations.isEmpty else { return }
        let nextIndex = (currentIndex + offset + stations.count) % stations.count
        select(stations[nextIndex], autoplay: autoplay)
    }

    func evaluate(_ javaScript: String, reportErrors: Bool = true) {
        guard let webView else { return }
        webView.evaluateJavaScript(Self.bridgeableCommand(javaScript)) { [weak self] _, error in
            guard reportErrors, let error else { return }
            Task { @MainActor [weak self] in
                self?.lastError = "The YouTube player could not be controlled: \(error.localizedDescription)"
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
