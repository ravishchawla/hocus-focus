import Foundation

/// A YouTube stream that can be played by the built-in Lofi Girl player.
///
/// YouTube video IDs are deliberately validated before they reach JavaScript.
/// This also makes it safe to support a custom YouTube URL in a future UI.
struct LofiStation: Identifiable, Hashable, Codable {
    let videoID: String
    let title: String
    let subtitle: String
    let systemImage: String

    var id: String { videoID }

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    }

    var thumbnailURL: URL {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")!
    }

    init?(
        videoID: String,
        title: String,
        subtitle: String = "Lofi Girl · Live on YouTube",
        systemImage: String = "radio"
    ) {
        guard Self.isValidVideoID(videoID) else { return nil }
        self.videoID = videoID
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    /// Extracts the video ID from regular, shortened, live, embed, and Shorts
    /// YouTube links. The returned station can be appended to a custom catalog.
    static func from(
        youtubeURL url: URL,
        title: String = "Custom YouTube station"
    ) -> LofiStation? {
        guard let host = url.host?.lowercased() else { return nil }

        let candidate: String?
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            candidate = url.pathComponents.dropFirst().first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if let queryID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "v" })?
                .value {
                candidate = queryID
            } else {
                let components = url.pathComponents.filter { $0 != "/" }
                candidate = components.count >= 2 && ["embed", "live", "shorts"].contains(components[0])
                    ? components[1]
                    : nil
            }
        } else {
            candidate = nil
        }

        guard let candidate else { return nil }
        return LofiStation(videoID: candidate, title: title)
    }

    private static func isValidVideoID(_ videoID: String) -> Bool {
        videoID.count == 11 && videoID.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }
}

extension Array where Element == LofiStation {
    /// The current official Lofi Girl live streams. YouTube occasionally rotates
    /// livestream IDs, so callers can inject a replacement catalog at init time.
    static let lofiGirlLiveStations: [LofiStation] = [
        LofiStation(
            videoID: "X4VbdwhkE10",
            title: "Lofi hip hop radio",
            subtitle: "Beats to relax/study to",
            systemImage: "book.fill"
        )!,
        LofiStation(
            videoID: "qGohtGC5Rtk",
            title: "Study With Me",
            subtitle: "Pomodoro study sessions",
            systemImage: "timer"
        )!,
        LofiStation(
            videoID: "4xDzrJKXOOY",
            title: "Synthwave radio",
            subtitle: "Beats to chill/game to",
            systemImage: "waveform"
        )!,
        LofiStation(
            videoID: "1Tl2FtV06qo",
            title: "Asian lofi radio",
            subtitle: "Beats to relax/study to",
            systemImage: "sparkles"
        )!,
        LofiStation(
            videoID: "E2vONfzoyRI",
            title: "Jazz lofi radio",
            subtitle: "Beats to chill/study to",
            systemImage: "music.quarternote.3"
        )!,
        LofiStation(
            videoID: "CwPCy1GLS38",
            title: "Sad lofi radio",
            subtitle: "Beats for rainy days",
            systemImage: "cloud.rain.fill"
        )!,
        LofiStation(
            videoID: "N0snMcR6aaA",
            title: "Relaxing piano radio",
            subtitle: "Calm music to focus to",
            systemImage: "pianokeys"
        )!,
        LofiStation(
            videoID: "GSfT7H87zq4",
            title: "Synth ambient radio",
            subtitle: "Deep-space music to sleep to",
            systemImage: "moon.stars.fill"
        )!,
    ]
}
