import SwiftUI
import GoldfishCore

/// Each miss points at the student's own sentence, or at the gap in the lesson.
/// The correct answer stays hidden until the same question is missed twice.
struct MissReviewView: View {
    @Environment(AppModel.self) private var model
    let chapterID: String

    var body: some View {
        if let exam = model.exam(chapterID), let run = model.data.latestRun(for: chapterID),
           let lesson = model.data.lessons.first(where: { $0.id == run.lessonID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if run.misses.isEmpty {
                        FishMessage(title: "No misses", message: "\(model.fishName) got everything right last time.", mood: .proud)
                    } else {
                        FishSays(
                            text: "Here's where I got stuck. Fix your sentences, then quiz me again.",
                            mood: .inspecting, size: 48
                        )
                    }
                    ForEach(run.misses, id: \.questionID) { answer in
                        if let question = exam.question(answer.questionID) {
                            MissCard(
                                chapterID: chapterID, question: question, answer: answer,
                                lesson: lesson, concept: exam.concept(question.conceptID)
                            )
                        }
                    }
                    if !run.misses.isEmpty {
                        NavigationLink(value: Route.quiz(chapterID, .recheck)) {
                            Text("Re-quiz the misses")
                        }
                        .buttonStyle(.primary)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Miss review")
            .navigationBarTitleDisplayMode(.inline)
            // A task gets the whole screen. The tab bar comes back when you leave.
            .toolbar(.hidden, for: .tabBar)
        } else {
            FishMessage(title: "No quiz yet", message: "Quiz the fish first.")
        }
    }
}

struct MissCard: View {
    @Environment(AppModel.self) private var model
    let chapterID: String
    let question: Question
    let answer: FishAnswer
    let lesson: Lesson
    let concept: Concept?

    @State private var comparing = false
    /// True while "Show me where to look" is open on a Gap.
    @State private var looking = false

    var body: some View {
        let stat = model.data.questionStats[question.id] ?? QuestionStat()
        let section = lesson.section(question.conceptID)
        Card {
            HStack(spacing: 8) {
                VerdictChip(verdict: answer.verdict)
                Text(concept?.name ?? "")
                    .font(.poppins(.footnote))
                    .foregroundStyle(Theme.ink3)
                Spacer()
            }
            Text(question.stem).font(.poppins(.headline))

            if answer.verdict == .mixUp, let index = answer.choice.optionIndex {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.fishName) said")
                        .font(.poppins(.subheadline))
                        .foregroundStyle(Theme.brand2)
                    Text("\(FishPrompt.letter(for: index))) \(question.option(index))")
                        .font(.poppins(.callout, weight: .medium))
                        .foregroundStyle(Theme.mixUpTint.text)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your lesson says")
                        .font(.poppins(.subheadline))
                        .foregroundStyle(Theme.brand2)
                    Group {
                        if section.isEmpty {
                            Text(answer.traceSentence ?? answer.quote)
                        } else {
                            HighlightedText(text: section, highlight: answer.traceSentence)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .paperStyle()
                }
            } else {
                // A Gap: the fish's thought bubble is empty because nothing was taught.
                HStack(spacing: 8) {
                    FishView(mood: .shrug, size: 40)
                    Text("Nothing in your lesson covered this.")
                        .font(.poppins(.callout, weight: .medium))
                }
                if let note = answer.note {
                    Text(note).font(.poppins(.caption)).foregroundStyle(.secondary)
                }
                WhereToLook(chapterID: chapterID, question: question, concept: concept, isOpen: $looking)
            }

            if stat.revealsAnswer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Answer: \(question.correctOption)").font(.poppins(.callout, weight: .semibold))
                    Text(question.explanation).font(.poppins(.caption)).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            } else {
                Text("The answer stays hidden until \(model.fishName) misses this twice. Try fixing your lesson first.")
                    .font(.poppins(.caption))
                    .foregroundStyle(.secondary)
            }

            // After a Fresh Water quiz, the old text for sections that still fail.
            if let previous = model.previousSection(chapterID: chapterID, conceptID: question.conceptID) {
                DisclosureGroup("Compare with last time", isExpanded: $comparing) {
                    Text(previous)
                        .font(.poppins(.callout))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.poppins(.callout))
            }

            // While the passage is open, its own button is the way on, so the lesson is written with it put away.
            if !looking {
                Button {
                    model.showBowl(chapterID, focus: question.conceptID)
                } label: {
                    Text("Fix this section")
                }
                .buttonStyle(.secondary)
            }
        }
    }
}

/// On a Gap, the part of the chapter that answers it, in the chapter's own words, with no model call.
/// It counts as a peek, and the answer itself still waits for a second miss.
///
/// It is framed for reading, not for picking out the answer: the whole part is shown with nothing lit up,
/// with the idea's "why" question to think about while reading. "Put it away and teach Finn" comes after a
/// short pause (`ReadingPause`) and hides the passage again, so the student explains it from memory
///. The Bowl's own-words check still flags anything copied.
struct WhereToLook: View {
    @Environment(AppModel.self) private var model
    let chapterID: String
    let question: Question
    let concept: Concept?
    @Binding var isOpen: Bool

    @State private var passage: Passage?
    @State private var openedAt = Date()
    @State private var pause: Double = ReadingPause.shortest
    @State private var missing = false

    var body: some View {
        if isOpen, let passage = passage {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where to look · peek \(model.data.currentLesson(for: chapterID)?.peekCount ?? 1)")
                    .font(.poppins(.subheadline))
                    .foregroundStyle(Theme.brand2)
                Text("Read the whole part, not just the line with the answer. Then put it away and explain it to \(model.fishName) in your own words.")
                    .font(.poppins(.footnote))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if let why = concept?.whyQuestion, !why.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("While you read, think about")
                            .font(.poppins(.caption, weight: .semibold))
                            .foregroundStyle(Theme.ink3)
                        Text(why)
                            .font(.poppins(.callout, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("FROM \(passage.chapterTitle.uppercased())")
                        .font(.poppins(.caption2))
                        .tracking(0.6)
                        .foregroundStyle(Theme.ink3)
                    Text(passage.text)
                        .font(.poppins(.callout))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.frost, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))

                TimelineView(.periodic(from: openedAt, by: 0.25)) { context in
                    let elapsed = context.date.timeIntervalSince(openedAt)
                    let ready = elapsed >= pause
                    VStack(alignment: .leading, spacing: 8) {
                        if !ready {
                            ProgressView(value: min(1, max(0, elapsed / pause)))
                                .tint(Theme.brand)
                                .accessibilityLabel("Reading time")
                        }
                        Button(ready ? "Put it away and teach \(model.fishName)" : "Take your time with it") {
                            putAway()
                        }
                        .buttonStyle(.primary)
                        .disabled(!ready)
                    }
                }
            }
            .padding(.top, 4)
        } else {
            Button("Show me where to look") { open() }
                .buttonStyle(.secondary)
            if missing {
                Text("This question's sentence could not be found in the chapter.")
                    .font(.poppins(.caption))
                    .foregroundStyle(Theme.ink3)
            }
        }
    }

    private func open() {
        guard let found = model.passageToRead(chapterID: chapterID, question: question) else {
            missing = true
            return
        }
        if let lesson = model.data.currentLesson(for: chapterID) {
            model.recordPeek(lessonID: lesson.id)
        }
        passage = found
        pause = ReadingPause.seconds(for: found.text)
        openedAt = Date()
        withAnimation { isOpen = true }
    }

    private func putAway() {
        withAnimation { isOpen = false }
        passage = nil
        model.showBowl(chapterID, focus: question.conceptID)
    }
}
