import Foundation

/// 上次同一器械（同一单双手方式）做过的组。
struct PreviousPerformance: Hashable {
    var workoutID: UUID
    var date: Date
    var sets: [SetEntry]
}

enum FinishResult: Equatable {
    case finished(UUID)
    /// 没有完成任何组：只能放弃
    case nothingCompleted
    case noActiveWorkout
}

// MARK: - 标题

extension Workout {
    /// 自动标题包含：开始时选的部位 + 训练中实际做了（至少完成一组）的动作的直接训练部位。
    func titleMuscles(catalog: ExerciseCatalog) -> [MuscleGroup] {
        var set = Set(selectedMuscles)
        for entry in exercises where entry.hasCompletedSets {
            set.formUnion(catalog.definition(entry.exerciseID).primary)
        }
        return MuscleGroup.sorted(set)
    }

    func autoTitle(catalog: ExerciseCatalog) -> String {
        let muscles = titleMuscles(catalog: catalog)
        return muscles.isEmpty ? "训练" : muscles.map { $0.displayName }.joined(separator: " · ")
    }

    func title(catalog: ExerciseCatalog) -> String {
        if let t = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return autoTitle(catalog: catalog)
    }

    func entryIndex(_ id: UUID) -> Int? { exercises.firstIndex { $0.id == id } }
}

// MARK: - 历史查询

extension AppData {
    var workoutsNewestFirst: [Workout] { workouts.sorted { $0.startedAt > $1.startedAt } }

    /// 查找某器械在 `date` 之前最近一次训练里完成的组（同一次训练里分成多段的会合并）。
    func previousPerformance(exerciseID: String, handedness: Handedness, before date: Date, excluding: UUID? = nil) -> PreviousPerformance? {
        for w in workoutsNewestFirst where w.startedAt < date && w.id != excluding {
            let sets = w.exercises
                .filter { $0.exerciseID == exerciseID && $0.effectiveHandedness == handedness }
                .flatMap { $0.completedSets }
            if !sets.isEmpty {
                return PreviousPerformance(workoutID: w.id, date: w.startedAt, sets: sets)
            }
        }
        return nil
    }

    /// 某个部位最近一次练的时间和动作数（新训练选部位时显示）。
    func lastSession(for muscle: MuscleGroup, catalog: ExerciseCatalog) -> (date: Date, exerciseCount: Int)? {
        for w in workoutsNewestFirst {
            let n = w.exercises.filter { $0.hasCompletedSets && catalog.definition($0.exerciseID).primary.contains(muscle) }.count
            if n > 0 { return (w.startedAt, n) }
        }
        return nil
    }

    /// 根据选的部位，从每个部位最近一次训练复制动作，组数与上次相同（默认 2 组），数值留空待填。
    func templateEntries(for muscles: [MuscleGroup], catalog: ExerciseCatalog) -> [ExerciseEntry] {
        var result: [ExerciseEntry] = []
        var seen = Set<String>()
        let history = workoutsNewestFirst
        for muscle in MuscleGroup.sorted(muscles) {
            guard let source = history.first(where: { w in
                w.exercises.contains { $0.hasCompletedSets && catalog.definition($0.exerciseID).primary.contains(muscle) }
            }) else { continue }
            for entry in source.exercises where entry.hasCompletedSets {
                let def = catalog.definition(entry.exerciseID)
                guard def.primary.contains(muscle) else { continue }
                let key = "\(entry.exerciseID)|\(entry.effectiveHandedness.rawValue)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                // 同一次训练中可能分成多段（换器械再换回来），合并全部完成组
                let done = source.exercises
                    .filter { $0.exerciseID == entry.exerciseID && $0.effectiveHandedness == entry.effectiveHandedness }
                    .flatMap { $0.completedSets }
                let sets = done.map { SetEntry(kind: $0.kind, plateBasis: $0.plateBasis) }
                result.append(ExerciseEntry(exerciseID: entry.exerciseID,
                                            handedness: def.supportsHandedness ? entry.effectiveHandedness : nil,
                                            sets: sets.isEmpty ? [SetEntry()] : sets))
            }
        }
        return result
    }

    // MARK: - 进行中的训练

