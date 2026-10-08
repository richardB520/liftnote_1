import XCTest
#if canImport(LiftNoteCore)
@testable import LiftNoteCore
#else
@testable import LiftNote
#endif

final class VoiceParserTests: XCTestCase {
    let catalog = ExerciseCatalog()

    private func parse(_ s: String, context: String? = nil, recent: [String] = []) -> VoiceParseResult {
        VoiceParser.parse(s, catalog: catalog, contextExerciseID: context, recentExerciseIDs: recent)
    }

    func testChineseNumbers() {
        XCTAssertEqual(VoiceParser.parseChineseInteger("四十五"), 45)
        XCTAssertEqual(VoiceParser.parseChineseInteger("十"), 10)
        XCTAssertEqual(VoiceParser.parseChineseInteger("一百二"), 120)
        XCTAssertEqual(VoiceParser.parseChineseInteger("一百零五"), 105)
        XCTAssertEqual(VoiceParser.parseChineseNumber("二十二点五"), 22.5)
        XCTAssertEqual(VoiceParser.normalize("四十五公斤做了两组"), "45kg做了2组")
        XCTAssertEqual(VoiceParser.normalize("和上次一样"), "和上次一样", "不能把'一样'转成数字")
        XCTAssertEqual(VoiceParser.normalize("绳索二头"), "绳索二头")
    }

    func testGlobalWeightWithOrdinalSets() {
        let r = parse("诺德士坐姿胸推，45公斤，做了两组，第一组10次，第二组8次，两组都比上次轻松")
        XCTAssertEqual(r.bestMatch?.id, "nautilus.sel.chest-press")
        XCTAssertEqual(r.sets.count, 2)
        XCTAssertEqual(r.sets.map { $0.weight }, [45, 45])
        XCTAssertEqual(r.sets.map { $0.reps }, [10, 8])
        XCTAssertEqual(r.sets.map { $0.quality }, [.better, .better])
    }

    /// 截图里的原句：40 公斤应该属于第二组
    func testWeightBeforeNextOrdinalBelongsToNextSet() {
        let r = parse("PRIME 上辈划船 插片 45公斤，第一组10次，40公斤第二组8次，都更好")
        XCTAssertEqual(r.bestMatch?.id, "prime.sel.upper-back-row")
        XCTAssertEqual(r.sets.map { $0.weight }, [45, 40])
        XCTAssertEqual(r.sets.map { $0.reps }, [10, 8])
        XCTAssertEqual(r.sets.map { $0.quality }, [.better, .better])
    }

    func testRepsThenWeightInsideOrdinal() {
        let r = parse("第一组10次45公斤，第二组8次40公斤")
        XCTAssertEqual(r.sets.map { $0.weight }, [45, 40])
        XCTAssertEqual(r.sets.map { $0.reps }, [10, 8])
    }

    func testQualityOnlyForThatSet() {
        let r = parse("第一组45公斤10次，第二组40公斤8次，比上次费劲")
        XCTAssertEqual(r.sets.map { $0.quality }, [nil, .worse])
    }

    func testPairsWithoutOrdinals() {
        let r = parse("45公斤10次，40公斤8次")
        XCTAssertEqual(r.sets.map { $0.weight }, [45, 40])
        XCTAssertEqual(r.sets.map { $0.reps }, [10, 8])
    }

    func testCountExpandsSingleSet() {
        let r = parse("哑铃侧平举 10公斤 15次 两组")
        XCTAssertEqual(r.bestMatch?.id, "gen.db.lateral-raise")
        XCTAssertEqual(r.sets.count, 2)
        XCTAssertEqual(r.sets.map { $0.weight }, [10, 10])
        XCTAssertEqual(r.sets.map { $0.reps }, [15, 15])
    }

    func testEachSetReps() {
        let r = parse("胸推45公斤，两组，每组10次")
        XCTAssertEqual(r.sets.count, 2)
        XCTAssertEqual(r.sets.map { $0.reps }, [10, 10])
        XCTAssertEqual(r.sets.map { $0.weight }, [45, 45])
    }

    func testOnlyFirstSetSaidLeavesSecondIncomplete() {
        let r = parse("诺德士坐姿胸推 做两组 第一组45公斤10次")
        XCTAssertEqual(r.sets.count, 2)
        XCTAssertEqual(r.sets[0].reps, 10)
        XCTAssertNil(r.sets[1].reps)
    }

    func testPrimePositionsAndBasis() {
        let r = parse("PRIME挂片上背划船，每侧一号位20公斤，二号位10，三号位没挂，做了10次，比上次好")
        XCTAssertEqual(r.bestMatch?.id, "prime.pl.upper-back-row")
        XCTAssertTrue(r.mentionsPrimePositions)
        XCTAssertEqual(r.plateBasis, .perSide)
        XCTAssertEqual(r.sets.count, 1)
        XCTAssertEqual(r.sets[0].primeLoad, PrimeLoad(20, 10, nil))
        XCTAssertEqual(r.sets[0].reps, 10)
        XCTAssertEqual(r.sets[0].quality, .better)
    }

    func testPrimeWithoutBasisIsUnknown() {
        let r = parse("PRIME挂片胸推 一号位20 做了10次")
        XCTAssertNil(r.plateBasis)
        XCTAssertEqual(r.sets.first?.primeLoad, PrimeLoad(20, nil, nil))
    }

