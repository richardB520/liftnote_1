import Foundation

/// 器械动作库：内置条目 + 用户自定义条目。
struct ExerciseCatalog {
    var custom: [ExerciseDefinition]

    init(custom: [ExerciseDefinition] = []) {
        self.custom = custom
    }

    var all: [ExerciseDefinition] { ExerciseCatalog.builtIn + custom }

    func definition(_ id: String) -> ExerciseDefinition {
        if let d = ExerciseCatalog.builtInByID[id] { return d }
        if let d = custom.first(where: { $0.id == id }) { return d }
        return ExerciseDefinition.placeholder(id: id)
    }

    func contains(_ id: String) -> Bool {
        ExerciseCatalog.builtInByID[id] != nil || custom.contains { $0.id == id }
    }

    /// 搜索：动作名、别名、品牌、系列、器械类型、肌群都可以搜（支持中文）。
    func search(_ query: String, brand: Brand? = nil, kind: EquipmentKind? = nil, muscle: MuscleGroup? = nil) -> [ExerciseDefinition] {
        let q = TextNormalizer.compact(query)
        return all.filter { d in
            if let brand, d.brand != brand { return false }
            if let kind, d.kind != kind { return false }
            if let muscle, !d.primary.contains(muscle) { return false }
            guard !q.isEmpty else { return true }
            return ExerciseCatalog.searchText(for: d).contains(q)
        }
    }

    static func searchText(for d: ExerciseDefinition) -> String {
        var parts = [d.name, d.series, d.brand.displayName, d.kind.displayName] + d.aliases + d.brand.spokenAliases
        parts += d.primary.map { $0.displayName }
        return TextNormalizer.compact(parts.joined(separator: "|"))
    }

    // MARK: 内置库

    static let builtInByID: [String: ExerciseDefinition] = {
        var map: [String: ExerciseDefinition] = [:]
        for d in builtIn { map[d.id] = d }
        return map
    }()

    private static func e(_ id: String, _ brand: Brand, _ series: String, _ kind: EquipmentKind, _ name: String,
                          _ primary: [MuscleGroup], _ secondary: [MuscleGroup] = [], _ aliases: [String] = []) -> ExerciseDefinition {
        ExerciseDefinition(id: id, name: name, brand: brand, series: series, kind: kind,
                           primary: primary, secondary: secondary, aliases: aliases)
    }

    static let builtIn: [ExerciseDefinition] = nautilus + prime + atlantis + hammerStrength + generic

