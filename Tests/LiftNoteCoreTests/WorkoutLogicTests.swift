import XCTest
#if canImport(LiftNoteCore)
@testable import LiftNoteCore
#else
@testable import LiftNote
#endif

final class WorkoutLogicTests: XCTestCase {
    let catalog = ExerciseCatalog()
    let chestPress = "nautilus.sel.chest-press"
    let pushdown = "gen.cable.pushdown"
    let lateral = "gen.cable.lateral-raise"
    let primeRow = "prime.pl.upper-back-row"

    private func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    /// 生成一次已结束的训练
    private func finishedWorkout(_ data: inout AppData, muscles: [MuscleGroup], at start: Date,
                                 _ items: [(String, [(Double, Int)])]) {
        data.startWorkout(muscles: muscles, catalog: catalog, now: start)
        data.activeWorkout?.exercises = []
        for (id, sets) in items {
            let entryID = data.addExercise(id, catalog: catalog, setCount: sets.count, now: start)!
            let entry = data.activeWorkout!.exercises.first(where: { $0.id == entryID })!
            for (i, s) in sets.enumerated() {
                let setID = entry.sets[i].id
                data.updateActiveSet(entryID: entryID, setID: setID, now: start) {
                    $0.weight = s.0
                    $0.reps = s.1
                }
                data.completeSet(entryID: entryID, setID: setID, catalog: catalog, now: start)
            }
        }
        XCTAssertEqual(data.finishActiveWorkout(now: start.addingTimeInterval(3600)).isFinished, true)
    }

    func testTemplateCopiesLastSessionForSelectedMuscleWithEmptyValues() {
        var data = AppData()
        finishedWorkout(&data, muscles: [.chest], at: date("2026-10-01 10:00"), [(chestPress, [(45, 10), (40, 8)])])
        data.startWorkout(muscles: [.chest], catalog: catalog, now: date("2026-10-03 10:00"))
        let w = data.activeWorkout!
        XCTAssertEqual(w.exercises.count, 1)
        XCTAssertEqual(w.exercises[0].exerciseID, chestPress)
        XCTAssertEqual(w.exercises[0].sets.count, 2)
        XCTAssertTrue(w.exercises[0].sets.allSatisfy { !$0.isCompleted && $0.weight == nil && $0.quality == nil })

        let prev = data.previousPerformance(exerciseID: chestPress, handedness: .bilateral, before: w.startedAt)
        XCTAssertEqual(prev?.sets.map { $0.weight }, [45, 40])
        XCTAssertEqual(prev?.sets.map { $0.reps }, [10, 8])
    }

    func testNoMusclesSelectedGivesEmptyTemplate() {
        var data = AppData()
        finishedWorkout(&data, muscles: [.chest], at: date("2026-10-01 10:00"), [(chestPress, [(45, 10)])])
        data.startWorkout(muscles: [], catalog: catalog, now: date("2026-10-03 10:00"))
        XCTAssertEqual(data.activeWorkout?.exercises.count, 0)
    }

    func testWarmupAndIncompleteSetsDoNotCountTowardsWeeklyVolume() {
        var data = AppData()
        let start = date("2026-10-06 10:00") // 周二
        data.startWorkout(muscles: [.chest], catalog: catalog, now: start)
        let entryID = data.addExercise(chestPress, catalog: catalog, setCount: 3, now: start)!
        let sets = data.activeWorkout!.exercises.first(where: { $0.id == entryID })!.sets
        data.updateActiveSet(entryID: entryID, setID: sets[0].id, now: start) { $0.kind = .warmup; $0.weight = 20; $0.reps = 12 }
        data.completeSet(entryID: entryID, setID: sets[0].id, catalog: catalog, now: start)
        data.updateActiveSet(entryID: entryID, setID: sets[1].id, now: start) { $0.weight = 45; $0.reps = 10 }
        data.completeSet(entryID: entryID, setID: sets[1].id, catalog: catalog, now: start)
        // 第三组没完成
        data.updateActiveSet(entryID: entryID, setID: sets[2].id, now: start) { $0.weight = 45 }

        let v = WeeklyVolume.compute(data: data, week: WeeklyVolume.week(containing: start), catalog: catalog)
        XCTAssertEqual(v.count(.chest), 1)
        XCTAssertEqual(v.count(.triceps), 0, "间接参与的肌群不计组数")
    }

    func testWeekStartsMonday() {
        let sunday = date("2026-10-11 22:00")
        let monday = date("2026-10-12 06:00")
        XCTAssertNotEqual(WeeklyVolume.week(containing: sunday).start, WeeklyVolume.week(containing: monday).start)
        XCTAssertEqual(WeeklyVolume.week(containing: date("2026-10-06 10:00")).start,
                       WeeklyVolume.week(containing: sunday).start)
    }

