import SwiftUI
import GoldfishCore

/// The fish takes the held-out final questions from the current lesson, the student
/// takes a longer Your Turn, then the cloud writes the Report Card.
struct FinalExamView: View {
    @Environment(AppModel.self) private var model
    let chapterID: String

    enum Phase: Equatable {
        case intro
        case fish
        case student
        case writing
    }

    @State private var phase: Phase = .intro
    @State private var quiz = QuizSession()
    @State private var yourTurn = YourTurnSession()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch phase {
                case .intro:
                    intro
                case .fish:
                    Text("Part 1: \(model.fishName) takes the final").font(.poppins(.headline))
                    QuizRunnerView(session: quiz)
                    if let message = quiz.errorMessage {
                        QuizErrorCard(message: message, offline: quiz.offlineWithoutFish, chapterID: chapterID)
                    }
                    if quiz.finished, let run = quiz.run {
                        Card {
                            Text("Your explanation covered \(run.score) of \(run.answers.count)")
                                .font(.poppins(.title3, weight: .bold))
                            Text("These questions were never shown before, so only a real explanation gets them right.")
                                .font(.poppins(.callout))
                                .foregroundStyle(.secondary)
                        }
                        Button("Part 2: your turn") { startStudent() }
                            .buttonStyle(.primary)
                    }
                case .student:
                    Text("Part 2: you answer unaided").font(.poppins(.headline))
                    if !yourTurn.finished {
                        QuizProgress(session: yourTurn)
                    }
                    YourTurnRunnerView(session: yourTurn, isFinal: true)
                    if yourTurn.finished {
                        YourTurnSummary(session: yourTurn, isFinal: true)
                        Button("Write my Report Card") {
                            Task { await writeReport() }
                        }
                        .buttonStyle(.primary)
                    }
                case .writing:
                    CloudWritingView(
                        captions: ["Reading how the final went…", "Writing your Report Card…"],
                        tier: model.firebaseReady ? .cloud : .scripted
                    )
                    .padding(.top, 24)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .safeAreaInset(edge: .bottom) {
            if phase == .fish {
                HybridMeter(answers: quiz.answers, isOnline: model.network.isOnline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.surface)
                    .overlay(alignment: .top) {
                        Theme.line.frame(height: 1)
                    }
            }
        }
        .navigationTitle("Final exam")
        .navigationBarTitleDisplayMode(.inline)
        // A task gets the whole screen. The tab bar comes back when you leave.
        .toolbar(.hidden, for: .tabBar)
        .task(id: phase) {
            if phase == .fish {
                await quiz.start(model: model, chapterID: chapterID, kind: .finalExam, prediction: nil)
            }
        }
    }

    private var intro: some View {
        let finals = model.exam(chapterID)?.questions(in: .finalExam).count ?? 0
        let ideas = model.exam(chapterID)?.concepts.count ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            PixelTank(mood: .focused, scale: 4, fishAt: UnitPoint(x: 0.5, y: 0.62))
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
            SpeechBubble(
                text: "The big one! I'll answer \(finals) questions I've never seen, using only your current lesson. Then it's your turn.",
                tail: .top,
                name: model.fishName
            )
            Card {
                Label("\(finals) held-out questions for \(model.fishName)", systemImage: "graduationcap")
                Label("\(ideas) cards for you, one per idea, unaided", systemImage: "person.fill.checkmark")
                Label("A Report Card written in the cloud", systemImage: "cloud")
            }
            .font(.poppins(.callout, weight: .medium))
            Button("Start the final exam") { phase = .fish }
                .buttonStyle(.primary)
                .disabled(finals == 0 || model.data.currentLesson(for: chapterID) == nil)
        }
    }

    private func startStudent() {
        guard let exam = model.exam(chapterID) else { return }
        // An exam gives one try per card.
        yourTurn.allowsRetry = false
        // One card per idea, so the final reaches the whole chapter.
        yourTurn.start(QuizPicker.cards(
            exam: exam, chapterID: chapterID, progress: model.data.concepts, history: model.data.studentAnswers,
            today: model.today, everything: true
        ))
        phase = .student
    }

    private func writeReport() async {
        phase = .writing
        await model.finishFinalExam(chapterID: chapterID)
        if model.path.last == .finalExam(chapterID) {
            model.path.removeLast()
        }
        model.path.append(.report(chapterID))
    }
}
