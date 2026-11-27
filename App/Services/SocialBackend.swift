import Foundation
import FirebaseAuth
import FirebaseFirestore
import GoldfishCore

/// Everything profiles, friends, sharing and teach-offs need from the cloud.
/// The Firestore layout and its security rules are in `firestore.rules` at the repo root.
protocol SocialBackend {
    /// Signs in anonymously, or returns the user already signed in. Returns the user ID.
    func signIn() async throws -> String
    func currentUID() -> String?

    func saveProfile(_ profile: PublicProfile) async throws
    func profile(_ uid: String) async throws -> PublicProfile?
    /// False when another student already has this code.
    func claimFriendCode(_ code: String, uid: String) async throws -> Bool
    func uid(forFriendCode code: String) async throws -> String?

    func sendRequest(_ request: FriendRequest, to uid: String) async throws
    func incomingRequests(_ uid: String) async throws -> [FriendRequest]
    /// Adds each student to the other's list and removes the request, in one write.
    func accept(_ request: FriendRequest, me: Friend, them: Friend) async throws
    func decline(fromUid: String, me: String) async throws
    func friends(_ uid: String) async throws -> [Friend]
    func removeFriend(_ friendUid: String, me: String) async throws

    func share(_ shared: SharedChapter, ownerUid: String) async throws
    func sharedChapter(_ code: String) async throws -> SharedChapter?
    func stopSharing(_ code: String) async throws

    /// Creates the challenge and the challenger's result together.
    func createChallenge(_ challenge: Challenge, result: ChallengeResult) async throws
    func challenges(for uid: String) async throws -> [Challenge]
    /// Nil when there is no result yet, or when the rules hide it because you have not finished yours.
    func result(challengeID: String, uid: String) async throws -> ChallengeResult?
    func submit(_ result: ChallengeResult, challengeID: String) async throws
    func deleteChallenge(_ id: String, me: String) async throws

    /// Removes the profile, the friend code and every friend link, then the sign-in itself.
    func deleteAccount(uid: String, friendCode: String, friends: [String], shareCodes: [String]) async throws
}

struct SocialError: Error, CustomStringConvertible {
    let description: String
}

/// Firestore errors carry gRPC codes. 7 is PERMISSION_DENIED, which our rules return both for
/// "not allowed" and for writing a document that already exists. 14 is UNAVAILABLE (offline).
enum FirestoreCode {
    static func code(_ error: Error) -> Int? {
        let nsError = error as NSError
        guard nsError.domain.lowercased().contains("firestore") else { return nil }
        return nsError.code
    }

    static func isPermissionDenied(_ error: Error) -> Bool {
        code(error) == 7
    }

    static func isOffline(_ error: Error) -> Bool {
        code(error) == 14
    }
}

/// The real backend: Firebase Auth with anonymous sign-in, and Cloud Firestore.
/// Each document keeps its content as one JSON string in `body`, written and read by GoldfishCore types.
struct FirebaseSocialBackend: SocialBackend {
    private var db: Firestore {
        Firestore.firestore()
    }

    func signIn() async throws -> String {
        if let uid = Auth.auth().currentUser?.uid {
            return uid
        }
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }

    func currentUID() -> String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: Profiles and codes

    func saveProfile(_ profile: PublicProfile) async throws {
        try await db.collection("profiles").document(profile.uid).setData(["body": SocialJSON.encode(profile)])
    }

    func profile(_ uid: String) async throws -> PublicProfile? {
        try await body(db.collection("profiles").document(uid), as: PublicProfile.self)
    }

    func claimFriendCode(_ code: String, uid: String) async throws -> Bool {
        do {
            // The rules allow creating a code but never overwriting one, so a taken code is refused.
            try await db.collection("friendCodes").document(code).setData(["uid": uid])
            return true
        } catch let error where FirestoreCode.isPermissionDenied(error) {
            return false
        }
    }

    func uid(forFriendCode code: String) async throws -> String? {
        let snapshot = try await db.collection("friendCodes").document(code).getDocument()
        guard snapshot.exists else { return nil }
        return snapshot.data()?["uid"] as? String
    }

    // MARK: Friends

    func sendRequest(_ request: FriendRequest, to uid: String) async throws {
        let ref = db.collection("requests").document(uid).collection("incoming").document(request.fromUid)
        try await ref.setData(["body": SocialJSON.encode(request)])
    }

    func incomingRequests(_ uid: String) async throws -> [FriendRequest] {
        let snapshot = try await db.collection("requests").document(uid).collection("incoming").getDocuments()
        return snapshot.documents.compactMap { decode($0.data(), as: FriendRequest.self) }
    }

    func accept(_ request: FriendRequest, me: Friend, them: Friend) async throws {
        let batch = db.batch()
        batch.setData(["body": try SocialJSON.encode(them)], forDocument: friendRef(owner: me.uid, friend: them.uid))
        batch.setData(["body": try SocialJSON.encode(me)], forDocument: friendRef(owner: them.uid, friend: me.uid))
        batch.deleteDocument(db.collection("requests").document(me.uid).collection("incoming").document(them.uid))
        try await batch.commit()
    }

