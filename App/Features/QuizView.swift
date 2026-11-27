import SwiftUI
import GoldfishCore

extension FishChoice {
    var optionIndex: Int? {
        if case .option(let index) = self {
            return index
        }
        return nil
    }
}

/// Runs one fish quiz: questions asked one at a time, each answer stored as it arrives.
/// Answers for an unchanged lesson come from the cache and cost nothing.
@MainActor
@Observable
final class QuizSession {
    var questions: [Question] = []
    var answers: [FishAnswer] = []
    var started = false
    var running = false
    var finished = false
    var errorMessage: String?
    /// Offline with no on-device model: the screen offers Your Turn instead.
    var offlineWithoutFish = false
    var run: QuizRun?
    /// True when finishing the quiz was the first teaching of the day, which lights the fire.
    var litFire = false
    /// The Pop Quiz plays the closing sound itself, when the student reaches the results.
    var playsEndCue = true

    var current: Question? {
        guard running, answers.count < questions.count else { return nil }
        return questions[answers.count]
    }

    func question(for answer: FishAnswer) -> Question? {
        questions.first { $0.id == answer.questionID }
    }

    func start(model: AppModel, chapterID: String, kind: QuizKind, prediction: Int?) async {
        guard !started else { return }
        started = true
        guard let exam = model.exam(chapterID), let lesson = model.data.currentLesson(for: chapterID) else {
            errorMessage = "Teach the fish something first."
            return
        }
        let lessonText = model.fishText(for: lesson)
        guard !lessonText.isEmpty else {
            errorMessage = "Your lesson is empty, so there is nothing to answer from yet."
            return
        }

        // No fixed length. A Pop Quiz asks one question per idea, so every idea is tested each round,
        // and a re-quiz asks every question the fish missed.
        switch kind {
        case .finalExam:
            questions = QuizPicker.finalExam(exam: exam)
        case .recheck:
            questions = QuizPicker.popQuiz(exam: exam, stats: model.data.questionStats, count: Int.max, onlyMissed: true)
            if questions.isEmpty {
                questions = QuizPicker.fishRound(exam: exam, stats: model.data.questionStats)
            }
        case .pop:
            questions = QuizPicker.fishRound(exam: exam, stats: model.data.questionStats)
        case .teachOff:
            // Every practice question, so two lessons are compared on the same set.
            questions = TeachOff.questions(exam: exam)
        }
        guard !questions.isEmpty else {
            errorMessage = "This exam has no questions of that kind."
            return
        }

        var run = QuizRun(
            id: UUID().uuidString, chapterID: chapterID, lessonID: lesson.id, kind: kind,
            lessonHash: AnswerCacheKey.lessonHash(lessonText), predictedScore: prediction, startedAt: model.now
        )
        let asker = FishAsker(engine: model.fishEngine(for: exam), rules: model.settings.quoteRules)
        running = true

        for question in questions {
            if Task.isCancelled {
                running = false
                return
            }
            if let cached = model.cachedAnswer(lessonText: lessonText, question: question) {
                answers.append(cached)
                continue
            }
            do {
                let answer = try await asker.ask(question, lesson: lessonText)
                model.storeAnswer(answer, lessonText: lessonText, question: question)
                answers.append(answer)
            } catch {
                running = false
                if Task.isCancelled { return }
                model.recordFishFailure(error)
                let errorKind = ModelErrorKind.classify(String(describing: error))
                offlineWithoutFish = errorKind == .offline
                errorMessage = errorKind.userMessage
                return
            }
        }

        run.answers = answers
        run.finishedAt = model.now
        litFire = model.finishQuiz(run)
        self.run = run
        running = false
        finished = true
        if playsEndCue {
            playEndCue(model: model)
        }
    }

    /// Lighting the fire outranks the cheer, so one sound plays at the end.
    func playEndCue(model: AppModel) {
        guard let run = run else { return }
        if litFire {
            model.cue(.fire)
        } else if run.misses.isEmpty {
            model.cue(.cheer)
        }
    }
}

/// The Pop Quiz and the re-quiz, one question at a time. Finn works through the questions in the
/// background while the student reads each answer: his pick, and the sentence of theirs he used, on one
/// card. "Next question" replaces it. After the last one comes the purple result header, and every answer
/// can still be read at the end.
struct QuizView: View {
    @Environment(AppModel.self) private var model
    let chapterID: String
    let kind: QuizKind

