import SwiftUI
import GoldfishCore

/// What is due today in the current deck, its newest chapters, and the forgiving fire. The first tab.
/// Laid out like the Figma home page: the deck and the fire on top, a greeting beside an add button, a purple
/// banner, then sections of list cards. The banner holds Finn's tank and the one thing he most needs from you.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var addingChapter = false

    /// Today shows this many chapters. The deck has them all.
    private let chapterLimit = 3

    var body: some View {
        let deckID = model.currentDeck?.id ?? ""
        let due = model.dueChapters(inDeck: deckID)
        let chapters = model.chapters(inDeck: deckID)
        let yourTurn = chapters.filter { model.yourTurnDueCount($0.id) > 0 }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    DeckSwitcher()
                    Spacer(minLength: 12)
                    FireBadge(streak: model.fire)
                }
                .padding(.top, 8)

                header
                    .padding(.top, 14)

                FireCard(streak: model.fire, week: Streak.week(model.data.teachingDays, endingOn: model.today))
                    .padding(.top, 14)

                banner(due: due)
                    .padding(.top, 14)

                otherDecksNudge

                if due.count > 1 {
                    SectionHeader(title: "Fresh Water", detail: "\(due.count) due")
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                    VStack(spacing: 12) {
                        ForEach(Array(due.dropFirst())) { chapter in
                            Button {
                                model.startFreshWater(chapter.id)
                            } label: {
                                ListCard(chapter.title) {
                                    PixelMark(sprite: FinnSprites.drop, scale: 4)
                                } detail: {
                                    Text("\(model.fishName) forgot this. Re-teach it from memory.")
                                        .font(.poppins(.footnote))
                                        .foregroundStyle(Theme.ink3)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !yourTurn.isEmpty {
                    let ready = yourTurn.reduce(0) { $0 + model.yourTurnDueCount($1.id) }
                    SectionHeader(title: "Your Turn", detail: "\(ready) ready")
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                    VStack(spacing: 12) {
                        // Mixed Bowl: every due card in the deck, chapters taking turns.
                        if yourTurn.count > 1 {
                            NavigationLink(value: Route.deckQuiz(deckID)) {
                                ListCard("Quiz the whole deck") {
                                    PixelMark(sprite: FinnSprites.mastered, scale: 4)
                                } detail: {
                                    Text("\(ready) cards from \(yourTurn.count) chapters, mixed")
                                        .font(.poppins(.footnote))
                                        .foregroundStyle(Theme.ink3)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(yourTurn) { chapter in
                            NavigationLink(value: Route.yourTurn(chapter.id)) {
                                ListCard(chapter.title) {
                                    PixelMark(sprite: FinnSprites.recalled, scale: 4)
                                } detail: {
                                    Text("\(model.yourTurnDueCount(chapter.id)) card(s) ready")
                                        .font(.poppins(.footnote))
                                        .foregroundStyle(Theme.ink3)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                SectionHeader(title: "Chapters", detail: chapters.isEmpty ? "Add" : "View all") {
                    if chapters.isEmpty {
                        addingChapter = true
                    } else {
                        model.tab = .decks
                        model.paths[.decks] = [.deck(deckID)]
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 12)

                if chapters.isEmpty {
                    FishMessage(
                        title: "No chapters in this deck",
                        message: "Add a chapter you need to learn, or load the sample chapter.",
                        mood: .curious
                    )
                    if model.chapter(SampleChapter.id) == nil {
                        Button("Load the sample chapter") { model.loadSample() }
                            .buttonStyle(.secondary)
                    }
                }
                VStack(spacing: 12) {
                    ForEach(Array(chapters.prefix(chapterLimit))) { chapter in
                        NavigationLink(value: Route.chapter(chapter.id)) {
                            ChapterRow(chapter: chapter)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            // Room to scroll the last card clear of the floating tab bar.
            .padding(.bottom, 32)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $addingChapter) {
            AddChapterView { chapter in
                model.path.append(.chapter(chapter.id))
            }
        }
    }

    /// The greeting, with a purple add button where the Figma home page has its avatar.
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hello!")
                    .font(.poppins(.title))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("What will you teach \(model.fishName) today?")
                    .font(.poppins(.callout, weight: .medium))
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 12)
            AddButton(label: "Add a chapter") { addingChapter = true }
        }
    }

    /// Today shows one deck, so a line says when another deck has Fresh Water due. Nothing is hidden.
    @ViewBuilder
    private var otherDecksNudge: some View {
        let others = model.otherDecksWithDue()
        if let first = others.first {
            Button {
                model.setCurrentDeck(first.deck.id)
            } label: {
                HStack(spacing: 10) {
                    PixelMark(sprite: FinnSprites.drop, scale: 2)
                    Text(others.count == 1
                         ? "\(first.deck.name) has \(first.due) chapter(s) due"
                         : "\(others.count) other decks have chapters due")
                        .font(.poppins(.footnote))
                        .foregroundStyle(Theme.ink2)
                    Spacer(minLength: 8)
                    Text("Switch")
                        .font(.poppins(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.link)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Theme.frost, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private func banner(due: [Chapter]) -> some View {
        if let first = due.first {
            HomeBanner(
                title: "Fresh Water!",
                detail: "\(model.fishName) forgot \(first.title)",
                action: "Re-teach it",
                mood: .forgetful
            ) {
                model.startFreshWater(first.id)
            }
        } else if model.currentDeck.map({ model.chapters(inDeck: $0.id).isEmpty }) ?? true {
            HomeBanner(
                title: "Fill the bowl",
                detail: "\(model.fishName)'s bowl is empty. Add a chapter, or try the sample.",
                action: "Load the sample",
                mood: .curious
            ) {
                model.loadSample()
            }
        } else {
            HomeBanner(
                title: "All caught up",
                detail: "Nothing is due. Come back when \(model.fishName) forgets.",
                mood: .happy
            )
        }
    }

    // The week strip now lives inside FireCard, beside the forgiving fire.
}

/// The purple banner from the Figma home page ("New Course!"), with Finn's tank on the right.
struct HomeBanner: View {
    let title: String
    let detail: String
    var action: String?
    let mood: FishMood
    var perform: (() -> Void)?

    var body: some View {
        if let perform = perform {
            Button(action: perform) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.poppins(.title2))
                Text(detail)
                    .font(.poppins(.callout, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let action = action {
                    Text(action)
                        .font(.poppins(.footnote))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                        .background(Theme.brand3.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)

            PixelTank(mood: mood, scale: 3, fishAt: UnitPoint(x: 0.46, y: 0.64), weeds: [0.04], bubbles: 2)
                .frame(width: 150, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 158)
        .background {
            ZStack(alignment: .topTrailing) {
                Theme.banner
                Circle()
                    .fill(Theme.bannerGlow)
                    .frame(width: 300, height: 300)
                    .offset(x: 120, y: -150)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ChapterRow: View {
    @Environment(AppModel.self) private var model
    let chapter: Chapter

    var body: some View {
        let states = (model.exam(chapter.id)?.concepts ?? []).map { model.data.conceptState($0.id) }
        let counts = model.masteredCount(chapter.id)
        let next = model.data.chapterProgress[chapter.id]?.nextDueOn
        ListCard(chapter.title) {
            PixelMark(sprite: tileMark(states: states, next: next), scale: 4)
        } detail: {
            if !states.isEmpty {
                HStack(spacing: 2) {
                    ForEach(Array(states.prefix(10).enumerated()), id: \.offset) { _, state in
                        ConceptToken(state: state)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Mastered \(counts.mastered) of \(counts.total) concepts")
            }
            Text(next.map { dueText($0) } ?? "Mastered \(counts.mastered) of \(counts.total) concepts")
                .font(.poppins(.footnote))
                .foregroundStyle(Theme.ink3)
        }
    }

    /// A drop when Fresh Water is due, otherwise the furthest any concept has come.
    private func tileMark(states: [ConceptState], next: Day?) -> PixelSprite {
        if let next = next, model.today.days(until: next) <= 0 {
            return FinnSprites.drop
        }
        if !states.isEmpty && states.allSatisfy({ $0 == .mastered }) {
            return FinnSprites.mastered
        }
        if states.contains(.mastered) || states.contains(.recalled) {
            return FinnSprites.recalled
        }
        if states.contains(.taught) {
            return FinnSprites.taught
        }
        return FinnSprites.notTaught
    }

    private func dueText(_ day: Day) -> String {
        let days = model.today.days(until: day)
        if days <= 0 { return "Fresh Water due now" }
        if days == 1 { return "Fresh Water tomorrow" }
        return "Fresh Water in \(days) days"
    }
}
