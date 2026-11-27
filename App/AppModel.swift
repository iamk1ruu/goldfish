import Foundation
import Observation
import GoldfishCore

enum Route: Hashable {
    case chapter(String)
    case teach(String)
    case quiz(String, QuizKind)
    case review(String)
    /// The student's cards for a chapter: due ones first, or every idea if nothing is due.
    case yourTurn(String)
    /// One card for every idea in a chapter.
    case chapterQuiz(String)
    /// The due cards from every chapter in a deck (Mixed Bowl).
    case deckQuiz(String)
    case finalExam(String)
    case report(String)
    case map(String)
    case deck(String)
    case settings
    case diagnostics
    /// A teach-off with a friend, by challenge ID.
    case teachOff(String)
    /// Starting a teach-off on a chapter, by chapter ID.
    case newTeachOff(String)
}

/// The tabs of the Liquid Glass tab bar.
enum AppTab: Hashable {
    case today
    case decks
    case tutor
    case friends
    case settings
}

struct GoldfishError: Error, CustomStringConvertible {
    let description: String
}

/// The app's state. Rules live in GoldfishCore; this class wires them to storage, models and screens.
@MainActor
@Observable
final class AppModel {
    static let offsetKey = "goldfish.timeOffsetDays"

    var data: GoldfishData
    var settings = GoldfishSettings()
    /// The tab bar's selection.
    var tab: AppTab = .today
    /// One navigation stack per tab.
    var paths: [AppTab: [Route]] = [:]
    /// The selected tab's stack. Screens push and pop through this, so a flow stays in the tab it started in.
    var path: [Route] {
        get { paths[tab] ?? [] }
        set { paths[tab] = newValue }
    }
    private(set) var timeOffsetDays: Int
    /// The concept section Miss review asked the Bowl to open.
    var focusConceptID: String?
    /// The student's Call It guess, passed from the Bowl to the quiz.
    var pendingPrediction: Int?
    var fairCheckStatus: [String: String] = [:]
    var remoteChanges: [String] = []
    var storeMessage: String?

    let launch: LaunchOptions
    let firebaseReady: Bool
    let diagnostics = DiagnosticsLog()
    let network = NetworkMonitor()
    let sounds = SoundPlayer()
    /// Profiles, friends, shared chapters and teach-offs.
    let social: SocialModel

    /// Orla's search index for one deck, embedded once and kept until the deck's chapters change.
    @ObservationIgnored var tutorSearchCache: TutorSearchCache?

    @ObservationIgnored private let store: JSONStore?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var checkers: [String: OwnWordsChecker] = [:]
    @ObservationIgnored private var started = false

    init(launch: LaunchOptions, firebaseReady: Bool) {
        self.launch = launch
        self.firebaseReady = firebaseReady
        // Screenshot mode gets made-up friends, so the Friends screens can be checked in the Simulator.
        if launch.screenshotMode {
            social = SocialModel(backend: FixtureSocialBackend())
        } else if firebaseReady {
            social = SocialModel(backend: FirebaseSocialBackend())
        } else {
            social = SocialModel(backend: nil)
        }
        if launch.screenshotMode {
            timeOffsetDays = 0
            store = nil
            data = GoldfishData()
        } else {
            timeOffsetDays = UserDefaults.standard.integer(forKey: AppModel.offsetKey)
            let url = (try? JSONStore.defaultURL())
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("goldfish.json")
            let jsonStore = JSONStore(fileURL: url)
            let loaded = jsonStore.load()
            store = jsonStore
            data = loaded.data
            if case .recovered(let name) = loaded.outcome {
                storeMessage = "Saved data could not be read, so it was moved to \(name) and the app started fresh."
            }
        }
        if let screen = launch.screen {
            applyFixture(screen: screen)
        }
    }

    // MARK: Time

    var calendar: Calendar {
        Calendar.current
    }

    /// Real time plus the Diagnostics time machine.
    var now: Date {
        OffsetClock(offsetDays: timeOffsetDays, calendar: calendar).now
    }

