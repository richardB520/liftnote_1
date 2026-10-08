import Foundation

/// 语音里解析出的一组。
struct VoiceParsedSet: Hashable {
    /// "第 N 组"
    var ordinal: Int? = nil
    var weight: Double? = nil
    var primeLoad: PrimeLoad? = nil
    var reps: Int? = nil
    var quality: QualityMark? = nil
}

struct VoiceParseResult {
    var normalizedText: String
    /// 匹配到的器械，最可能的排前面
    var candidates: [ExerciseDefinition]
    /// 前两名得分相同，需要用户选
    var isAmbiguous: Bool
    /// 没说器械，沿用当前动作
    var usedContextExercise: Bool
    var sets: [VoiceParsedSet]
    var plateBasis: PlateBasis?
    var handedness: Handedness?
    var mentionsPrimePositions: Bool

    var bestMatch: ExerciseDefinition? { isAmbiguous ? nil : candidates.first }
}

enum VoiceParser {

    // MARK: 入口

    /// - Parameters:
    ///   - contextExerciseID: 没说器械名时沿用的动作（比如正在做的动作）
    ///   - previousWeight: "沿用上组重量" 时参考的重量
    ///   - recentExerciseIDs: 最近用过的器械，同分时优先
    static func parse(_ text: String, catalog: ExerciseCatalog, contextExerciseID: String? = nil,
                      previousWeight: Double? = nil, recentExerciseIDs: [String] = []) -> VoiceParseResult {
        let normalized = normalize(text)
        let tokens = tokenize(normalized)
        let (sets, hasPositions) = assignSets(tokens, previousWeight: previousWeight)

        var (candidates, ambiguous) = matchExercises(normalized, catalog: catalog, recent: recentExerciseIDs)
        var usedContext = false
        if candidates.isEmpty, let ctx = contextExerciseID, catalog.contains(ctx) {
            candidates = [catalog.definition(ctx)]
            ambiguous = false
            usedContext = true
        }

        return VoiceParseResult(normalizedText: normalized,
                                candidates: candidates,
                                isAmbiguous: ambiguous,
                                usedContextExercise: usedContext,
                                sets: sets,
                                plateBasis: detectBasis(normalized),
                                handedness: detectHandedness(normalized),
                                mentionsPrimePositions: hasPositions)
    }

    // MARK: 规范化

    /// 常见误识别和同义词。顺序有意义：先纠错，再换单位。
    static let replacements: [(String, String)] = [
        ("上辈", "上背"), ("上贝", "上背"), ("尚背", "上背"),
        ("二投", "二头"), ("三投", "三头"), ("二楼", "二头"),
        ("划传", "划船"), ("画船", "划船"), ("滑船", "划船"),
        ("下啦", "下拉"), ("坐资", "坐姿"), ("座姿", "坐姿"),
        ("弯具", "弯举"), ("湾举", "弯举"), ("侧平局", "侧平举"), ("侧平具", "侧平举"),
        ("胸腿", "胸推"), ("凶推", "胸推"),
        ("挂偏", "挂片"), ("插偏", "插片"), ("号味", "号位"), ("好位", "号位"),
        ("绳锁", "绳索"), ("神索", "绳索"), ("哑玲", "哑铃"), ("杠玲", "杠铃"),
        ("公金", "公斤"), ("工斤", "公斤"), ("功斤", "公斤"),
        ("千克", "kg"), ("公斤", "kg"), ("kgs", "kg"), ("磅", "lb"), ("lbs", "lb"),
        ("这一组", "这组"), ("每一组", "每组"), ("上一组", "上组"), ("下一组", "下组"),
        ("，", ","), ("、", ","), ("；", ","), (";", ","), ("。", ","), ("！", ","), ("？", ","), ("!", ","), ("?", ","),
    ]

    static func normalize(_ text: String) -> String {
        var s = TextNormalizer.compact(text)
        for (a, b) in replacements {
            s = s.replacingOccurrences(of: a, with: b)
        }
        return convertChineseNumerals(s)
    }

    private static let numeralChars: Set<Character> = ["零", "一", "二", "两", "三", "四", "五", "六", "七", "八", "九", "十", "百", "点"]

    private static func digitValue(_ ch: Character) -> Int? {
        switch ch {
        case "零": return 0
        case "一": return 1
        case "二", "两": return 2
        case "三": return 3
        case "四": return 4
        case "五": return 5
        case "六": return 6
        case "七": return 7
        case "八": return 8
        case "九": return 9
        default: return nil
        }
    }

