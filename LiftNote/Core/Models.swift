import Foundation

// MARK: - 肌群

/// 每周统计的七个肌群。肩前束、肩后束不单独统计。
enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Hashable {
    case chest
    case back
    case quads
    case hamstrings
    case biceps
    case triceps
    case sideDelts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "胸"
        case .back: return "背"
        case .quads: return "腿前侧"
        case .hamstrings: return "腿后侧"
        case .biceps: return "二头"
        case .triceps: return "三头"
        case .sideDelts: return "肩中束"
        }
    }

    var detail: String {
        switch self {
        case .chest: return "胸大肌"
        case .back: return "背阔肌 · 上背"
        case .quads: return "股四头肌"
        case .hamstrings: return "腘绳肌 · 臀"
        case .biceps: return "肱二头肌"
        case .triceps: return "肱三头肌"
        case .sideDelts: return "三角肌中束"
        }
    }

    var sortIndex: Int { MuscleGroup.allCases.firstIndex(of: self) ?? 0 }

    static func sorted<S: Sequence>(_ muscles: S) -> [MuscleGroup] where S.Element == MuscleGroup {
        Array(Set(muscles)).sorted { $0.sortIndex < $1.sortIndex }
    }
}

// MARK: - 器械

enum Brand: String, Codable, CaseIterable, Identifiable, Hashable {
    case nautilus
    case prime
    case atlantis
    case hammerStrength
    case generic
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nautilus: return "诺德士 Nautilus"
        case .prime: return "PRIME"
        case .atlantis: return "Atlantis"
        case .hammerStrength: return "Hammer Strength"
        case .generic: return "自由重量 / 通用"
        case .custom: return "自定义"
        }
    }

    var shortName: String {
        switch self {
        case .nautilus: return "诺德士"
        case .prime: return "PRIME"
        case .atlantis: return "Atlantis"
        case .hammerStrength: return "Hammer"
        case .generic: return ""
        case .custom: return ""
        }
    }

    /// 语音和搜索中可能出现的叫法（已小写、无空格）。
    var spokenAliases: [String] {
        switch self {
        case .nautilus: return ["诺德士", "诺德斯", "诺得士", "罗德士", "nautilus", "鹦鹉螺"]
        case .prime: return ["prime", "普莱姆", "普瑞姆", "普莱玛", "派姆"]
        case .atlantis: return ["atlantis", "亚特兰蒂斯", "阿特兰蒂斯", "亚特兰"]
        case .hammerStrength: return ["hammerstrength", "hammer", "悍马", "汉默", "锤力", "哈默"]
        case .generic: return []
        case .custom: return []
        }
    }
}

enum EquipmentKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case plateLoaded
    case selectorized
    case cable
    case barbell
    case dumbbell
    case smith
    case bodyweight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plateLoaded: return "挂片"
        case .selectorized: return "插片"
        case .cable: return "绳索"
        case .barbell: return "杠铃"
        case .dumbbell: return "哑铃"
        case .smith: return "史密斯"
        case .bodyweight: return "自重"
        }
    }

    var spokenAliases: [String] {
        switch self {
        case .plateLoaded: return ["挂片", "挂铃片", "片式"]
        case .selectorized: return ["插片", "插销", "配重片"]
        case .cable: return ["绳索", "龙门架", "拉索", "缆绳"]
        case .barbell: return ["杠铃"]
        case .dumbbell: return ["哑铃"]
        case .smith: return ["史密斯"]
        case .bodyweight: return ["自重", "徒手"]
        }
    }
}

/// 重量记录方式：普通单一重量，或 PRIME 挂片器械的 1/2/3 号挂片位。
enum LoadFormat: String, Codable, Hashable {
    case standard
    case primeThreePosition
}

/// PRIME 挂片重量的基准。
enum PlateBasis: String, Codable, CaseIterable, Identifiable, Hashable {
    /// 左右两侧挂相同重量，记录的是每一侧
    case perSide
    /// 只有一组三根杆，两边共用
    case shared

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .perSide: return "每侧"
        case .shared: return "共用"
        }
    }
}

