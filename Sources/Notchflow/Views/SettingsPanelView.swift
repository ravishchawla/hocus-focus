import SwiftUI

struct SettingsPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var timer: FocusTimer

    @State private var focusMinutes = 25
    @State private var breakMinutes = 5
    @State private var coffeeMinutes = 5

    init(model: AppModel) {
        self.model = model
        timer = model.timer
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("Timer", systemImage: "timer")
                        .font(.system(size: 11, weight: .bold))
                    Spacer()
                    Button("Done") {
                        model.updateDurations(
                            focusMinutes: focusMinutes,
                            breakMinutes: breakMinutes,
                            coffeeMinutes: coffeeMinutes
                        )
                        model.surface = .main
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NotchflowTheme.orange)
                    .controlSize(.small)
                }

                durationRow("Focus", value: $focusMinutes, range: 1...120)
                durationRow("Short break", value: $breakMinutes, range: 1...30)
                durationRow("Coffee", value: $coffeeMinutes, range: 1...30)
            }
            .padding(12)
            .background(NotchflowTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Label("Behavior", systemImage: "switch.2")
                    .font(.system(size: 11, weight: .bold))
                Toggle("Auto-start breaks", isOn: $timer.autoStartBreaks)
                Toggle("Completion notifications", isOn: $model.notificationsEnabled)
                Toggle("Simulate notch", isOn: $model.simulateNotch)
                Toggle("Launch at login", isOn: $model.launchAtLogin)
            }
            .font(.system(size: 10, weight: .medium))
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(NotchflowTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Label("Focus audio", systemImage: "waveform")
                    .font(.system(size: 11, weight: .bold))
                HStack {
                    PresetArtwork(preset: model.focusAudio.activePreset, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.focusAudio.activePreset.displayName)
                            .font(.system(size: 10, weight: .semibold))
                        Text(model.focusAudio.activePreset.subtitle)
                            .font(.system(size: 8))
                            .foregroundStyle(NotchflowTheme.secondary)
                    }
                }
                Slider(
                    value: Binding(
                        get: { Double(model.focusAudio.volume) },
                        set: { model.focusAudio.volume = Float($0) }
                    ),
                    in: 0...1
                )
                .tint(NotchflowTheme.orange)
                Button("Choose a sound") { model.surface = .presets }
                    .buttonStyle(.link)
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(NotchflowTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 8)
        .onAppear {
            focusMinutes = max(1, timer.focusSeconds / 60)
            breakMinutes = max(1, timer.shortBreakSeconds / 60)
            coffeeMinutes = max(1, timer.coffeeSeconds / 60)
        }
    }

    private func durationRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(NotchflowTheme.secondary)
            Spacer()
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue) min")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
            }
            .labelsHidden()
            Text("\(value.wrappedValue)m")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .frame(width: 24, alignment: .trailing)
        }
    }
}