    @State private var session = QuizSession()
    /// The question on screen. Finn may already have answered further ahead.
    @State private var shown = 0
    @State private var showingResults = false

    var body: some View {
        ScrollView {
            if showingResults, let run = session.run {
                VStack(alignment: .leading, spacing: 0) {
                    QuizResultHeader(run: run)
                    QuizSummary(run: run, chapterID: chapterID, questions: session.questions)
                        .padding(16)
                }
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if !session.questions.isEmpty {
                        QuizSegments(questions: session.questions.count, answers: Array(session.answers.prefix(revealed)))
                    }
                    if let question = shownQuestion {
                        PopQuizQuestion(
                            question: question,
                            answer: shownAnswer,
                            failed: session.errorMessage != nil,
                            isLast: shown + 1 >= session.questions.count,
                            onNext: next
                        )
                    }
                    if let message = session.errorMessage, shownAnswer == nil {
                        QuizErrorCard(message: message, offline: session.offlineWithoutFish, chapterID: chapterID)
                    }
                    if session.finished && shown + 1 < session.questions.count {
                        Button("Skip to the results") {
                            withAnimation { showingResults = true }
                            session.playEndCue(model: model)
                        }
                        .font(.poppins(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.link)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
                .animation(.easeInOut(duration: 0.25), value: shown)
            }
        }
        .screenBackground()
        .safeAreaInset(edge: .bottom) {
            HybridMeter(answers: session.answers, isOnline: model.network.isOnline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Theme.surface)
                .overlay(alignment: .top) {
                    Theme.line.frame(height: 1)
                }
        }
        .navigationTitle(kind == .recheck ? "Re-quiz" : "Pop Quiz")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !showingResults && !session.questions.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(min(shown + 1, session.questions.count)) of \(session.questions.count)")
                        .font(.poppins(.footnote, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.ink3)
                }
            }
        }
        // A task gets the whole screen. The tab bar comes back when you leave.
        .toolbar(.hidden, for: .tabBar)
        // A sound as each answer is shown, not as Finn works ahead.
        .onChange(of: revealed) { old, new in
            guard !showingResults, new > old, session.answers.indices.contains(new - 1) else { return }
            switch session.answers[new - 1].verdict {
            case .correct: model.cue(.correct)
            case .mixUp: model.cue(.mixUp)
            case .gap: model.cue(.gap)
            }
        }
        .task {
            session.playsEndCue = false
            let prediction = kind == .pop ? model.pendingPrediction : nil
            model.pendingPrediction = nil
            await session.start(model: model, chapterID: chapterID, kind: kind, prediction: prediction)
        }
    }

    /// How many answers the student has seen, counting the one on screen.
    private var revealed: Int {
        min(session.answers.count, shown + 1)
    }

    private var shownQuestion: Question? {
        session.questions.indices.contains(shown) ? session.questions[shown] : nil
    }

    private var shownAnswer: FishAnswer? {
        session.answers.indices.contains(shown) ? session.answers[shown] : nil
    }

    private func next() {
        if shown + 1 < session.questions.count {
            withAnimation { shown += 1 }
        } else if session.finished {
            withAnimation { showingResults = true }
            session.playEndCue(model: model)
        }
    }
}

/// A segment per question, coloured by verdict as each answer is shown.
struct QuizSegments: View {
    let questions: Int
    let answers: [FishAnswer]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(questions, 1), id: \.self) { index in
                Capsule()
                    .fill(index < answers.count ? Theme.color(for: answers[index].verdict) : Theme.rule)
                    .frame(height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(answers.count) of \(questions) answered")
    }
}