/// 单手轮流 / 双手一起。单手轮流时左右各做完算一组，次数填每侧次数。
enum Handedness: String, Codable, CaseIterable, Identifiable, Hashable {
    case bilateral
    case unilateral

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bilateral: return "双手"
        case .unilateral: return "单手轮流"
        }
    }
}

struct ExerciseDefinition: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var brand: Brand
    /// 系列 / 型号；自定义器械时也可写品牌名
    var series: String
    var kind: EquipmentKind
    /// 直接训练、计入每周组数的肌群
    var primary: [MuscleGroup]
    /// 间接参与，不计入组数
    var secondary: [MuscleGroup]
    var aliases: [String]
    var isCustom: Bool

    init(id: String, name: String, brand: Brand, series: String, kind: EquipmentKind,
         primary: [MuscleGroup], secondary: [MuscleGroup] = [], aliases: [String] = [], isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.brand = brand
        self.series = series
        self.kind = kind
        self.primary = primary
        self.secondary = secondary
        self.aliases = aliases
        self.isCustom = isCustom
    }

    var loadFormat: LoadFormat {
        (brand == .prime && kind == .plateLoaded) ? .primeThreePosition : .standard
    }

    /// 背部动作全部可切换单双手；手臂、肩中束只有绳索动作可切换；胸、腿不提供。
    var supportsHandedness: Bool {
        if primary.contains(.back) { return true }
        if kind == .cable && (primary.contains(.biceps) || primary.contains(.triceps) || primary.contains(.sideDelts)) {
            return true
        }
        return false
    }

    var displayName: String {
        let b = brand.shortName
        return b.isEmpty ? name : "\(b) \(name)"
    }

    /// 例："PRIME · 挂片 · Plate Loaded"
    var equipmentLabel: String {
        var parts: [String] = []
        if brand != .generic && brand != .custom { parts.append(brand.shortName) }
        parts.append(kind.displayName)
        if !series.isEmpty { parts.append(series) }
        return parts.joined(separator: " · ")
    }

    static func placeholder(id: String) -> ExerciseDefinition {
        ExerciseDefinition(id: id, name: "已删除的动作", brand: .custom, series: "", kind: .selectorized, primary: [])
    }
}

// MARK: - 训练记录

enum SetKind: String, Codable, Hashable {
    case working
    case warmup
}

/// 每组的质量变化：独立于重量和次数。
enum QualityMark: String, Codable, CaseIterable, Identifiable, Hashable {
    case better
    case same
    case worse

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .better: return "↑"
        case .same: return "→"
        case .worse: return "↓"
        }
    }

    var displayName: String {
        switch self {
        case .better: return "比上次好"
        case .same: return "和上次一样"
        case .worse: return "不如上次"
        }
    }
}

/// PRIME 挂片器械 1/2/3 号位各挂的重量（kg）。
struct PrimeLoad: Codable, Hashable {
    var positions: [Double?]

    init(_ p1: Double? = nil, _ p2: Double? = nil, _ p3: Double? = nil) {
        positions = [p1, p2, p3]
    }

    subscript(index: Int) -> Double? {
        get { index < positions.count ? positions[index] : nil }
        set {
            while positions.count <= index { positions.append(nil) }
            positions[index] = newValue
        }
    }

    var total: Double { positions.compactMap { $0 }.reduce(0, +) }

    var isEmpty: Bool { positions.allSatisfy { ($0 ?? 0) == 0 } }

    /// 用于比较挂片分配是否改变
    var normalized: [Double] { (0..<3).map { self[$0] ?? 0 } }
}

struct SetEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var kind: SetKind = .working
    var weight: Double? = nil
    var primeLoad: PrimeLoad? = nil
    var plateBasis: PlateBasis? = nil
    var reps: Int? = nil
    var quality: QualityMark? = nil
    var isCompleted: Bool = false
    var completedAt: Date? = nil

    var hasAnyData: Bool {
        weight != nil || reps != nil || quality != nil || !(primeLoad?.isEmpty ?? true)
    }

    /// 这一组的数据是否足够记为完成
    func isLoggable(for definition: ExerciseDefinition) -> Bool {
        guard let reps, reps > 0 else { return false }
        switch definition.loadFormat {
        case .primeThreePosition:
            return primeLoad != nil && plateBasis != nil
        case .standard:
            return definition.kind == .bodyweight || weight != nil
        }
    }

    var countsAsWorkingSet: Bool { isCompleted && kind == .working }
}