    mutating func startWorkout(muscles: [MuscleGroup], catalog: ExerciseCatalog, now: Date = Date()) {
        activeWorkout = Workout(startedAt: now,
                                selectedMuscles: MuscleGroup.sorted(muscles),
                                exercises: templateEntries(for: muscles, catalog: catalog),
                                updatedAt: now)
    }

    mutating func discardActiveWorkout() {
        activeWorkout = nil
    }

    mutating func updateActive(now: Date = Date(), _ body: (inout Workout) -> Void) {
        guard var w = activeWorkout else { return }
        body(&w)
        w.updatedAt = now
        activeWorkout = w
    }

    @discardableResult
    mutating func addExercise(_ exerciseID: String, catalog: ExerciseCatalog, setCount: Int? = nil, now: Date = Date()) -> UUID? {
        guard activeWorkout != nil else { return nil }
        let def = catalog.definition(exerciseID)
        let basis = lastPlateBasis(exerciseID: exerciseID)
        let count = max(1, setCount ?? settings.defaultSetsPerExercise)
        let entry = ExerciseEntry(exerciseID: exerciseID,
                                  handedness: def.supportsHandedness ? .bilateral : nil,
                                  sets: (0..<count).map { _ in SetEntry(plateBasis: basis) })
        updateActive(now: now) { $0.exercises.append(entry) }
        return entry.id
    }

    /// 上次这个 PRIME 挂片器械用的挂片基准，新组沿用。
    func lastPlateBasis(exerciseID: String) -> PlateBasis? {
        for w in workoutsNewestFirst {
            for e in w.exercises where e.exerciseID == exerciseID {
                if let b = e.sets.last(where: { $0.plateBasis != nil })?.plateBasis { return b }
            }
        }
        return nil
    }

    /// 训练中更换器械：已完成的组留在原器械下，未完成的组换到新器械。
    @discardableResult
    mutating func swapEquipment(entryID: UUID, to newExerciseID: String, catalog: ExerciseCatalog, now: Date = Date()) -> UUID? {
        guard let w = activeWorkout, let idx = w.entryIndex(entryID) else { return nil }
        let old = w.exercises[idx]
        let def = catalog.definition(newExerciseID)
        let basis = lastPlateBasis(exerciseID: newExerciseID)
        let handedness: Handedness? = def.supportsHandedness ? old.effectiveHandedness : nil
        let pending = old.sets.filter { !$0.isCompleted }
        let pendingCount = max(1, pending.count)
        let freshSets = (0..<pendingCount).map { i -> SetEntry in
            SetEntry(kind: i < pending.count ? pending[i].kind : .working, plateBasis: basis)
        }
        var newID = old.id
        updateActive(now: now) { w in
            if old.hasCompletedSets {
                w.exercises[idx].sets = old.completedSets
                let entry = ExerciseEntry(exerciseID: newExerciseID, handedness: handedness, sets: freshSets)
                newID = entry.id
                w.exercises.insert(entry, at: idx + 1)
            } else {
                w.exercises[idx].exerciseID = newExerciseID
                w.exercises[idx].handedness = handedness
                w.exercises[idx].sets = freshSets
            }
            if let t = w.restTimer, t.entryID == old.id, !old.hasCompletedSets { w.restTimer = nil }
        }
        return newID
    }

