import SwiftUI

struct TimerControlsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var timer: FocusTimer

    init(model: AppModel) {
        self.model = model
        timer = model.timer
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