    func testAmbiguousPrimeAsksUser() {
        let r = parse("PRIME 上背划船 45公斤 10次")
        XCTAssertTrue(r.isAmbiguous)
        XCTAssertEqual(Set(r.candidates.prefix(2).map { $0.id }), ["prime.pl.upper-back-row", "prime.sel.upper-back-row"])
        // 最近用过的器械优先
        let r2 = parse("PRIME 上背划船 45公斤 10次", recent: ["prime.pl.upper-back-row"])
        XCTAssertEqual(r2.bestMatch?.id, "prime.pl.upper-back-row")
    }

    func testCableKindWins() {
        let r = parse("绳索二头弯举 单手 15公斤 12次")
        XCTAssertEqual(r.bestMatch?.id, "gen.cable.curl")
        XCTAssertEqual(r.handedness, .unilateral)
    }

    func testContextExerciseWhenNoNameSaid() {
        let r = parse("第二组，40公斤，9次，比上次费劲", context: "nautilus.sel.chest-press")
        XCTAssertTrue(r.usedContextExercise)
        XCTAssertEqual(r.bestMatch?.id, "nautilus.sel.chest-press")
        XCTAssertEqual(r.sets.first?.ordinal, 2)
        XCTAssertEqual(r.sets.first?.weight, 40)
        XCTAssertEqual(r.sets.first?.quality, .worse)
    }

    func testSameWeightIsNotQuality() {
        let r = VoiceParser.parse("一样重 8次", catalog: catalog, previousWeight: 45)
        XCTAssertEqual(r.sets.first?.weight, 45)
        XCTAssertNil(r.sets.first?.quality)
    }

    // MARK: 写入训练

    func testApplyVoiceSavesCompleteAndKeepsIncomplete() {
        var data = AppData()
        data.startWorkout(muscles: [.chest], catalog: catalog, now: Date())
        let r = parse("诺德士坐姿胸推 做两组 第一组45公斤10次")
        let res = data.applyVoice(exerciseID: r.bestMatch!.id, handedness: nil, plateBasis: nil, sets: r.sets,
                                  keepIncomplete: true, catalog: catalog)
        XCTAssertEqual(res?.completedSetIDs.count, 1)
        XCTAssertEqual(res?.pendingSetIDs.count, 1)
        let entry = data.activeWorkout!.exercises[0]
        XCTAssertEqual(entry.sets.count, 2)
        XCTAssertTrue(entry.sets[0].isCompleted)
        XCTAssertFalse(entry.sets[1].isCompleted)
        let v = WeeklyVolume.compute(data: data, week: WeeklyVolume.week(containing: Date()), catalog: catalog)
        XCTAssertEqual(v.count(.chest), 1)
    }

    func testApplyVoiceOnlyExerciseAddsBlankSets() {
        var data = AppData()
        data.startWorkout(muscles: [], catalog: catalog, now: Date())
        let res = data.applyVoice(exerciseID: "gen.cable.pushdown", handedness: nil, plateBasis: nil, sets: [],
                                  keepIncomplete: true, catalog: catalog)
        XCTAssertEqual(data.activeWorkout?.exercises.first?.sets.count, 2)
        XCTAssertNil(res?.restSeconds, "只添加动作不开始休息计时")
    }

    func testApplyVoiceFillsExistingTemplateSets() {
        var data = AppData()
        data.startWorkout(muscles: [], catalog: catalog, now: Date())
        let id = data.addExercise("nautilus.sel.chest-press", catalog: catalog)!
        data.updateActiveSet(entryID: id, setID: data.activeWorkout!.exercises[0].sets[1].id) { $0.weight = 40 }
        let r = parse("第二组8次", context: "nautilus.sel.chest-press")
        data.applyVoice(exerciseID: r.bestMatch!.id, handedness: nil, plateBasis: nil, sets: r.sets,
                        keepIncomplete: false, targetEntryID: id, catalog: catalog)
        let sets = data.activeWorkout!.exercises[0].sets
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[1].weight, 40, "保留已有输入")
        XCTAssertEqual(sets[1].reps, 8)
        XCTAssertTrue(sets[1].isCompleted)
    }

    // MARK: 停顿接续

    func testPauseDoesNotOverwrite() {
        var acc = TranscriptAccumulator()
        acc.receive("胸推", isFinal: false)
        acc.receive("胸推45公斤", isFinal: false)
        // 停顿后识别器从头开始返回新的一段
        acc.receive("两组", isFinal: false)
        acc.receive("两组每组10次", isFinal: false)
        XCTAssertEqual(acc.text, "胸推45公斤，两组每组10次")
    }

    func testFinalThenNewTask() {
        var acc = TranscriptAccumulator()
        acc.receive("胸推45公斤。", isFinal: true)
        acc.receive("两组", isFinal: false)
        XCTAssertEqual(acc.text, "胸推45公斤。，两组")
        acc.commitPending()
        acc.receive("胸推45公斤两组", isFinal: true) // 重复送来的整句不重复追加
        XCTAssertEqual(TranscriptAccumulator.key(acc.text), TranscriptAccumulator.key("胸推45公斤两组"))
    }

    func testRevisionReplacesInsteadOfAppending() {
        var acc = TranscriptAccumulator()
        acc.receive("上辈划船", isFinal: false)
        acc.receive("上背划船", isFinal: false)
        XCTAssertEqual(acc.text, "上背划船")
    }
}
