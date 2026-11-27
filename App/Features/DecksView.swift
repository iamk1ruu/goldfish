import SwiftUI
import GoldfishCore

// Decks keep each subject's chapters apart. One deck is current; Today and Orla follow it.

/// The Decks tab: every deck as a card. Opening one makes it the current deck.
struct DecksView: View {
    @Environment(AppModel.self) private var model
    @State private var makingDeck = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Decks")
                            .font(.poppins(.title))
                            .foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text("One deck per subject, so chapters never mix.")
                            .font(.poppins(.callout, weight: .medium))
                            .foregroundStyle(Theme.ink3)
                    }
                    Spacer(minLength: 12)
                    AddButton(label: "New deck") { makingDeck = true }
                }
                .padding(.top, 10)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.data.decks) { deck in
                        NavigationLink(value: Route.deck(deck.id)) {
                            DeckCard(deck: deck, isCurrent: deck.id == model.currentDeck?.id)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { makingDeck = true } label: { NewDeckCard() }
                        .buttonStyle(.plain)
                }
                .padding(.top, 22)
            }
            .padding(.horizontal, 16)
            // Room to scroll the last card clear of the floating tab bar.
            .padding(.bottom, 32)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $makingDeck) {
            DeckEditor(deck: nil)
        }
    }
}

/// A deck in the grid: its colour and letter, name, chapter count and what is due.
struct DeckCard: View {
    @Environment(AppModel.self) private var model
    let deck: Deck
    let isCurrent: Bool

    var body: some View {
        let chapters = model.chapters(inDeck: deck.id)
        let due = model.dueChapters(inDeck: deck.id).count
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                DeckBadge(deck: deck, size: 52)
                Spacer(minLength: 4)
                if isCurrent {
                    Pill(text: "Current", tint: Theme.Tint(text: .white, fill: Theme.brand))
                }
            }
            Text(deck.name)
                .font(.poppins(.headline))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(chapters.count == 1 ? "1 chapter" : "\(chapters.count) chapters")
                    .font(.poppins(.footnote))
                    .foregroundStyle(Theme.ink3)
                if due > 0 {
                    Pill(text: "\(due) due", tint: Theme.taughtTint, mark: FinnSprites.drop)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .strokeBorder(isCurrent ? Theme.brand : Theme.line, lineWidth: isCurrent ? 2 : 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(isCurrent ? "The current deck" : "Opens this deck and makes it current")
    }
}

/// The last card in the grid: a dashed outline that makes a deck.
private struct NewDeckCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
            Text("New deck")
                .font(.poppins(.callout, weight: .semibold))
        }
        .foregroundStyle(Theme.link)
        .frame(maxWidth: .infinity, minHeight: 150)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .strokeBorder(Theme.brand2.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .contentShape(Rectangle())
    }
}

/// One deck's chapters. Opening it makes it the current deck.
struct DeckView: View {
    @Environment(AppModel.self) private var model
    let deckID: String

