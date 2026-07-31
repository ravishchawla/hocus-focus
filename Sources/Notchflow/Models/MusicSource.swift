import Foundation

enum MusicSource: String, CaseIterable, Identifiable, Codable {
    case appleMusic
    case lofiGirl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMusic:
            "Apple Music"
        case .lofiGirl:
            "Lofi Girl"
        }
    }

    var systemImage: String {
        switch self {
        case .appleMusic:
            "music.note"
        case .lofiGirl:
            "play.rectangle.fill"
        }
    }
}