    func decline(fromUid: String, me: String) async throws {
        try await db.collection("requests").document(me).collection("incoming").document(fromUid).delete()
    }

    func friends(_ uid: String) async throws -> [Friend] {
        let snapshot = try await db.collection("friends").document(uid).collection("list").getDocuments()
        return snapshot.documents.compactMap { decode($0.data(), as: Friend.self) }
    }

    func removeFriend(_ friendUid: String, me: String) async throws {
        let batch = db.batch()
        batch.deleteDocument(friendRef(owner: me, friend: friendUid))
        batch.deleteDocument(friendRef(owner: friendUid, friend: me))
        try await batch.commit()
    }

    private func friendRef(owner: String, friend: String) -> DocumentReference {
        db.collection("friends").document(owner).collection("list").document(friend)
    }

    // MARK: Shared chapters

    func share(_ shared: SharedChapter, ownerUid: String) async throws {
        let body = try SocialJSON.encode(shared)
        guard body.utf8.count <= SharedChapter.maxBytes else {
            throw SocialError(description: "This chapter is too long to share. Split it into two chapters first.")
        }
        try await db.collection("sharedChapters").document(shared.code).setData(["ownerUid": ownerUid, "body": body])
    }

    func sharedChapter(_ code: String) async throws -> SharedChapter? {
        try await body(db.collection("sharedChapters").document(code), as: SharedChapter.self)
    }

    func stopSharing(_ code: String) async throws {
        try await db.collection("sharedChapters").document(code).delete()
    }

    // MARK: Teach-offs

    func createChallenge(_ challenge: Challenge, result: ChallengeResult) async throws {
        let ref = db.collection("challenges").document(challenge.id)
        let batch = db.batch()
        batch.setData(
            ["fromUid": challenge.fromUid, "toUid": challenge.toUid, "body": try SocialJSON.encode(challenge)],
            forDocument: ref
        )
        batch.setData(["body": try SocialJSON.encode(result)], forDocument: ref.collection("results").document(result.uid))
        try await batch.commit()
    }

    func challenges(for uid: String) async throws -> [Challenge] {
        let sent = try await db.collection("challenges").whereField("fromUid", isEqualTo: uid).getDocuments()
        let received = try await db.collection("challenges").whereField("toUid", isEqualTo: uid).getDocuments()
        return (sent.documents + received.documents).compactMap { decode($0.data(), as: Challenge.self) }
    }

    func result(challengeID: String, uid: String) async throws -> ChallengeResult? {
        do {
            return try await body(
                db.collection("challenges").document(challengeID).collection("results").document(uid),
                as: ChallengeResult.self
            )
        } catch let error where FirestoreCode.isPermissionDenied(error) {
            // Their result stays hidden until yours is in.
            return nil
        }
    }

    func submit(_ result: ChallengeResult, challengeID: String) async throws {
        let ref = db.collection("challenges").document(challengeID).collection("results").document(result.uid)
        try await ref.setData(["body": SocialJSON.encode(result)])
    }

    func deleteChallenge(_ id: String, me: String) async throws {
        let ref = db.collection("challenges").document(id)
        let batch = db.batch()
        batch.deleteDocument(ref.collection("results").document(me))
        batch.deleteDocument(ref)
        try await batch.commit()
    }

    // MARK: Leaving

    func deleteAccount(uid: String, friendCode: String, friends: [String], shareCodes: [String]) async throws {
        let batch = db.batch()
        for friend in friends {
            batch.deleteDocument(friendRef(owner: uid, friend: friend))
            batch.deleteDocument(friendRef(owner: friend, friend: uid))
        }
        for code in shareCodes {
            batch.deleteDocument(db.collection("sharedChapters").document(code))
        }
        batch.deleteDocument(db.collection("friendCodes").document(friendCode))
        batch.deleteDocument(db.collection("profiles").document(uid))
        try await batch.commit()
        for challenge in try await challenges(for: uid) {
            try? await deleteChallenge(challenge.id, me: uid)
        }
        try? await Auth.auth().currentUser?.delete()
        try? Auth.auth().signOut()
    }

    // MARK: Bodies

    private func body<T: Decodable>(_ ref: DocumentReference, as type: T.Type) async throws -> T? {
        let snapshot = try await ref.getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return decode(data, as: type)
    }

    private func decode<T: Decodable>(_ data: [String: Any], as type: T.Type) -> T? {
        guard let text = data["body"] as? String else { return nil }
        return try? SocialJSON.decode(type, from: text)
    }
}

