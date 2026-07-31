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

struct EqualizerView: View {
    var active: Bool
    var tint: Color = NotchflowTheme.orange
    var compact = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !active)) { context in
            let tick = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: compact ? 2 : 3) {
                ForEach(0..<4, id: \.self) { index in
                    let wave = active ? abs(sin(tick * (2.4 + Double(index) * 0.33) + Double(index))) : 0.16
                    Capsule()
                        .fill(tint.opacity(0.72 + Double(index) * 0.07))
                        .frame(
                            width: compact ? 2 : 3,
                            height: max(compact ? 3 : 4, (compact ? 12 : 18) * wave)
                        )
                }
            }
            .frame(height: compact ? 13 : 20)
        }
        .accessibilityHidden(true)
    }
}

struct PresetArtwork: View {
    let preset: FocusPreset
    var size: CGFloat = 48

    private var colors: [Color] {
        switch preset {
        case .calm:
            [Color(red: 0.78, green: 0.72, blue: 0.61), Color(red: 0.27, green: 0.34, blue: 0.36)]
        case .rain:
            [Color(red: 0.39, green: 0.51, blue: 0.60), Color(red: 0.09, green: 0.14, blue: 0.20)]
        case .study:
            [Color(red: 0.56, green: 0.36, blue: 0.23), Color(red: 0.10, green: 0.16, blue: 0.18)]
        case .jazz:
            [Color(red: 0.56, green: 0.20, blue: 0.13), Color(red: 0.08, green: 0.06, blue: 0.09)]
        case .cozy:
            [Color(red: 0.86, green: 0.48, blue: 0.24), Color(red: 0.20, green: 0.10, blue: 0.07)]
        case .loFi:
            [Color(red: 0.40, green: 0.31, blue: 0.48), Color(red: 0.11, green: 0.12, blue: 0.20)]
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: size * 0.72, height: size * 0.72)
                .blur(radius: size * 0.1)
                .offset(x: size * 0.22, y: -size * 0.22)
            Image(systemName: preset.systemImage)
                .font(.system(size: size * 0.30, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityLabel(preset.displayName)
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