struct ExerciseEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var exerciseID: String
    var handedness: Handedness? = nil
    var sets: [SetEntry] = []
    var note: String = ""

    var effectiveHandedness: Handedness { handedness ?? .bilateral }

    var completedSets: [SetEntry] { sets.filter { $0.isCompleted } }

    var hasCompletedSets: Bool { sets.contains { $0.isCompleted } }
}

struct RestTimerState: Codable, Hashable {
    var entryID: UUID
    var setID: UUID
    var startedAt: Date
    var endsAt: Date

    var duration: TimeInterval { endsAt.timeIntervalSince(startedAt) }

    func remaining(at now: Date) -> TimeInterval { max(0, endsAt.timeIntervalSince(now)) }
}

struct Workout: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var startedAt: Date
    var endedAt: Date? = nil
    /// 开始时选的部位
    var selectedMuscles: [MuscleGroup] = []
    /// 手动改过的名称；为空时用自动标题
    var customTitle: String? = nil
    var notes: String = ""
    var exercises: [ExerciseEntry] = []
    var updatedAt: Date
    /// 只在进行中的训练里使用
    var restTimer: RestTimerState? = nil

    var completedSetCount: Int { exercises.reduce(0) { $0 + $1.completedSets.count } }

    var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }
}

// MARK: - 设置与总数据

struct AppSettings: Codable, Hashable {
    /// 常规 / 双手动作的组间休息（秒）
    var defaultRestSeconds: Int = 90
    /// 单手轮流动作的组间休息（秒）
    var unilateralRestSeconds: Int = 120
    /// 单个动作的休息时间，key = 动作 id + "|" + 单双手
    var exerciseRestOverrides: [String: Int] = [:]
    var restTimerEnabled: Bool = true
    var weeklyTargetMin: Int = 10
    var weeklyTargetMax: Int = 20
    var defaultSetsPerExercise: Int = 2

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults
        defaultRestSeconds = try c.decodeIfPresent(Int.self, forKey: .defaultRestSeconds) ?? d.defaultRestSeconds
        unilateralRestSeconds = try c.decodeIfPresent(Int.self, forKey: .unilateralRestSeconds) ?? d.unilateralRestSeconds
        exerciseRestOverrides = try c.decodeIfPresent([String: Int].self, forKey: .exerciseRestOverrides) ?? [:]
        restTimerEnabled = try c.decodeIfPresent(Bool.self, forKey: .restTimerEnabled) ?? d.restTimerEnabled
        weeklyTargetMin = try c.decodeIfPresent(Int.self, forKey: .weeklyTargetMin) ?? d.weeklyTargetMin
        weeklyTargetMax = try c.decodeIfPresent(Int.self, forKey: .weeklyTargetMax) ?? d.weeklyTargetMax
        defaultSetsPerExercise = try c.decodeIfPresent(Int.self, forKey: .defaultSetsPerExercise) ?? d.defaultSetsPerExercise
    }

    static let defaults = AppSettings()

    static func overrideKey(exerciseID: String, handedness: Handedness) -> String {
        "\(exerciseID)|\(handedness.rawValue)"
    }

    func restSeconds(exerciseID: String, handedness: Handedness) -> Int {
        if let v = exerciseRestOverrides[AppSettings.overrideKey(exerciseID: exerciseID, handedness: handedness)] {
            return v
        }
        return handedness == .unilateral ? unilateralRestSeconds : defaultRestSeconds
    }
}

struct AppData: Codable, Hashable {
    var schemaVersion: Int = 1
    /// 已结束的训练
    var workouts: [Workout] = []
    /// 进行中的训练（草稿，App 关闭后可恢复）
    var activeWorkout: Workout? = nil
    var customExercises: [ExerciseDefinition] = []
    var settings: AppSettings = AppSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        workouts = try c.decodeIfPresent([Workout].self, forKey: .workouts) ?? []
        activeWorkout = try c.decodeIfPresent(Workout.self, forKey: .activeWorkout)
        customExercises = try c.decodeIfPresent([ExerciseDefinition].self, forKey: .customExercises) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
    }
}
