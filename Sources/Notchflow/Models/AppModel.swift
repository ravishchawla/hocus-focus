import AppKit
import Combine
import Foundation
import ServiceManagement
import UserNotifications

enum NotchTab: String, CaseIterable, Identifiable {
    case timer
    case music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timer: "Timer"
        case .music: "Music"
        }
    }

    var systemImage: String {
        switch self {
        case .timer: "timer"
        case .music: "music.note"
        }
    }
}

enum NotchSurface: Equatable {
    case main
    case settings
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let timer: FocusTimer
    let music: MusicBridge
    let lofiYouTube: LofiYouTubePlayer

    @Published var selectedTab: NotchTab = .timer
    @Published var surface: NotchSurface = .main
    @Published var isExpanded = false
    @Published var isPinned = false
    @Published var compactWidth: CGFloat = 210
    @Published var compactHeight: CGFloat = 36
    @Published var expandedWidth: CGFloat = 720
    @Published var expandedHeight: CGFloat = 204
    @Published var simulateNotch: Bool {
        didSet { defaults.set(simulateNotch, forKey: Keys.simulateNotch) }
    }
    @Published var collapseDelay: Double {
        didSet { defaults.set(collapseDelay, forKey: Keys.collapseDelay) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            guard launchAtLogin != oldValue else { return }
            updateLaunchAtLogin()
        }
    }
    @Published var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
            if notificationsEnabled && notificationsEnabled != oldValue {
                requestNotificationPermission()
            }
        }
    }
    @Published var musicSource: MusicSource {
        didSet {
            guard musicSource != oldValue else { return }
            defaults.set(musicSource.rawValue, forKey: Keys.musicSource)
            applyMusicSource()
        }
    }
    @Published var displayPreference: DisplayPreference {
        didSet {
            guard displayPreference != oldValue else { return }
            defaults.set(displayPreference.storageValue, forKey: Keys.displayPreference)
        }
    }
    /// Remembered only so Settings can name a pinned display that is currently
    /// unplugged. The panel always matches on `displayPreference`.
    @Published var pinnedDisplayName: String? {
        didSet {
            guard pinnedDisplayName != oldValue else { return }
            if let pinnedDisplayName {
                defaults.set(pinnedDisplayName, forKey: Keys.pinnedDisplayName)
            } else {
                defaults.removeObject(forKey: Keys.pinnedDisplayName)
            }
        }
    }

    private let defaults: UserDefaults
    private var collapseWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let focusSeconds = "timer.focusSeconds"
        static let breakSeconds = "timer.breakSeconds"
        static let coffeeSeconds = "timer.coffeeSeconds"
        static let autoStart = "timer.autoStartBreaks"
        static let musicSource = "music.source"
        static let simulateNotch = "panel.simulateNotch"
        static let collapseDelay = "panel.collapseDelay"
        static let launchAtLogin = "app.launchAtLogin"
        static let notificationsEnabled = "app.notificationsEnabled"
        static let timerState = "timer.persistedState"
        static let displayPreference = "panel.displayPreference"
        static let pinnedDisplayName = "panel.pinnedDisplayName"
    }

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults

        let focusSeconds = defaults.integer(forKey: Keys.focusSeconds)
        let breakSeconds = defaults.integer(forKey: Keys.breakSeconds)
        let coffeeSeconds = defaults.integer(forKey: Keys.coffeeSeconds)
        timer = FocusTimer(
            focusSeconds: focusSeconds > 0 ? focusSeconds : 25 * 60,
            shortBreakSeconds: breakSeconds > 0 ? breakSeconds : 5 * 60,
            coffeeSeconds: coffeeSeconds > 0 ? coffeeSeconds : 5 * 60,
            now: now
        )
        timer.autoStartBreaks = defaults.object(forKey: Keys.autoStart) == nil
            ? false
            : defaults.bool(forKey: Keys.autoStart)
        if let savedTimerState = defaults.data(forKey: Keys.timerState) {
            timer.restoreState(from: savedTimerState)
        }

        music = MusicBridge()
        lofiYouTube = LofiYouTubePlayer(defaults: defaults)
        if let rawSource = defaults.string(forKey: Keys.musicSource),
           let source = MusicSource(rawValue: rawSource) {
            musicSource = source
        } else {
            musicSource = .appleMusic
        }

        simulateNotch = defaults.object(forKey: Keys.simulateNotch) == nil
            ? false
            : defaults.bool(forKey: Keys.simulateNotch)
        collapseDelay = defaults.object(forKey: Keys.collapseDelay) == nil
            ? 0.75
            : defaults.double(forKey: Keys.collapseDelay)
        displayPreference = DisplayPreference(
            storageValue: defaults.string(forKey: Keys.displayPreference)
        )
        pinnedDisplayName = defaults.string(forKey: Keys.pinnedDisplayName)
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.notificationsEnabled)

        timer.onCompletion = { [weak self] completedMode in
            self?.handleCompletion(of: completedMode)
        }
        timer.onStateChange = { [weak self] in self?.persistTimerState() }

        timer.$autoStartBreaks
            .dropFirst()
            .sink { [weak self] value in self?.defaults.set(value, forKey: Keys.autoStart) }
            .store(in: &cancellables)

    }

    func updateDurations(focusMinutes: Int, breakMinutes: Int, coffeeMinutes: Int) {
        let focus = max(1, focusMinutes) * 60
        let shortBreak = max(1, breakMinutes) * 60
        let coffee = max(1, coffeeMinutes) * 60
        timer.updateDurations(
            focusSeconds: focus,
            shortBreakSeconds: shortBreak,
            coffeeSeconds: coffee
        )
        defaults.set(focus, forKey: Keys.focusSeconds)
        defaults.set(shortBreak, forKey: Keys.breakSeconds)
        defaults.set(coffee, forKey: Keys.coffeeSeconds)
    }

    /// Stores both halves of the choice: the stable identifier the panel matches
    /// on, and the display's name for the Settings menu.
    func selectDisplay(_ preference: DisplayPreference, name: String?) {
        pinnedDisplayName = preference == .followMouse ? nil : name
        displayPreference = preference
    }

    func expand(pin: Bool = false) {
        collapseWorkItem?.cancel()
        if pin { isPinned = true }
        withAnimationState { isExpanded = true }
        if selectedTab == .music { musicSurfaceDidAppear() }
    }

    func toggleExpanded() {
        collapseWorkItem?.cancel()
        isPinned.toggle()
        withAnimationState { isExpanded = isPinned || !isExpanded }
        if isExpanded && selectedTab == .music {
            musicSurfaceDidAppear()
        } else {
            musicSurfaceDidDisappear()
            surface = .main
        }
    }

    func collapse(force: Bool = false) {
        collapseWorkItem?.cancel()
        guard force || !isPinned else { return }
        if force { isPinned = false }
        withAnimationState { isExpanded = false }
        surface = .main
        musicSurfaceDidDisappear()
    }

    func scheduleCollapse() {
        collapseWorkItem?.cancel()
        guard !isPinned else { return }
        let workItem = DispatchWorkItem { [weak self] in self?.collapse() }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: workItem)
    }

    func cancelScheduledCollapse() {
        collapseWorkItem?.cancel()
    }

    func showSettings() {
        surface = .settings
        expand(pin: true)
        syncMusicPollingWithVisibleSurface()
    }

    func saveTimerDurationsFromCurrentValues() {
        defaults.set(timer.focusSeconds, forKey: Keys.focusSeconds)
        defaults.set(timer.shortBreakSeconds, forKey: Keys.breakSeconds)
        defaults.set(timer.coffeeSeconds, forKey: Keys.coffeeSeconds)
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func applicationDidWake() {
        timer.refresh()
        if musicSource != .lofiGirl { music.refresh() }
    }

    func musicSurfaceDidAppear() {
        syncMusicPollingWithVisibleSurface()
    }

    func musicSurfaceDidDisappear() {
        syncMusicPollingWithVisibleSurface()
    }

    func syncMusicPollingWithVisibleSurface() {
        let appleMusicPageIsVisible = selectedTab == .music && musicSource == .appleMusic
        let appleMusicTimerControlIsVisible = selectedTab == .timer && !timerMediaUsesLofi
        let shouldPoll = isExpanded
            && surface == .main
            && (appleMusicPageIsVisible || appleMusicTimerControlIsVisible)

        if shouldPoll {
            music.startPolling()
        } else {
            music.stopPolling()
        }
    }

    /// The Timer transport follows a retained Lofi session only when Lofi Girl
    /// is still the selected source. Otherwise it controls Apple Music.
    var timerMediaUsesLofi: Bool {
        musicSource == .lofiGirl && lofiYouTube.hasControllablePlaybackSession
    }

    var timerMediaIsPlaying: Bool {
        timerMediaUsesLofi ? lofiYouTube.isActivelyPlaying : music.isPlaying
    }

    var timerMediaSourceName: String {
        timerMediaUsesLofi ? "Lofi Girl" : "Apple Music"
    }

    func toggleTimerMediaPlayback() {
        if timerMediaUsesLofi, lofiYouTube.toggleExistingPlayback() {
            return
        }
        music.togglePlayPause()
    }

    private func pauseTimerMediaPlayback() {
        if musicSource == .lofiGirl && lofiYouTube.hasRetainedPlayer {
            lofiYouTube.pause()
        } else {
            music.pause()
        }
    }

    func persistTimerState() {
        defaults.set(timer.encodedState(), forKey: Keys.timerState)
    }

    private func handleCompletion(of mode: TimerMode) {
        if mode == .focus {
            pauseTimerMediaPlayback()
        }

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        guard notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.sound = .default
        switch mode {
        case .focus:
            content.title = "Focus complete"
            content.body = "Take a short break. You earned it."
        case .shortBreak, .coffee:
            content.title = "Break complete"
            content.body = "Ready for another focused session?"
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func updateLaunchAtLogin() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            defaults.set(false, forKey: Keys.launchAtLogin)
        }
    }

    private func applyMusicSource() {
        if musicSource == .appleMusic {
            lofiYouTube.pause()
        }
        syncMusicPollingWithVisibleSurface()
    }

    private func withAnimationState(_ changes: () -> Void) {
        changes()
    }
}
