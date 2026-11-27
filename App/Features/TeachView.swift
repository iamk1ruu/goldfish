import SwiftUI
import GoldfishCore

/// The Bowl. One field per concept, a word limit, no pasting, copied
/// sentences flagged, and the chapter hidden behind a counted Peek button.
struct TeachView: View {
    @Environment(AppModel.self) private var model
    let chapterID: String

    @State private var reading = false
    @State private var predicting = false
    @State private var startAfterSheet = false
    @State private var pasteBlocked = false
    /// The section a paste was blocked in, so the keyboard can come back to it.
    @State private var blockedConceptID: String?
    @State private var editorResets: [String: Int] = [:]
    @FocusState private var focused: String?

    var body: some View {
        if let chapter = model.chapter(chapterID), let exam = model.exam(chapterID),
           let lesson = model.data.currentLesson(for: chapterID) {
            bowl(chapter: chapter, exam: exam, lesson: lesson)
        } else {
            VStack(spacing: 16) {
                FishMessage(title: "Nothing in the Bowl yet", message: "Start a lesson to teach this chapter.", mood: .curious)
                Button("Start teaching") { model.openTeaching(chapterID) }
                    .buttonStyle(.primary)
                    .padding(.horizontal)
            }
        }
    }

    private func bowl(chapter: Chapter, exam: Exam, lesson: Lesson) -> some View {
        let words = LessonComposer.wordCount(lesson)
        let limit = model.settings.bowlWordLimit
        let overLimit = words > limit
        let fishText = model.fishText(for: lesson)
        // One question per idea, so the quiz is as long as the chapter has ideas.
        let quizLength = QuizPicker.fishRound(exam: exam, stats: model.data.questionStats).count

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(lesson: lesson)
                    ForEach(exam.concepts) { concept in
                        sectionEditor(concept: concept, lesson: lesson)
                            .id(concept.id)
                    }
                }
                .padding(16)
            }
            .onAppear {
                if let focus = model.focusConceptID {
                    proxy.scrollTo(focus, anchor: .top)
                    focused = focus
                    model.focusConceptID = nil
                }
            }
        }
        .screenBackground()
        .navigationTitle(lesson.kind == .freshWater ? "Fresh Water" : "The Bowl")
        .navigationBarTitleDisplayMode(.inline)
        // A task gets the whole screen. The tab bar comes back when you leave.
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.recordPeek(lessonID: lesson.id)
                    reading = true
                } label: {
                    Label("Peek (\(lesson.peekCount))", systemImage: "eye")
                }
                .accessibilityLabel("Peek at the chapter. You have peeked \(lesson.peekCount) times.")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                HStack {
                    Text("\(words) of \(limit) words")
                        .foregroundStyle(overLimit ? Theme.mixUpTint.text : Theme.ink3)
                    Spacer()
                    Text("Peeks: \(lesson.peekCount)")
                        .foregroundStyle(Theme.ink3)
                }
                .font(.poppins(.footnote).monospacedDigit())
                if overLimit {
                    Text("Trim your lesson to \(limit) words so \(model.fishName) can read it on this iPhone.")
                        .font(.poppins(.caption))
                        .foregroundStyle(Theme.mixUpTint.text)
                }
                Button("Quiz \(model.fishName)") {
                    focused = nil
                    predicting = true
                }
                .buttonStyle(.primary)
                .disabled(fishText.isEmpty || overLimit || quizLength == 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(Theme.surface)
            .overlay(alignment: .top) {
                Theme.line.frame(height: 1)
            }
        }
        .sheet(isPresented: $reading) {
            ReaderView(chapter: chapter)
        }
        .sheet(isPresented: $predicting, onDismiss: {
            if startAfterSheet {
                startAfterSheet = false
                model.path.append(.quiz(chapterID, .pop))
            }
        }) {
            CallItSheet(fishName: model.fishName, questionCount: quizLength) { guess in
                model.pendingPrediction = guess
                startAfterSheet = true
                predicting = false
            }
        }
        .alert("Say it your way", isPresented: $pasteBlocked) {
            Button("OK", role: .cancel) {
                // Back to the same section, with the text as it was before the paste.
                focused = blockedConceptID
            }
        } message: {
            Text("Pasting is blocked in the Bowl. Explain it in your own words, as if to a friend.")
        }
    }

    @ViewBuilder
    private func header(lesson: Lesson) -> some View {
        if lesson.kind == .freshWater {
            FishSays(
                text: "I forgot everything! Teach me again from memory. Your old lesson is hidden until after the quiz.",
                mood: .forgetful, size: 48
            )
        } else {
            FishSays(
                text: "Teach me! A few sentences per idea, in your own words. I only know what you write here.",
                mood: .listening, size: 48
            )
        }
        Text("The chapter stays hidden while you teach. Teaching from memory is what makes it stick.")
            .font(.poppins(.footnote))
            .foregroundStyle(Theme.ink3)
    }

    private func sectionEditor(concept: Concept, lesson: Lesson) -> some View {
        let text = lesson.section(concept.id)
        let copied = model.copiedSentences(chapterID: chapterID, text: text)
        // The concept is a Figma field label. The editor is paper: the student's words are the only cream thing.
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(concept.name)
                    .font(.poppins(.subheadline))
                    .foregroundStyle(Theme.brand2)
                Spacer()
                StateChip(state: model.data.conceptState(concept.id))
            }
            TextEditor(text: binding(conceptID: concept.id, lessonID: lesson.id))
                .id("\(concept.id)-\(editorResets[concept.id] ?? 0)")
                .focused($focused, equals: concept.id)
                .font(.poppins(.callout))
                .foregroundStyle(Theme.paperInk)
                .tint(Theme.link)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                        .strokeBorder(focused == concept.id ? Theme.brand2 : Theme.paperLine, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Explain \(concept.name.lowercased()) to \(model.fishName)…")
                            .font(.poppins(.callout))
                            .foregroundStyle(Theme.paperHint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Your explanation of \(concept.name)")
            ForEach(copied, id: \.self) { sentence in
                Label("Say it your way: \"\(sentence)\" copies the chapter, so it won't count.", systemImage: "quote.bubble")
                    .font(.poppins(.caption))
                    .foregroundStyle(Theme.mixUpTint.text)
            }
        }
    }

    /// Rejects pastes of more than a short phrase. Recreating the editor drops the pasted text and keeps
    /// what was there before. Tapping OK on the alert puts the keyboard back in the same section.
    private func binding(conceptID: String, lessonID: String) -> Binding<String> {
        Binding(
            get: {
                model.data.lessons.first(where: { $0.id == lessonID })?.section(conceptID) ?? ""
            },
            set: { newValue in
                let old = model.data.lessons.first(where: { $0.id == lessonID })?.section(conceptID) ?? ""
                if PasteGuard.isLargeInsert(old: old, new: newValue) {
                    editorResets[conceptID, default: 0] += 1
                    blockedConceptID = conceptID
                    pasteBlocked = true
                    return
                }
                model.updateSection(lessonID: lessonID, conceptID: conceptID, text: newValue)
            }
        )
    }
}

/// The student predicts the fish's score before a Pop Quiz.
struct CallItSheet: View {
    let fishName: String
    let questionCount: Int
    let onStart: (Int?) -> Void

    @State private var guess: Int

    init(fishName: String, questionCount: Int, onStart: @escaping (Int?) -> Void) {
        self.fishName = fishName
        self.questionCount = questionCount
        self.onStart = onStart
        _guess = State(initialValue: max(0, questionCount / 2))
    }

    var body: some View {
        VStack(spacing: 18) {
            FishView(mood: .thinking, size: 72)
            Text("Call it").font(.poppins(.title2))
            Text("How many of \(questionCount) questions will \(fishName) get right from your lesson?")
                .font(.poppins(.body))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink2)
            Stepper(value: $guess, in: 0...max(questionCount, 0)) {
                Text("\(guess) of \(questionCount)")
                    .font(.poppins(.title, weight: .bold).monospacedDigit())
            }
            .padding(.horizontal, 32)
            Button("Start the quiz") { onStart(guess) }
                .buttonStyle(.primary)
            Button("Skip the guess") { onStart(nil) }
                .font(.poppins(.callout))
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}
