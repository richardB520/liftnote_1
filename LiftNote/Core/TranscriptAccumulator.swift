import Foundation

/// 把语音识别的分段结果拼起来：停顿后继续说会接在后面，不会覆盖前面的话；
/// 同一句的识别修正只替换、不重复追加。直到用户点"说完了"才结束。
struct TranscriptAccumulator: Equatable {
    private(set) var committed: [String] = []
    private(set) var partial: String = ""

    var text: String {
        var parts = committed
        if !partial.isEmpty { parts.append(partial) }
        return parts.joined(separator: "，")
    }

    var isEmpty: Bool { committed.isEmpty && partial.isEmpty }

    /// 收到一次识别结果（同一个识别任务里结果会不断修正）。
    mutating func receive(_ newText: String, isFinal: Bool) {
        let t = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty && !t.isEmpty && TranscriptAccumulator.isRestart(previous: partial, next: t) {
            commit(partial)
        }
        if !t.isEmpty { partial = t }
        if isFinal {
            commit(partial)
            partial = ""
        }
    }

    /// 识别任务重启前（停顿、超时）调用，保留已识别内容。
    mutating func commitPending() {
        commit(partial)
        partial = ""
    }

    mutating func reset() {
        committed = []
        partial = ""
    }

    private mutating func commit(_ s: String) {
        let segment = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = TranscriptAccumulator.key(segment)
        guard !key.isEmpty else { return }
        if let last = committed.last {
            let lastKey = TranscriptAccumulator.key(last)
            // 同一句重复送来
            if lastKey == key || lastKey.hasSuffix(key) { return }
            // 新结果包含了上一段（识别器把前面的话也带上了）
            if key.hasPrefix(lastKey) {
                committed[committed.count - 1] = segment
                return
            }
        }
        let allKey = TranscriptAccumulator.key(committed.joined())
        if !allKey.isEmpty && key.hasPrefix(allKey) {
            committed = [segment]
            return
        }
        committed.append(segment)
    }

    /// 去掉标点和空格后比较，避免整句重新识别时标点变化造成重复。
    static func key(_ s: String) -> String {
        String(s.filter { !$0.isPunctuation && !$0.isWhitespace && !$0.isSymbol }).lowercased()
    }

    static func commonPrefixCount(_ a: String, _ b: String) -> Int {
        var n = 0
        var ia = a.startIndex, ib = b.startIndex
        while ia < a.endIndex && ib < b.endIndex && a[ia] == b[ib] {
            n += 1
            ia = a.index(after: ia)
            ib = b.index(after: ib)
        }
        return n
    }

    /// 判断新结果是不是停顿后重新开始的一段（而不是对同一句的修正）。
    static func isRestart(previous: String, next: String) -> Bool {
        let a = key(previous), b = key(next)
        if a.isEmpty || b.isEmpty { return false }
        if b.hasPrefix(a) || a.hasPrefix(b) { return false }
        let common = commonPrefixCount(a, b)
        if common * 2 >= min(a.count, b.count) { return false }
        // 修正一般长度相近；重新开始的一段开头很短
        return b.count < a.count
    }
}
