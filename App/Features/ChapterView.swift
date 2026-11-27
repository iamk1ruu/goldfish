import SwiftUI
import GoldfishCore

/// A chapter's home: reading goals, teaching, Your Turn, the final exam and progress.
struct ChapterView: View {
    @Environment(AppModel.self) private var model
    let chapterID: String

    @State private var reading = false
    @State private var confirmDelete = false
    @State private var sharing = false

    var body: some View {
        if let chapter = model.chapter(chapterID), let exam = model.exam(chapterID) {
            content(chapter: chapter, exam: exam)
        } else {
            FishMessage(title: "Chapter not found", message: "It may have been deleted.")
        }
    }

    private func content(chapter: Chapter, exam: Exam) -> some View {
        let lesson = model.data.currentLesson(for: chapterID)
        let due = Tides.isDue(model.data.chapterProgress[chapterID], today: model.today)
        let counts = model.masteredCount(chapterID)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FishSays(
                    text: fishLine(due: due, taught: lesson != nil),
                    mood: due ? .forgetful : (lesson == nil ? .curious : .happy),
                    size: 48
                )

                Card {
                    HStack {
                        Text("Hidden Exam").font(.poppins(.headline))
                        Spacer()
                        if chapter.isSample {
                            Label("Built in", systemImage: "shippingbox")
                                .font(.poppins(.caption2, weight: .semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            TierBadge(tier: .cloud)
                        }
                    }
                    Text(examSummary(exam: exam, chapter: chapter))
                        .font(.poppins(.callout))
                        .foregroundStyle(.secondary)
                    if let coverage = exam.coverage {
                        // How much of the chapter the questions reach.
                        Pill(
                            text: coverage.isComplete
                                ? "Covers all \(coverage.passages) parts of the chapter"
                                : "Covers \(coverage.covered) of \(coverage.passages) parts of the chapter",
                            tint: coverage.isComplete ? Theme.correctTint : Theme.gapTint,
                            systemImage: coverage.isComplete ? "checkmark" : "circle.dashed"
                        )
                    }
                    if let status = model.fairCheckStatus[chapterID] {
                        Label(status, systemImage: "checkmark.shield")
                            .font(.poppins(.caption))
                            .foregroundStyle(.secondary)
                    }
                }

                // Told before reading that they will teach, with the concepts as reading goals.
                SectionHeader(title: "Ideas to teach", detail: "\(exam.concepts.count)")
                    .padding(.top, 8)
                Card {
                    Text("Read for these ideas. You'll explain each one to \(model.fishName) from memory.")
                        .font(.poppins(.callout))
                        .foregroundStyle(.secondary)
                    ForEach(exam.concepts) { concept in
                        HStack(spacing: 12) {
                            ConceptToken(state: model.data.conceptState(concept.id))
                            Text(concept.name)
                                .font(.poppins(.callout, weight: .medium))
                            Spacer()
                            StateChip(state: model.data.conceptState(concept.id))
                        }
                    }
                    Button {
                        reading = true
                    } label: {
                        Label("Read the chapter", systemImage: "book")
                    }
                    .padding(.top, 4)
                }

                VStack(spacing: 10) {
                    if due {
                        Button("Fresh Water: re-teach from memory") {
                            model.startFreshWater(chapterID)
                        }
                        .buttonStyle(.primary)
                    }
                    Button(teachTitle(lesson: lesson)) {
                        model.openTeaching(chapterID)
                    }
                    .buttonStyle(.primary)

                    HStack(spacing: 10) {
                        // Your Turn as cards: one per idea, so the whole chapter is quizzed.
                        NavigationLink(value: Route.chapterQuiz(chapterID)) {
                            Label("Quiz me · \(exam.concepts.count)", systemImage: "rectangle.stack")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.secondary)
                        NavigationLink(value: Route.finalExam(chapterID)) {
                            Label("Final exam", systemImage: "graduationcap")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.secondary)
                        .disabled(lesson == nil)
                    }
                    if !due, lesson != nil, model.data.latestRun(for: chapterID) != nil {
                        Button("Re-teach from memory now") {
                            model.startFreshWater(chapterID)
                        }
                        .font(.poppins(.callout))
                    }
                }

                SectionHeader(title: "Progress")
                    .padding(.top, 8)
                NavigationLink(value: Route.map(chapterID)) {
                    ListCard("Mastery Map") {
                        PixelMark(sprite: FinnSprites.mastered, scale: 4)
                    } detail: {
                        Text("You've mastered \(counts.mastered) of \(counts.total) concepts")
                            .font(.poppins(.footnote))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .buttonStyle(.plain)
                if model.data.reports[chapterID] != nil {
                    NavigationLink(value: Route.report(chapterID)) {
                        ListCard("Report Card") {
                            PixelMark(sprite: FinnSprites.cap, scale: 3)
                        } detail: {
                            Text("Written in the cloud after the final exam")
                                .font(.poppins(.footnote))
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                    .buttonStyle(.plain)
                }

                withFriends(chapter: chapter)

                examDateCard(chapter: chapter)

                if !chapter.isSample {
                    Button("Delete chapter", role: .destructive) {
                        confirmDelete = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $reading) {
            ReaderView(chapter: chapter)
        }
        .sheet(isPresented: $sharing) {
            ShareChapterSheet(chapterID: chapterID)
        }
        .confirmationDialog("Delete this chapter and all its progress?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.deleteChapter(chapterID)
            }
        }
    }

    private func examSummary(exam: Exam, chapter: Chapter) -> String {
        let practice = exam.questions(in: .practice).count
        let final = exam.questions(in: .finalExam).count
        let yourTurn = exam.questions(in: .yourTurn).count
        let author = chapter.isSample ? "Written by hand for the sample chapter" : "Written by \(exam.compiledBy) in the cloud"
        return "\(author). \(exam.concepts.count) concepts, \(practice) practice, \(final) final and \(yourTurn) Your Turn questions. You only see a question after \(model.fishName) has tried it."
    }

    /// What the fish says at the top of the chapter, matched to his mood.
    private func fishLine(due: Bool, taught: Bool) -> String {
        if due {
            return "I forgot this one. Fresh Water will bring it back."
        }
        if !taught {
            return "I haven't learned this yet. Read it, then teach me."
        }
        return "I still remember this one. Quiz me, or take your turn."
    }

    private func teachTitle(lesson: Lesson?) -> String {
        guard let lesson = lesson else { return "Teach \(model.fishName)" }
        return lesson.kind == .freshWater ? "Continue Fresh Water" : "Open the Bowl"
    }

    /// Share the chapter, or start a teach-off on it.
    @ViewBuilder
    private func withFriends(chapter: Chapter) -> some View {
        if model.social.available {
            SectionHeader(title: "With friends")
                .padding(.top, 8)
            if let sharer = chapter.sharedBy {
                Label("Shared by \(sharer)", systemImage: "person.crop.circle")
                    .font(.poppins(.footnote))
                    .foregroundStyle(Theme.ink3)
            }
            if model.data.social == nil {
                Button {
                    model.tab = .friends
                } label: {
                    ListCard("Teach-off with a friend") {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.link)
                    } detail: {
                        Text("Turn on friends first, in the Friends tab")
                            .font(.poppins(.footnote))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: Route.newTeachOff(chapterID)) {
                    ListCard("Teach-off with a friend") {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.link)
                    } detail: {
                        Text("Both fish take the same questions. See whose lesson worked")
                            .font(.poppins(.footnote))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .buttonStyle(.plain)
                Button {
                    sharing = true
                } label: {
                    ListCard("Share this chapter") {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.link)
                    } detail: {
                        Text(model.data.sharedCodes[chapterID].map { "Code \(ShareCode.display($0))" }
                             ?? "Your friend gets the chapter and its questions, not your lesson")
                            .font(.poppins(.footnote))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func examDateCard(chapter: Chapter) -> some View {
        Card {
            Toggle("Exam date", isOn: Binding(
                get: { chapter.examDate != nil },
                set: { on in
                    let date = on ? (Calendar.current.date(byAdding: .day, value: 14, to: model.now) ?? model.now) : nil
                    model.setExamDate(date, chapterID: chapterID)
                }
            ))
            if let date = chapter.examDate {
                DatePicker("Date", selection: Binding(
                    get: { date },
                    set: { model.setExamDate($0, chapterID: chapterID) }
                ), displayedComponents: .date)
                Text("Reviews are spaced to fit, with the last one the day before.")
                    .font(.poppins(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The built-in reader. Peeks from the Bowl open this too.
struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    let chapter: Chapter

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(chapter.sourceText)
                    .font(.poppins(.body))
                    .lineSpacing(4)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(chapter.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