/// One question. Finn thinks in his tank, then his pick lights up among the options and the sentence
/// of yours he used sits on paper below. A Gap never marks the option he guessed, so it cannot leak an
/// answer, and a Mix-up marks only his pick, never the right one.
struct PopQuizQuestion: View {
    @Environment(AppModel.self) private var model
    let question: Question
    let answer: FishAnswer?
    let failed: Bool
    let isLast: Bool
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(question.stem)
                .font(.poppins(.title3))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            PixelTank(mood: mood, scale: 3, fishAt: UnitPoint(x: 0.25, y: 0.62), weeds: [0.03, 0.9])
                .frame(height: 138)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let answer = answer {
                        VerdictChip(verdict: answer.verdict)
                            .padding(12)
                    }
                }

            VStack(spacing: 8) {
                ForEach(question.options.indices, id: \.self) { index in
                    FishOptionRow(letter: FishPrompt.letter(for: index), text: question.options[index], pick: pick(index))
                }
            }

            if let answer = answer {
                details(answer)
                Button(isLast ? "See how \(model.fishName) did" : "Next question", action: onNext)
                    .buttonStyle(.primary)
            } else if !failed {
                HStack(spacing: 10) {
                    BubbleDots()
                    Text("\(model.fishName) is thinking on this iPhone…")
                        .font(.poppins(.footnote))
                        .foregroundStyle(Theme.ink3)
                }
            }
        }
        .id(question.id)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    private var mood: FishMood {
        guard let answer = answer else { return failed ? .confused : .thinking }
        switch answer.verdict {
        case .correct: return .proud
        case .mixUp: return .confused
        case .gap: return .shrug
        }
    }

    private func pick(_ index: Int) -> FishOptionRow.Pick {
        guard let answer = answer, answer.verdict != .gap, answer.choice.optionIndex == index else { return .none }
        return answer.verdict == .correct ? .correct : .mixUp
    }

    @ViewBuilder
    private func details(_ answer: FishAnswer) -> some View {
        if answer.verdict == .gap {
            HStack(spacing: 10) {
                FishView(mood: .shrug, size: 40)
                Text("\"You didn't teach me this.\"")
                    .font(.poppins(.callout, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            if let note = answer.note {
                Text(note)
                    .font(.poppins(.caption))
                    .foregroundStyle(Theme.ink3)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Because you wrote")
                    .font(.poppins(.subheadline))
                    .foregroundStyle(Theme.brand2)
                HighlightedText(text: answer.traceSentence ?? answer.quote, highlight: answer.quote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .paperStyle()
            }
        }
        HStack(spacing: 8) {
            TierBadge(tier: answer.tier, cached: answer.cached)
            if !answer.cached && answer.latencyMs > 0 {
                Text(String(format: "%.1f s", Double(answer.latencyMs) / 1000))
                    .font(.poppins(.caption2).monospacedDigit())
                    .foregroundStyle(Theme.ink3)
            }
        }
    }
}

/// An option in the Pop Quiz. It cannot be tapped: Finn answers, the student watches.
struct FishOptionRow: View {
    enum Pick {
        case none
        case correct
        case mixUp
    }

    let letter: String
    let text: String
    let pick: Pick

    var body: some View {
        HStack(spacing: 12) {
            Text(letter)
                .font(.poppins(.footnote, weight: .semibold))
                .foregroundStyle(pick == .none ? Theme.ink : Color.white)
                .frame(width: 26, height: 26)
                .background(pick == .none ? Theme.line : tint.text, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(text)
                .font(.poppins(.callout, weight: .medium))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if pick != .none {
                Text("\(model.fishName.uppercased())'S ANSWER")
                    .font(.poppins(.caption2, weight: .semibold))
                    .foregroundStyle(tint.text)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(pick == .none ? Theme.card : tint.fill, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .strokeBorder(pick == .none ? Theme.rule : tint.text, lineWidth: pick == .none ? 1 : 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(pick == .none ? [] : .isSelected)
    }

    @Environment(AppModel.self) private var model

    private var tint: Theme.Tint {
        pick == .correct ? Theme.correctTint : Theme.mixUpTint
    }
}

/// The purple result header from the mock-up, after the last question.
struct QuizResultHeader: View {
    @Environment(AppModel.self) private var model
    let run: QuizRun

    var body: some View {
        let clean = run.misses.isEmpty
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(run.kind == .recheck ? "Re-quiz" : "Pop Quiz")
                    .font(.poppins(.footnote, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                Text("\(model.fishName) got \(run.score) of \(run.answers.count)\(clean ? "!" : "")")
                    .font(.poppins(size: 30, weight: .bold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
            }
            PixelTank(mood: clean ? FishMood.proud : FishMood.happy, scale: 4, fishAt: UnitPoint(x: 0.5, y: 0.62), weeds: [0.06, 0.86], bubbles: 3, jumps: clean)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background {
            ZStack(alignment: .topLeading) {
                Theme.banner
                Circle()
                    .fill(Theme.bannerGlow)
                    .frame(width: 360, height: 360)
                    .offset(x: -160, y: -200)
            }
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The list of answers so far, for the final exam and teach-offs. The question Finn is working on stays
/// at the top, with the answers before it below, newest first, so it never sinks down the screen.
struct QuizRunnerView: View {
    @Environment(AppModel.self) private var model
    let session: QuizSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let current = session.current {
                Card {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Question \(session.answers.count + 1) of \(session.questions.count)")
                                .font(.poppins(.footnote))
                                .foregroundStyle(Theme.ink3)
                            Text(current.stem)
                                .font(.poppins(.title3))
                                .foregroundStyle(Theme.ink)
                            Text("\(model.fishName) is thinking on this iPhone…")
                                .font(.poppins(.footnote))
                                .foregroundStyle(Theme.ink3)
                        }
                        Spacer()
                        BubbleDots()
                    }
                }
            }
            ForEach(Array(session.answers.enumerated().reversed()), id: \.offset) { index, answer in
                if let question = session.question(for: answer) {
                    AnswerRow(number: index + 1, question: question, answer: answer)
                }
            }
        }
    }
}

/// A segment per question over Finn's tank, for the teach-off. He thinks while a question runs,
/// and the latest verdict sits in the corner of the water.
struct QuizTankHeader: View {
    let session: QuizSession

    var body: some View {
        VStack(spacing: 12) {
            QuizSegments(questions: session.questions.count, answers: session.answers)

            PixelTank(mood: mood, scale: 3, fishAt: UnitPoint(x: 0.25, y: 0.62), weeds: [0.03, 0.9])
                .frame(height: 138)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if session.current == nil, let last = session.answers.last {
                        VerdictChip(verdict: last.verdict)
                            .padding(12)
                    }
                }
        }
    }

    private var mood: FishMood {
        if session.errorMessage != nil {
            return .confused
        }
        if session.current != nil {
            return .thinking
        }
        if let run = session.run {
            return run.misses.isEmpty ? .proud : .happy
        }
        return .curious
    }
}

/// One fish answer. A Gap never shows the option the fish guessed, so it cannot leak the answer.
struct AnswerRow: View {
    @Environment(AppModel.self) private var model
    let number: Int
    let question: Question
    let answer: FishAnswer

    var body: some View {
        Card {
            HStack(alignment: .top) {
                Text("\(number). \(question.stem)")
                    .font(.poppins(.subheadline, weight: .semibold))
                Spacer()
                VerdictChip(verdict: answer.verdict)
            }
            if answer.verdict == .gap {
                Text("\(model.fishName): \"You didn't teach me this.\"")
                    .font(.poppins(.callout))
                if let note = answer.note {
                    Text(note).font(.poppins(.caption)).foregroundStyle(.secondary)
                }
            } else if let index = answer.choice.optionIndex {
                Text("\(model.fishName): \(FishPrompt.letter(for: index))) \(question.option(index))")
                    .font(.poppins(.callout))
                if let trace = answer.traceSentence {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Because you wrote")
                            .font(.poppins(.subheadline))
                            .foregroundStyle(Theme.brand2)
                        Text(trace)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .paperStyle()
                    }
                }
            }
            HStack(spacing: 8) {
                TierBadge(tier: answer.tier, cached: answer.cached)
                if !answer.cached && answer.latencyMs > 0 {
                    Text(String(format: "%.1f s", Double(answer.latencyMs) / 1000))
                        .font(.poppins(.caption2).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Under the result header: Finn's line on the Call It guess, the chapter's mastery marks, what to do
/// next, and every answer to read again.
struct QuizSummary: View {
    @Environment(AppModel.self) private var model
    let run: QuizRun
    let chapterID: String
    let questions: [Question]

    @State private var showingAnswers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FishSays(text: line, mood: run.misses.isEmpty ? .happy : .curious, size: 48)

            if let exam = model.exam(chapterID) {
                Card {
                    HStack {
                        Text("Mastery")
                            .font(.poppins(.headline))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 8)
                        HStack(spacing: 4) {
                            ForEach(exam.concepts) { concept in
                                ConceptToken(state: model.data.conceptState(concept.id), size: 18)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(model.masteredCount(chapterID).mastered == 1
                            ? "1 idea mastered" : "\(model.masteredCount(chapterID).mastered) ideas mastered")
                    }
                }
            }

            if run.misses.isEmpty {
                HStack(spacing: 10) {
                    NavigationLink(value: Route.yourTurn(chapterID)) {
                        Text("Your Turn")
                    }
                    .buttonStyle(.primary)
                    Button("The Bowl") { model.showBowl(chapterID) }
                        .buttonStyle(.secondary)
                }
                NavigationLink(value: Route.finalExam(chapterID)) {
                    Text("Take the final exam")
                        .font(.poppins(.callout, weight: .semibold))
                        .foregroundStyle(Theme.link)
                        .frame(maxWidth: .infinity)
                }
            } else {
                NavigationLink(value: Route.review(chapterID)) {
                    Text("Review \(run.misses.count) miss\(run.misses.count == 1 ? "" : "es")")
                }
                .buttonStyle(.primary)
                HStack(spacing: 10) {
                    Button("Back to the Bowl") { model.showBowl(chapterID) }
                        .buttonStyle(.secondary)
                    NavigationLink(value: Route.yourTurn(chapterID)) {
                        Text("Your Turn")
                    }
                    .buttonStyle(.secondary)
                }
            }

            CuriousFishCard(chapterID: chapterID, run: run)

            DisclosureGroup(isExpanded: $showingAnswers) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(run.answers.enumerated()), id: \.offset) { index, answer in
                        if let question = questions.first(where: { $0.id == answer.questionID }) {
                            AnswerRow(number: index + 1, question: question, answer: answer)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Every answer (\(run.answers.count))")
                    .font(.poppins(.callout, weight: .semibold))
                    .foregroundStyle(Theme.link)
            }
        }
    }

    private var line: String {
        if let predicted = run.predictedScore {
            let difference = run.score - predicted
            if difference == 0 { return "You called \(predicted). Spot on." }
            if difference > 0 { return "You called \(predicted). Your lesson was better than you thought." }
            return "You called \(predicted). Your lesson wasn't as clear as you thought."
        }
        if run.misses.isEmpty {
            return "I got them all! Your lesson made sense to me."
        }
        return "\(run.misses.count) to fix. Let's look at where I got stuck."
    }
}

/// Once a session, after a correct answer, the fish asks "why" about that concept.
/// The question was written by the cloud with the exam, so it appears instantly.
struct CuriousFishCard: View {
    @Environment(AppModel.self) private var model
    let chapterID: String
    let run: QuizRun

    @State private var reply = ""
    @State private var warning: String?

    var body: some View {
        if let concept = conceptToAsk {
            Card {
                FishSays(text: concept.whyQuestion, mood: .curious, size: 48)
                TextField("Answer in a sentence. It goes into your lesson.", text: $reply, axis: .vertical)
                    .paperStyle()
                if let warning = warning {
                    Text(warning).font(.poppins(.caption)).foregroundStyle(Theme.mixUpTint.text)
                }
                HStack {
                    Button("Add to my lesson") { add(concept) }
                        .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    Button("Not now") { model.markCuriousAsked(chapterID) }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var conceptToAsk: Concept? {
        guard model.shouldAskCurious(chapterID), let exam = model.exam(chapterID),
              let correct = run.answers.first(where: { $0.verdict == .correct }),
              let question = exam.question(correct.questionID),
              let concept = exam.concept(question.conceptID),
              !concept.whyQuestion.isEmpty
        else { return nil }
        return concept
    }

    private func add(_ concept: Concept) {
        if PasteGuard.isLargeInsert(old: "", new: reply) || !model.copiedSentences(chapterID: chapterID, text: reply).isEmpty {
            warning = "Say it your way. That looks copied from the chapter."
            return
        }
        guard let lesson = model.data.currentLesson(for: chapterID) else { return }
        model.appendToSection(lessonID: lesson.id, conceptID: concept.id, sentence: reply)
        model.markCuriousAsked(chapterID)
    }
}

/// Explains a failed quiz. Offline with no on-device model, Your Turn still works.
struct QuizErrorCard: View {
    @Environment(AppModel.self) private var model
    let message: String
    let offline: Bool
    let chapterID: String

    var body: some View {
        Card {
            FishSays(text: message, mood: .confused, size: 48)
            if offline {
                Text("Your Turn needs no model, so you can still practise.")
                    .font(.poppins(.callout))
                NavigationLink(value: Route.yourTurn(chapterID)) {
                    Text("Go to Your Turn")
                }
                .buttonStyle(.primary)
            } else {
                Text("Settings, then a long press on the version number, opens Diagnostics with details.")
                    .font(.poppins(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