    @State private var addingChapter = false
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        if let deck = model.data.deck(deckID) {
            content(deck)
        } else {
            FishMessage(title: "Deck not found", message: "It may have been deleted.")
        }
    }

    private func content(_ deck: Deck) -> some View {
        let chapters = model.chapters(inDeck: deck.id)
        let dueIDs = Set(model.dueChapters(inDeck: deck.id).map { $0.id })
        let due = chapters.filter { dueIDs.contains($0.id) }
        let others = chapters.filter { !dueIDs.contains($0.id) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    DeckBadge(deck: deck, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deck.name)
                            .font(.poppins(.title))
                            .foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(chapters.count == 1 ? "1 chapter" : "\(chapters.count) chapters")
                            .font(.poppins(.callout, weight: .medium))
                            .foregroundStyle(Theme.ink3)
                    }
                    Spacer(minLength: 12)
                    AddButton(label: "Add a chapter") { addingChapter = true }
                }
                .padding(.top, 6)

                if !chapters.isEmpty {
                    // Mixed Bowl: the due cards from every chapter here, or every idea if nothing is due.
                    NavigationLink(value: Route.deckQuiz(deck.id)) {
                        Label("Quiz the deck", systemImage: "rectangle.stack")
                    }
                    .buttonStyle(.primary)
                    .padding(.top, 16)
                }

                if chapters.isEmpty {
                    FishMessage(
                        title: "No chapters yet",
                        message: "Add the first chapter of \(deck.name). \(model.fishName) will learn it from you.",
                        mood: .curious
                    )
                    .padding(.top, 24)
                    if model.chapter(SampleChapter.id) == nil {
                        Button("Load the sample chapter") { model.loadSample() }
                            .buttonStyle(.secondary)
                    }
                }

                if !due.isEmpty {
                    SectionHeader(title: "Fresh Water", detail: "\(due.count) due")
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                    rows(due)
                }
                if !others.isEmpty {
                    SectionHeader(title: due.isEmpty ? "Chapters" : "Learning", detail: "\(others.count)")
                        .padding(.top, 24)
                        .padding(.bottom, 12)
                    rows(others)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit deck", systemImage: "pencil") { editing = true }
                    if model.data.decks.count > 1 {
                        Button("Delete deck", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Deck options")
            }
        }
        .onAppear { model.setCurrentDeck(deck.id) }
        .sheet(isPresented: $addingChapter) {
            AddChapterView { chapter in
                model.path.append(.chapter(chapter.id))
            }
        }
        .sheet(isPresented: $editing) {
            DeckEditor(deck: deck)
        }
        .confirmationDialog(
            "Delete \(deck.name) and its \(chapters.count) chapter(s)? Their lessons and progress go too.",
            isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Delete deck", role: .destructive) { model.deleteDeck(deck.id) }
        }
    }

    private func rows(_ chapters: [Chapter]) -> some View {
        VStack(spacing: 12) {
            ForEach(chapters) { chapter in
                NavigationLink(value: Route.chapter(chapter.id)) {
                    ChapterRow(chapter: chapter)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Makes a deck, or edits one: a name and a colour.
struct DeckEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let deck: Deck?

    @State private var name: String
    @State private var color: DeckColor

    init(deck: Deck?) {
        self.deck = deck
        _name = State(initialValue: deck?.name ?? "")
        _color = State(initialValue: deck?.color ?? .blue)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LabeledField(label: "Deck name") {
                        DeckBadge(name: name, color: color, size: 26)
                        TextField("Science", text: $name)
                            .submitLabel(.done)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Colour")
                            .font(.poppins(.subheadline))
                            .foregroundStyle(Theme.brand2)
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(DeckColor.allCases, id: \.self) { choice in
                                Button {
                                    color = choice
                                } label: {
                                    Circle()
                                        .fill(Theme.color(for: choice))
                                        .frame(width: 44, height: 44)
                                        .overlay {
                                            if choice == color {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundStyle(Theme.ink(for: choice))
                                            }
                                        }
                                        .padding(4)
                                        .overlay(Circle().strokeBorder(choice == color ? Theme.color(for: choice) : .clear, lineWidth: 2))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(choice.label)
                                .accessibilityAddTraits(choice == color ? .isSelected : [])
                            }
                        }
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(deck == nil ? "New deck" : "Edit deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(deck == nil ? "Make the deck" : "Save") {
                    save()
                }
                .buttonStyle(.primary)
                .padding(16)
                .background(Theme.surface)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        if let deck = deck {
            model.editDeck(deck.id, name: name, color: color)
        } else {
            model.addDeck(name: name, color: color)
        }
        dismiss()
    }
}

/// The current deck as a pill, with a menu to switch decks or make one. On Today and the Tutor tab.
struct DeckSwitcher: View {
    @Environment(AppModel.self) private var model
    @State private var makingDeck = false

    var body: some View {
        Menu {
            ForEach(model.data.decks) { deck in
                Button {
                    model.setCurrentDeck(deck.id)
                } label: {
                    if deck.id == model.currentDeck?.id {
                        Label(deck.name, systemImage: "checkmark")
                    } else {
                        Text(deck.name)
                    }
                }
            }
            Divider()
            Button("New deck", systemImage: "plus") { makingDeck = true }
        } label: {
            HStack(spacing: 6) {
                if let deck = model.currentDeck {
                    DeckBadge(deck: deck, size: 24)
                    Text(deck.name)
                        .font(.poppins(.callout, weight: .semibold))
                        .lineLimit(1)
                } else {
                    Text("Make a deck")
                        .font(.poppins(.callout, weight: .semibold))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(height: 36)
            .background(Theme.lavender, in: Capsule())
        }
        .accessibilityLabel("Current deck: \(model.currentDeck?.name ?? "none"). Switch deck")
        .sheet(isPresented: $makingDeck) {
            DeckEditor(deck: nil)
        }
    }
}

/// A deck's mark: its colour with the first letter of its name. Decks are named by the student, so a colour
/// and a letter work for any subject, and the letter keeps decks apart for colour-blind students.
struct DeckBadge: View {
    let name: String
    let color: DeckColor
    var size: CGFloat = 24

    init(deck: Deck, size: CGFloat = 24) {
        self.name = deck.name
        self.color = deck.color
        self.size = size
    }

    init(name: String, color: DeckColor, size: CGFloat = 24) {
        self.name = name
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?")
            .font(.poppins(size: size * 0.5, weight: .bold))
            .foregroundStyle(Theme.ink(for: color))
            .frame(width: size, height: size)
            .background(Theme.color(for: color), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The round purple add button, where the Figma home page has its avatar.
struct AddButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.brand, in: Circle())
        }
        .accessibilityLabel(label)
    }
}