    // 诺德士 Nautilus
    static let nautilus: [ExerciseDefinition] = [
        e("nautilus.sel.chest-press", .nautilus, "插片", .selectorized, "坐姿胸推", [.chest], [.triceps], ["胸推", "推胸"]),
        e("nautilus.sel.incline-press", .nautilus, "插片", .selectorized, "上斜胸推", [.chest], [.triceps], ["上斜推胸", "上胸推"]),
        e("nautilus.sel.pec-fly", .nautilus, "插片", .selectorized, "蝴蝶机夹胸", [.chest], [], ["夹胸", "蝴蝶机", "飞鸟"]),
        e("nautilus.sel.lat-pulldown", .nautilus, "插片", .selectorized, "高位下拉", [.back], [.biceps], ["下拉"]),
        e("nautilus.sel.seated-row", .nautilus, "插片", .selectorized, "坐姿划船", [.back], [.biceps], ["划船"]),
        e("nautilus.sel.pullover", .nautilus, "插片", .selectorized, "背阔肌套举", [.back], [], ["pullover", "直臂下拉", "套举"]),
        e("nautilus.sel.rear-delt", .nautilus, "插片", .selectorized, "反向飞鸟", [], [.back], ["后束飞鸟", "反飞鸟"]),
        e("nautilus.sel.lateral-raise", .nautilus, "插片", .selectorized, "侧平举机", [.sideDelts], [], ["侧平举"]),
        e("nautilus.sel.shoulder-press", .nautilus, "插片", .selectorized, "坐姿肩推", [.sideDelts], [.triceps], ["肩推", "推肩"]),
        e("nautilus.sel.biceps-curl", .nautilus, "插片", .selectorized, "二头弯举机", [.biceps], [], ["二头弯举", "弯举"]),
        e("nautilus.sel.triceps-ext", .nautilus, "插片", .selectorized, "三头伸展机", [.triceps], [], ["三头伸展", "三头"]),
        e("nautilus.sel.triceps-press", .nautilus, "插片", .selectorized, "坐姿臂屈伸", [.triceps], [.chest], ["臂屈伸", "三头下压"]),
        e("nautilus.sel.leg-extension", .nautilus, "插片", .selectorized, "腿屈伸", [.quads], [], ["坐姿腿屈伸", "踢腿"]),
        e("nautilus.sel.seated-leg-curl", .nautilus, "插片", .selectorized, "坐姿腿弯举", [.hamstrings], [], ["腿弯举", "勾腿"]),
        e("nautilus.sel.prone-leg-curl", .nautilus, "插片", .selectorized, "俯卧腿弯举", [.hamstrings], [], ["趴着腿弯举"]),
        e("nautilus.sel.leg-press", .nautilus, "插片", .selectorized, "坐姿蹬腿", [.quads], [.hamstrings], ["蹬腿", "腿举", "腿推"]),
        e("nautilus.sel.glute", .nautilus, "插片", .selectorized, "臀部后踢", [.hamstrings], [], ["后踢腿", "臀推机"]),
        e("nautilus.pl.chest-press", .nautilus, "Leverage", .plateLoaded, "胸推", [.chest], [.triceps], ["推胸"]),
        e("nautilus.pl.incline-press", .nautilus, "Leverage", .plateLoaded, "上斜胸推", [.chest], [.triceps], ["上斜推胸"]),
        e("nautilus.pl.lat-pulldown", .nautilus, "Leverage", .plateLoaded, "高位下拉", [.back], [.biceps], ["下拉"]),
        e("nautilus.pl.row", .nautilus, "Leverage", .plateLoaded, "划船", [.back], [.biceps], ["坐姿划船"]),
        e("nautilus.pl.shoulder-press", .nautilus, "Leverage", .plateLoaded, "肩推", [.sideDelts], [.triceps], ["推肩"]),
        e("nautilus.pl.leg-press", .nautilus, "Leverage", .plateLoaded, "倒蹬", [.quads], [.hamstrings], ["蹬腿", "腿推"]),
        e("nautilus.pl.squat", .nautilus, "Leverage", .plateLoaded, "深蹲机", [.quads], [.hamstrings], ["深蹲", "哈克深蹲"]),
    ]

