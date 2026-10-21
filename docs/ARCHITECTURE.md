# Architecture

LiftNote is split into a pure domain layer and a thin SwiftUI shell.

```
┌──────────────────────── iOS app (SwiftUI) ────────────────────────┐
│ Views ──► AppStore (ObservableObject, @MainActor)                 │
│             │  mutate { (inout AppData) in … }  → debounced atomic │
│             │                                     JSON save        │
│             ├─► RestAlerts (UserNotifications)                     │
│             └─► RestLiveActivity (ActivityKit) ──► LiftNoteWidgets │
│ SpeechRecognizer (Speech + AVAudioEngine) ──► TranscriptAccumulator│
└──────────────────────────────┬────────────────────────────────────┘
                               ▼
              LiftNoteCore (Foundation only, macOS + Linux)
   Models · ExerciseCatalog · WorkoutLogic · WeeklyVolume · VoiceParser · VoiceApply · Backup
```

## Data model

`AppData` is a single `Codable` value: finished `workouts`, an optional `activeWorkout` (the draft that survives app termination), custom equipment and settings. Every UI change goes through `AppStore.mutate`, which applies a pure mutating function from Core to a copy, publishes it, schedules a debounced atomic write, and re-syncs rest alerts when the timer state changed. Keeping state as one value type makes the domain rules unit-testable without the UI.

`Workout → [ExerciseEntry] → [SetEntry]`. An entry references an `ExerciseDefinition` by stable id (brand + series + movement), plus an optional `Handedness`. A set has `kind` (working / warm-up), either `weight` or `primeLoad` (three horn positions + `PlateBasis` per-side / shared), `reps`, an optional `QualityMark`, and completion state.

## Domain rules

**Weekly volume.** A set counts if it is completed, a working set, and its workout started inside the local calendar week (Monday start, `Calendar.current` time zone, so DST is handled). Each counted set adds 1 to every *primary* muscle of its exercise; secondary muscles are informational only. The in-progress workout counts too.

**Templates.** For each selected muscle, take the most recent finished workout containing a completed set of an exercise whose primary muscles include it, and copy that workout's matching exercises in order (deduplicated by exercise + handedness). The number of sets equals the completed sets last time across all segments of that exercise in the workout, so swapping away and back doesn't lose sets. Values are left empty; the previous performance is shown next to each set.

**"Previous" reference.** The most recent finished workout that started strictly before the current one and contains the same exercise id and handedness. Editing or deleting history changes the reference automatically because it is computed, not stored.

**Equipment swap (live).** Completed sets stay on the original entry; unfinished sets move to a new entry for the new machine. **Equipment change (history)** rewrites the entry in place, keeping reps, quality and timestamps; if the load format differs (standard ↔ PRIME horns) the weights are cleared and the user is asked to re-enter them.

**Load change vs. quality.** `LoadChange.compare` reports heavier / lighter / more or fewer reps, or `redistributed` when PRIME plates moved between horns without all positions increasing. Quality is never inferred; it is whatever the user marked.

## Voice parser

Pipeline: `normalize → tokenize → assignSets` plus `matchExercises`.

1. **Normalize.** Lower-case, strip whitespace, full-width to half-width, fix common mis-hearings (上辈→上背, 公金→公斤 …), unify units (公斤/千克→kg, 磅→lb), and convert Chinese numerals **only in numeric context** (followed by a unit or 组/次/号, preceded by 第 or 号位). This keeps words like 一样, 二头 and 三头 intact.
2. **Tokenize** into `load`, `reps(perSet:)`, `ordinal` (第N组), `count` (N组), horn `position`, `quality(scope)` and `copyPrevious`. Quality scope is derived from the clause: 都/全部/每组 → all sets, 这组 → current set, otherwise the set being described. Consecutive horn positions merge into one PRIME load.
3. **Assign.**
   - With ordinals: tokens before the first ordinal are globals. If the speaker puts weights *before* ordinals ("45kg, 第一组10次, 40kg第二组8次"), a weight immediately preceding 第N组 belongs to set N.
   - Without ordinals: pairing follows the speaker's order, weight→reps or reps→weight, detected from whichever comes first.
   - `N组` expands a single described set or adds blank sets; globals fill gaps.
4. **Match equipment** by the longest name/alias contained in the text. Brand mentions are a hard filter, the equipment kind (插片/挂片/绳索…) is a strong bonus, recently used machines break ties, and remaining ties are reported as ambiguous so the UI asks.

`TranscriptAccumulator` handles Apple's recognizer restarting after a pause. A new partial result that is not a continuation or revision of the current one (no shared prefix, shorter) commits the previous segment. Final results commit. Duplicates are detected by comparing text without punctuation.

## Testing

`swift test` runs the Core suite on macOS and Linux. The same files are compiled into the Xcode `LiftNoteTests` bundle via `#if canImport(LiftNoteCore)`. CI also builds the iOS app and widget for the simulator.

## Generated Xcode project

`LiftNote.xcodeproj` is produced by `tools/gen_xcodeproj.py` (explicit file references, three targets, shared scheme), which keeps the project diff-friendly and reproducible from the file tree.
