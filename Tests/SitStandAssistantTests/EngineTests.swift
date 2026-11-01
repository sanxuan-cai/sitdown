import XCTest
@testable import SitStandAssistant

final class EngineTests: XCTestCase {
    private let start = ISO8601DateFormatter().date(from: "2026-11-02T02:00:00Z")!
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
    }

    @MainActor func testExpiryRequiresConfirmationAndSnoozeKeepsPosture() {
        let engine = Engine(fileURL: location(), now: start, live: false)
        engine.start(at: start)
        engine.tick(at: start.addingTimeInterval(1800))
        XCTAssertTrue(engine.isDue)
        XCTAssertEqual(engine.posture, .sitting)
        engine.snooze(at: start.addingTimeInterval(1860))
        XCTAssertFalse(engine.isDue)
        XCTAssertEqual(engine.session?.deadline, start.addingTimeInterval(2160))
        engine.tick(at: start.addingTimeInterval(2200))
        XCTAssertTrue(engine.isDue)
        XCTAssertEqual(engine.today.sitting, 2200, accuracy: 0.001)
        engine.confirm(at: start.addingTimeInterval(2200))
        XCTAssertEqual(engine.posture, .standing)
        XCTAssertEqual(engine.session?.deadline, start.addingTimeInterval(3100))
    }

    @MainActor func testDurationEditsApplyOnNextRoundAndEarlyConfirmationWorks() {
        let engine = Engine(fileURL: location(), now: start, live: false)
        engine.start(at: start)
        engine.updateSettings({ $0.standingMinutes = 12; $0.sittingMinutes = 40 }, at: start.addingTimeInterval(30))
        XCTAssertEqual(engine.session?.deadline, start.addingTimeInterval(1800))
        engine.confirm(at: start.addingTimeInterval(60))
        XCTAssertEqual(engine.session?.deadline, start.addingTimeInterval(780))
        engine.tick(at: start.addingTimeInterval(120))
        XCTAssertEqual(engine.today.sitting, 60, accuracy: 0.001)
        XCTAssertEqual(engine.today.standing, 60, accuracy: 0.001)
    }

    @MainActor func testAwayAndRelaunchDoNotAccrueInactiveTime() {
        let url = location()
        let engine = Engine(fileURL: url, now: start, live: false)
        engine.start(at: start)
        engine.setAway(true, at: start.addingTimeInterval(60))
        engine.tick(at: start.addingTimeInterval(600))
        engine.setAway(false, at: start.addingTimeInterval(660))
        engine.shutdown(at: start.addingTimeInterval(720))
        let restored = Engine(fileURL: url, now: start.addingTimeInterval(3600), live: false)
        restored.tick(at: start.addingTimeInterval(3660))
        XCTAssertTrue(restored.isDue)
        XCTAssertEqual(restored.today.sitting, 180, accuracy: 0.001)
        XCTAssertEqual(restored.posture, .sitting)
    }

    @MainActor func testScheduledStopCapsStatsAndSuppressesRestart() {
        let engine = Engine(fileURL: location(), now: start, live: false)
        let minute = Calendar.current.component(.hour, from: start) * 60 + Calendar.current.component(.minute, from: start)
        engine.updateSettings({
            $0.scheduleEnabled = true
            $0.weekdaysOnly = false
            $0.periods = [SchedulePeriod(start: minute, end: minute + 10)]
        }, at: start)
        XCTAssertNotNil(engine.session?.scheduleKey)
        engine.tick(at: start.addingTimeInterval(1200))
        XCTAssertNil(engine.session)
        XCTAssertEqual(engine.today.sitting, 600, accuracy: 0.001)
    }

    @MainActor func testManualStopSurvivesRestartDuringSameSlot() {
        let url = location()
        let engine = Engine(fileURL: url, now: start, live: false)
        let minute = Calendar.current.component(.hour, from: start) * 60 + Calendar.current.component(.minute, from: start)
        engine.updateSettings({
            $0.scheduleEnabled = true
            $0.weekdaysOnly = false
            $0.periods = [SchedulePeriod(start: minute, end: minute + 60)]
        }, at: start)
        engine.stop(at: start.addingTimeInterval(60))
        let restored = Engine(fileURL: url, now: start.addingTimeInterval(120), live: false)
        restored.tick(at: start.addingTimeInterval(120))
        XCTAssertNil(restored.session)
    }

    @MainActor func testManualSessionOutlivesScheduleAndInvalidScheduleStopsOnlyAutomaticSession() {
        let engine = Engine(fileURL: location(), now: start, live: false)
        engine.start(at: start)
        engine.updateSettings({ $0.scheduleEnabled = true; $0.periods = [] }, at: start.addingTimeInterval(60))
        engine.tick(at: start.addingTimeInterval(3600))
        XCTAssertNotNil(engine.session)
        XCTAssertNil(engine.session?.scheduleKey)
        XCTAssertEqual(engine.today.sitting, 3600, accuracy: 0.001)
        engine.stop(at: start.addingTimeInterval(3600))
        engine.tick(at: start.addingTimeInterval(7200))
        XCTAssertEqual(engine.today.sitting, 3600, accuracy: 0.001)
    }

    @MainActor func testInvalidatingScheduleEndsAutomaticSession() {
        let engine = Engine(fileURL: location(), now: start, live: false)
        let minute = Calendar.current.component(.hour, from: start) * 60 + Calendar.current.component(.minute, from: start)
        engine.updateSettings({
            $0.scheduleEnabled = true; $0.weekdaysOnly = false
            $0.periods = [SchedulePeriod(start: minute, end: minute + 60)]
        }, at: start)
        XCTAssertNotNil(engine.session)
        engine.updateSettings({ $0.periods.append($0.periods[0]) }, at: start.addingTimeInterval(60))
        XCTAssertNil(engine.session)
        XCTAssertNotNil(engine.settings.scheduleError)
    }

    func testMidnightSplitsStatistics() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = ISO8601DateFormatter().date(from: "2026-11-03T00:00:00Z")!
        var totals: [String: DayTotal] = [:]
        DayTotal.accumulate(from: midnight.addingTimeInterval(-60), to: midnight.addingTimeInterval(120), posture: .standing, into: &totals, calendar: calendar)
        XCTAssertEqual(totals["2026-11-02"]?.standing, 60)
        XCTAssertEqual(totals["2026-11-03"]?.standing, 120)
    }

    func testScheduleValidationAndWeekends() {
        var settings = Settings()
        settings.periods = [SchedulePeriod(start: 600, end: 720), SchedulePeriod(start: 720, end: 800)]
        XCTAssertNil(settings.scheduleError)
        settings.periods[1].start = 719
        XCTAssertNotNil(settings.scheduleError)
        settings.periods = [SchedulePeriod(start: 1200, end: 500)]
        XCTAssertNotNil(settings.scheduleError)
        settings.periods = [SchedulePeriod(start: 0, end: 1439)]
        settings.scheduleEnabled = true
        let sunday = ISO8601DateFormatter().date(from: "2026-11-01T10:00:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertNil(settings.activeSlot(at: sunday, calendar: calendar))
        settings.weekdaysOnly = false
        XCTAssertNotNil(settings.activeSlot(at: sunday, calendar: calendar))
    }

    @MainActor func testReminderVisibilityFollowsDueSnoozeAndAway() {
        let engine = Engine(fileURL: location(), now: start, live: false)
        var changes: [Bool] = []
        engine.onReminder = { changes.append($0) }
        engine.start(at: start)
        engine.tick(at: start.addingTimeInterval(1800))
        engine.tick(at: start.addingTimeInterval(1801))
        XCTAssertEqual(changes, [true])
        engine.setAway(true, at: start.addingTimeInterval(1802))
        engine.setAway(false, at: start.addingTimeInterval(1900))
        engine.snooze(at: start.addingTimeInterval(1900))
        XCTAssertEqual(changes, [true, false, true, false])
        engine.tick(at: start.addingTimeInterval(2200))
        engine.stop(at: start.addingTimeInterval(2200))
        XCTAssertEqual(changes, [true, false, true, false, true, false])
    }

    @MainActor func testSettingRangesAreClampedAndPreserved() {
        let url = location()
        let engine = Engine(fileURL: url, now: start, live: false)
        engine.updateSettings({
            $0.sittingMinutes = 0; $0.standingMinutes = 999; $0.snoozeMinutes = 90
        }, at: start)
        let restored = Engine(fileURL: url, now: start, live: false)
        XCTAssertEqual(restored.settings.sittingMinutes, 1)
        XCTAssertEqual(restored.settings.standingMinutes, 240)
        XCTAssertEqual(restored.settings.snoozeMinutes, 60)
    }
}