/// Made-up friends for screenshot mode, so the Friends screens can be checked in the Simulator
/// without Firebase. Nothing leaves the phone.
final class FixtureSocialBackend: SocialBackend, @unchecked Sendable {
    private var profiles: [String: PublicProfile] = [:]
    private var codes: [String: String] = [:]
    private var requests: [String: [FriendRequest]] = [:]
    private var lists: [String: [Friend]] = [:]
    private var shares: [String: SharedChapter] = [:]
    private var challengeList: [Challenge] = []
    private var results: [String: [String: ChallengeResult]] = [:]

    init() {
        let now = Date()
        let maya = PublicProfile(uid: "maya", displayName: "Maya", fishName: "Bubbles", friendCode: "MAYA22", fireDays: 6, fireFlame: "lit", bestFire: 9, mastered: 14, updatedAt: now)
        let theo = PublicProfile(uid: "theo", displayName: "Theo", fishName: "Captain", friendCode: "THEO33", fireDays: 2, fireFlame: "embers", bestFire: 5, mastered: 4, updatedAt: now)
        profiles = ["maya": maya, "theo": theo]
        codes = ["MAYA22": "maya", "THEO33": "theo"]
        lists["me"] = [Friend(uid: "maya", displayName: "Maya", since: now)]
        requests["me"] = [FriendRequest(fromUid: "theo", fromName: "Theo", fromFishName: "Captain", sentAt: now)]
        let challenge = Challenge(
            id: "fixture-teachoff", chapterCode: "SAMPLE23", chapterID: SampleChapter.id,
            chapterTitle: SampleChapter.chapter(createdAt: now).title,
            fromUid: "maya", fromName: "Maya", toUid: "me", toName: "You", createdAt: now
        )
        challengeList = [challenge]
        let exam = SampleChapter.exam(compiledAt: now)
        var mayaResults: [String: Bool] = [:]
        for (index, question) in TeachOff.questions(exam: exam).enumerated() {
            mayaResults[question.id] = index % 4 != 3
        }
        results[challenge.id] = ["maya": ChallengeResult(
            uid: "maya", name: "Maya", fishName: "Bubbles",
            score: TeachOffScore(results: mayaResults, onDevice: mayaResults.count, cloud: 0, finishedAt: now)
        )]
    }

    func signIn() async throws -> String { "me" }
    func currentUID() -> String? { "me" }
    func saveProfile(_ profile: PublicProfile) async throws { profiles[profile.uid] = profile }
    func profile(_ uid: String) async throws -> PublicProfile? { profiles[uid] }

    func claimFriendCode(_ code: String, uid: String) async throws -> Bool {
        guard codes[code] == nil else { return false }
        codes[code] = uid
        return true
    }

    func uid(forFriendCode code: String) async throws -> String? { codes[code] }
    func sendRequest(_ request: FriendRequest, to uid: String) async throws { requests[uid, default: []].append(request) }
    func incomingRequests(_ uid: String) async throws -> [FriendRequest] { requests[uid] ?? [] }

    func accept(_ request: FriendRequest, me: Friend, them: Friend) async throws {
        lists[me.uid, default: []].append(them)
        lists[them.uid, default: []].append(me)
        requests[me.uid]?.removeAll { $0.fromUid == them.uid }
    }

    func decline(fromUid: String, me: String) async throws { requests[me]?.removeAll { $0.fromUid == fromUid } }
    func friends(_ uid: String) async throws -> [Friend] { lists[uid] ?? [] }

    func removeFriend(_ friendUid: String, me: String) async throws {
        lists[me]?.removeAll { $0.uid == friendUid }
        lists[friendUid]?.removeAll { $0.uid == me }
    }

    func share(_ shared: SharedChapter, ownerUid: String) async throws { shares[shared.code] = shared }
    func sharedChapter(_ code: String) async throws -> SharedChapter? { shares[code] }
    func stopSharing(_ code: String) async throws { shares[code] = nil }

    func createChallenge(_ challenge: Challenge, result: ChallengeResult) async throws {
        challengeList.append(challenge)
        results[challenge.id, default: [:]][result.uid] = result
    }

    func challenges(for uid: String) async throws -> [Challenge] {
        challengeList.filter { $0.fromUid == uid || $0.toUid == uid }
    }

    func result(challengeID: String, uid: String) async throws -> ChallengeResult? {
        let all = results[challengeID] ?? [:]
        // The same rule as Firestore: someone else's result shows only once yours is in.
        if uid != "me" && all["me"] == nil {
            return nil
        }
        return all[uid]
    }

    func submit(_ result: ChallengeResult, challengeID: String) async throws {
        results[challengeID, default: [:]][result.uid] = result
    }

    func deleteChallenge(_ id: String, me: String) async throws {
        challengeList.removeAll { $0.id == id }
        results[id] = nil
    }

    func deleteAccount(uid: String, friendCode: String, friends: [String], shareCodes: [String]) async throws {
        profiles[uid] = nil
        codes[friendCode] = nil
        lists[uid] = nil
    }
}