    func testSwapEquipmentKeepsCompletedSetsOnOriginal() {
        var data = AppData()
        let now = date("2026-10-03 10:00")
        data.startWorkout(muscles: [.chest], catalog: catalog, now: now)
        let entryID = data.addExercise(chestPress, catalog: catalog, setCount: 2, now: now)!
        let first = data.activeWorkout!.exercises[0].sets[0].id
        data.updateActiveSet(entryID: entryID, setID: first, now: now) { $0.weight = 45; $0.reps = 10 }
        data.completeSet(entryID: entryID, setID: first, catalog: catalog, now: now)

        let newID = data.swapEquipment(entryID: entryID, to: "hammer.pl.bench-press", catalog: catalog, now: now)
        let w = data.activeWorkout!
        XCTAssertEqual(w.exercises.count, 2)
        XCTAssertEqual(w.exercises[0].exerciseID, chestPress)
        XCTAssertEqual(w.exercises[0].sets.count, 1)
        XCTAssertTrue(w.exercises[0].sets[0].isCompleted)
        XCTAssertEqual(w.exercises[1].id, newID)
        XCTAssertEqual(w.exercises[1].exerciseID, "hammer.pl.bench-press")
        XCTAssertEqual(w.exercises[1].sets.count, 1)
    }

    func testSwapBackAndForthTemplateKeepsAllSets() {
        var data = AppData()
        let start = date("2026-10-02 10:00")
        data.startWorkout(muscles: [.chest], catalog: catalog, now: start)
        data.activeWorkout?.exercises = [
            ExerciseEntry(exerciseID: chestPress, sets: [SetEntry(weight: 45, reps: 10, isCompleted: true)]),
            ExerciseEntry(exerciseID: "hammer.pl.bench-press", sets: [SetEntry(weight: 60, reps: 8, isCompleted: true)]),
            ExerciseEntry(exerciseID: chestPress, sets: [SetEntry(weight: 40, reps: 9, isCompleted: true)]),
        ]
        data.finishActiveWorkout(now: start.addingTimeInterval(3600))
        data.startWorkout(muscles: [.chest], catalog: catalog, now: date("2026-10-05 10:00"))
        let entries = data.activeWorkout!.exercises
        XCTAssertEqual(entries.map { $0.exerciseID }, [chestPress, "hammer.pl.bench-press"])
        XCTAssertEqual(entries[0].sets.count, 2)
    }

    func testFinishWithoutCompletedSetsRequiresDiscard() {
        var data = AppData()
        data.startWorkout(muscles: [.chest], catalog: catalog, now: Date())
        XCTAssertEqual(data.finishActiveWorkout(), .nothingCompleted)
        XCTAssertNotNil(data.activeWorkout)
        data.discardActiveWorkout()
        XCTAssertNil(data.activeWorkout)
        XCTAssertTrue(data.workouts.isEmpty)
    }

    func testAutoTitleIncludesMusclesAddedDuringWorkout() {
        var data = AppData()
        let now = date("2026-10-03 13:00")
        data.startWorkout(muscles: [.chest, .triceps], catalog: catalog, now: now)
        let skipped = data.addExercise("gen.bb.curl", catalog: catalog, now: now)!
        let lat = data.addExercise(lateral, catalog: catalog, now: now)!
        let setID = data.activeWorkout!.exercises.first(where: { $0.id == lat })!.sets[0].id
        data.updateActiveSet(entryID: lat, setID: setID, now: now) { $0.weight = 10; $0.reps = 15 }
        data.completeSet(entryID: lat, setID: setID, catalog: catalog, now: now)
        XCTAssertEqual(data.activeWorkout!.autoTitle(catalog: catalog), "胸 · 三头 · 肩中束")
        _ = skipped
        data.activeWorkout?.customTitle = "推日"
        XCTAssertEqual(data.activeWorkout!.title(catalog: catalog), "推日")
    }

    func testDeleteHistorySetUpdatesVolumeAndPreviousReference() {
        var data = AppData()
        let start = date("2026-10-06 10:00")
        finishedWorkout(&data, muscles: [.chest], at: start, [(chestPress, [(45, 10), (40, 8)])])
        let w = data.workouts[0]
        let entry = w.exercises[0]
        data.deleteHistorySet(workoutID: w.id, entryID: entry.id, setID: entry.sets[1].id)
        let v = WeeklyVolume.compute(data: data, week: WeeklyVolume.week(containing: start), catalog: catalog)
        XCTAssertEqual(v.count(.chest), 1)
        let prev = data.previousPerformance(exerciseID: chestPress, handedness: .bilateral, before: start.addingTimeInterval(86400))
        XCTAssertEqual(prev?.sets.count, 1)

        data.deleteHistorySet(workoutID: w.id, entryID: entry.id, setID: entry.sets[0].id)
        XCTAssertTrue(data.workouts[0].exercises.isEmpty)
    }

    func testChangeWorkoutDateKeepsDuration() {
        var data = AppData()
        let start = date("2026-10-06 10:00")
        finishedWorkout(&data, muscles: [.chest], at: start, [(chestPress, [(45, 10)])])
        let id = data.workouts[0].id
        let newStart = date("2026-10-05 18:00")
        data.changeWorkoutDate(id, to: newStart)
        XCTAssertEqual(data.workouts[0].startedAt, newStart)
        XCTAssertEqual(data.workouts[0].duration, 3600)
    }

