import Foundation

/// A YouTube stream that can be played by the built-in Lofi Girl player.
///
/// YouTube video IDs are deliberately validated before they reach JavaScript.
/// This also makes it safe to support a custom YouTube URL in a future UI.
///
/// A station is identified by its `slug`, never by `videoID`. Lofi Girl ends a
/// broadcast and starts a fresh one every few months, so the video ID is
/// current-address rather than identity: it is resolved at runtime by
/// ``LofiStreamDirectory`` and the value stored here is only the last known
/// good fallback. Equality and hashing follow the slug so that a rotation
/// cannot invalidate a saved selection or an in-flight comparison.
struct LofiStation: Identifiable, Hashable, Codable {
    let slug: String
    let videoID: String
    let title: String
    let subtitle: String
    let systemImage: String
    /// Lowercased fragments that must *all* appear in a live broadcast's title
    /// for it to be considered this station. Empty for custom stations, which
    /// are never re-resolved.
    let matchPhrases: [String]

    var id: String { slug }

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    }

    var thumbnailURL: URL {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")!
    }

    init?(
        slug: String,
        videoID: String,
        title: String,
        subtitle: String = "Lofi Girl · Live on YouTube",
        systemImage: String = "radio",
        matchPhrases: [String] = []
    ) {
        guard Self.isValidVideoID(videoID), !slug.isEmpty else { return nil }
        self.slug = slug
        self.videoID = videoID
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.matchPhrases = matchPhrases.map { $0.lowercased() }
    }

    /// Returns the same station pointing at a newly resolved broadcast.
    func withVideoID(_ newVideoID: String) -> LofiStation {
        guard Self.isValidVideoID(newVideoID), newVideoID != videoID else { return self }
        return LofiStation(
            slug: slug,
            videoID: newVideoID,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            matchPhrases: matchPhrases
        ) ?? self
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
        // A hand-entered link names one exact broadcast, so it is its own
        // identity and is deliberately left out of live re-resolution.
        return LofiStation(slug: "custom-\(candidate)", videoID: candidate, title: title)
    }

    static func == (lhs: LofiStation, rhs: LofiStation) -> Bool {
        lhs.slug == rhs.slug
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(slug)
    }

    private static func isValidVideoID(_ videoID: String) -> Bool {
        videoID.count == 11 && videoID.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }
}

extension Array where Element == LofiStation {
    /// The official Lofi Girl live streams, with the video IDs that were current
    /// when this build shipped. ``LofiStreamDirectory`` replaces the IDs with
    /// whatever is live now; these remain the offline fallback.
    static let lofiGirlLiveStations: [LofiStation] = [
        LofiStation(
            slug: "lofi-hip-hop",
            videoID: "rFZHOHl-L8A",
            title: "Lofi hip hop radio",
            subtitle: "Beats to relax/study to",
            systemImage: "book.fill",
            // The channel also runs a "sleep/chill" edition of this show, so the
            // mood half of the title is required to tell them apart.
            matchPhrases: ["lofi hip hop radio", "relax/study"]
        )!,
        LofiStation(
            slug: "study-with-me",
            videoID: "qGohtGC5Rtk",
            title: "Study With Me",
            subtitle: "Pomodoro study sessions",
            systemImage: "timer",
            matchPhrases: ["study with me"]
        )!,
        LofiStation(
            slug: "synthwave",
            videoID: "4xDzrJKXOOY",
            title: "Synthwave radio",
            subtitle: "Beats to chill/game to",
            systemImage: "waveform",
            matchPhrases: ["synthwave radio"]
        )!,
        LofiStation(
            slug: "asian-lofi",
            videoID: "1Tl2FtV06qo",
            title: "Asian lofi radio",
            subtitle: "Beats to relax/study to",
            systemImage: "sparkles",
            matchPhrases: ["asian lofi radio"]
        )!,
        LofiStation(
            slug: "jazz-lofi",
            videoID: "E2vONfzoyRI",
            title: "Jazz lofi radio",
            subtitle: "Beats to chill/study to",
            systemImage: "music.quarternote.3",
            matchPhrases: ["jazz lofi radio"]
        )!,
        LofiStation(
            slug: "sad-lofi",
            videoID: "CwPCy1GLS38",
            title: "Sad lofi radio",
            subtitle: "Beats for rainy days",
            systemImage: "cloud.rain.fill",
            matchPhrases: ["sad lofi radio"]
        )!,
        LofiStation(
            slug: "relaxing-piano",
            videoID: "N0snMcR6aaA",
            title: "Relaxing piano radio",
            subtitle: "Calm music to focus to",
            systemImage: "pianokeys",
            matchPhrases: ["relaxing piano radio"]
        )!,
        LofiStation(
            slug: "synth-ambient",
            videoID: "GSfT7H87zq4",
            title: "Synth ambient radio",
            subtitle: "Deep-space music to sleep to",
            systemImage: "moon.stars.fill",
            // Plain "ambient" also matches the channel's deep-sleep and dark
            // ambient shows; the full show name is required.
            matchPhrases: ["synth ambient radio"]
        )!,
    ]
}
