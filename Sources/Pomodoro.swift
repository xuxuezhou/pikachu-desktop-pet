import Foundation

// MARK: - Local pomodoro timer (pure offline; pet becomes a quiet companion)

final class Pomodoro {
    enum Phase: Equatable {
        case idle
        case focus(remaining: Int)
        case rest(remaining: Int)
    }

    static let focusSeconds = 25 * 60
    static let restSeconds = 5 * 60

    private(set) var phase: Phase = .idle
    private var timer: Timer?

    var onPhaseChange: ((Phase) -> Void)?
    var onTick: ((Phase) -> Void)?

    var isActive: Bool { phase != .idle }

    var menuTitle: String {
        switch phase {
        case .idle:
            return "🍅 开始专注（25 分钟）"
        case .focus(let remaining):
            return "🍅 专注中 \(Pomodoro.format(remaining))（点击停止）"
        case .rest(let remaining):
            return "☕️ 休息中 \(Pomodoro.format(remaining))（点击停止）"
        }
    }

    static func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func toggle() {
        if isActive { stop() } else { startFocus() }
    }

    func startFocus() {
        setPhase(.focus(remaining: Pomodoro.focusSeconds))
        startTimer()
        logInfo("Pomodoro focus started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        setPhase(.idle)
        logInfo("Pomodoro stopped")
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        switch phase {
        case .idle:
            timer?.invalidate()
            timer = nil
        case .focus(let remaining):
            let next = remaining - 1
            if next <= 0 {
                SaveManager.shared.update {
                    $0.daily.pomodorosCompleted += 1
                    $0.totals.pomodoros += 1
                }
                setPhase(.rest(remaining: Pomodoro.restSeconds))
                logInfo("Pomodoro focus completed")
            } else {
                phase = .focus(remaining: next)
                onTick?(phase)
            }
        case .rest(let remaining):
            let next = remaining - 1
            if next <= 0 {
                timer?.invalidate()
                timer = nil
                setPhase(.idle)
            } else {
                phase = .rest(remaining: next)
                onTick?(phase)
            }
        }
    }

    private func setPhase(_ newPhase: Phase) {
        phase = newPhase
        onPhaseChange?(newPhase)
        onTick?(newPhase)
    }
}