    var today: Day {
        Day(now, calendar: calendar)
    }

    func setTimeOffset(_ days: Int) {
        timeOffsetDays = max(0, days)
        UserDefaults.standard.set(timeOffsetDays, forKey: AppModel.offsetKey)
    }

    // MARK: Saving

    func scheduleSave() {
        guard store != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let store = store else { return }
        do {
            try store.save(data)
        } catch {
            diagnostics.log("Save failed: \(error)")
        }
    }

    // MARK: Engines

    var fishName: String {
        let trimmed = data.fishName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Finn" : trimmed
    }

    var usesScriptedFish: Bool {
        launch.scriptedFish || !firebaseReady
    }

    func fishEngine(for exam: Exam) -> FishEngine {
        if usesScriptedFish {
            return ScriptedFishEngine(questions: exam.questions, delayMs: 300)
        }
        let cloudModel = settings.fishCloudModel
        return ResilientFishEngine(
            primary: FirebaseFishEngine(route: .hybrid, cloudModel: cloudModel),
            cloud: FirebaseFishEngine(route: .cloudOnly, cloudModel: cloudModel),
            log: logger()
        )
    }

    var examCompiler: ExamCompiler {
        if firebaseReady {
            return GeminiExamCompiler(modelName: settings.examModel)
        }
        return FixtureExamCompiler()
    }

    var reportWriter: ReportWriter {
        if firebaseReady {
            return GeminiReportWriter(modelName: settings.reportModel)
        }
        return FixtureReportWriter()
    }

    /// A log function that can be called from any thread.
    func logger() -> @Sendable (String) -> Void {
        let diagnostics = self.diagnostics
        return { message in
            Task { @MainActor in
                diagnostics.log(message)
            }
        }
    }

    // MARK: Startup and background

    func startup() async {
        guard !started else { return }
        started = true
        diagnostics.log("Started. Firebase \(firebaseReady ? "configured" : "not configured"). Fish: \(usesScriptedFish ? "scripted" : "hybrid").")
        if let message = storeMessage {
            diagnostics.log(message)
        }
        guard firebaseReady else { return }
        diagnostics.log("Apple's model: \(AppleModelStatus.summary)")
        let result = await RemoteSettings.fetch(into: settings)
        settings = result.settings
        remoteChanges = result.changed
        if !result.changed.isEmpty {
            diagnostics.log("Remote Config changed: \(result.changed.joined(separator: ", "))")
        }
        await flushPendingReports()
        await social.resume(model: self)
    }

    func enterBackground() {
        saveNow()
        guard !launch.screenshotMode, let plan = data.reminder, plan.enabled else { return }
        let due = dueChapters().first?.title
        let name = fishName
        Task {
            _ = await FeedingTime.schedule(plan, fishName: name, dueChapter: due)
        }
    }

    // MARK: Lookups

    func chapter(_ id: String) -> Chapter? {
        data.chapter(id)
    }

    func exam(_ chapterID: String) -> Exam? {
        data.exams[chapterID]
    }

    func dueChapters() -> [Chapter] {
        data.chapters.filter { Tides.isDue(data.chapterProgress[$0.id], today: today) }
    }

    func yourTurnDueCount(_ chapterID: String) -> Int {
        data.dueConceptCount(chapterID: chapterID, today: today)
    }

    func masteredCount(_ chapterID: String) -> (mastered: Int, total: Int) {
        guard let exam = exam(chapterID) else { return (0, 0) }
        return (MasteryRules.masteredCount(exam.concepts, progress: data.concepts), exam.concepts.count)
    }

    func checker(for chapterID: String) -> OwnWordsChecker? {
        if let cached = checkers[chapterID] {
            return cached
        }
        guard let chapter = chapter(chapterID) else { return nil }
        let checker = OwnWordsChecker(chapterText: chapter.sourceText)
        checkers[chapterID] = checker
        return checker
    }