    // PRIME：挂片（1/2/3 号挂片位）与插片分开
    static let prime: [ExerciseDefinition] = [
        e("prime.pl.chest-press", .prime, "Plate Loaded", .plateLoaded, "胸推", [.chest], [.triceps], ["推胸", "坐姿胸推"]),
        e("prime.pl.incline-press", .prime, "Plate Loaded", .plateLoaded, "上斜胸推", [.chest], [.triceps], ["上斜推胸", "上胸推"]),
        e("prime.pl.decline-press", .prime, "Plate Loaded", .plateLoaded, "下斜胸推", [.chest], [.triceps], ["下斜推胸"]),
        e("prime.pl.lat-pulldown", .prime, "Plate Loaded", .plateLoaded, "高位下拉", [.back], [.biceps], ["下拉"]),
        e("prime.pl.upper-back-row", .prime, "Plate Loaded", .plateLoaded, "上背划船", [.back], [.biceps], ["上背", "高位划船"]),
        e("prime.pl.low-row", .prime, "Plate Loaded", .plateLoaded, "低位划船", [.back], [.biceps], ["划船", "坐姿划船"]),
        e("prime.pl.pullover", .prime, "Plate Loaded", .plateLoaded, "背阔肌套举", [.back], [], ["pullover", "套举"]),
        e("prime.pl.shoulder-press", .prime, "Plate Loaded", .plateLoaded, "肩推", [.sideDelts], [.triceps], ["推肩"]),
        e("prime.pl.lateral-raise", .prime, "Plate Loaded", .plateLoaded, "侧平举", [.sideDelts], [], ["侧平举机"]),
        e("prime.pl.biceps-curl", .prime, "Plate Loaded", .plateLoaded, "二头弯举", [.biceps], [], ["弯举"]),
        e("prime.pl.triceps", .prime, "Plate Loaded", .plateLoaded, "坐姿臂屈伸", [.triceps], [.chest], ["臂屈伸", "三头"]),
        e("prime.pl.leg-press", .prime, "Plate Loaded", .plateLoaded, "倒蹬", [.quads], [.hamstrings], ["蹬腿", "腿推", "腿举"]),
        e("prime.pl.hack-squat", .prime, "Plate Loaded", .plateLoaded, "哈克深蹲", [.quads], [.hamstrings], ["哈克", "深蹲"]),
        e("prime.pl.pendulum-squat", .prime, "Plate Loaded", .plateLoaded, "钟摆深蹲", [.quads], [.hamstrings], ["钟摆"]),
        e("prime.pl.leg-extension", .prime, "Plate Loaded", .plateLoaded, "腿屈伸", [.quads], [], ["踢腿"]),
        e("prime.pl.leg-curl", .prime, "Plate Loaded", .plateLoaded, "腿弯举", [.hamstrings], [], ["勾腿"]),
        e("prime.pl.hip-thrust", .prime, "Plate Loaded", .plateLoaded, "臀推", [.hamstrings], [], ["臀桥"]),
        e("prime.sel.chest-press", .prime, "插片", .selectorized, "胸推", [.chest], [.triceps], ["推胸", "坐姿胸推"]),
        e("prime.sel.incline-press", .prime, "插片", .selectorized, "上斜胸推", [.chest], [.triceps], ["上斜推胸"]),
        e("prime.sel.pec-fly", .prime, "插片", .selectorized, "夹胸", [.chest], [], ["蝴蝶机", "飞鸟"]),
        e("prime.sel.lat-pulldown", .prime, "插片", .selectorized, "高位下拉", [.back], [.biceps], ["下拉"]),
        e("prime.sel.upper-back-row", .prime, "插片", .selectorized, "上背划船", [.back], [.biceps], ["上背", "高位划船"]),
        e("prime.sel.seated-row", .prime, "插片", .selectorized, "坐姿划船", [.back], [.biceps], ["划船"]),
        e("prime.sel.rear-delt", .prime, "插片", .selectorized, "反向飞鸟", [], [.back], ["后束飞鸟"]),
        e("prime.sel.lateral-raise", .prime, "插片", .selectorized, "侧平举", [.sideDelts], [], ["侧平举机"]),
        e("prime.sel.shoulder-press", .prime, "插片", .selectorized, "肩推", [.sideDelts], [.triceps], ["推肩"]),
        e("prime.sel.biceps-curl", .prime, "插片", .selectorized, "二头弯举", [.biceps], [], ["弯举"]),
        e("prime.sel.triceps-ext", .prime, "插片", .selectorized, "三头伸展", [.triceps], [], ["三头"]),
        e("prime.sel.leg-extension", .prime, "插片", .selectorized, "腿屈伸", [.quads], [], ["踢腿"]),
        e("prime.sel.seated-leg-curl", .prime, "插片", .selectorized, "坐姿腿弯举", [.hamstrings], [], ["腿弯举", "勾腿"]),
        e("prime.sel.leg-press", .prime, "插片", .selectorized, "坐姿蹬腿", [.quads], [.hamstrings], ["蹬腿", "腿推"]),
    ]

