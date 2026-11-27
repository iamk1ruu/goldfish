import SwiftUI
import GoldfishCore

/// What a card quiz deals from.
enum QuizScope: Hashable {
    /// One chapter's due cards, or every idea if nothing is due.
    case chapterDue(String)
    /// One card for every idea in a chapter.
    case chapterAll(String)
    /// The due cards from every chapter in a deck (Mixed Bowl), or every idea if nothing is due.
    case deck(String)
}

/// Where the grading of one typed answer has got to.
enum RecallGrading: Equatable {
    case grading
    case graded(RecallGrade)
    /// The model could not be reached or gave no grade. Nothing is shown.
    case unavailable
}

/// A card quiz: the student answers unaided, one card at a time. Recall first, then choose and
/// say how sure, then the card turns over to the answer, the explanation and the chapter's own sentence.
/// These answers, not the fish's, decide mastery. The number of cards follows the content.
///
/// Every card missed on the first try comes back once at the end, as practice. Only first tries
/// are recorded, so the second try changes no score, box or mastery count.
@MainActor
@Observable
final class YourTurnSession {
    /// The first pass: the cards dealt.
    var cards: [QuizCard] = []
    /// The cards missed on the first try, filled in when the first pass ends.
    var retries: [QuizCard] = []
    /// Position in `cards` followed by `retries`.
    var index = 0
    var recall = ""
    var showingOptions = false
    var chosen: Int?
    var sure: Bool?
    var lastResult: StudentAnswer?
    /// First tries only. These are the answers that were recorded.
    var results: [StudentAnswer] = []
    /// How each second try went, by question ID. Never recorded.
    var retryResults: [String: Bool] = [:]
    /// Graded recall, by position in the deal.
    var grades: [Int: RecallGrading] = [:]
    var started = false
    /// True when nothing was due, so every idea was dealt instead.
    var dealtEverything = false
    /// The final exam has no second try.
    var allowsRetry = true
    private(set) var retriesDealt = false

    var deal: [QuizCard] {
        cards + retries
    }

    var current: QuizCard? {
        deal.indices.contains(index) ? deal[index] : nil
    }

    /// True during the second tries at the end.
    var isRetry: Bool {
        index >= cards.count
    }

    /// 1-based, during the second tries.
    var retryNumber: Int {
        index - cards.count + 1
    }

    var finished: Bool {
        started && index >= deal.count && (retriesDealt || !allowsRetry || cards.isEmpty)
    }

    func start(_ cards: [QuizCard], dealtEverything: Bool = false) {
        guard !started else { return }
        self.cards = cards
        self.dealtEverything = dealtEverything
        started = true
    }

    func submit(model: AppModel, isFinal: Bool) {
        guard let card = current, let choice = chosen else { return }
        let question = card.question
        let answer = StudentAnswer(
            questionID: question.id, conceptID: question.conceptID, recallText: recall,
            chosenIndex: choice, sure: sure, correct: choice == question.correctIndex,
            answeredAt: model.now, day: model.today, isFinal: isFinal
        )
        let position = index
        let recorded = !isRetry
        if recorded {
            let mastered = model.recordStudentAnswer(answer, chapterID: card.chapterID)
            results.append(answer)
            // A miss only turns the card over. Nothing sounds like a wrong-answer buzzer.
            model.cue(mastered ? .mastered : (answer.correct ? .correct : .flip))
        } else {
            // Practice only, so nothing is recorded.
            retryResults[question.id] = answer.correct
            model.cue(answer.correct ? .correct : .flip)
        }
        lastResult = answer

        // Shown, never scored, and only once the Grading Check has passed.
        let typed = recall
        if model.gradesRecall && !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            grades[position] = .grading
            Task {
                if let result = await model.gradeRecall(question: question, text: typed) {
                    if recorded {
                        model.setRecallGrade(result.grade, questionID: question.id, answeredAt: answer.answeredAt)
                    }
                    self.grades[position] = .graded(result)
                } else {
                    self.grades[position] = .unavailable
                }
            }
        }
    }

    func next() {
        index += 1
        recall = ""
        showingOptions = false
        chosen = nil
        sure = nil
        lastResult = nil
        if index == cards.count && allowsRetry && !retriesDealt {
            retries = OneMoreGo.cards(from: cards, firstTries: results)
            retriesDealt = true
        }
    }
}

