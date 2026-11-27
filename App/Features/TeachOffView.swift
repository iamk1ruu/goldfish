import SwiftUI
import GoldfishCore

/// A teach-off. Your Finn takes every practice question from your lesson, and the result is compared
/// with your friend's Finn on the same questions. Only verdicts are shared, never the lessons.
struct TeachOffView: View {
    enum Mode: Hashable {
        /// Choose a friend and send a new teach-off on this chapter.
        case new(chapterID: String)
        /// A teach-off that already exists.
        case existing(challengeID: String)
    }

    @Environment(AppModel.self) private var model
    let mode: Mode

    @State private var session = QuizSession()
    @State private var friendID: String?
    /// After a new teach-off is sent, the screen shows it like an existing one.
    @State private var sentID: String?
    @State private var gettingChapter = false

    private var challengeID: String? {
        if let sentID = sentID { return sentID }
        if case .existing(let id) = mode { return id }
        return nil
    }

    private var card: TeachOffCard? {
        challengeID.flatMap { model.social.card($0) }
    }

    private var chapterID: String? {
        switch mode {
        case .new(let id): return id
        case .existing: return card?.challenge.chapterID
        }
    }

    private var friendName: String {
        if let card = card {
            return card.challenge.other(than: model.data.social?.uid ?? "").name
        }
        return model.social.friends.first { $0.id == friendID }?.name ?? "your friend"
    }