    static let atlantis: [ExerciseDefinition] = [
        e("atlantis.sel.chest-press", .atlantis, "Precision 插片", .selectorized, "胸推", [.chest], [.triceps], ["推胸", "坐姿胸推"]),
        e("atlantis.sel.pec-fly", .atlantis, "Precision 插片", .selectorized, "夹胸", [.chest], [], ["蝴蝶机", "飞鸟"]),
        e("atlantis.sel.lat-pulldown", .atlantis, "Precision 插片", .selectorized, "高位下拉", [.back], [.biceps], ["下拉"]),
        e("atlantis.sel.seated-row", .atlantis, "Precision 插片", .selectorized, "坐姿划船", [.back], [.biceps], ["划船"]),
        e("atlantis.sel.rear-delt", .atlantis, "Precision 插片", .selectorized, "反向飞鸟", [], [.back], ["后束飞鸟"]),
        e("atlantis.sel.lateral-raise", .atlantis, "Precision 插片", .selectorized, "侧平举", [.sideDelts], [], ["侧平举机"]),
        e("atlantis.sel.shoulder-press", .atlantis, "Precision 插片", .selectorized, "肩推", [.sideDelts], [.triceps], ["推肩"]),
        e("atlantis.sel.biceps-curl", .atlantis, "Precision 插片", .selectorized, "二头弯举", [.biceps], [], ["弯举"]),
        e("atlantis.sel.triceps-ext", .atlantis, "Precision 插片", .selectorized, "三头伸展", [.triceps], [], ["三头"]),
        e("atlantis.sel.leg-extension", .atlantis, "Precision 插片", .selectorized, "腿屈伸", [.quads], [], ["踢腿"]),
        e("atlantis.sel.leg-curl", .atlantis, "Precision 插片", .selectorized, "腿弯举", [.hamstrings], [], ["勾腿", "坐姿腿弯举"]),
        e("atlantis.pl.chest-press", .atlantis, "挂片", .plateLoaded, "胸推", [.chest], [.triceps], ["推胸"]),
        e("atlantis.pl.incline-press", .atlantis, "挂片", .plateLoaded, "上斜胸推", [.chest], [.triceps], ["上斜推胸"]),
        e("atlantis.pl.lat-pulldown", .atlantis, "挂片", .plateLoaded, "高位下拉", [.back], [.biceps], ["下拉"]),
        e("atlantis.pl.row", .atlantis, "挂片", .plateLoaded, "划船", [.back], [.biceps], ["低位划船"]),
        e("atlantis.pl.leg-press", .atlantis, "挂片", .plateLoaded, "倒蹬", [.quads], [.hamstrings], ["蹬腿", "腿推"]),
        e("atlantis.pl.hack-squat", .atlantis, "挂片", .plateLoaded, "哈克深蹲", [.quads], [.hamstrings], ["哈克"]),
        e("atlantis.pl.leg-curl", .atlantis, "挂片", .plateLoaded, "腿弯举", [.hamstrings], [], ["勾腿"]),
    ]