    /// The lesson text the fish reads: sections in order, without copied sentences.
    func fishText(for lesson: Lesson) -> String {
        guard let exam = exam(lesson.chapterID) else { return "" }
        return LessonComposer.fishText(lesson: lesson, concepts: exam.concepts, checker: checker(for: lesson.chapterID))
    }

    func copiedSentences(chapterID: String, text: String) -> [String] {
        checker(for: chapterID)?.copiedSentences(in: text) ?? []
    }

    // MARK: Navigation

    /// Goes back to the Bowl if it is already open, otherwise opens it.
    func showBowl(_ chapterID: String, focus conceptID: String? = nil) {
        focusConceptID = conceptID
        if let index = path.lastIndex(of: .teach(chapterID)) {
            path.removeLast(path.count - index - 1)
        } else {
            path.append(.teach(chapterID))
        }
    }

    // MARK: Chapters

    /// The sample chapter goes into a Science deck, which becomes current so the student sees it.
    func loadSample() {
        data.addChapter(SampleChapter.chapter(createdAt: now), exam: SampleChapter.exam(compiledAt: now))
        if let deckID = data.chapter(SampleChapter.id)?.deckID {
            data.setCurrentDeck(deckID)
        }
        scheduleSave()
    }

    func finishOnboarding(fishName: String) {
        let trimmed = fishName.trimmingCharacters(in: .whitespacesAndNewlines)
        data.fishName = trimmed.isEmpty ? "Finn" : trimmed
        if chapter(SampleChapter.id) == nil {
            loadSample()
        }
        data.onboarded = true
        scheduleSave()
        tab = .today
        path = [.chapter(SampleChapter.id)]
    }

    /// Stores a chapter after the cloud writes and the validator checks its exam.
    /// A compile that leaves too few questions is retried once.
    func createChapter(title: String, text: String, pdfData: Data?, examDate: Date?) async throws -> Chapter {
        let id = UUID().uuidString.lowercased()
        // The chapter goes into the deck that was current when the student started, even if they switch while waiting.
        let deckID = data.currentDeck?.id
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let chapterTitle = cleanTitle.isEmpty ? "Untitled chapter" : cleanTitle
        var best: ExamBuildResult? = nil
        var lastError: Error? = nil
        var bestDraft: ExamDraft?

        for attempt in 1...2 {
            let started = Date()
            do {
                let draft = try await examCompiler.compile(title: chapterTitle, chapterText: text, pdfData: pdfData)
                let built = ExamValidator.build(
                    draft: draft, chapterID: id, chapterText: text,
                    compiledBy: firebaseReady ? settings.examModel : "fixture", compiledAt: now
                )
                diagnostics.record(ModelCallRecord(
                    lane: "exam", tier: .cloud, modelVersion: settings.examModel, latencyMs: Self.ms(since: started),
                    ok: true, detail: "attempt \(attempt): kept \(built.kept), dropped \(built.dropped.count)"
                ))
                for dropped in built.dropped.prefix(10) {
                    diagnostics.log("Dropped \"\(dropped.stem)\": \(dropped.reasons.joined(separator: "; "))")
                }
                if best == nil || built.kept > (best?.kept ?? 0) {
                    best = built
                    bestDraft = draft
                }
                if !built.needsRetry {
                    break
                }
            } catch {
                lastError = error
                diagnostics.record(ModelCallRecord(
                    lane: "exam", tier: .cloud, modelVersion: settings.examModel, latencyMs: Self.ms(since: started),
                    ok: false, detail: String(describing: error)
                ))
                let kind = ModelErrorKind.classify(String(describing: error))
                if kind == .offline || kind == .appCheck {
                    throw GoldfishError(description: kind.userMessage)
                }
            }
        }

        guard var built = best, !built.exam.questions(in: .practice).isEmpty else {
            if let error = lastError {
                throw GoldfishError(description: "The exam could not be written: \(ModelErrorKind.classify(String(describing: error)).userMessage)")
            }
            throw GoldfishError(description: "The cloud's questions did not pass the checks. Try again, or try a shorter chapter.")
        }

        // Every passage of the chapter should have a question. If some have none, one more cloud pass
        // writes concepts for just those passages, and the two drafts are joined.
        let firstCheck = CoverageCheck.check(questions: built.exam.questions, chapterText: text)
        if !firstCheck.uncovered.isEmpty, let draft = bestDraft {
            let started = Date()
            do {
                let extra = try await examCompiler.compile(
                    title: chapterTitle, chapterText: firstCheck.uncovered.joined(separator: "\n\n"), pdfData: nil
                )
                let rebuilt = ExamValidator.build(
                    draft: ExamDraft(concepts: draft.concepts + extra.concepts), chapterID: id, chapterText: text,
                    compiledBy: firebaseReady ? settings.examModel : "fixture", compiledAt: now
                )
                if rebuilt.kept > built.kept {
                    built = rebuilt
                }
                diagnostics.record(ModelCallRecord(
                    lane: "exam", tier: .cloud, modelVersion: settings.examModel, latencyMs: Self.ms(since: started),
                    ok: true, detail: "coverage top-up for \(firstCheck.uncovered.count) passage(s): now \(built.kept) questions"
                ))
            } catch {
                diagnostics.log("Coverage top-up failed, keeping the first exam: \(error)")
            }
        }
        var exam = built.exam
        exam.coverage = CoverageCheck.check(questions: exam.questions, chapterText: text).coverage

        let chapter = Chapter(id: id, title: chapterTitle, sourceText: text, createdAt: now, examDate: examDate, deckID: deckID)
        data.addChapter(chapter, exam: exam)
        scheduleSave()
        Task {
            await runFairCheck(chapterID: id)
        }
        return data.chapter(id) ?? chapter
    }