/// The card quiz screen: Finn watching from his tank, the card, then how you did against him.
struct YourTurnView: View {
    @Environment(AppModel.self) private var model
    let scope: QuizScope

    @State private var session = YourTurnSession()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if session.started && session.cards.isEmpty {
                    FishMessage(title: "No cards yet", message: "Add a chapter here first. Its Hidden Exam brings the cards.", mood: .curious)
                } else if !session.finished {
                    QuizProgress(session: session)
                    if session.dealtEverything && session.index == 0 && session.lastResult == nil {
                        Text("Nothing is due, so here is every idea.")
                            .font(.poppins(.footnote))
                            .foregroundStyle(Theme.ink3)
                    }
                    YourTurnRunnerView(session: session, isFinal: false)
                } else {
                    YourTurnSummary(session: session, isFinal: false)
                    if case .deck = scope {
                        // The tab bar is hidden during a quiz, so the deck quiz needs its own way out.
                        Button("Back to the deck") {
                            if !model.path.isEmpty {
                                model.path.removeLast()
                            }
                        }
                        .buttonStyle(.primary)
                    } else if let chapterID = session.cards.first?.chapterID {
                        NavigationLink(value: Route.map(chapterID)) {
                            Text("See the Mastery Map")
                        }
                        .buttonStyle(.primary)
                    }
                }
            }
            .padding(16)
            .animation(.easeInOut(duration: 0.25), value: session.index)
        }
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // A task gets the whole screen. The tab bar comes back when you leave.
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: deal)
    }

    private var title: String {
        if case .deck(let id) = scope, let deck = model.data.deck(id) {
            return "\(deck.name) quiz"
        }
        return "Your Turn"
    }

    private func deal() {
        guard !session.started else { return }
        let progress = model.data.concepts
        let history = model.data.studentAnswers
        let today = model.today
        func cards(_ chapterID: String, everything: Bool) -> [QuizCard] {
            guard let exam = model.exam(chapterID) else { return [] }
            return QuizPicker.cards(exam: exam, chapterID: chapterID, progress: progress, history: history, today: today, everything: everything)
        }
        switch scope {
        case .chapterAll(let id):
            session.start(cards(id, everything: true))
        case .chapterDue(let id):
            let due = cards(id, everything: false)
            session.start(due.isEmpty ? cards(id, everything: true) : due, dealtEverything: due.isEmpty)
        case .deck(let id):
            let exams = model.chapters(inDeck: id).compactMap { chapter in
                model.exam(chapter.id).map { (chapterID: chapter.id, exam: $0) }
            }
            let due = QuizPicker.deckCards(exams: exams, progress: progress, history: history, today: today)
            if due.isEmpty {
                session.start(exams.flatMap { cards($0.chapterID, everything: true) }, dealtEverything: true)
            } else {
                session.start(due)
            }
        }
    }
}

/// How far through the deal you are, with Finn watching from his tank. He cheers a right answer and
/// perks up at a wrong one, because it is something you could teach him. He never looks upset.
struct QuizProgress: View {
    let session: YourTurnSession