    static let hammerStrength: [ExerciseDefinition] = [
        e("hammer.pl.bench-press", .hammerStrength, "Plate-Loaded", .plateLoaded, "平板胸推", [.chest], [.triceps], ["胸推", "推胸", "卧推"]),
        e("hammer.pl.incline-press", .hammerStrength, "Plate-Loaded", .plateLoaded, "上斜胸推", [.chest], [.triceps], ["上斜推胸", "上胸推"]),
        e("hammer.pl.decline-press", .hammerStrength, "Plate-Loaded", .plateLoaded, "下斜胸推", [.chest], [.triceps], ["下斜推胸"]),
        e("hammer.pl.wide-chest", .hammerStrength, "Plate-Loaded", .plateLoaded, "宽握胸推", [.chest], [.triceps], ["宽胸推"]),
        e("hammer.pl.front-pulldown", .hammerStrength, "Plate-Loaded", .plateLoaded, "高位下拉", [.back], [.biceps], ["下拉", "前下拉"]),
        e("hammer.pl.low-row", .hammerStrength, "Plate-Loaded", .plateLoaded, "低位划船", [.back], [.biceps], ["划船"]),
        e("hammer.pl.high-row", .hammerStrength, "Plate-Loaded", .plateLoaded, "高位划船", [.back], [.biceps], ["上背划船"]),
        e("hammer.pl.dy-row", .hammerStrength, "Plate-Loaded", .plateLoaded, "DY 划船", [.back], [.biceps], ["dy划船", "单臂划船"]),
        e("hammer.pl.shoulder-press", .hammerStrength, "Plate-Loaded", .plateLoaded, "肩推", [.sideDelts], [.triceps], ["推肩"]),
        e("hammer.pl.leg-press", .hammerStrength, "Plate-Loaded", .plateLoaded, "倒蹬", [.quads], [.hamstrings], ["蹬腿", "腿推"]),
        e("hammer.pl.hack-squat", .hammerStrength, "Plate-Loaded", .plateLoaded, "哈克深蹲", [.quads], [.hamstrings], ["哈克"]),
        e("hammer.pl.v-squat", .hammerStrength, "Plate-Loaded", .plateLoaded, "V 型深蹲", [.quads], [.hamstrings], ["v深蹲"]),
        e("hammer.pl.leg-extension", .hammerStrength, "Plate-Loaded", .plateLoaded, "腿屈伸", [.quads], [], ["踢腿"]),
        e("hammer.pl.kneeling-leg-curl", .hammerStrength, "Plate-Loaded", .plateLoaded, "跪姿腿弯举", [.hamstrings], [], ["腿弯举", "勾腿"]),
        e("hammer.pl.glute", .hammerStrength, "Plate-Loaded", .plateLoaded, "臀推", [.hamstrings], [], ["臀桥"]),
        e("hammer.sel.chest-press", .hammerStrength, "Select 插片", .selectorized, "胸推", [.chest], [.triceps], ["推胸"]),
        e("hammer.sel.pec-fly", .hammerStrength, "Select 插片", .selectorized, "夹胸", [.chest], [], ["蝴蝶机", "飞鸟"]),
        e("hammer.sel.lat-pulldown", .hammerStrength, "Select 插片", .selectorized, "高位下拉", [.back], [.biceps], ["下拉"]),
        e("hammer.sel.seated-row", .hammerStrength, "Select 插片", .selectorized, "坐姿划船", [.back], [.biceps], ["划船"]),
        e("hammer.sel.rear-delt", .hammerStrength, "Select 插片", .selectorized, "反向飞鸟", [], [.back], ["后束飞鸟"]),
        e("hammer.sel.lateral-raise", .hammerStrength, "Select 插片", .selectorized, "侧平举", [.sideDelts], [], ["侧平举机"]),
        e("hammer.sel.shoulder-press", .hammerStrength, "Select 插片", .selectorized, "肩推", [.sideDelts], [.triceps], ["推肩"]),
        e("hammer.sel.biceps-curl", .hammerStrength, "Select 插片", .selectorized, "二头弯举", [.biceps], [], ["弯举"]),
        e("hammer.sel.triceps-ext", .hammerStrength, "Select 插片", .selectorized, "三头伸展", [.triceps], [], ["三头"]),
        e("hammer.sel.leg-extension", .hammerStrength, "Select 插片", .selectorized, "腿屈伸", [.quads], [], ["踢腿"]),
        e("hammer.sel.seated-leg-curl", .hammerStrength, "Select 插片", .selectorized, "坐姿腿弯举", [.hamstrings], [], ["腿弯举", "勾腿"]),
        e("hammer.mts.chest-press", .hammerStrength, "MTS 插片", .selectorized, "MTS 胸推", [.chest], [.triceps], ["mts胸推"]),
        e("hammer.mts.pulldown", .hammerStrength, "MTS 插片", .selectorized, "MTS 高位下拉", [.back], [.biceps], ["mts下拉"]),
        e("hammer.mts.row", .hammerStrength, "MTS 插片", .selectorized, "MTS 划船", [.back], [.biceps], ["mts划船"]),
        e("hammer.mts.shoulder-press", .hammerStrength, "MTS 插片", .selectorized, "MTS 肩推", [.sideDelts], [.triceps], ["mts肩推"]),
    ]