    private var lessonReady: Bool {
        guard let id = chapterID, let lesson = model.data.currentLesson(for: id) else { return false }
        return !model.fishText(for: lesson).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if session.started {
                    QuizTankHeader(session: session)
                    QuizRunnerView(session: session)
                    if let error = session.errorMessage {
                        FishSays(text: error, mood: .confused, size: 48)
                    }
                    if session.finished && model.social.working {
                        HStack(spacing: 10) {
                            BubbleDots()
                            Text("Sending your result…")
                                .font(.poppins(.footnote))
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                }
                if !session.started || (session.finished && !model.social.working) {
                    content
                }
                if let message = model.social.message {
                    Label(message, systemImage: "info.circle")
                        .font(.poppins(.footnote))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Teach-off")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(session.running ? .hidden : .visible, for: .tabBar)
        .verdictSounds(session: session)
        .refreshable {
            await model.social.refresh(model: model)
        }
        .task {
            if card == nil, case .existing = mode {
                await model.social.refresh(model: model)
            }
        }
        .onChange(of: session.finished) { _, finished in
            if finished {
                Task { await send() }
            }
        }
    }

    // MARK: What to show

    @ViewBuilder
    private var content: some View {
        if let card = card, let mine = card.mine {
            results(card: card, mine: mine)
        } else if case .new(let id) = mode {
            newTeachOff(chapterID: id)
        } else if let card = card {
            yourTurn(card: card)
        } else {
            FishMessage(title: "Teach-off not found", message: "Pull down to refresh. It may have been deleted.", mood: .shrug)
        }
    }

    private func intro(questions: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PixelTank(mood: .focused, scale: 3, fishAt: UnitPoint(x: 0.3, y: 0.62), weeds: [0.04, 0.9], bubbles: 2)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
            SpeechBubble(
                text: "I'll take all \(questions) practice questions from your lesson. \(friendName)'s fish takes the same ones from theirs. Only our scores are shared, never your lessons.",
                tail: .top,
                name: model.fishName
            )
        }
    }

    private func questionCount(_ chapterID: String?) -> Int {
        guard let id = chapterID, let exam = model.exam(id) else { return 0 }
        return TeachOff.questions(exam: exam).count
    }

    // A new teach-off: pick a friend, then run.
    @ViewBuilder
    private func newTeachOff(chapterID: String) -> some View {
        let friends = model.social.friends
        intro(questions: questionCount(chapterID))
        if model.data.social == nil || friends.isEmpty {
            Card {
                Text(model.data.social == nil ? "Turn on friends first." : "Add a friend first.")
                    .font(.poppins(.headline))
                Text("A teach-off is with someone on your friends list.")
                    .font(.poppins(.callout))
                    .foregroundStyle(Theme.ink2)
                Button("Go to Friends") {
                    model.tab = .friends
                }
                .buttonStyle(.secondary)
            }
        } else {
            SectionHeader(title: "Who with?")
            ForEach(friends) { friend in
                OptionRow(letter: String(friend.name.prefix(1)).uppercased(), text: friend.name, selected: friendID == friend.id) {
                    friendID = friend.id
                    model.cue(.select)
                }
            }
            runButton(chapterID: chapterID, title: "Start the teach-off", enabled: friendID != nil)
        }
    }

    // Your friend sent it, and your Finn has not taken it yet.
    @ViewBuilder
    private func yourTurn(card: TeachOffCard) -> some View {
        let challenge = card.challenge
        let have = model.chapter(challenge.chapterID) != nil
        intro(questions: have ? questionCount(challenge.chapterID) : 0)
        Card {
            Text("\(challenge.fromName) challenged you on \"\(challenge.chapterTitle)\".")
                .font(.poppins(.headline))
            Text("Their fish has already taken it. Teach yours, and you'll see both results.")
                .font(.poppins(.callout))
                .foregroundStyle(Theme.ink2)
        }
        if !have {
            Button {
                gettingChapter = true
                Task {
                    _ = await model.social.open(code: challenge.chapterCode, model: model)
                    gettingChapter = false
                }
            } label: {
                if gettingChapter { BubbleDots() } else { Text("Get the chapter") }
            }
            .buttonStyle(.primary)
            .disabled(gettingChapter)
        } else {
            runButton(chapterID: challenge.chapterID, title: "Run the teach-off", enabled: true)
        }
    }

    /// Teach first if the lesson is empty, then run.
    @ViewBuilder
    private func runButton(chapterID: String, title: String, enabled: Bool) -> some View {
        if !lessonReady {
            Button("Teach \(model.fishName) this chapter first") {
                model.openTeaching(chapterID)
            }
            .buttonStyle(.primary)
            Text("Come back here when your lesson is written. Pop Quizzes along the way are fine: \(friendName) can use them too.")
                .font(.poppins(.caption))
                .foregroundStyle(Theme.ink3)
        } else {
            Button(title) {
                run(chapterID: chapterID)
            }
            .buttonStyle(.primary)
            .disabled(!enabled || model.social.working)
            Button("Improve the lesson first") {
                model.openTeaching(chapterID)
            }
            .buttonStyle(.secondary)
        }
    }

    // Both sides, or yours while you wait.
    @ViewBuilder
    private func results(card: TeachOffCard, mine: ChallengeResult) -> some View {
        let exam = model.exam(card.challenge.chapterID)
        Text(card.challenge.chapterTitle)
            .font(.poppins(.title2))
            .foregroundStyle(Theme.ink)
        if let theirs = card.theirs {
            let comparison = exam.map { TeachOff.compare(mine: mine.score, theirs: theirs.score, exam: $0) }
            let yours = comparison?.mine ?? mine.score.right
            let theirsRight = comparison?.theirs ?? theirs.score.right
            let total = comparison?.total ?? mine.score.total
            HStack(spacing: 12) {
                tile("Your lesson", "\(yours)/\(total)")
                tile("\(theirs.name)'s lesson", "\(theirsRight)/\(total)")
            }
            if let comparison = comparison {
                SpeechBubble(text: TeachOff.finnLine(comparison, fishName: model.fishName, friendName: theirs.name), tail: nil, name: model.fishName)
                conceptRows(comparison, friendName: theirs.name)
            }
        } else {
            HStack(spacing: 12) {
                tile("Your lesson", "\(mine.score.right)/\(mine.score.total)")
                tile("\(friendName)'s lesson", "…")
            }
            FishSays(text: "Waiting for \(friendName)'s fish. Pull down to check again.", mood: .sleepy, size: 48)
        }
        Text("Your fish answered \(mine.score.onDevice) on this iPhone and \(mine.score.cloud) in the cloud.")
            .font(.poppins(.caption))
            .foregroundStyle(Theme.ink3)
        if let id = chapterID, model.data.latestRun(for: id)?.misses.isEmpty == false {
            NavigationLink(value: Route.review(id)) {
                Text("Fix what \(model.fishName) missed")
            }
            .buttonStyle(.primary)
        }
        if let id = chapterID, model.chapter(id) != nil, lessonReady {
            Button("Run it again with my new lesson") {
                run(chapterID: id)
            }
            .buttonStyle(.secondary)
            .disabled(model.social.working)
        }
    }

    private func conceptRows(_ comparison: TeachOffComparison, friendName: String) -> some View {
        Card {
            Text("Idea by idea")
                .font(.poppins(.headline))
            ForEach(comparison.concepts) { concept in
                HStack {
                    Text(concept.name)
                        .font(.poppins(.callout))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Text("You \(concept.mine)/\(concept.total)")
                        .font(.poppins(.footnote, weight: concept.mine > concept.theirs ? Font.Weight.bold : Font.Weight.regular).monospacedDigit())
                        .foregroundStyle(concept.mine >= concept.theirs ? Theme.link : Theme.ink3)
                    Text("\(friendName) \(concept.theirs)/\(concept.total)")
                        .font(.poppins(.footnote, weight: concept.theirs > concept.mine ? Font.Weight.bold : Font.Weight.regular).monospacedDigit())
                        .foregroundStyle(concept.theirs >= concept.mine ? Theme.link : Theme.ink3)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        Card(flat: true) {
            Text(label)
                .font(.poppins(.footnote))
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)
            Text(value)
                .font(.poppins(size: 28, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.link)
        }
    }

    // MARK: Running and sending

    private func run(chapterID: String) {
        model.social.message = nil
        session = QuizSession()
        let session = session
        Task {
            await session.start(model: model, chapterID: chapterID, kind: .teachOff, prediction: nil)
        }
    }

    private func send() async {
        guard session.finished, let run = session.run else { return }
        if case .new(let chapterID) = mode, sentID == nil {
            guard let friend = model.social.friends.first(where: { $0.id == friendID }) else { return }
            sentID = await model.social.startTeachOff(chapterID: chapterID, friend: friend, answers: run.answers, model: model)
            guard sentID != nil else { return }
        } else if let id = challengeID {
            await model.social.submit(challengeID: id, answers: run.answers, model: model)
            guard model.social.card(id)?.mine != nil else { return }
        }
        // The results replace the quiz once they are in. On a failure the answers stay on screen with the message.
        session = QuizSession()
    }
}

/// Share a chapter with a code. Your friend gets the chapter and its Hidden Exam, never your lesson.
struct ShareChapterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let chapterID: String

    var body: some View {
        let code = model.data.sharedCodes[chapterID]
        let title = model.chapter(chapterID)?.title ?? "this chapter"
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FishSays(text: "Your friend gets \"\(title)\" and the same hidden questions. Your lesson stays here.", mood: .curious, size: 48)
                    if let code = code {
                        let shown = ShareCode.display(code)
                        Card {
                            Text("SHARE CODE")
                                .font(.poppins(.caption2))
                                .tracking(0.6)
                                .foregroundStyle(Theme.ink3)
                            Text(shown)
                                .font(.poppins(size: 32, weight: .bold).monospaced())
                                .foregroundStyle(Theme.link)
                                .textSelection(.enabled)
                            Text("In Goldfish, they open the Friends tab and enter it under \"Open a shared chapter\".")
                                .font(.poppins(.footnote))
                                .foregroundStyle(Theme.ink3)
                        }
                        ShareLink(item: "Learn \"\(title)\" with me on Goldfish. Open the Friends tab and enter the code \(shown).") {
                            Label("Send the code", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.primary)
                        Button("Stop sharing", role: .destructive) {
                            Task { await model.social.stopSharing(chapterID: chapterID, model: model) }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Button {
                            Task { _ = await model.social.share(chapterID: chapterID, model: model) }
                        } label: {
                            if model.social.working { BubbleDots() } else { Text("Make a share code") }
                        }
                        .buttonStyle(.primary)
                        .disabled(model.social.working)
                    }
                    Text("Anyone with the code can read the chapter's text, so only share material you're allowed to pass on, like your own notes.")
                        .font(.poppins(.caption))
                        .foregroundStyle(Theme.ink3)
                    if let message = model.social.message {
                        Label(message, systemImage: "info.circle")
                            .font(.poppins(.footnote))
                            .foregroundStyle(Theme.ink2)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Share chapter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