    var body: some View {
        let right = session.results.filter { $0.correct }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.isRetry
                    ? "One more go · \(session.retryNumber) of \(session.retries.count)"
                    : "Card \(min(session.index + 1, session.cards.count)) of \(session.cards.count)")
                    .font(.poppins(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.ink2)
                Spacer()
                Text(session.isRetry ? "\(right) of \(session.cards.count) first try" : "\(right) right")
                    .font(.poppins(.footnote))
                    .foregroundStyle(Theme.ink3)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.rule)
                    Capsule()
                        .fill(Theme.brand)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            PixelTank(mood: mood, scale: 3, fishAt: UnitPoint(x: 0.5, y: 0.7), weeds: [0.04, 0.9], bubbles: 2)
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        }
    }

    /// The first pass fills the bar. The second tries come after it is full.
    private var progress: CGFloat {
        guard !session.isRetry else { return 1 }
        return CGFloat(session.index) / CGFloat(max(session.cards.count, 1))
    }

    private var mood: FishMood {
        guard let result = session.lastResult else { return .happy }
        return result.correct ? .proud : .curious
    }
}

/// One card: recall, then options and how sure, then the answer side.
struct YourTurnRunnerView: View {
    @Environment(AppModel.self) private var model
    let session: YourTurnSession
    let isFinal: Bool