    static let generic: [ExerciseDefinition] = [
        // 胸
        e("gen.bb.bench", .generic, "", .barbell, "杠铃卧推", [.chest], [.triceps], ["卧推", "平板卧推"]),
        e("gen.bb.incline-bench", .generic, "", .barbell, "上斜杠铃卧推", [.chest], [.triceps], ["上斜卧推"]),
        e("gen.db.bench", .generic, "", .dumbbell, "哑铃卧推", [.chest], [.triceps], ["哑铃推胸"]),
        e("gen.db.incline-bench", .generic, "", .dumbbell, "上斜哑铃卧推", [.chest], [.triceps], ["上斜哑铃"]),
        e("gen.db.fly", .generic, "", .dumbbell, "哑铃飞鸟", [.chest], [], ["飞鸟"]),
        e("gen.smith.incline", .generic, "", .smith, "史密斯上斜卧推", [.chest], [.triceps], ["史密斯卧推"]),
        e("gen.cable.fly", .generic, "", .cable, "绳索夹胸", [.chest], [], ["龙门架夹胸", "夹胸"]),
        e("gen.cable.low-fly", .generic, "", .cable, "绳索低位夹胸", [.chest], [], ["低位夹胸"]),
        e("gen.bw.dip", .generic, "", .bodyweight, "双杠臂屈伸", [.chest, .triceps], [], ["双杠"]),
        e("gen.bw.pushup", .generic, "", .bodyweight, "俯卧撑", [.chest], [.triceps], []),
        // 背
        e("gen.bw.pullup", .generic, "", .bodyweight, "引体向上", [.back], [.biceps], ["引体"]),
        e("gen.bb.row", .generic, "", .barbell, "杠铃划船", [.back], [.biceps], ["俯身划船"]),
        e("gen.db.row", .generic, "", .dumbbell, "哑铃划船", [.back], [.biceps], ["单臂哑铃划船"]),
        e("gen.cable.pulldown", .generic, "", .cable, "绳索高位下拉", [.back], [.biceps], ["高位下拉", "下拉"]),
        e("gen.cable.seated-row", .generic, "", .cable, "绳索坐姿划船", [.back], [.biceps], ["坐姿划船", "划船"]),
        e("gen.cable.straight-arm", .generic, "", .cable, "绳索直臂下压", [.back], [], ["直臂下压", "直臂下拉"]),
        e("gen.cable.single-pulldown", .generic, "", .cable, "绳索单臂下拉", [.back], [.biceps], ["单臂下拉"]),
        e("gen.cable.face-pull", .generic, "", .cable, "绳索面拉", [], [.back], ["面拉"]),
        e("gen.bb.deadlift", .generic, "", .barbell, "硬拉", [.hamstrings, .back], [], ["传统硬拉"]),
        // 腿
        e("gen.bb.squat", .generic, "", .barbell, "杠铃深蹲", [.quads], [.hamstrings], ["深蹲"]),
        e("gen.smith.squat", .generic, "", .smith, "史密斯深蹲", [.quads], [.hamstrings], []),
        e("gen.db.split-squat", .generic, "", .dumbbell, "保加利亚分腿蹲", [.quads], [.hamstrings], ["分腿蹲", "保加利亚"]),
        e("gen.bb.rdl", .generic, "", .barbell, "罗马尼亚硬拉", [.hamstrings], [], ["罗马尼亚", "直腿硬拉"]),
        e("gen.db.rdl", .generic, "", .dumbbell, "哑铃罗马尼亚硬拉", [.hamstrings], [], ["哑铃硬拉"]),
        e("gen.bb.hip-thrust", .generic, "", .barbell, "杠铃臀推", [.hamstrings], [], ["臀推"]),
        // 肩中束
        e("gen.db.lateral-raise", .generic, "", .dumbbell, "哑铃侧平举", [.sideDelts], [], ["侧平举"]),
        e("gen.cable.lateral-raise", .generic, "", .cable, "绳索侧平举", [.sideDelts], [], ["侧平举", "单臂侧平举"]),
        e("gen.cable.y-raise", .generic, "", .cable, "绳索 Y 字侧平举", [.sideDelts], [], ["y字侧平举", "y字举"]),
        e("gen.cable.upright-row", .generic, "", .cable, "绳索直立划船", [.sideDelts], [], ["直立划船"]),
        e("gen.db.shoulder-press", .generic, "", .dumbbell, "哑铃推举", [.sideDelts], [.triceps], ["哑铃肩推", "推举"]),
        // 二头
        e("gen.db.curl", .generic, "", .dumbbell, "哑铃弯举", [.biceps], [], ["弯举"]),
        e("gen.db.hammer-curl", .generic, "", .dumbbell, "锤式弯举", [.biceps], [], ["锤式"]),
        e("gen.db.incline-curl", .generic, "", .dumbbell, "上斜哑铃弯举", [.biceps], [], ["上斜弯举"]),
        e("gen.bb.curl", .generic, "", .barbell, "杠铃弯举", [.biceps], [], []),
        e("gen.bb.preacher", .generic, "", .barbell, "牧师凳弯举", [.biceps], [], ["牧师凳"]),
        e("gen.cable.curl", .generic, "", .cable, "绳索二头弯举", [.biceps], [], ["绳索弯举", "二头弯举"]),
        e("gen.cable.rope-hammer", .generic, "", .cable, "绳索锤式弯举", [.biceps], [], ["绳索锤式"]),
        e("gen.cable.bayesian", .generic, "", .cable, "绳索背后弯举", [.biceps], [], ["拜耳弯举", "贝叶斯弯举"]),
        // 三头
        e("gen.cable.pushdown", .generic, "", .cable, "绳索三头下压", [.triceps], [], ["三头下压", "下压"]),
        e("gen.cable.overhead-ext", .generic, "", .cable, "绳索过顶臂屈伸", [.triceps], [], ["过顶臂屈伸", "过顶三头"]),
        e("gen.cable.single-pushdown", .generic, "", .cable, "绳索单臂反握下压", [.triceps], [], ["反握下压"]),
        e("gen.cable.kickback", .generic, "", .cable, "绳索三头后撤", [.triceps], [], ["三头后撤", "后撤"]),
        e("gen.bb.skullcrusher", .generic, "", .barbell, "仰卧臂屈伸", [.triceps], [], ["碎颅者"]),
        e("gen.db.overhead-ext", .generic, "", .dumbbell, "哑铃颈后臂屈伸", [.triceps], [], ["颈后臂屈伸"]),
    ]
}

/// 文本规范化：小写、去空白、全角转半角。
enum TextNormalizer {
    static func compact(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() {
            if ch.isWhitespace { continue }
            out.append(fullWidthToHalf(ch))
        }
        return out
    }

    static func fullWidthToHalf(_ ch: Character) -> Character {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return ch }
        let v = scalar.value
        if v >= 0xFF01 && v <= 0xFF5E, let half = Unicode.Scalar(v - 0xFEE0) {
            return Character(half)
        }
        if v == 0x3002 { return "。" }
        return ch
    }
}