    func deleteChapter(_ chapterID: String) {
        data.deleteChapter(chapterID)
        checkers[chapterID] = nil
        path = []
        scheduleSave()
    }

    /// Forgets a chapter's own-words checker, for a chapter that is being deleted with its deck.
    func invalidateChecker(_ chapterID: String) {
        checkers[chapterID] = nil
    }

    func setExamDate(_ date: Date?, chapterID: String) {
        data.setExamDate(date, for: chapterID, calendar: calendar)
        scheduleSave()
    }

    /// Runs in the background while the student reads. Needs Apple's model.
    func runFairCheck(chapterID: String) async {
        guard firebaseReady, !usesScriptedFish, AppleModelStatus.isAvailable, let exam = exam(chapterID) else {
            return
        }
        fairCheckStatus[chapterID] = "Checking the exam on this iPhone…"
        let asker = FishAsker(
            engine: FirebaseFishEngine(route: .onDeviceOnly, cloudModel: settings.fishCloudModel),
            rules: settings.quoteRules
        )
        let started = Date()
        let results = await FairExamCheck.run(questions: exam.questions, asker: asker, onProgress: { done, total in
            Task { @MainActor in
                self.fairCheckStatus[chapterID] = "Checking the exam on this iPhone… \(done)/\(total)"
            }
        })
        guard let current = self.exam(chapterID) else { return }
        let checked = FairExamCheck.apply(results, to: current)
        data.exams[chapterID] = checked.exam
        fairCheckStatus[chapterID] = checked.dropped.isEmpty
            ? "Fair check: all \(results.count) questions can be answered from a good sentence."
            : "Fair check: removed \(checked.dropped.count) question(s) the fish could not answer even from an ideal sentence."
        diagnostics.record(ModelCallRecord(
            lane: "fairCheck", tier: .onDevice, modelVersion: ModelVersion.appleOnDevice,
            latencyMs: Self.ms(since: started), ok: true, detail: "\(results.count) checked, \(checked.dropped.count) dropped"
        ))
        scheduleSave()
    }

    func resetAll() {
        data = GoldfishData()
        try? store?.reset()
        checkers = [:]
        tutorSearchCache = nil
        paths = [:]
        tab = .today
        setTimeOffset(0)
    }

    static func ms(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }
}