    var body: some View {
        @Bindable var session = session
        if let card = session.current {
            let question = card.question
            let remaining = session.deal.count - session.index - 1
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    if let concept = model.exam(card.chapterID)?.concept(question.conceptID) {
                        Pill(text: concept.name, tint: Theme.Tint(text: Theme.link, fill: Theme.lavender))
                    }
                    if session.isRetry {
                        Pill(text: "One more go", tint: Theme.Tint(text: Theme.link, fill: Theme.lavender))
                    }
                    Spacer()
                }
                Text(question.stem)
                    .font(.poppins(.title3))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let result = session.lastResult {
                    answerSide(card: card, result: result)
                } else if !session.showingOptions {
                    if session.isRetry {
                        Text("You missed this one a few cards ago. Try it again from memory. It won't change your score.")
                            .font(.poppins(.footnote))
                            .foregroundStyle(Theme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Answer from memory first")
                        .font(.poppins(.subheadline))
                        .foregroundStyle(Theme.brand2)
                    TextField("Type what you remember…", text: $session.recall, axis: .vertical)
                        .lineLimit(2...5)
                        .paperStyle()
                    Button(session.recall.trimmingCharacters(in: .whitespaces).isEmpty ? "I can't recall it, show the options" : "Show the options") {
                        withAnimation { session.showingOptions = true }
                    }
                    .buttonStyle(.primary)
                } else {
                    if !session.recall.isEmpty {
                        Text("You wrote: \(session.recall)")
                            .font(.poppins(.caption))
                            .foregroundStyle(Theme.ink3)
                    }
                    ForEach(question.options.indices, id: \.self) { index in
                        OptionRow(
                            letter: FishPrompt.letter(for: index),
                            text: question.options[index],
                            selected: session.chosen == index
                        ) {
                            session.chosen = index
                            model.cue(.select)
                        }
                    }
                    // A second try is not scored, so it does not ask how sure you are.
                    if !session.isRetry {
                        Picker("How sure are you?", selection: $session.sure) {
                            Text("Sure").tag(Bool?.some(true))
                            Text("Unsure").tag(Bool?.some(false))
                        }
                        .pickerStyle(.segmented)
                    }
                    Button("Check") {
                        withAnimation { session.submit(model: model, isFinal: isFinal) }
                    }
                    .buttonStyle(.primary)
                    .disabled(session.chosen == nil)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.line)
            )
            // The next cards peek out underneath, so it reads as a deck.
            .background {
                ZStack {
                    if remaining >= 2 {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Theme.rule)
                            .padding(.horizontal, 20)
                            .offset(y: 16)
                    }
                    if remaining >= 1 {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Theme.line)
                            .padding(.horizontal, 10)
                            .offset(y: 8)
                    }
                }
            }
            .padding(.bottom, 16)
            // By position, so a second try of the card just answered still turns in as a new card.
            .id("\(session.index)-\(card.id)")
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
    }

    /// The card turned over: right or not, the answer, why, and the chapter's own sentence.
    @ViewBuilder
    private func answerSide(card: QuizCard, result: StudentAnswer) -> some View {
        let question = card.question
        Pill(
            text: session.isRetry ? (result.correct ? "Got it this time" : "Not yet") : (result.correct ? "You got it" : "Not quite"),
            tint: result.correct ? Theme.correctTint : Theme.mixUpTint
        )
        Text("Answer: \(FishPrompt.letter(for: question.correctIndex))) \(question.correctOption)")
            .font(.poppins(.callout, weight: .semibold))
            .foregroundStyle(Theme.ink)
        Text(question.explanation)
            .font(.poppins(.callout))
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 4) {
            Text("FROM YOUR CHAPTER")
                .font(.poppins(.caption2))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)
            Text(question.sourceQuote)
                .font(.poppins(.callout))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.frost, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))

        // What you typed before the options, next to the answer, with its grade once grading is on.
        if !result.recallText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("You wrote, from memory")
                    .font(.poppins(.subheadline))
                    .foregroundStyle(Theme.brand2)
                Text(result.recallText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .paperStyle()
                recallGrade(session.grades[session.index])
            }
        }

        if result.sureButWrong && !session.isRetry {
            Text("You were sure, so this one comes back first tomorrow.")
                .font(.poppins(.caption))
                .foregroundStyle(Theme.mixUpTint.text)
        }
        // A miss is something to teach: explaining it to Finn is the fix, not rereading the answer.
        if !result.correct && !isFinal {
            Button("Teach \(model.fishName) this") {
                model.showBowl(card.chapterID, focus: question.conceptID)
            }
            .buttonStyle(.secondary)
        }
        Button(isLastCard ? "See how you did" : "Next card") {
            withAnimation { session.next() }
        }
        .buttonStyle(.primary)
    }

    /// True when no card follows this one: the last second try, or the last card with nothing missed.
    private var isLastCard: Bool {
        if session.index + 1 < session.deal.count {
            return false
        }
        // At the end of the first pass, a miss means a second try still follows.
        if !session.isRetry && session.allowsRetry {
            return session.results.allSatisfy(\.correct)
        }
        return true
    }

    @ViewBuilder
    private func recallGrade(_ grading: RecallGrading?) -> some View {
        switch grading {
        case .grading?:
            HStack(spacing: 8) {
                BubbleDots()
                Text("Checking your words…")
                    .font(.poppins(.caption))
                    .foregroundStyle(Theme.ink3)
            }
        case .graded(let result)?:
            HStack(spacing: 8) {
                Pill(text: label(result.grade), tint: tint(result.grade))
                TierBadge(tier: result.tier)
            }
            Text(line(result.grade))
                .font(.poppins(.caption))
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        case .unavailable?, nil:
            EmptyView()
        }
    }

    private func label(_ grade: ShortAnswerGrade) -> String {
        switch grade {
        case .match: return "Says what the answer says"
        case .partial: return "Partly right"
        case .miss: return "Missed the key idea"
        }
    }

    private func tint(_ grade: ShortAnswerGrade) -> Theme.Tint {
        switch grade {
        case .match: return Theme.correctTint
        case .partial: return Theme.taughtTint
        case .miss: return Theme.gapTint
        }
    }

    /// Fixed lines, so nothing the model writes is shown: only its grade, which the Grading Check tested.
    private func line(_ grade: ShortAnswerGrade) -> String {
        switch grade {
        case .match: return "Your own words got there before you saw the options."
        case .partial: return "Close. Put your words next to the answer above and find what is missing."
        case .miss: return "Your words missed the key idea. Read the answer above, then try saying it your way."
        }
    }
}

/// How you did, against Finn. Your score is what you know from memory. Finn's is what your lesson taught
/// him on the same ideas. The gap says what to do next. "Sure but wrong" answers come first.
struct YourTurnSummary: View {
    @Environment(AppModel.self) private var model
    let session: YourTurnSession
    let isFinal: Bool

