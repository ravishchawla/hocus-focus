import SwiftUI

struct NotchRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: model.isExpanded ? 0 : 5,
                bottomLeadingRadius: model.isExpanded ? 28 : 15,
                bottomTrailingRadius: model.isExpanded ? 28 : 15,
                topTrailingRadius: model.isExpanded ? 0 : 5,
                style: .continuous
            )
            .fill(NotchflowTheme.panel)
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: model.isExpanded ? 0 : 5,
                    bottomLeadingRadius: model.isExpanded ? 28 : 15,
                    bottomTrailingRadius: model.isExpanded ? 28 : 15,
                    topTrailingRadius: model.isExpanded ? 0 : 5,
                    style: .continuous
                )
                .stroke(Color.white.opacity(model.isExpanded ? 0.10 : 0.05), lineWidth: 0.8)
            }

            if model.isExpanded {
                ExpandedNotchView(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                CollapsedNotchView(model: model)
                    .transition(.opacity)
            }
        }
        .frame(
            width: model.isExpanded ? model.expandedWidth : model.compactWidth,
            height: model.isExpanded ? model.expandedHeight : model.compactHeight
        )
        .contentShape(Rectangle())
        .animation(.spring(response: 0.33, dampingFraction: 0.84), value: model.isExpanded)
        .preferredColorScheme(.dark)
    }
}

private struct CollapsedNotchView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var timer: FocusTimer

    init(model: AppModel) {
        self.model = model
        timer = model.timer
    }

    var body: some View {
        Button {
            model.expand(pin: true)
        } label: {
            HStack(spacing: 0) {
                Text(modeLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(NotchflowTheme.secondary)
                    .frame(width: 70, alignment: .leading)

                Spacer(minLength: model.compactWidth > 280 ? 176 : 10)

                Text(timer.displayTime)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(timer.isRunning ? NotchflowTheme.orangeSoft : Color.white.opacity(0.88))
                    .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(modeLabel), \(timer.displayTime) remaining. Open Hocus Focus")
    }

    private var modeLabel: String {
        switch timer.mode {
        case .shortBreak:
            "BREAK"
        case .coffee:
            "COFFEE"
        case .focus:
            switch timer.state {
            case .idle:
                "READY"
            case .running:
                "FOCUS"
            case .paused:
                "PAUSED"
            case .completed:
                "DONE"
            }
        }
    }
}

private struct ExpandedNotchView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 50)
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)

            Group {
                switch model.surface {
                case .settings:
                    SettingsPanelView(model: model)
                case .main:
                    if model.selectedTab == .timer {
                        TimerControlsView(model: model)
                    } else {
                        MusicControlsView(model: model)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(NotchTab.allCases) { tab in
                Button {
                    model.surface = .main
                    model.selectedTab = tab
                    if tab == .music {
                        model.musicSurfaceDidAppear()
                    } else {
                        model.musicSurfaceDidDisappear()
                    }
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(model.selectedTab == tab ? .white : NotchflowTheme.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(
                            model.selectedTab == tab && model.surface == .main
                                ? NotchflowTheme.raised
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                model.isPinned.toggle()
                if !model.isPinned { model.scheduleCollapse() }
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.isPinned ? NotchflowTheme.orangeSoft : NotchflowTheme.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPinned ? "Unpin expanded notch" : "Pin expanded notch")

            Button {
                model.surface = model.surface == .settings ? .main : .settings
                if model.surface == .main && model.selectedTab == .music {
                    model.musicSurfaceDidAppear()
                } else {
                    model.musicSurfaceDidDisappear()
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.surface == .settings ? .white : NotchflowTheme.secondary)
                    .frame(width: 30, height: 30)
                    .background(model.surface == .settings ? NotchflowTheme.raised : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            Button {
                model.collapse(force: true)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NotchflowTheme.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse Hocus Focus")
        }
    }
}
