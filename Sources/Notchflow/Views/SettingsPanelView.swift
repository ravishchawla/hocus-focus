import AppKit
import SwiftUI

struct SettingsPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var timer: FocusTimer

    @State private var focusMinutes = 25
    @State private var breakMinutes = 5
    @State private var coffeeMinutes = 5
    @State private var displayOptions: [DisplayOption] = []

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NotchflowTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Label("Behavior", systemImage: "switch.2")
                    .font(.system(size: 11, weight: .bold))
                Toggle("Auto-start breaks", isOn: $timer.autoStartBreaks)
                Toggle("Completion notifications", isOn: $model.notificationsEnabled)
                Toggle("Simulate notch", isOn: $model.simulateNotch)
                Toggle("Launch at login", isOn: $model.launchAtLogin)

                Divider().overlay(Color.white.opacity(0.08))

                displaySection
            }
            .font(.system(size: 10, weight: .medium))
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NotchflowTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 8)
        .onAppear {
            focusMinutes = max(1, timer.focusSeconds / 60)
            breakMinutes = max(1, timer.shortBreakSeconds / 60)
            coffeeMinutes = max(1, timer.coffeeSeconds / 60)
            refreshDisplayOptions()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didChangeScreenParametersNotification
            )
        ) { _ in
            refreshDisplayOptions()
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Show on display", systemImage: "display")
                .font(.system(size: 11, weight: .bold))

            Picker("Show on display", selection: displaySelection) {
                Text("Follow the mouse").tag(DisplayPreference.followMouse)
                ForEach(displayOptions) { option in
                    Text(option.menuTitle)
                        .tag(DisplayPreference.pinned(displayID: option.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .font(.system(size: 10, weight: .medium))
            .accessibilityLabel("Display the notch stays on")
        }
    }

    /// Captures the chosen display's name alongside its identifier so the menu
    /// can still name it after that monitor is unplugged.
    private var displaySelection: Binding<DisplayPreference> {
        Binding(
            get: { model.displayPreference },
            set: { preference in
                let name = preference.pinnedDisplayID.flatMap { id in
                    displayOptions.first(where: { $0.id == id })?.name
                }
                model.selectDisplay(preference, name: name ?? model.pinnedDisplayName)
            }
        )
    }

    private func refreshDisplayOptions() {
        var options = DisplayOption.connected()
        // Keep a pinned-but-unplugged display listed, otherwise the picker
        // renders blank and the saved choice looks lost.
        if let pinnedID = model.displayPreference.pinnedDisplayID,
           !options.contains(where: { $0.id == pinnedID }) {
            options.append(
                DisplayOption(
                    id: pinnedID,
                    name: model.pinnedDisplayName ?? "Saved display",
                    isConnected: false
                )
            )
        }
        displayOptions = options
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
