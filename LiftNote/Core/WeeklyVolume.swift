import Foundation

/// 计入某肌群周组数的一组，用于点开部位追溯具体组。
struct VolumeContribution: Identifiable, Hashable {
    var id: String { "\(workoutID)-\(setID)" }
    var workoutID: UUID
    var entryID: UUID
    var setID: UUID
    var date: Date
    var exerciseID: String
    var setNumber: Int
    var set: SetEntry
    var isInProgress: Bool
}

struct WeeklyVolume: Hashable {
    var week: DateInterval
    var counts: [MuscleGroup: Int]
    var contributions: [MuscleGroup: [VolumeContribution]]

    func count(_ m: MuscleGroup) -> Int { counts[m] ?? 0 }

    enum Status { case below, inRange, above }

    func status(_ m: MuscleGroup, settings: AppSettings) -> Status {
        let n = count(m)
        if n < settings.weeklyTargetMin { return .below }
        if n > settings.weeklyTargetMax { return .above }
        return .inRange
    }

    /// 周一为一周的开始，按手机当地日历（含夏令时）计算。
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    static func week(containing date: Date, calendar: Calendar = WeeklyVolume.calendar) -> DateInterval {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: date) { return interval }
        let start = calendar.startOfDay(for: date)
        return DateInterval(start: start, duration: 7 * 86400)
    }

    static func week(offset: Int, from date: Date, calendar: Calendar = WeeklyVolume.calendar) -> DateInterval {
        let base = week(containing: date, calendar: calendar)
        let shifted = calendar.date(byAdding: .weekOfYear, value: offset, to: base.start) ?? base.start
        return week(containing: shifted, calendar: calendar)
    }

    /// 只统计已完成的工作组；热身组、未完成的组不计。每组给动作的每个直接训练肌群各算 1 组。
    static func compute(data: AppData, week: DateInterval, catalog: ExerciseCatalog) -> WeeklyVolume {
        var counts: [MuscleGroup: Int] = [:]
        var contributions: [MuscleGroup: [VolumeContribution]] = [:]
        var all = data.workouts.map { ($0, false) }
        if let active = data.activeWorkout { all.append((active, true)) }
        for (w, inProgress) in all.sorted(by: { $0.0.startedAt < $1.0.startedAt }) {
            guard w.startedAt >= week.start && w.startedAt < week.end else { continue }
            for entry in w.exercises {
                let def = catalog.definition(entry.exerciseID)
                var number = 0
                for s in entry.sets {
                    if s.kind == .working { number += 1 }
                    guard s.countsAsWorkingSet else { continue }
                    for m in def.primary {
                        counts[m, default: 0] += 1
                        contributions[m, default: []].append(
                            VolumeContribution(workoutID: w.id, entryID: entry.id, setID: s.id, date: s.completedAt ?? w.startedAt,
                                               exerciseID: entry.exerciseID, setNumber: number, set: s, isInProgress: inProgress))
                    }
                }
            }
        }
        return WeeklyVolume(week: week, counts: counts, contributions: contributions)
    }
}
