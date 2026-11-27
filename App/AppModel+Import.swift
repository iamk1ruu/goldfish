import Foundation
import GoldfishCore

/// Where a document import has got to, for the writing screen.
struct ImportProgress: Equatable {
    /// 1-based.
    var part: Int
    var count: Int
    var title: String
}

// A whole document is covered. A long one becomes several chapters, cut at its headings,
// each small enough for the fish to learn and each with a Hidden Exam that reaches every passage.
extension AppModel {
    /// How the document will be split, so the student sees the chapters before anything is written.
    func documentParts(title: String, text: String) -> [DocumentPart] {
        ExamPlan.parts(title: title, text: text)
    }

    /// Writes one chapter per part, in order, into the current deck. If a later part fails, the chapters
    /// already made are kept and the error says how far it got.
    func createChapters(
        title: String, text: String, examDate: Date?,
        onProgress: (ImportProgress) -> Void
    ) async throws -> [Chapter] {
        let parts = documentParts(title: title, text: text)
        var made: [Chapter] = []
        for part in parts {
            onProgress(ImportProgress(part: part.number, count: part.count, title: part.title))
            do {
                made.append(try await createChapter(title: part.title, text: part.text, pdfData: nil, examDate: examDate))
            } catch {
                if made.isEmpty {
                    throw error
                }
                throw GoldfishError(description: "Made \(made.count) of \(parts.count) chapters. Part \(part.number) could not be written: \(error)")
            }
        }
        return made
    }
}
