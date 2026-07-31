import Combine
import Foundation

enum TimerMode: String, CaseIterable, Codable {
    case focus
    case shortBreak
    case coffee
}

enum TimerRunState: String, Codable {
    case idle
    case running
    case paused
    case completed
}

@MainActor
final class FocusTimer: ObservableObject {
    @Published private(set) var mode: TimerMode
    @Published private(set) var state: TimerRunState
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var totalSeconds: Int
    @Published private(set) var completedFocusSessions: Int
    @Published var autoStartBreaks: Bool

    var onCompletion: ((TimerMode) -> Void)?
    var onStateChange: (() -> Void)?

    var focusSeconds: Int {
        get { focusDuration }
        set {
            setDuration(newValue, for: .focus)
            onStateChange?()
        }
    }

    var shortBreakSeconds: Int {
        get { shortBreakDuration }
        set {
            setDuration(newValue, for: .shortBreak)
            onStateChange?()
        }
    }

    var coffeeSeconds: Int {
        get { coffeeDuration }
        set {
            setDuration(newValue, for: .coffee)
            onStateChange?()
        }
    }

    var displayTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Elapsed progress from `0` at the start of a session to `1` at its end.
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        let elapsedFraction = 1 - (remainingInterval / TimeInterval(totalSeconds))
        return min(max(elapsedFraction, 0), 1)
    }

    var isRunning: Bool {
        state == .running
    }

    private var focusDuration: Int
    private var shortBreakDuration: Int
    private var coffeeDuration: Int
    private var remainingInterval: TimeInterval
    private var deadline: Date?
    private var ticker: AnyCancellable?
    private let currentDate: () -> Date

    init(
        focusSeconds: Int = 1_500,
        shortBreakSeconds: Int = 300,
        coffeeSeconds: Int = 300,
        now: @escaping () -> Date = { Date() }
    ) {
        let focusDuration = Self.validDuration(focusSeconds)

        self.focusDuration = focusDuration
        self.shortBreakDuration = Self.validDuration(shortBreakSeconds)
        self.coffeeDuration = Self.validDuration(coffeeSeconds)
        self.currentDate = now
        self.mode = .focus
        self.state = .idle
        self.remainingSeconds = focusDuration
        self.totalSeconds = focusDuration
        self.completedFocusSessions = 0
        self.autoStartBreaks = false
        self.remainingInterval = TimeInterval(focusDuration)
    }

    func updateDurations(
        focusSeconds: Int? = nil,
        shortBreakSeconds: Int? = nil,
        coffeeSeconds: Int? = nil
    ) {
        if let focusSeconds {
            setDuration(focusSeconds, for: .focus)
        }
        if let shortBreakSeconds {
            setDuration(shortBreakSeconds, for: .shortBreak)
        }
        if let coffeeSeconds {
            setDuration(coffeeSeconds, for: .coffee)
        }
        onStateChange?()
    }

    func start() {
        start(at: currentDate())
        onStateChange?()
    }

    func pause() {
        guard state == .running else { return }

        refresh(now: currentDate())
        guard state == .running else { return }

        stopTicker()
        deadline = nil
        state = .paused
        onStateChange?()
    }

    func toggle() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }

    /// Resets the current mode to its full duration without changing modes.
    func reset() {
        configure(mode: mode)
        onStateChange?()
    }

    /// Ends the current flow and returns to a fresh focus session.
    func stop() {
        configure(mode: .focus)
        onStateChange?()
    }

    /// Advances to the next mode without recording a completed focus session.
    func skip() {
        switch mode {
        case .focus:
            configure(mode: .shortBreak)
            if autoStartBreaks {
                start()
            }
        case .shortBreak, .coffee:
            configure(mode: .focus)
        }
        onStateChange?()
    }

    func startCoffeeBreak() {
        configure(mode: .coffee)
        start(at: currentDate())
        onStateChange?()
    }

    func endCoffeeBreak() {
        guard mode == .coffee else { return }
        configure(mode: .focus)
        onStateChange?()
    }

    func encodedState() -> Data? {
        let remaining: TimeInterval
        if state == .running, let deadline {
            remaining = max(0, deadline.timeIntervalSince(currentDate()))
        } else {
            remaining = remainingInterval
        }

        let record = PersistenceRecord(
            mode: mode,
            state: state,
            remainingInterval: remaining,
            deadline: deadline,
            focusDuration: focusDuration,
            shortBreakDuration: shortBreakDuration,
            coffeeDuration: coffeeDuration,
            completedFocusSessions: completedFocusSessions
        )
        return try? JSONEncoder().encode(record)
    }

    func restoreState(from data: Data) {
        guard let record = try? JSONDecoder().decode(PersistenceRecord.self, from: data) else {
            return
        }

        stopTicker()
        focusDuration = Self.validDuration(record.focusDuration)
        shortBreakDuration = Self.validDuration(record.shortBreakDuration)
        coffeeDuration = Self.validDuration(record.coffeeDuration)
        mode = record.mode
        totalSeconds = duration(for: record.mode)
        completedFocusSessions = max(0, record.completedFocusSessions)

        let restoredRemaining = min(
            max(0, record.remainingInterval),
            TimeInterval(totalSeconds)
        )
        remainingInterval = restoredRemaining
        remainingSeconds = max(0, Int(ceil(restoredRemaining)))
        deadline = nil

        guard record.state == .running, let storedDeadline = record.deadline else {
            state = record.state == .completed ? .idle : record.state
            if state == .idle && remainingSeconds == 0 {
                configure(mode: mode)
            }
            return
        }

        state = .running
        deadline = storedDeadline
        if storedDeadline > currentDate() {
            refresh(now: currentDate())
            startTicker()
        } else {
            remainingInterval = 0
            remainingSeconds = 0
            completeCurrentMode(at: currentDate())
        }
    }

    /// Reconciles the displayed countdown with its wall-clock deadline.
    /// Calling this after wake immediately accounts for all time spent asleep.
    func refresh(now date: Date? = nil) {
        guard state == .running, let deadline else { return }

        let date = date ?? currentDate()
        let secondsUntilDeadline = deadline.timeIntervalSince(date)

        guard secondsUntilDeadline > 0 else {
            remainingInterval = 0
            remainingSeconds = 0
            completeCurrentMode(at: date)
            return
        }

        remainingInterval = min(secondsUntilDeadline, TimeInterval(totalSeconds))
        remainingSeconds = max(1, Int(ceil(remainingInterval)))
    }

    private func start(at date: Date) {
        guard state != .running else {
            refresh(now: date)
            return
        }

        if state == .completed || remainingInterval <= 0 {
            configure(mode: mode)
        }

        deadline = date.addingTimeInterval(remainingInterval)
        state = .running
        startTicker()
    }

    private func completeCurrentMode(at date: Date) {
        let completedMode = mode

        stopTicker()
        deadline = nil
        state = .completed

        if completedMode == .focus {
            completedFocusSessions += 1
            configure(mode: .shortBreak)
            if autoStartBreaks {
                start(at: date)
            }
        } else {
            configure(mode: .focus)
        }

        onCompletion?(completedMode)
        onStateChange?()
    }

    private func configure(mode newMode: TimerMode) {
        stopTicker()
        deadline = nil

        let duration = duration(for: newMode)
        mode = newMode
        state = .idle
        totalSeconds = duration
        remainingSeconds = duration
        remainingInterval = TimeInterval(duration)
    }

    private func setDuration(_ seconds: Int, for timerMode: TimerMode) {
        let duration = Self.validDuration(seconds)

        switch timerMode {
        case .focus:
            focusDuration = duration
        case .shortBreak:
            shortBreakDuration = duration
        case .coffee:
            coffeeDuration = duration
        }

        guard mode == timerMode, state != .running else { return }

        totalSeconds = duration
        remainingSeconds = duration
        remainingInterval = TimeInterval(duration)
        deadline = nil
        if state == .completed {
            state = .idle
        }
    }

    private func duration(for timerMode: TimerMode) -> Int {
        switch timerMode {
        case .focus:
            focusDuration
        case .shortBreak:
            shortBreakDuration
        case .coffee:
            coffeeDuration
        }
    }

    private func startTicker() {
        guard ticker == nil else { return }

        ticker = Timer.publish(
            every: 0.25,
            tolerance: 0.05,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private static func validDuration(_ seconds: Int) -> Int {
        max(1, seconds)
    }

    private struct PersistenceRecord: Codable {
        let mode: TimerMode
        let state: TimerRunState
        let remainingInterval: TimeInterval
        let deadline: Date?
        let focusDuration: Int
        let shortBreakDuration: Int
        let coffeeDuration: Int
        let completedFocusSessions: Int
    }
}
