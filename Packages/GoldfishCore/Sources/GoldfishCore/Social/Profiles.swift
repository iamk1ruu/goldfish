import Foundation

/// What friends can see about you. Lessons, answers and chapters are never part of it.
public struct PublicProfile: Codable, Equatable {
    public var uid: String
    public var displayName: String
    public var fishName: String
    public var friendCode: String
    public var fireDays: Int
    /// A `FireStreak.Flame` raw value.
    public var fireFlame: String
    public var bestFire: Int
    /// Concepts mastered across every chapter.
    public var mastered: Int
    public var updatedAt: Date

    public init(
        uid: String, displayName: String, fishName: String, friendCode: String,
        fireDays: Int, fireFlame: String, bestFire: Int, mastered: Int, updatedAt: Date
    ) {
        self.uid = uid
        self.displayName = displayName
        self.fishName = fishName
        self.friendCode = friendCode
        self.fireDays = fireDays
        self.fireFlame = fireFlame
        self.bestFire = bestFire
        self.mastered = mastered
        self.updatedAt = updatedAt
    }

    public static let maxNameLength = 24

    public static func make(uid: String, displayName: String, friendCode: String, data: GoldfishData, today: Day, at date: Date) -> PublicProfile {
        let fire = FireStreak.compute(data.teachingDays, today: today)
        let mastered = data.exams.values.reduce(0) { total, exam in
            total + MasteryRules.masteredCount(exam.concepts, progress: data.concepts)
        }
        let fish = cleanName(data.fishName)
        return PublicProfile(
            uid: uid,
            displayName: cleanName(displayName),
            fishName: fish.isEmpty ? "Finn" : fish,
            friendCode: friendCode,
            fireDays: fire.days,
            fireFlame: fire.flame.rawValue,
            bestFire: fire.best,
            mastered: mastered,
            updatedAt: date
        )
    }

    /// Trimmed, with runs of spaces collapsed, and at most `maxNameLength` characters.
    public static func cleanName(_ raw: String) -> String {
        let words = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return String(words.joined(separator: " ").prefix(maxNameLength))
    }

    /// The fire as friends see it. It is the fire on the day the profile was last updated.
    public var fire: FireStreak {
        FireStreak(flame: FireStreak.Flame(rawValue: fireFlame) ?? .out, days: fireDays, best: bestFire)
    }
}

/// A friend request, stored under the person it is sent to.
public struct FriendRequest: Codable, Equatable, Identifiable {
    public var fromUid: String
    public var fromName: String
    public var fromFishName: String
    public var sentAt: Date

    public var id: String { fromUid }

    public init(fromUid: String, fromName: String, fromFishName: String, sentAt: Date) {
        self.fromUid = fromUid
        self.fromName = fromName
        self.fromFishName = fromFishName
        self.sentAt = sentAt
    }
}

/// An entry in a friends list. The live fire and counts come from the friend's profile.
public struct Friend: Codable, Equatable, Identifiable {
    public var uid: String
    public var displayName: String
    public var since: Date

    public var id: String { uid }

    public init(uid: String, displayName: String, since: Date) {
        self.uid = uid
        self.displayName = displayName
        self.since = since
    }
}

/// A teach-off between two friends on one shared chapter.
public struct Challenge: Codable, Equatable, Identifiable {
    public var id: String
    public var chapterCode: String
    public var chapterID: String
    public var chapterTitle: String
    public var fromUid: String
    public var fromName: String
    public var toUid: String
    public var toName: String
    public var createdAt: Date

    public init(
        id: String, chapterCode: String, chapterID: String, chapterTitle: String,
        fromUid: String, fromName: String, toUid: String, toName: String, createdAt: Date
    ) {
        self.id = id
        self.chapterCode = chapterCode
        self.chapterID = chapterID
        self.chapterTitle = chapterTitle
        self.fromUid = fromUid
        self.fromName = fromName
        self.toUid = toUid
        self.toName = toName
        self.createdAt = createdAt
    }

    /// The other student, seen from `uid`'s side.
    public func other(than uid: String) -> (uid: String, name: String) {
        uid == fromUid ? (toUid, toName) : (fromUid, fromName)
    }
}

/// One side of a teach-off.
public struct ChallengeResult: Codable, Equatable {
    public var uid: String
    public var name: String
    public var fishName: String
    public var score: TeachOffScore

    public init(uid: String, name: String, fishName: String, score: TeachOffScore) {
        self.uid = uid
        self.name = name
        self.fishName = fishName
        self.score = score
    }
}

/// What this phone remembers about its profile. The cloud copy is `PublicProfile`.
public struct SocialState: Codable, Equatable {
    public var uid: String
    public var displayName: String
    public var friendCode: String

    public init(uid: String, displayName: String, friendCode: String) {
        self.uid = uid
        self.displayName = displayName
        self.friendCode = friendCode
    }
}

/// Sounds and haptics. Both on by default. Sounds follow the silent switch.
public struct Preferences: Codable, Equatable {
    public var sounds: Bool
    public var haptics: Bool

    public init(sounds: Bool = true, haptics: Bool = true) {
        self.sounds = sounds
        self.haptics = haptics
    }
}
