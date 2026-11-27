import SwiftUI
import GoldfishCore

/// The Tutor tab. Orla has read the current deck. Ask her anything: she answers with a hint, a
/// question back and the passage to reread, then sends you to teach Finn. She never gives the answer
///. Each question is single-turn, except that a short follow-up is searched together
/// with the question before it. Switching decks clears the page so subjects never mix.
struct TutorView: View {
    @Environment(AppModel.self) private var model
    @State private var question = ""
    /// Oldest first.
    @State private var answers: [TutorAnswer] = []
    @State private var asking = false
    @State private var errorMessage: String?
    @FocusState private var typing: Bool

    var body: some View {
        let deck = model.currentDeck
        let chapters = deck.map { model.chapters(inDeck: $0.id) } ?? []
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ask Orla")
                                .font(.poppins(.title))
                                .foregroundStyle(Theme.ink)
                                .accessibilityAddTraits(.isHeader)
                            Text("A tutor who points, never tells.")
                                .font(.poppins(.callout, weight: .medium))
                                .foregroundStyle(Theme.ink3)
                        }
                        Spacer(minLength: 12)
                        DeckSwitcher()
                    }
                    .padding(.top, 10)

                    PixelTank(mood: nil, scale: 3, fishAt: UnitPoint(x: 0.5, y: 0.66), weeds: [0.04, 0.9], bubbles: 3, orla: orlaMood)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))

                    SpeechBubble(text: intro(deck: deck, chapters: chapters), tail: .top, name: "Orla")

                    if answers.isEmpty && !chapters.isEmpty {
                        suggestions(chapters)
                    }

                    ForEach(answers) { answer in
                        TutorAnswerCard(answer: answer)
                            .id(answer.id)
                    }

                    if asking {
                        HStack(spacing: 10) {
                            BubbleDots()
                            Text("Orla is looking through \(deck?.name ?? "your deck") on this iPhone…")
                                .font(.poppins(.footnote))
                                .foregroundStyle(Theme.ink3)
                        }
                        .id("thinking")
                    }

                    if let errorMessage = errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.poppins(.footnote))
                            .foregroundStyle(Theme.mixUpTint.text)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .onChange(of: answers.count) {
                if let last = answers.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .top) }
                }
            }
            .onChange(of: asking) {
                if asking {
                    withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                }
            }
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            askBar(deck: deck, hasChapters: !chapters.isEmpty)
        }
        .onChange(of: model.currentDeck?.id) {
            // A new subject starts a clean page.
            answers = []
            errorMessage = nil
        }
    }

    private var orlaMood: OrlaMood {
        if asking { return .thinking }
        if errorMessage != nil { return .asking }
        return answers.isEmpty ? .calm : .hinting
    }

    private func intro(deck: Deck?, chapters: [Chapter]) -> String {
        guard let deck = deck else {
            return "Make a deck first. I read one subject at a time."
        }
        if chapters.isEmpty {
            return "Your \(deck.name) deck has no chapters yet. Add one and I'll read it."
        }
        return "I've read your \(deck.name) deck. Ask me anything. I'll show you where the answer is, but you find it, then teach it to \(model.fishName)."
    }

    /// Three starting points from the deck's ideas, so a first question is one tap away.
    private func suggestions(_ chapters: [Chapter]) -> some View {
        let concepts = chapters.flatMap { model.exam($0.id)?.concepts ?? [] }.prefix(3)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Try asking about")
                .font(.poppins(.subheadline))
                .foregroundStyle(Theme.brand2)
            ForEach(Array(concepts)) { concept in
                Button {
                    ask("Help me understand \(concept.name.lowercased()).")
                } label: {
                    HStack {
                        Text(concept.name)
                            .font(.poppins(.callout, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.link)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                            .strokeBorder(Theme.rule)
                    )
                }
                .buttonStyle(.plain)
                .disabled(asking)
            }
        }
    }

    /// The student's question is their own words, so it is typed on paper.
    private func askBar(deck: Deck?, hasChapters: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about \(deck?.name ?? "this deck")…", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit { ask(question) }
                .paperStyle()
            Button {
                ask(question)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(canAsk(hasChapters) ? Theme.brand : Theme.brand.opacity(0.35), in: Circle())
            }
            .disabled(!canAsk(hasChapters))
            .accessibilityLabel("Ask Orla")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Theme.line.frame(height: 1)
        }
    }

    private func canAsk(_ hasChapters: Bool) -> Bool {
        hasChapters && !asking && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !asking else { return }
        question = ""
        typing = false
        errorMessage = nil
        asking = true
        // What was searched last time, so "Why doesn't it swell up?" knows what "it" is.
        let previous = answers.last?.searchedText
        Task {
            do {
                let answer = try await model.askOrla(trimmed, previous: previous)
                answers.append(answer)
            } catch {
                errorMessage = String(describing: error)
            }
            asking = false
        }
    }
}

/// One question and Orla's reply: the student's words on paper, her hint, her question back,
/// and the passage to reread, copied from the chapter itself.
struct TutorAnswerCard: View {
    @Environment(AppModel.self) private var model
    let answer: TutorAnswer

    var body: some View {
        let reply = answer.reply
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 48)
                Text(answer.question)
                    .paperStyle()
                    .accessibilityLabel("You asked: \(answer.question)")
            }

            HStack(alignment: .center, spacing: 10) {
                OrlaView(mood: .hinting, size: 40)
                SpeechBubble(text: reply.hint, tail: .leading, name: "Orla")
            }

            Card {
                Text("Ask yourself")
                    .font(.poppins(.subheadline))
                    .foregroundStyle(Theme.brand2)
                Text(reply.ask)
                    .font(.poppins(.callout, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let passage = reply.passage {
                    Text("Reread")
                        .font(.poppins(.subheadline))
                        .foregroundStyle(Theme.brand2)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(passage.chapterTitle.uppercased())
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
                }

                HStack(spacing: 8) {
                    if let tier = answer.tier {
                        TierBadge(tier: tier)
                        if tier != .scripted {
                            Text(String(format: "%.1f s", Double(answer.latencyMs) / 1000))
                                .font(.poppins(.caption2).monospacedDigit())
                                .foregroundStyle(Theme.ink3)
                        }
                    } else {
                        Pill(text: "Searched on this iPhone", tint: Theme.onDeviceTint, mark: FinnSprites.phone)
                    }
                    Spacer(minLength: 8)
                    if let passage = reply.passage {
                        Button("Teach \(model.fishName)") {
                            model.openTeaching(passage.chapterID)
                        }
                        .font(.poppins(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.link)
                    }
                }
                .padding(.top, 4)

                // How she found it, when that is worth saying.
                if let note = answer.searchNote {
                    Text(note)
                        .font(.poppins(.caption))
                        .foregroundStyle(Theme.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