    func testChangeHistoryEquipmentKeepsSetsAndFlagsFormatChange() {
        var data = AppData()
        let start = date("2026-10-06 10:00")
        finishedWorkout(&data, muscles: [.back], at: start, [("prime.sel.upper-back-row", [(50, 10), (50, 9)])])
        let w = data.workouts[0]
        let sameFormat = data.changeHistoryEquipment(workoutID: w.id, entryID: w.exercises[0].id, to: "hammer.pl.high-row", catalog: catalog)
        XCTAssertFalse(sameFormat)
        XCTAssertEqual(data.workouts[0].exercises[0].sets.map { $0.weight }, [50, 50])

        let changed = data.changeHistoryEquipment(workoutID: w.id, entryID: w.exercises[0].id, to: primeRow, catalog: catalog)
        XCTAssertTrue(changed)
        let sets = data.workouts[0].exercises[0].sets
        XCTAssertEqual(sets.map { $0.reps }, [10, 9])
        XCTAssertTrue(sets.allSatisfy { $0.isCompleted && $0.weight == nil })
    }

    func testHandednessSupport() {
        XCTAssertTrue(catalog.definition(primeRow).supportsHandedness, "背部挂片也能单双手")
        XCTAssertTrue(catalog.definition("nautilus.sel.lat-pulldown").supportsHandedness)
        XCTAssertTrue(catalog.definition(pushdown).supportsHandedness)
        XCTAssertTrue(catalog.definition(lateral).supportsHandedness)
        XCTAssertFalse(catalog.definition("gen.db.curl").supportsHandedness, "手臂只有绳索动作可切换")
        XCTAssertFalse(catalog.definition(chestPress).supportsHandedness)
        XCTAssertFalse(catalog.definition("nautilus.sel.leg-extension").supportsHandedness)
    }

    func testRestDurationDependsOnHandedness() {
        var data = AppData()
        data.settings.defaultRestSeconds = 90
        data.settings.unilateralRestSeconds = 150
        let now = Date()
        data.startWorkout(muscles: [], catalog: catalog, now: now)
        let id = data.addExercise(pushdown, catalog: catalog, now: now)!
        data.setHandedness(entryID: id, .unilateral, now: now)
        let setID = data.activeWorkout!.exercises[0].sets[0].id
        data.updateActiveSet(entryID: id, setID: setID, now: now) { $0.weight = 20; $0.reps = 12 }
        XCTAssertEqual(data.completeSet(entryID: id, setID: setID, catalog: catalog, now: now), 150)
        XCTAssertEqual(data.activeWorkout?.restTimer?.setID, setID)

        data.settings.exerciseRestOverrides[AppSettings.overrideKey(exerciseID: pushdown, handedness: .unilateral)] = 60
        XCTAssertEqual(data.settings.restSeconds(exerciseID: pushdown, handedness: .unilateral), 60)
        XCTAssertEqual(data.settings.restSeconds(exerciseID: pushdown, handedness: .bilateral), 90)
    }

    func testPrimeLoadComparison() {
        let prev = SetEntry(primeLoad: PrimeLoad(20, 10, nil), plateBasis: .perSide, reps: 10, isCompleted: true)
        let heavier = SetEntry(primeLoad: PrimeLoad(20, 15, nil), plateBasis: .perSide, reps: 10)
        let moved = SetEntry(primeLoad: PrimeLoad(10, 20, nil), plateBasis: .perSide, reps: 10)
        XCTAssertEqual(LoadChange.compare(heavier, to: prev, format: .primeThreePosition), .heavier(5))
        XCTAssertEqual(LoadChange.compare(moved, to: prev, format: .primeThreePosition), .redistributed)
        XCTAssertEqual(PrimeLoad(20, 10, 5).total, 35)
    }

    func testBackupMergeDoesNotOverwriteNewerLocalEdits() throws {
        var data = AppData()
        finishedWorkout(&data, muscles: [.chest], at: date("2026-10-01 10:00"), [(chestPress, [(45, 10)])])
        let backup = try BackupCodec.decode(BackupCodec.encode(data))
        let id = data.workouts[0].id
        data.updateWorkout(id, now: Date().addingTimeInterval(60)) { $0.customTitle = "改过" }
        let (merged, report) = BackupCodec.merge(current: data, imported: backup)
        XCTAssertEqual(merged.workouts.count, 1)
        XCTAssertEqual(merged.workouts[0].customTitle, "改过")
        XCTAssertEqual(report.skipped, 1)

        let (fresh, report2) = BackupCodec.merge(current: AppData(), imported: backup)
        XCTAssertEqual(fresh.workouts.count, 1)
        XCTAssertEqual(report2.added, 1)
    }
}

extension FinishResult {
    var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }
}