    /// 只在数字后面跟着单位（kg、次、组、号位…）或前面是"第"、"号位"时才转换，避免把"一样""二头"转成数字。
    static func convertChineseNumerals(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            guard numeralChars.contains(ch) && ch != "点" else {
                out.append(ch)
                i += 1
                continue
            }
            var j = i
            while j < chars.count && numeralChars.contains(chars[j]) { j += 1 }
            var end = j
            while end > i && chars[end - 1] == "点" { end -= 1 }
            let run = String(chars[i..<end])
            let following = String(chars[end..<min(chars.count, end + 2)])
            let prev: Character? = i > 0 ? chars[i - 1] : nil
            let before = String(chars[max(0, i - 2)..<i])
            if shouldConvert(run: run, following: following, prev: prev, before: before), let v = parseChineseNumber(run) {
                out += WeightFormat.kg(v)
            } else {
                out += run
            }
            i = end
        }
        return out
    }

    private static func shouldConvert(run: String, following: String, prev: Character?, before: String) -> Bool {
        if prev == "第" { return true }
        if before.hasSuffix("号位") || prev == "挂" || before == "挂了" { return true }
        if run == "一" && (following.hasPrefix("个") || following.hasPrefix("下")) { return false }
        for unit in ["kg", "lb", "次", "下", "个", "组", "号"] where following.hasPrefix(unit) {
            return true
        }
        return false
    }

    static func parseChineseNumber(_ run: String) -> Double? {
        let parts = run.split(separator: "点", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let integer = parseChineseInteger(String(first)) else { return nil }
        var value = Double(integer)
        if parts.count == 2 {
            var frac = ""
            for ch in parts[1] {
                guard let d = digitValue(ch) else { return nil }
                frac += String(d)
            }
            if !frac.isEmpty, let f = Double("0." + frac) { value += f }
        }
        return value
    }

    static func parseChineseInteger(_ s: String) -> Int? {
        guard !s.isEmpty else { return nil }
        var total = 0
        var current = 0
        var lastUnit = 1
        var sawZero = false
        var sawAny = false
        for ch in s {
            if ch == "十" {
                total += (current == 0 ? 1 : current) * 10
                current = 0
                lastUnit = 10
                sawAny = true
            } else if ch == "百" {
                total += (current == 0 ? 1 : current) * 100
                current = 0
                lastUnit = 100
                sawAny = true
            } else if ch == "零" {
                sawZero = true
                current = 0
                sawAny = true
            } else if let d = digitValue(ch) {
                current = current * 10 + d
                sawAny = true
            } else {
                return nil
            }
        }
        guard sawAny else { return nil }
        // "一百二" = 120
        if lastUnit == 100 && !sawZero && current > 0 && current < 10 {
            return total + current * 10
        }
        return total + current
    }

    // MARK: 分词

    enum QualityScope: Hashable {
        /// "都 / 全部 / 每组" —— 所有组
        case all
        /// "这组" —— 只当前组
        case this
        /// 默认：所在位置的组
        case local
    }

    enum Load: Hashable {
        case kg(Double)
        case prime(PrimeLoad)
    }

    enum Token: Hashable {
        case load(Load)
        case reps(Int, perSet: Bool)
        case ordinal(Int)
        case count(Int)
        case position(Int, Double?)
        case quality(QualityMark, QualityScope)
        case copyPrevious
    }

    private static let qualityPhrases: [(String, QualityMark)] = {
        let better = ["比上次好", "比上次更好", "比上次轻松", "比上次轻", "质量更高", "质量高", "更轻松", "更好", "轻松", "进步", "更稳", "更标准", "很好"]
        let worse = ["比上次差", "比上次累", "比上次费劲", "比上次吃力", "比上次难", "不如上次", "没上次好", "没有上次好", "没上次轻松",
                     "没有上次轻松", "不轻松", "不太好", "不好", "更费劲", "更吃力", "费劲", "吃力", "退步", "更差", "变差", "更累", "很累"]
        let same = ["和上次一样", "跟上次一样", "和上次差不多", "跟上次差不多", "差不多", "持平", "一样"]
        let all = better.map { ($0, QualityMark.better) } + worse.map { ($0, QualityMark.worse) } + same.map { ($0, QualityMark.same) }
        return all.sorted { $0.0.count > $1.0.count }
    }()

    private static let copyPhrases = ["重量一样", "一样重", "重量不变", "沿用上组", "沿用", "同上", "跟上组一样", "和上组一样"]
        .sorted { $0.count > $1.count }

    private static let clauseDelimiters: Set<Character> = [","]

    static func tokenize(_ s: String) -> [Token] {
        let c = Array(s)
        let n = c.count
        var tokens: [Token] = []

        func matches(_ word: String, at i: Int) -> Bool {
            let w = Array(word)
            guard i >= 0, i + w.count <= n else { return false }
            for k in 0..<w.count where c[i + k] != w[k] { return false }
            return true
        }

        func readNumber(_ i: Int) -> (Double, Int)? {
            var k = i
            var str = ""
            var sawDot = false
            while k < n {
                if c[k].isASCII && c[k].isNumber {
                    str.append(c[k])
                } else if c[k] == "." && !sawDot && !str.isEmpty && k + 1 < n && c[k + 1].isASCII && c[k + 1].isNumber {
                    sawDot = true
                    str.append(".")
                } else {
                    break
                }
                k += 1
            }
            guard !str.isEmpty, let v = Double(str) else { return nil }
            return (v, k - i)
        }

        func skip(_ words: [String], from i: Int) -> Int {
            var k = i
            var moved = true
            while moved {
                moved = false
                for w in words where matches(w, at: k) {
                    k += w.count
                    moved = true
                    break
                }
            }
            return k
        }

        func scope(at i: Int) -> QualityScope {
            var start = i
            while start > 0 && !clauseDelimiters.contains(c[start - 1]) { start -= 1 }
            let clause = String(c[start..<i])
            if clause.contains("都") || clause.contains("全部") || clause.contains("每组") || clause.contains("全") { return .all }
            if clause.contains("这组") || clause.contains("这次这组") { return .this }
            return .local
        }

        var i = 0
        while i < n {
            // 第 N 组
            if c[i] == "第", let (num, len) = readNumber(i + 1) {
                var k = i + 1 + len
                if k < n && c[k] == "组" { k += 1 }
                tokens.append(.ordinal(Int(num)))
                i = k
                continue
            }
            // 每组 N 次
            if matches("每组", at: i) {
                let k = skip(["都是", "都", "是", "做了", "做"], from: i + 2)
                if let (num, len) = readNumber(k), k + len < n, ["次", "下", "个"].contains(c[k + len]) {
                    tokens.append(.reps(Int(num), perSet: true))
                    i = k + len + 1
                    continue
                }
                i += 2
                continue
            }
            if let (num, len) = readNumber(i) {
                var k = i + len
                // N 号位
                if matches("号位", at: k) || (k < n && c[k] == "号") {
                    k += matches("号位", at: k) ? 2 : 1
                    let index = Int(num) - 1
                    k = skip(["挂了", "挂", "放了", "放", "是", "上"], from: k)
                    var handled = false
                    for empty in ["没挂", "没有", "不挂", "空着", "空", "没"] where matches(empty, at: k) {
                        if (0..<3).contains(index) { tokens.append(.position(index, nil)) }
                        k += empty.count
                        handled = true
                        break
                    }
                    if !handled, let (v, vl) = readNumber(k) {
                        k += vl
                        if matches("kg", at: k) { k += 2 }
                        if (0..<3).contains(index) { tokens.append(.position(index, v)) }
                    }
                    i = k
                    continue
                }
                if matches("kg", at: k) {
                    tokens.append(.load(.kg(num)))
                    i = k + 2
                } else if matches("lb", at: k) {
                    let kg = (num * 0.45359237 * 10).rounded() / 10
                    tokens.append(.load(.kg(kg)))
                    i = k + 2
                } else if k < n && ["次", "下", "个"].contains(c[k]) {
                    tokens.append(.reps(Int(num), perSet: false))
                    i = k + 1
                } else if k < n && c[k] == "组" {
                    tokens.append(.count(Int(num)))
                    i = k + 1
                } else {
                    i = k
                }
                continue
            }
            if let phrase = copyPhrases.first(where: { matches($0, at: i) }) {
                tokens.append(.copyPrevious)
                i += phrase.count
                continue
            }
            if let (phrase, mark) = qualityPhrases.first(where: { matches($0.0, at: i) }) {
                tokens.append(.quality(mark, scope(at: i)))
                i += phrase.count
                continue
            }
            i += 1
        }
        return mergePositions(tokens)
    }

    /// 连续的 1/2/3 号位合成一个 PRIME 重量。
    private static func mergePositions(_ tokens: [Token]) -> [Token] {
        var out: [Token] = []
        var building: PrimeLoad? = nil
        for t in tokens {
            if case .position(let idx, let v) = t {
                var p = building ?? PrimeLoad()
                p[idx] = v
                building = p
            } else {
                if let p = building { out.append(.load(.prime(p))); building = nil }
                out.append(t)
            }
        }
        if let p = building { out.append(.load(.prime(p))) }
        return out
    }

    // MARK: 把重量 / 次数分给每一组

    private struct Draft {
        var ordinal: Int?
        var load: Load?
        var reps: Int?
        var quality: QualityMark?
        var copy = false
    }

    private struct Globals {
        var load: Load?
        var reps: Int?
        var count: Int?
        var quality: QualityMark?
        var allQuality: QualityMark?
        var copy = false
    }

    static func assignSets(_ input: [Token], previousWeight: Double?) -> ([VoiceParsedSet], Bool) {
        var tokens = input
        let hasPositions = tokens.contains { if case .load(.prime) = $0 { return true }; return false }
        let hasOrdinals = tokens.contains { if case .ordinal = $0 { return true }; return false }

        // "45公斤，第一组10次，40公斤第二组8次"：习惯把重量说在"第N组"前面时，
        // 紧跟在"第N组"前面的重量属于第 N 组。
        // 如果第一个重量出现在第一个"第N组"之后（"第一组10次45公斤"），重量跟在组后面，不调整。
        let firstOrdinal = tokens.firstIndex { if case .ordinal = $0 { return true }; return false }
        let firstLoad = tokens.firstIndex { if case .load = $0 { return true }; return false }
        if hasOrdinals, let fo = firstOrdinal, let fl = firstLoad, fl < fo {
            var seenOrdinal = false
            var k = 0
            while k < tokens.count {
                if case .ordinal = tokens[k] { seenOrdinal = true }
                if seenOrdinal, k + 1 < tokens.count, case .load = tokens[k], case .ordinal = tokens[k + 1] {
                    tokens.swapAt(k, k + 1)
                    k += 2
                    continue
                }
                k += 1
            }
        }

        var sets: [Draft] = []
        var g = Globals()
        var current: Int? = nil

        if hasOrdinals {
            for t in tokens {
                switch t {
                case .ordinal(let n):
                    if let idx = sets.firstIndex(where: { $0.ordinal == n }) {
                        current = idx
                    } else {
                        sets.append(Draft(ordinal: n))
                        current = sets.count - 1
                    }
                case .load(let l):
                    if let c = current {
                        if sets[c].load == nil { sets[c].load = l }
                    } else {
                        g.load = l
                    }
                case .reps(let r, let perSet):
                    if perSet || current == nil {
                        g.reps = r
                    } else if let c = current, sets[c].reps == nil {
                        sets[c].reps = r
                    }
                case .count(let n):
                    g.count = n
                case .quality(let q, let scope):
                    switch scope {
                    case .all: g.allQuality = q
                    case .this, .local:
                        if let c = current { sets[c].quality = q } else { g.quality = q }
                    }
                case .copyPrevious:
                    if let c = current { sets[c].copy = true } else { g.copy = true }
                case .position:
                    break
                }
            }
        } else {
            // 没说"第几组"：按说话顺序配对。先说重量就"重量→次数"配对，先说次数就"次数→重量"。
            var repsFirst = false
            for t in tokens {
                if case .load = t { repsFirst = false; break }
                if case .reps(_, let perSet) = t, !perSet { repsFirst = true; break }
            }
            var pendingLoad: Load? = nil
            var pendingCopy = false
            for t in tokens {
                switch t {
                case .load(let l):
                    if repsFirst {
                        if let c = current {
                            if sets[c].load == nil { sets[c].load = l }
                        } else {
                            g.load = l
                        }
                    } else {
                        pendingLoad = l
                    }
                case .reps(let r, let perSet):
                    if perSet { g.reps = r; continue }
                    if repsFirst {
                        sets.append(Draft(reps: r))
                    } else {
                        sets.append(Draft(load: pendingLoad, reps: r, copy: pendingCopy))
                        pendingLoad = nil
                        pendingCopy = false
                    }
                    current = sets.count - 1
                case .count(let n):
                    g.count = n
                case .quality(let q, let scope):
                    switch scope {
                    case .all: g.allQuality = q
                    case .this, .local:
                        if let c = current { sets[c].quality = q } else { g.quality = q }
                    }
                case .copyPrevious:
                    if current == nil && pendingLoad == nil {
                        g.copy = true
                    } else if repsFirst, let c = current {
                        sets[c].copy = true
                    } else {
                        pendingCopy = true
                    }
                case .ordinal, .position:
                    break
                }
            }
            if let l = pendingLoad {
                if let c = current, sets[c].load == nil {
                    sets[c].load = l
                } else if sets.isEmpty {
                    g.load = l
                }
            }
        }

        // 组数
        if let n = g.count, n > sets.count, n <= 20 {
            if !hasOrdinals && sets.count == 1 {
                let template = sets[0]
                while sets.count < n { sets.append(template) }
            } else {
                var next = (sets.compactMap { $0.ordinal }.max() ?? sets.count) + 1
                while sets.count < n {
                    sets.append(Draft(ordinal: hasOrdinals ? next : nil))
                    next += 1
                }
            }
        }
        if sets.isEmpty && (g.load != nil || g.reps != nil) {
            sets.append(Draft())
        }

        if hasOrdinals {
            sets.sort { ($0.ordinal ?? Int.max) < ($1.ordinal ?? Int.max) }
        }

        // 应用全局值
        var result: [VoiceParsedSet] = []
        var previousLoad: Load? = previousWeight.map { Load.kg($0) }
        for d in sets {
            var load = d.load
            if load == nil {
                if d.copy || g.copy {
                    load = previousLoad
                } else {
                    load = g.load
                }
            }
            var ps = VoiceParsedSet(ordinal: d.ordinal)
            switch load {
            case .kg(let w)?: ps.weight = w
            case .prime(let p)?: ps.primeLoad = p
            case nil: break
            }
            ps.reps = d.reps ?? g.reps
            ps.quality = d.quality ?? g.allQuality ?? g.quality
            if let load { previousLoad = load }
            result.append(ps)
        }
        return (result, hasPositions)
    }

    // MARK: 器械匹配

    static func matchExercises(_ text: String, catalog: ExerciseCatalog, recent: [String]) -> ([ExerciseDefinition], Bool) {
        let brands = Brand.allCases.filter { b in b.spokenAliases.contains { text.contains($0) } }
        let kinds = EquipmentKind.allCases.filter { k in k.spokenAliases.contains { text.contains($0) } }
        var scored: [(ExerciseDefinition, Int)] = []
        for d in catalog.all {
            let terms = ([d.name] + d.aliases).map { TextNormalizer.compact($0) }.filter { $0.count >= 2 }
            let longest = terms.filter { text.contains($0) }.map { $0.count }.max() ?? 0
            guard longest >= 2 else { continue }
            var score = longest * 10
            if !brands.isEmpty {
                guard brands.contains(d.brand) else { continue }
                score += 100
            }
            if !kinds.isEmpty {
                score += kinds.contains(d.kind) ? 40 : -40
            }
            let series = TextNormalizer.compact(d.series)
            if series.count >= 2 && text.contains(series) { score += 15 }
            if let r = recent.firstIndex(of: d.id) { score += max(1, 6 - r) }
            if d.isCustom { score += 2 }
            scored.append((d, score))
        }
        scored.sort { a, b in a.1 != b.1 ? a.1 > b.1 : a.0.id < b.0.id }
        let ambiguous = scored.count > 1 && scored[0].1 == scored[1].1
        return (Array(scored.prefix(8).map { $0.0 }), ambiguous)
    }

    static func detectBasis(_ text: String) -> PlateBasis? {
        if ["每侧", "每边", "一侧", "单侧", "两侧一样", "两边一样", "左右一样"].contains(where: { text.contains($0) }) { return .perSide }
        if ["共用", "共享"].contains(where: { text.contains($0) }) { return .shared }
        return nil
    }

    static func detectHandedness(_ text: String) -> Handedness? {
        if ["单手", "单臂", "单边"].contains(where: { text.contains($0) }) { return .unilateral }
        if ["双手", "双臂", "两只手"].contains(where: { text.contains($0) }) { return .bilateral }
        return nil
    }
}
