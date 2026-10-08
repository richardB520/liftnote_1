import Foundation

struct MergeReport: Equatable {
    var added = 0
    var updated = 0
    var skipped = 0
    var customExercisesAdded = 0

    var summary: String {
        "新增 \(added) 次训练，更新 \(updated) 次，保留本机较新的 \(skipped) 次，新增自定义器械 \(customExercisesAdded) 个"
    }
}

enum BackupCodec {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func encode(_ data: AppData) throws -> Data {
        try encoder().encode(data)
    }

    static func decode(_ bytes: Data) throws -> AppData {
        try JSONDecoder().decode(AppData.self, from: bytes)
    }

    /// 导入备份：按训练 id 合并，只有备份里的版本更新时才覆盖，重复导入不会覆盖之后在本机的修改。
    static func merge(current: AppData, imported: AppData) -> (AppData, MergeReport) {
        var result = current
        var report = MergeReport()
        for w in imported.workouts {
            if let i = result.workouts.firstIndex(where: { $0.id == w.id }) {
                if w.updatedAt > result.workouts[i].updatedAt {
                    result.workouts[i] = w
                    report.updated += 1
                } else {
                    report.skipped += 1
                }
            } else {
                result.workouts.append(w)
                report.added += 1
            }
        }
        for d in imported.customExercises where !result.customExercises.contains(where: { $0.id == d.id }) {
            result.customExercises.append(d)
            report.customExercisesAdded += 1
        }
        if result.activeWorkout == nil, let active = imported.activeWorkout,
           !result.workouts.contains(where: { $0.id == active.id }) {
            var restored = active
            restored.restTimer = nil
            result.activeWorkout = restored
        }
        return (result, report)
    }
}
