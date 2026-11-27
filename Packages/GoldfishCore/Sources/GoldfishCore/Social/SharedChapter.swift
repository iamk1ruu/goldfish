import Foundation

/// A chapter and its Hidden Exam, shared with a code.
///
/// The student's lessons, answers and progress are never included: a friend gets the same material
/// and the same questions, and teaches it to their own Finn. Because the friend's phone uses the exam as
/// it is, the cloud is not called again and a teach-off compares answers to identical questions.
public struct SharedChapter: Codable, Equatable {
    public static let currentVersion = 1
    /// Firestore documents are capped at 1 MiB. The rules allow a little less.
    public static let maxBytes = 900_000
    public static let maxWords = 20_000

    public var version: Int
    public var code: String
    /// The display name of the student who shared it.
    public var ownerName: String
    public var chapter: Chapter
    public var exam: Exam
    public var sharedAt: Date

    public init(version: Int = SharedChapter.currentVersion, code: String, ownerName: String, chapter: Chapter, exam: Exam, sharedAt: Date) {
        self.version = version
        self.code = code
        self.ownerName = ownerName
        self.chapter = chapter
        self.exam = exam
        self.sharedAt = sharedAt
    }

    /// Strips everything personal from the chapter: its deck and exam date stay on the sharer's phone.
    public static func make(code: String, ownerName: String, chapter: Chapter, exam: Exam, at date: Date) -> SharedChapter {
        var clean = chapter
        clean.examDate = nil
        clean.deckID = nil
        clean.sharedBy = nil
        clean.shareCode = nil
        return SharedChapter(code: code, ownerName: ownerName, chapter: clean, exam: exam, sharedAt: date)
    }

    /// Everything wrong with a shared chapter that came from the network. Empty means it can be imported.
    public func problems() -> [String] {
        var problems: [String] = []
        if version > SharedChapter.currentVersion {
            problems.append("made by a newer version of Goldfish")
        }
        if chapter.id.isEmpty || exam.chapterID != chapter.id {
            problems.append("the exam does not belong to the chapter")
        }
        let words = TextTools.words(chapter.sourceText).count
        if words == 0 || words > SharedChapter.maxWords {
            problems.append("the chapter text is empty or too long")
        }
        if exam.concepts.isEmpty {
            problems.append("the exam has no concepts")
        }
        let conceptIDs = Set(exam.concepts.map { $0.id })
        if conceptIDs.count != exam.concepts.count {
            problems.append("two concepts share an ID")
        }
        if Set(exam.questions.map { $0.id }).count != exam.questions.count {
            problems.append("two questions share an ID")
        }
        if exam.questions(in: .practice).isEmpty {
            problems.append("the exam has no practice questions")
        }
        for question in exam.questions {
            if !conceptIDs.contains(question.conceptID)
                || question.options.count != 4
                || question.keyTerms.count != 4
                || !(0..<4).contains(question.correctIndex)
                || question.stem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                problems.append("question \(question.id) is malformed")
            }
        }
        return problems
    }

    /// The chapter as it is stored on the friend's phone, in the deck they have open.
    public func importedChapter(deckID: String?, at date: Date) -> Chapter {
        var imported = chapter
        imported.createdAt = date
        imported.examDate = nil
        imported.deckID = deckID
        imported.sharedBy = ownerName
        imported.shareCode = code
        return imported
    }
}