    /// 完成一组。返回应开始的休息秒数（数据不完整或设置关闭时为 nil）。
    @discardableResult
    mutating func completeSet(entryID: UUID, setID: UUID, catalog: ExerciseCatalog, now: Date = Date()) -> Int? {
        guard let w = activeWorkout, let ei = w.entryIndex(entryID),
              let si = w.exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return nil }
        let entry = w.exercises[ei]
        let def = catalog.definition(entry.exerciseID)
        guard entry.sets[si].isLoggable(for: def) else { return nil }
        let rest = settings.restSeconds(exerciseID: entry.exerciseID, handedness: entry.effectiveHandedness)
        let startsRest = settings.restTimerEnabled && rest > 0
        updateActive(now: now) { w in
            w.exercises[ei].sets[si].isCompleted = true
            w.exercises[ei].sets[si].completedAt = now
            if startsRest {
                w.restTimer = RestTimerState(entryID: entryID, setID: setID, startedAt: now,
                                             endsAt: now.addingTimeInterval(TimeInterval(rest)))
            }
        }
        return startsRest ? rest : nil
    }

    mutating func uncompleteSet(entryID: UUID, setID: UUID, now: Date = Date()) {
        updateActive(now: now) { w in
            guard let ei = w.entryIndex(entryID),
                  let si = w.exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
            w.exercises[ei].sets[si].isCompleted = false
            w.exercises[ei].sets[si].completedAt = nil
            if w.restTimer?.setID == setID { w.restTimer = nil }
        }
    }

    mutating func addSet(entryID: UUID, kind: SetKind = .working, now: Date = Date()) {
        updateActive(now: now) { w in
            guard let ei = w.entryIndex(entryID) else { return }
            let basis = w.exercises[ei].sets.last(where: { $0.plateBasis != nil })?.plateBasis
            let set = SetEntry(kind: kind, plateBasis: basis)
            if kind == .warmup {
                let firstWorking = w.exercises[ei].sets.firstIndex { $0.kind == .working } ?? w.exercises[ei].sets.count
                w.exercises[ei].sets.insert(set, at: firstWorking)
            } else {
                w.exercises[ei].sets.append(set)
            }
        }
    }

    /// 删除一组。删掉最后一组时保留动作，方便继续加组。
    mutating func deleteActiveSet(entryID: UUID, setID: UUID, now: Date = Date()) {
        updateActive(now: now) { w in
            guard let ei = w.entryIndex(entryID) else { return }
            w.exercises[ei].sets.removeAll { $0.id == setID }
            if w.restTimer?.setID == setID { w.restTimer = nil }
        }
    }

    mutating func removeActiveExercise(entryID: UUID, now: Date = Date()) {
        updateActive(now: now) { w in
            w.exercises.removeAll { $0.id == entryID }
            if w.restTimer?.entryID == entryID { w.restTimer = nil }
        }
    }

    mutating func moveActiveExercise(entryID: UUID, by offset: Int, now: Date = Date()) {
        updateActive(now: now) { w in
            guard let i = w.entryIndex(entryID) else { return }
            let j = i + offset
            guard j >= 0 && j < w.exercises.count else { return }
            w.exercises.swapAt(i, j)
        }
    }

    mutating func setHandedness(entryID: UUID, _ handedness: Handedness, now: Date = Date()) {
        updateActive(now: now) { w in
            guard let i = w.entryIndex(entryID) else { return }
            w.exercises[i].handedness = handedness
        }
    }

    mutating func setPlateBasis(entryID: UUID, _ basis: PlateBasis, now: Date = Date()) {
        updateActive(now: now) { w in
            guard let i = w.entryIndex(entryID) else { return }
            for s in w.exercises[i].sets.indices { w.exercises[i].sets[s].plateBasis = basis }
        }
    }

    mutating func updateActiveSet(entryID: UUID, setID: UUID, now: Date = Date(), _ body: (inout SetEntry) -> Void) {
        updateActive(now: now) { w in
            guard let ei = w.entryIndex(entryID),
                  let si = w.exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
            body(&w.exercises[ei].sets[si])
        }
    }

    /// 结束训练：未完成的组和空动作不保存。一组都没完成时不保存，提示放弃。
    @discardableResult
    mutating func finishActiveWorkout(now: Date = Date()) -> FinishResult {
        guard var w = activeWorkout else { return .noActiveWorkout }
        guard w.completedSetCount > 0 else { return .nothingCompleted }
        for i in w.exercises.indices {
            w.exercises[i].sets = w.exercises[i].completedSets
        }
        w.exercises.removeAll { $0.sets.isEmpty }
        w.endedAt = now
        w.restTimer = nil
        w.updatedAt = now
        workouts.append(w)
        activeWorkout = nil
        return .finished(w.id)
    }

    // MARK: - 历史编辑

    func workout(_ id: UUID) -> Workout? { workouts.first { $0.id == id } }

    mutating func updateWorkout(_ id: UUID, now: Date = Date(), _ body: (inout Workout) -> Void) {
        guard let i = workouts.firstIndex(where: { $0.id == id }) else { return }
        body(&workouts[i])
        workouts[i].updatedAt = now
    }

    mutating func deleteWorkout(_ id: UUID) {
        workouts.removeAll { $0.id == id }
    }

    /// 修改训练开始时间，时长不变。
    mutating func changeWorkoutDate(_ id: UUID, to newStart: Date, now: Date = Date()) {
        updateWorkout(id, now: now) { w in
            let duration = w.duration
            w.startedAt = newStart
            if let duration { w.endedAt = newStart.addingTimeInterval(duration) }
        }
    }

    mutating func updateHistorySet(workoutID: UUID, entryID: UUID, setID: UUID, now: Date = Date(), _ body: (inout SetEntry) -> Void) {
        updateWorkout(workoutID, now: now) { w in
            guard let ei = w.entryIndex(entryID),
                  let si = w.exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { return }
            body(&w.exercises[ei].sets[si])
        }
    }

    /// 删除历史中的一组；动作没有组了就一起删掉。
    mutating func deleteHistorySet(workoutID: UUID, entryID: UUID, setID: UUID, now: Date = Date()) {
        updateWorkout(workoutID, now: now) { w in
            guard let ei = w.entryIndex(entryID) else { return }
            w.exercises[ei].sets.removeAll { $0.id == setID }
            if w.exercises[ei].sets.isEmpty { w.exercises.remove(at: ei) }
        }
    }

    mutating func deleteHistoryExercise(workoutID: UUID, entryID: UUID, now: Date = Date()) {
        updateWorkout(workoutID, now: now) { w in
            w.exercises.removeAll { $0.id == entryID }
        }
    }

    /// 补记一组（历史中的组都是已完成的）。
    mutating func addHistorySet(workoutID: UUID, entryID: UUID, set: SetEntry, now: Date = Date()) {
        updateWorkout(workoutID, now: now) { w in
            guard let ei = w.entryIndex(entryID) else { return }
            var s = set
            s.isCompleted = true
            if s.completedAt == nil { s.completedAt = w.endedAt ?? w.startedAt }
            w.exercises[ei].sets.append(s)
        }
    }

    mutating func addHistoryExercise(workoutID: UUID, exerciseID: String, catalog: ExerciseCatalog, now: Date = Date()) -> UUID? {
        guard workout(workoutID) != nil else { return nil }
        let def = catalog.definition(exerciseID)
        let entry = ExerciseEntry(exerciseID: exerciseID, handedness: def.supportsHandedness ? .bilateral : nil, sets: [])
        updateWorkout(workoutID, now: now) { $0.exercises.append(entry) }
        return entry.id
    }

    /// 历史中修改登记错的器械：保留组、次数、质量和时间。
    /// 重量格式不同（普通 ↔ PRIME 三挂片位）时清空重量，返回 true 表示需要重新确认重量。
    @discardableResult
    mutating func changeHistoryEquipment(workoutID: UUID, entryID: UUID, to newExerciseID: String, catalog: ExerciseCatalog, now: Date = Date()) -> Bool {
        guard let w = workout(workoutID), let ei = w.entryIndex(entryID) else { return false }
        let oldDef = catalog.definition(w.exercises[ei].exerciseID)
        let newDef = catalog.definition(newExerciseID)
        let formatChanged = oldDef.loadFormat != newDef.loadFormat
        updateWorkout(workoutID, now: now) { w in
            w.exercises[ei].exerciseID = newExerciseID
            w.exercises[ei].handedness = newDef.supportsHandedness ? w.exercises[ei].effectiveHandedness : nil
            if formatChanged {
                for s in w.exercises[ei].sets.indices {
                    w.exercises[ei].sets[s].weight = nil
                    w.exercises[ei].sets[s].primeLoad = nil
                    w.exercises[ei].sets[s].plateBasis = nil
                }
            }
        }
        return formatChanged
    }

    mutating func setHistoryHandedness(workoutID: UUID, entryID: UUID, _ handedness: Handedness, now: Date = Date()) {
        updateWorkout(workoutID, now: now) { w in
            guard let ei = w.entryIndex(entryID) else { return }
            w.exercises[ei].handedness = handedness
        }
    }

    // MARK: - 动作历史（横向笔记本）

    struct NotebookKey: Hashable {
        var exerciseID: String
        var handedness: Handedness
    }

    /// 做过的器械（最近用过的排前面）。
    func notebookKeys() -> [NotebookKey] {
        var seen = Set<NotebookKey>()
        var result: [NotebookKey] = []
        for w in workoutsNewestFirst {
            for e in w.exercises where e.hasCompletedSets {
                let k = NotebookKey(exerciseID: e.exerciseID, handedness: e.effectiveHandedness)
                if seen.insert(k).inserted { result.append(k) }
            }
        }
        return result
    }

    /// 某器械历次训练（旧 → 新），每次合并该次所有完成组。
    func notebookSessions(_ key: NotebookKey) -> [PreviousPerformance] {
        workouts.sorted { $0.startedAt < $1.startedAt }.compactMap { w in
            let sets = w.exercises
                .filter { $0.exerciseID == key.exerciseID && $0.effectiveHandedness == key.handedness }
                .flatMap { $0.completedSets }
            return sets.isEmpty ? nil : PreviousPerformance(workoutID: w.id, date: w.startedAt, sets: sets)
        }
    }
}