    var body: some View {
        let results = session.results
        let right = results.filter { $0.correct }.count
        let total = results.count
        let finnTried = session.cards.contains { finnStat($0) != nil }
        let finnRight = session.cards.filter { finnStat($0) == true }.count
        let ordered = results.filter { $0.sureButWrong } + results.filter { !$0.sureButWrong && !$0.correct } + results.filter { $0.correct }
        VStack(alignment: .leading, spacing: 14) {
            Text("You got \(right) of \(total)")
                .font(.poppins(.title2))
                .foregroundStyle(Theme.ink)

            // The second tries, kept apart from the score.
            if !session.retries.isEmpty {
                let again = session.retries.filter { session.retryResults[$0.question.id] == true }.count
                Text("One more go: \(again) of \(session.retries.count) right the second time. Your score counts first tries only.")
                    .font(.poppins(.callout))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if finnTried && !isFinal {
                HStack(spacing: 12) {
                    tile("You, from memory", "\(right)/\(total)")
                    tile("\(model.fishName), from your lesson", "\(finnRight)/\(total)")
                }
                SpeechBubble(text: comparison(you: right, finn: finnRight), tail: nil, name: model.fishName)
            }

            let sureWrong = results.filter { $0.sureButWrong }.count
            if sureWrong > 0 {
                Text("\(sureWrong) answer(s) you were sure about were wrong. Those come back first tomorrow.")
                    .font(.poppins(.callout))
                    .foregroundStyle(Theme.mixUpTint.text)
            }

            Card {
                ForEach(ordered, id: \.questionID) { answer in
                    if let card = session.cards.first(where: { $0.question.id == answer.questionID }) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: answer.correct ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                                .foregroundStyle(answer.correct ? Theme.correctTint.text : Theme.mixUpTint.text)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.question.stem)
                                    .font(.poppins(.callout))
                                    .foregroundStyle(Theme.ink)
                                if !answer.correct {
                                    Text("Answer: \(card.question.correctOption)")
                                        .font(.poppins(.caption))
                                        .foregroundStyle(Theme.ink3)
                                }
                            }
                            Spacer(minLength: 8)
                            if !answer.correct && !isFinal {
                                Button("Teach") {
                                    model.showBowl(card.chapterID, focus: card.question.conceptID)
                                }
                                .font(.poppins(.footnote, weight: .semibold))
                                .foregroundStyle(Theme.link)
                                .accessibilityLabel("Teach \(model.fishName) this")
                            }
                        }
                    }
                }
            }
        }
    }

    /// True if Finn's latest answer on this idea, from your lesson, was right. Nil if he has not tried it.
    private func finnStat(_ card: QuizCard) -> Bool? {
        guard let exam = model.exam(card.chapterID) else { return nil }
        let verdicts = exam.questions(in: .practice, concept: card.question.conceptID)
            .compactMap { model.data.questionStats[$0.id]?.lastVerdict }
        guard !verdicts.isEmpty else { return nil }
        return verdicts.contains(.correct)
    }

    /// The Goldfish lesson in one line: is the knowledge in your head, or only on paper?
    private func comparison(you: Int, finn: Int) -> String {
        if finn > you {
            return "Your lesson knows more than your memory. Teach me again from memory and the gap closes."
        }
        if you > finn {
            return "You know more than you wrote. Put it in the Bowl so I can learn it too."
        }
        return "Your memory and your lesson agree. Nice."
    }

    private func tile(_ label: String, _ value: String) -> some View {
        Card(flat: true) {
            Text(label)
                .font(.poppins(.footnote))
                .foregroundStyle(Theme.ink3)
            Text(value)
                .font(.poppins(size: 28, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.link)
        }
    }
}

/// A Figma option row: a letter badge and the option. The chosen one is outlined in purple.
struct OptionRow: View {
    let letter: String
    let text: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(letter)
                    .font(.poppins(.footnote, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Theme.ink)
                    .frame(width: 26, height: 26)
                    .background(selected ? Theme.brand : Theme.line, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(text)
                    .font(.poppins(.callout, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(selected ? Theme.lavender : Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .strokeBorder(selected ? Theme.brand : Theme.rule, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
