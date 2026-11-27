import SwiftUI
import UniformTypeIdentifiers
import GoldfishCore

/// Import a PDF or paste text. The cloud then writes the Hidden Exam.
struct AddChapterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let onCreated: (Chapter) -> Void

    @State private var title = ""
    @State private var text = ""
    @State private var importing = false
    @State private var hasExamDate = false
    @State private var examDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var working = false
    @State private var errorMessage: String?
    @State private var progress: ImportProgress?
    /// The document's split, worked out a moment after typing stops so long pastes stay smooth.
    @State private var parts: [DocumentPart] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if working {
                        writing
                    } else {
                        form
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .task(id: "\(title)\n\(text)") {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                parts = model.documentParts(title: title, text: text)
            }
            .navigationTitle("Add a chapter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(working)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !working {
                    Button("Write the Hidden Exam") {
                        Task { await create() }
                    }
                    .buttonStyle(.primary)
                    .disabled(!canCreate)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                    .background(Theme.surface)
                    .overlay(alignment: .top) {
                        Theme.line.frame(height: 1)
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .plainText]) { result in
                handleImport(result)
            }
            .interactiveDismissDisabled(working)
        }
    }

    /// Figma labelled fields. The chapter is the source, not the student's words, so it is not on paper.
    @ViewBuilder
    private var form: some View {
        LabeledField(label: "Chapter title") {
            TextField("Cell Membranes", text: $title)
        }

        Button {
            importing = true
        } label: {
            Label("Import a PDF or text file", systemImage: "doc.text")
        }
        .buttonStyle(.secondary)

        VStack(alignment: .leading, spacing: 8) {
            Text("Or paste the chapter")
                .font(.poppins(.subheadline))
                .foregroundStyle(Theme.brand2)
            TextEditor(text: $text)
                .font(.poppins(.callout))
                .frame(minHeight: 220)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                        .strokeBorder(Theme.brand2, lineWidth: 1)
                )
            HStack(alignment: .top) {
                Text("Read on this iPhone. Only the text goes to the cloud, to write the exam.")
                Spacer(minLength: 12)
                Text(wordCountText)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(tooLong ? Theme.mixUpTint.text : Theme.ink3)
            }
            .font(.poppins(.footnote))
            .foregroundStyle(Theme.ink3)
        }

        if words >= 80 && !tooLong && !parts.isEmpty {
            planPreview
        }

        Card {
            Toggle("I have an exam date", isOn: $hasExamDate)
                .font(.poppins(.callout, weight: .medium))
            if hasExamDate {
                DatePicker("Exam date", selection: $examDate, in: Date()..., displayedComponents: .date)
                    .font(.poppins(.callout))
            }
            Text("With an exam date, reviews are spaced to fit before it.")
                .font(.poppins(.footnote))
                .foregroundStyle(Theme.ink3)
        }

        if model.chapter(SampleChapter.id) == nil {
            Button("Use the sample chapter instead") {
                model.loadSample()
                if let sample = model.chapter(SampleChapter.id) {
                    onCreated(sample)
                }
                dismiss()
            }
            .font(.poppins(.callout, weight: .medium))
            .foregroundStyle(Theme.link)
            .frame(maxWidth: .infinity)
        }

        if let message = errorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.poppins(.callout))
                .foregroundStyle(Theme.mixUpTint.text)
        }
    }

    /// How the document will be split, before anything is written. A long document becomes several
    /// chapters, so the fish can learn each one, and every idea in each gets a question.
    private var planPreview: some View {
        let ideas = parts.reduce(0) { $0 + $1.conceptTarget }
        return Card(flat: true) {
            Text(parts.count == 1 ? "1 chapter, about \(ideas) ideas" : "\(parts.count) chapters, about \(ideas) ideas")
                .font(.poppins(.headline))
                .foregroundStyle(Theme.ink)
            if parts.count > 1 {
                Text("\(model.fishName) learns one chapter at a time, so this document is split at its headings. All of them go into \(model.currentDeck?.name ?? "this deck").")
                    .font(.poppins(.footnote))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(parts, id: \.number) { part in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(part.number)")
                            .font(.poppins(.footnote, weight: .bold))
                            .foregroundStyle(Theme.link)
                            .frame(width: 18, alignment: .leading)
                        Text(part.title)
                            .font(.poppins(.callout, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(part.conceptTarget) ideas")
                            .font(.poppins(.footnote))
                            .foregroundStyle(Theme.ink3)
                    }
                }
            }
            Text("Every part of it gets a question. If the cloud misses a part, it is asked once more for just that part.")
                .font(.poppins(.footnote))
                .foregroundStyle(Theme.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The cloud writes above the waterline while the fish waits below it.
    @ViewBuilder
    private var writing: some View {
        Text("Writing the Hidden Exam")
            .font(.poppins(.title2))
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
        Text("Questions are written in the cloud from your chapter. \(model.fishName) never sees them until the quiz.")
            .font(.poppins(.body))
            .foregroundStyle(Theme.ink2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        if let progress = progress, progress.count > 1 {
            Pill(
                text: "Chapter \(progress.part) of \(progress.count): \(progress.title)",
                tint: Theme.Tint(text: Theme.link, fill: Theme.lavender)
            )
            .frame(maxWidth: .infinity)
        }
        CloudWritingView(
            captions: [
                "Reading your chapter…",
                "Picking the big ideas…",
                "Writing questions \(model.fishName) hasn't seen…",
                "Hiding the exam…",
            ],
            tier: model.firebaseReady ? .cloud : .scripted
        )
    }

    private var words: Int {
        TextNormalizer.wordCount(text)
    }

    private var tooLong: Bool {
        words > model.settings.chapterWordLimit
    }

    private var wordCountText: String {
        if tooLong {
            return "\(words) words. The limit is \(model.settings.chapterWordLimit) per document. Please add it in two goes."
        }
        return "\(words) words"
    }

    private var canCreate: Bool {
        !working && words >= 80 && !tooLong
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let imported = try ChapterImport.load(url)
                text = imported.text
                if title.trimmingCharacters(in: .whitespaces).isEmpty {
                    title = imported.title
                }
                errorMessage = nil
            } catch {
                errorMessage = String(describing: error)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func create() async {
        working = true
        errorMessage = nil
        progress = nil
        defer { working = false }
        do {
            // One chapter per part of the document, each with an exam that covers it.
            let chapters = try await model.createChapters(
                title: title, text: text, examDate: hasExamDate ? examDate : nil
            ) { update in
                progress = update
            }
            if let first = chapters.first {
                onCreated(first)
            }
            dismiss()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
