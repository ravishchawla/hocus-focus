import SwiftUI

enum NotchflowTheme {
    static let orange = Color(red: 0.98, green: 0.31, blue: 0.10)
    static let orangeSoft = Color(red: 1.0, green: 0.47, blue: 0.24)
    static let panel = Color(red: 0.055, green: 0.055, blue: 0.058)
    static let raised = Color.white.opacity(0.075)
    static let border = Color.white.opacity(0.09)
    static let secondary = Color.white.opacity(0.58)
}

struct NotchIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isActive = false
    var prominent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: prominent ? 17 : 13, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : (isActive ? Color.white : NotchflowTheme.secondary))
                .frame(width: prominent ? 45 : 34, height: prominent ? 45 : 34)
                .background {
                    Circle()
                        .fill(prominent ? NotchflowTheme.orange : NotchflowTheme.raised)
                        .overlay {
                            Circle().stroke(NotchflowTheme.border, lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct TrackArtworkView: View {
    let track: NowPlayingTrack
    var size: CGFloat = 54

    var body: some View {
        Group {
            if let artworkURL = track.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [NotchflowTheme.orangeSoft, Color(red: 0.23, green: 0.08, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

struct ModeBadge: View {
    let mode: TimerMode

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(mode == .focus ? NotchflowTheme.orangeSoft : Color.white.opacity(0.72))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(NotchflowTheme.raised, in: Capsule())
    }

    private var title: String {
        switch mode {
        case .focus: "Focus"
        case .shortBreak: "Short break"
        case .coffee: "Coffee break"
        }
    }

    private var icon: String {
        switch mode {
        case .focus: "scope"
        case .shortBreak: "sparkles"
        case .coffee: "cup.and.saucer.fill"
        }
    }
}