// MARK: - 和上次比较（与质量箭头分开显示）

enum LoadChange: Hashable {
    case heavier(Double)
    case lighter(Double)
    case moreReps(Int)
    case fewerReps(Int)
    /// PRIME 挂片位分配变了，不能简单判断进步/退步
    case redistributed
    case same

    var label: String? {
        switch self {
        case .heavier(let d): return "+\(WeightFormat.kg(d))kg"
        case .lighter(let d): return "−\(WeightFormat.kg(d))kg"
        case .moreReps(let n): return "+\(n)次"
        case .fewerReps(let n): return "−\(n)次"
        case .redistributed: return "分配改变"
        case .same: return nil
        }
    }

    var isImprovement: Bool {
        switch self {
        case .heavier, .moreReps: return true
        default: return false
        }
    }

    static func compare(_ current: SetEntry, to previous: SetEntry?, format: LoadFormat) -> LoadChange? {
        guard let previous, let reps = current.reps else { return nil }
        let prevReps = previous.reps ?? 0
        switch format {
        case .primeThreePosition:
            guard let cur = current.primeLoad, let prev = previous.primeLoad else { return nil }
            if current.plateBasis != previous.plateBasis { return .redistributed }
            let a = cur.normalized, b = prev.normalized
            if a == b { return repsChange(reps, prevReps) }
            let allUp = zip(a, b).allSatisfy { pair in pair.0 >= pair.1 }
            let allDown = zip(a, b).allSatisfy { pair in pair.0 <= pair.1 }
            if allUp { return .heavier(cur.total - prev.total) }
            if allDown { return .lighter(prev.total - cur.total) }
            return .redistributed
        case .standard:
            let w = current.weight ?? 0, pw = previous.weight ?? 0
            if w > pw { return .heavier(w - pw) }
            if w < pw { return .lighter(pw - w) }
            return repsChange(reps, prevReps)
        }
    }

    private static func repsChange(_ reps: Int, _ prev: Int) -> LoadChange {
        if reps > prev { return .moreReps(reps - prev) }
        if reps < prev { return .fewerReps(prev - reps) }
        return .same
    }
}

// MARK: - 显示格式

enum WeightFormat {
    static func kg(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        var s = String(format: "%.2f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    static func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty else { return nil }
        return Double(t)
    }

    /// 例："45×10"、"20/10/– ×10"
    static func setSummary(_ s: SetEntry, format: LoadFormat) -> String {
        let reps = s.reps.map(String.init) ?? "–"
        switch format {
        case .primeThreePosition:
            let p = s.primeLoad ?? PrimeLoad()
            let parts = (0..<3).map { i -> String in
                if let v = p[i], v > 0 { return kg(v) }
                return "–"
            }
            return "\(parts.joined(separator: "/"))×\(reps)"
        case .standard:
            if let w = s.weight { return "\(kg(w))×\(reps)" }
            return "\(reps)次"
        }
    }

    static func duration(_ t: TimeInterval) -> String {
        let total = max(0, Int(t.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
