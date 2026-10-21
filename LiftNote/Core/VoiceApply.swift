import Foundation

struct VoiceApplyResult: Equatable {
    var entryID: UUID
    var completedSetIDs: [UUID]
    var pendingSetIDs: [UUID]
    var restSeconds: Int?
}

extension AppData {
    /// 把语音确认卡片里的组写入进行中的训练。
    /// - 数据完整的组记为完成；
    /// - `keepIncomplete` 为 true（"加入训练，稍后填写"）时，没填完的组也留在训练里待填；
    /// - 说了"第 N 组"就写到该动作的第 N 组，否则依次填进还没完成的组，不够再追加；
    /// - 只补充说到的字段，不清掉已有输入。
    @discardableResult
    mutating func applyVoice(exerciseID: String, handedness: Handedness?, plateBasis: PlateBasis?,
                             sets parsed: [VoiceParsedSet], keepIncomplete: Bool, targetEntryID: UUID? = nil,
                             catalog: ExerciseCatalog, now: Date = Date()) -> VoiceApplyResult? {
        guard var w = activeWorkout else { return nil }
        let def = catalog.definition(exerciseID)
        let hand: Handedness? = def.supportsHandedness ? (handedness ?? .bilateral) : nil
        let effectiveHand = hand ?? .bilateral
        let basis = plateBasis ?? lastPlateBasis(exerciseID: exerciseID)

        var entryIndex: Int? = nil
        if let t = targetEntryID, let i = w.entryIndex(t), w.exercises[i].exerciseID == exerciseID,
           w.exercises[i].effectiveHandedness == effectiveHand {
            entryIndex = i
        }
        if entryIndex == nil {
            entryIndex = w.exercises.lastIndex { e in
                e.exerciseID == exerciseID && e.effectiveHandedness == effectiveHand && e.sets.contains { !$0.isCompleted }
            }
        }
        let isNewEntry = entryIndex == nil
        let ei: Int
        if let entryIndex {
            ei = entryIndex
        } else {
            w.exercises.append(ExerciseEntry(exerciseID: exerciseID, handedness: hand, sets: []))
            ei = w.exercises.count - 1
        }

        var completed: [UUID] = []
        var pending: [UUID] = []

        for p in parsed {
            var candidate = SetEntry()
            candidate.weight = p.weight
            candidate.primeLoad = p.primeLoad
            candidate.reps = p.reps
            candidate.quality = p.quality
            if def.loadFormat == .primeThreePosition {
                candidate.plateBasis = basis
                // PRIME 只说了一个重量：当作 1 号位
                if candidate.primeLoad == nil, let wgt = candidate.weight {
                    candidate.primeLoad = PrimeLoad(wgt, nil, nil)
                    candidate.weight = nil
                }
            }

            // 找写入位置
            var target: Int? = nil
            if let n = p.ordinal, n >= 1, n - 1 < w.exercises[ei].sets.count {
                target = n - 1
            } else if p.ordinal == nil {
                target = w.exercises[ei].sets.firstIndex { !$0.isCompleted && !completed.contains($0.id) && !pending.contains($0.id) }
            }

            var merged: SetEntry
            if let t = target {
                merged = w.exercises[ei].sets[t]
                if let v = candidate.weight { merged.weight = v }
                if let v = candidate.primeLoad { merged.primeLoad = v }
                if let v = candidate.plateBasis { merged.plateBasis = v }
                if let v = candidate.reps { merged.reps = v }
                if let v = candidate.quality { merged.quality = v }
            } else {
                merged = candidate
            }

            let loggable = merged.isLoggable(for: def)
            guard loggable || keepIncomplete else { continue }
            if loggable {
                merged.isCompleted = true
                merged.completedAt = merged.completedAt ?? now
                completed.append(merged.id)
            } else {
                pending.append(merged.id)
            }
            if let t = target {
                w.exercises[ei].sets[t] = merged
            } else {
                w.exercises[ei].sets.append(merged)
            }
        }

        // 只说了动作：按默认组数加空组
        if isNewEntry && w.exercises[ei].sets.isEmpty {
            guard keepIncomplete else { return nil }
            let count = max(1, settings.defaultSetsPerExercise)
            for _ in 0..<count {
                let s = SetEntry(plateBasis: def.loadFormat == .primeThreePosition ? basis : nil)
                w.exercises[ei].sets.append(s)
                pending.append(s.id)
            }
        }

        var rest: Int? = nil
        if let last = completed.last, settings.restTimerEnabled {
            let seconds = settings.restSeconds(exerciseID: exerciseID, handedness: effectiveHand)
            if seconds > 0 {
                rest = seconds
                w.restTimer = RestTimerState(entryID: w.exercises[ei].id, setID: last, startedAt: now,
                                             endsAt: now.addingTimeInterval(TimeInterval(seconds)))
            }
        }
        w.updatedAt = now
        activeWorkout = w
        return VoiceApplyResult(entryID: w.exercises[ei].id, completedSetIDs: completed, pendingSetIDs: pending, restSeconds: rest)
    }
}
