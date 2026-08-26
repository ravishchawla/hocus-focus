import Foundation

/// One broadcast currently live on the Lofi Girl channel.
struct LofiLiveStream: Equatable {
    let videoID: String
    let title: String
}

/// Supplies the channel's "Live" tab HTML. Injectable so the parser and the
/// matching rules can be tested without touching the network.
protocol LofiChannelSource: Sendable {
    func channelStreamsPage() async throws -> String
}

struct YouTubeChannelSource: LofiChannelSource {
    static let lofiGirlChannelID = "UCSJ4gkVC6NrvII8umztf0Ow"

    let channelID: String
    let session: URLSession

    init(channelID: String = YouTubeChannelSource.lofiGirlChannelID, session: URLSession? = nil) {
        self.channelID = channelID
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func channelStreamsPage() async throws -> String {
        let url = URL(string: "https://www.youtube.com/channel/\(channelID)/streams")!
        var request = URLRequest(url: url)
        // The desktop page is the one that carries ytInitialData, and liveness
        // is only detectable through the English "watching" viewer count, so
        // the language is pinned rather than inherited from the system.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return html
    }
}

/// Pulls the live broadcasts out of a YouTube channel page.
///
/// YouTube ships the tab's contents as a `ytInitialData` JSON blob rather than
/// as markup, and renders each entry through a `lockupViewModel`. Parsing this
/// is inherently coupled to a layout Google can change, so every failure path
/// returns an empty result and leaves the caller on its bundled IDs.
enum LofiStreamsPageParser {
    static func liveStreams(inPageSource source: String) -> [LofiLiveStream] {
        guard let json = ytInitialData(in: source),
              let root = try? JSONSerialization.jsonObject(with: Data(json.utf8))
        else { return [] }

        var lockups: [[String: Any]] = []
        collectLockups(in: root, into: &lockups)

        var streams: [LofiLiveStream] = []
        var seen = Set<String>()
        for lockup in lockups {
            guard let videoID = lockup["contentId"] as? String, !seen.contains(videoID),
                  let metadata = lockup["metadata"] as? [String: Any],
                  let lockupMetadata = metadata["lockupMetadataViewModel"] as? [String: Any],
                  let titleBox = lockupMetadata["title"] as? [String: Any],
                  let title = titleBox["content"] as? String,
                  isLive(lockupMetadata["metadata"])
            else { continue }
            seen.insert(videoID)
            streams.append(LofiLiveStream(videoID: videoID, title: title))
        }
        return streams
    }

    /// An ended broadcast shows a view count and a date; only a live one carries
    /// a "N watching" row.
    private static func isLive(_ metadata: Any?) -> Bool {
        guard let metadata else { return false }
        var strings: [String] = []
        collectStrings(in: metadata, into: &strings)
        return strings.contains { $0.lowercased().contains("watching") }
    }

    private static func ytInitialData(in source: String) -> String? {
        let markers = ["var ytInitialData = ", "window[\"ytInitialData\"] = "]
        for marker in markers {
            guard let markerRange = source.range(of: marker),
                  let start = source[markerRange.upperBound...].firstIndex(of: "{")
            else { continue }
            // YouTube escapes "<" as \u003c inside JSON strings, so the script
            // terminator cannot appear within the blob itself.
            guard let end = source.range(of: ";</script>", range: start..<source.endIndex) else { continue }
            return String(source[start..<end.lowerBound])
        }
        return nil
    }

    private static func collectLockups(in node: Any, into results: inout [[String: Any]]) {
        if let dictionary = node as? [String: Any] {
            if let lockup = dictionary["lockupViewModel"] as? [String: Any] {
                results.append(lockup)
            }
            for value in dictionary.values { collectLockups(in: value, into: &results) }
        } else if let array = node as? [Any] {
            for value in array { collectLockups(in: value, into: &results) }
        }
    }

    private static func collectStrings(in node: Any, into results: inout [String]) {
        if let string = node as? String {
            results.append(string)
        } else if let dictionary = node as? [String: Any] {
            for value in dictionary.values { collectStrings(in: value, into: &results) }
        } else if let array = node as? [Any] {
            for value in array { collectStrings(in: value, into: &results) }
        }
    }
}

enum LofiStreamMatcher {
    /// Maps station slug to the video ID of the broadcast now carrying that
    /// show. A station only matches when exactly one live title contains all of
    /// its phrases; zero or several candidates means the channel's naming has
    /// drifted, and guessing would be worse than keeping the bundled ID.
    static func resolveVideoIDs(
        for stations: [LofiStation],
        among liveStreams: [LofiLiveStream]
    ) -> [String: String] {
        var resolved: [String: String] = [:]
        for station in stations where !station.matchPhrases.isEmpty {
            let candidates = liveStreams.filter { stream in
                let title = stream.title.lowercased()
                return station.matchPhrases.allSatisfy { title.contains($0) }
            }
            guard candidates.count == 1 else { continue }
            resolved[station.slug] = candidates[0].videoID
        }
        return resolved
    }
}

/// Resolves the catalog's video IDs against whatever Lofi Girl is broadcasting
/// right now, so an ended stream repairs itself instead of shipping a fix.
struct LofiStreamDirectory: Sendable {
    let source: LofiChannelSource

    init(source: LofiChannelSource = YouTubeChannelSource()) {
        self.source = source
    }

    /// Never throws: an offline Mac, a changed layout or an unrecognisable
    /// title all degrade to "no update", leaving the bundled IDs in place.
    func resolveVideoIDs(for stations: [LofiStation]) async -> [String: String] {
        guard let html = try? await source.channelStreamsPage() else { return [:] }
        let live = LofiStreamsPageParser.liveStreams(inPageSource: html)
        guard !live.isEmpty else { return [:] }
        return LofiStreamMatcher.resolveVideoIDs(for: stations, among: live)
    }
}
