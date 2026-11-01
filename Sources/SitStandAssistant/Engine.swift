import AppKit
import Combine

@MainActor
final class Engine: ObservableObject {
    @Published private(set) var state: SavedState
    @Published private(set) var now: Date
    @Published private(set) var isAway = false
    @Published private(set) var storageError: String?
    var onReminder: ((Bool) -> Void)?
    var onChange: (() -> Void)?

    private let fileURL: URL
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var lastAccounting: Date?
    private var lastSave: Date
    private var lastSound: Date?
    private var reminderVisible = false
    private let live: Bool
    private var sleeping = false
    private var sessionInactive = false
    private var screenLocked = false

    init(fileURL: URL? = nil, now: Date = Date(), live: Bool = true) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SitStandAssistant/state.json")
        self.now = now
        self.lastSave = now
        self.live = live
        if let data = try? Data(contentsOf: self.fileURL) {
            do { state = try JSONDecoder().decode(SavedState.self, from: data) }
            catch {
                state = SavedState()
                storageError = "无法读取已有数据，已使用默认设置。原文件已保留。"
                let backup = self.fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(Int(now.timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: self.fileURL, to: backup)
            }
        } else { state = SavedState() }
        state.settings.sittingMinutes = min(240, max(1, state.settings.sittingMinutes))
        state.settings.standingMinutes = min(240, max(1, state.settings.standingMinutes))
        state.settings.snoozeMinutes = min(60, max(1, state.settings.snoozeMinutes))
        // Never count the gap while the process was not running.
        lastAccounting = state.session == nil ? nil : now
        if live {
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSleeping(true) }
            })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSleeping(false) }
            })
            observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSessionInactive(true) }
            })
            observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSessionInactive(false) }
            })
            let distributed = DistributedNotificationCenter.default()
            for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
                lockObservers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        let date = Date()
                        self.account(until: date)
                        self.screenLocked = locked
                        self.updateAway(at: date)
                    }
                })
            }
            timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
    }

    var settings: Settings { state.settings }
    var session: Session? { state.session }
    var posture: Posture { state.session?.posture ?? state.selectedPosture }
    var isDue: Bool { state.session.map { $0.deadline <= now } ?? false }
    var remaining: TimeInterval { max(0, state.session?.deadline.timeIntervalSince(now) ?? 0) }
    var today: DayTotal { state.totals[DayTotal.key(now)] ?? DayTotal() }
    var countdown: String {
        let seconds = Int(ceil(remaining))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func updateSettings(_ edit: (inout Settings) -> Void, at date: Date = Date()) {
        account(until: date)
        var value = state.settings
        edit(&value)
        value.sittingMinutes = min(240, max(1, value.sittingMinutes))
        value.standingMinutes = min(240, max(1, value.standingMinutes))
        value.snoozeMinutes = min(60, max(1, value.snoozeMinutes))
        state.settings = value
        tick(at: date)
        save()
    }

    func selectPosture(_ posture: Posture) {
        guard session == nil else { return }
        state.selectedPosture = posture
        save()
    }

    func start(at date: Date = Date()) {
        guard session == nil else { return }
        begin(posture: state.selectedPosture, slot: nil, at: date)
    }

    private func begin(posture: Posture, slot: ScheduleSlot?, at date: Date) {
        now = date
        state.session = Session(posture: posture, deadline: date.addingTimeInterval(settings.duration(for: posture)), scheduleKey: slot?.key, scheduleEnd: slot?.end)
        lastAccounting = isAway ? nil : date
        lastSound = nil
        refreshReminder()
        save()
        onChange?()
    }

    func stop(at date: Date = Date()) {
        account(until: date)
        if let key = session?.scheduleKey { state.suppressedSlots.insert(key) }
        // A manual stop should also suppress an active slot when settings changed mid-session.
        if let slot = settings.activeSlot(at: date) { state.suppressedSlots.insert(slot.key) }
        state.selectedPosture = posture
        state.session = nil
        lastAccounting = nil
        now = date
        refreshReminder()
        save()
        onChange?()
    }

    func confirm(at date: Date = Date()) {
        tick(at: date)
        guard var current = session else { return }
        current.posture = current.posture.opposite
        current.deadline = date.addingTimeInterval(settings.duration(for: current.posture))
        state.session = current
        now = date
        lastSound = nil
        refreshReminder()
        save()
        onChange?()
    }

    func snooze(at date: Date = Date()) {
        tick(at: date)
        guard session != nil, isDue else { return }
        state.session?.deadline = date.addingTimeInterval(TimeInterval(settings.snoozeMinutes * 60))
        lastSound = nil
        refreshReminder()
        save()
        onChange?()
    }

    func tick(at date: Date = Date()) {
        account(until: date)
        now = date
        let slot = settings.activeSlot(at: date)
        if let current = session, let key = current.scheduleKey {
            if slot?.key != key || (current.scheduleEnd.map { date >= $0 } ?? false) {
                state.suppressedSlots.insert(key)
                state.selectedPosture = current.posture
                state.session = nil
                lastAccounting = nil
                save()
            } else if let end = slot?.end, end != current.scheduleEnd {
                state.session?.scheduleEnd = end
            }
        }
        if session == nil, !isAway, let slot, !state.suppressedSlots.contains(slot.key) {
            begin(posture: .sitting, slot: slot, at: date)
        }
        let todayPrefix = DayTotal.key(date) + "_"
        state.suppressedSlots = state.suppressedSlots.filter { $0.hasPrefix(todayPrefix) }
        refreshReminder()
        if !isAway, isDue, settings.soundEnabled, lastSound.map({ date.timeIntervalSince($0) >= 30 }) ?? true {
            if live { NSSound(named: "Glass")?.play() }
            lastSound = date
        }
        if date.timeIntervalSince(lastSave) >= 15 { save() }
        onChange?()
    }

    private func account(until date: Date) {
        guard let current = session, !isAway else { lastAccounting = nil; return }
        if let last = lastAccounting {
            // An automatic session cannot accrue beyond its scheduled end.
            let end = min(date, current.scheduleEnd ?? date)
            DayTotal.accumulate(from: last, to: end, posture: current.posture, into: &state.totals)
        }
        lastAccounting = date
    }

    private func setSleeping(_ value: Bool) {
        let date = Date()
        account(until: date)
        sleeping = value
        updateAway(at: date)
    }

    private func setSessionInactive(_ value: Bool) {
        let date = Date()
        account(until: date)
        sessionInactive = value
        updateAway(at: date)
    }

    // Also used by the regression tests to exercise suspension without sleeping the Mac.
    func setAway(_ value: Bool, at date: Date) {
        account(until: date)
        sessionInactive = value
        updateAway(at: date)
    }

    private func updateAway(at date: Date) {
        isAway = sleeping || sessionInactive || screenLocked
        lastAccounting = isAway || session == nil ? nil : date
        tick(at: date)
        save()
    }

    private func refreshReminder() {
        let visible = isDue && !isAway
        if visible != reminderVisible {
            reminderVisible = visible
            onReminder?(visible)
        }
    }

    func shutdown(at date: Date = Date()) {
        account(until: date)
        now = date
        save()
        timer?.invalidate()
        timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        lockObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        lockObservers.removeAll()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
            lastSave = now
        } catch { storageError = "数据保存失败：\(error.localizedDescription)" }
    }
}
