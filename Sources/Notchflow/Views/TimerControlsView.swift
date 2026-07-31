import SwiftUI

struct TimerControlsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var timer: FocusTimer
    @ObservedObject private var audio: FocusAudioEngine

    init(model: AppModel) {
        self.model = model
        timer = model.timer
        audio = model.focusAudio
    }

    var body: some View {
        if timer.mode == .coffee {
            CoffeeBreakView(model: model)
        } else {
            HStack(spacing: 16) {
                NotchIconButton(
                    systemName: "stop.fill",
                    accessibilityLabel: "Stop and reset timer",
                    action: timer.stop
                )

                NotchIconButton(
                    systemName: timer.isRunning ? "pause.fill" : "play.fill",
                    accessibilityLabel: timer.isRunning ? "Pause timer" : "Start timer",
                    prominent: true,
                    action: timer.toggle
                )

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        ModeBadge(mode: timer.mode)
                        Text(timer.displayTime)
                            .font(.system(size: 35, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .accessibilityLabel("\(timer.displayTime) remaining")
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [NotchflowTheme.orange, NotchflowTheme.orangeSoft],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(3, proxy.size.width * timer.progress))
                        }
                    }
                    .frame(height: 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    model.surface = .presets
                } label: {
                    HStack(spacing: 8) {
                        PresetArtwork(preset: audio.activePreset, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(audio.activePreset.displayName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                            HStack(spacing: 4) {
                                EqualizerView(active: audio.isPlaying, compact: true)
                                Text(audio.isPlaying ? "Playing" : "Focus sound")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(NotchflowTheme.secondary)
                            }
                        }
                    }
                    .padding(.trailing, 9)
                    .background(NotchflowTheme.raised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose focus sound")

                NotchIconButton(
                    systemName: "cup.and.saucer.fill",
                    accessibilityLabel: "Start coffee break",
                    action: timer.startCoffeeBreak
                )

                NotchIconButton(
                    systemName: "forward.end.fill",
                    accessibilityLabel: "Skip current interval",
                    action: timer.skip
                )
            }
            .padding(.horizontal, 10)
        }
    }
}

private struct CoffeeBreakView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var timer: FocusTimer

    init(model: AppModel) {
        self.model = model
        timer = model.timer
    }

    var body: some View {
        HStack(spacing: 16) {
            NotchIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "End coffee break",
                action: timer.endCoffeeBreak
            )

            ZStack {
                Circle()
                    .fill(NotchflowTheme.orange.opacity(0.16))
                    .frame(width: 68, height: 68)
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 29, weight: .medium))
                    .foregroundStyle(NotchflowTheme.orangeSoft)
                    .symbolEffect(.pulse, options: .repeating, isActive: timer.isRunning)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("COFFEE BREAK")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(NotchflowTheme.secondary)
                Text(timer.displayTime)
                    .font(.system(size: 36, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Spacer()

            Text("Breathe, stretch, and step away for a moment.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchflowTheme.secondary)
                .multilineTextAlignment(.trailing)
                .frame(width: 160)

            NotchIconButton(
                systemName: timer.isRunning ? "pause.fill" : "play.fill",
                accessibilityLabel: timer.isRunning ? "Pause coffee break" : "Start coffee break",
                prominent: true,
                action: timer.toggle
            )
        }
        .padding(.horizontal, 10)
    }
}

struct FocusPresetsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var audio: FocusAudioEngine

    init(model: AppModel) {
        self.model = model
        audio = model.focusAudio
    }

    var body: some View {
        HStack(spacing: 12) {
            NotchIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "Back to timer",
                action: { model.surface = .main }
            )

            ForEach(FocusPreset.allCases) { preset in
                Button {
                    audio.select(preset)
                    if !audio.isPlaying { audio.play() }
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottomTrailing) {
                            PresetArtwork(preset: preset, size: 66)
                            if audio.activePreset == preset && audio.isPlaying {
                                EqualizerView(active: true, tint: .white, compact: true)
                                    .padding(5)
                                    .background(.black.opacity(0.62), in: Circle())
                                    .offset(x: 5, y: 5)
                            }
                        }
                        Text(preset.displayName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(audio.activePreset == preset ? 1 : 0.64))
                    }
                }
                .buttonStyle(.plain)
                .help(preset.subtitle)
            }

            Spacer(minLength: 0)

            NotchIconButton(
                systemName: audio.isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: audio.isPlaying ? "Pause focus sound" : "Play focus sound",
                prominent: true,
                action: audio.toggle
            )
        }
        .padding(.horizontal, 10)
    }
}
