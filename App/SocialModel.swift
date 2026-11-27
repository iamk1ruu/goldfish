import Foundation
import Observation
import GoldfishCore

/// A friend with their profile, when it could be read.
struct FriendCard: Identifiable, Equatable {
    let friend: Friend
    var profile: PublicProfile?

    var id: String { friend.uid }

    var name: String {
        profile?.displayName ?? friend.displayName
    }
}

/// A teach-off with both sides, as far as this phone may see them.
struct TeachOffCard: Identifiable, Equatable {
    let challenge: Challenge
    var mine: ChallengeResult?
    /// Hidden by the rules until `mine` exists.
    var theirs: ChallengeResult?

    var id: String { challenge.id }

    enum Stage {
        /// Your Finn has not taken it yet.
        case yourTurn
        /// Yours is in. Theirs is not.
        case waiting
        case done
    }

    var stage: Stage {
        if mine == nil { return .yourTurn }
        return theirs == nil ? .waiting : .done
    }
}

/// Profiles, friends, shared chapters and teach-offs.
///
/// Friends are opt-in. Until the student turns them on, nothing about them is in the cloud.
/// Opening a shared chapter signs in anonymously, because the rules only let signed-in users read,
/// but it creates no profile.
@MainActor
@Observable
final class SocialModel {
    let backend: SocialBackend?

    var working = false
    var message: String?
    var profile: PublicProfile?
    var friends: [FriendCard] = []
    var requests: [FriendRequest] = []
    var teachOffs: [TeachOffCard] = []

    init(backend: SocialBackend?) {
        self.backend = backend
    }

    /// False when the app was built without Firebase.
    var available: Bool {
        backend != nil
    }

    func card(_ challengeID: String) -> TeachOffCard? {
        teachOffs.first { $0.id == challengeID }
    }

    // MARK: Turning friends on and off

    func turnOn(displayName: String, model: AppModel) async {
        guard let backend = backend else { return }
        let name = PublicProfile.cleanName(displayName)
        guard !name.isEmpty else {
            message = "Pick a name your friends will know you by."
            return
        }
        working = true
        defer { working = false }
        do {
            let uid = try await backend.signIn()
            var claimed: String?
            for _ in 0..<6 {
                let code = ShareCode.make(length: ShareCode.friendLength)
                if try await backend.claimFriendCode(code, uid: uid) {
                    claimed = code
                    break
                }
            }
            guard let code = claimed else {
                throw SocialError(description: "No friend code could be saved. Check that the Firestore rules are deployed (README).")
            }
            model.data.social = SocialState(uid: uid, displayName: name, friendCode: code)
            model.scheduleSave()
            message = nil
            await refresh(model: model)
        } catch {
            message = describe(error)
        }
    }

    /// At launch: signs back in. If the sign-in changed, for example after deleting the app, the old
    /// profile cannot be reached any more, so friends are turned off with a note.
    func resume(model: AppModel) async {
        guard let backend = backend, let state = model.data.social else { return }
        do {
            let uid = try await backend.signIn()
            if uid != state.uid {
                model.data.social = nil
                model.data.sharedCodes = [:]
                model.scheduleSave()
                message = "This install has a new sign-in, so your old friends profile can't be reached. Turn friends on again to get a new code."
                return
            }
            await refresh(model: model)
        } catch {
            model.diagnostics.log("Friends sign-in failed: \(error)")
        }
    }

    func turnOff(model: AppModel) async {
        guard let backend = backend, let state = model.data.social else { return }
        working = true
        defer { working = false }
        do {
            let friendIDs = (try? await backend.friends(state.uid))?.map { $0.uid } ?? friends.map { $0.id }
            try await backend.deleteAccount(
                uid: state.uid, friendCode: state.friendCode, friends: friendIDs,
                shareCodes: Array(model.data.sharedCodes.values)
            )
            model.data.social = nil
            model.data.sharedCodes = [:]
            model.scheduleSave()
            profile = nil
            friends = []
            requests = []
            teachOffs = []
            message = "Friends are off, and your profile is deleted."
        } catch {
            message = describe(error)
        }
    }

    // MARK: Refreshing

    func refresh(model: AppModel) async {
        guard let backend = backend, let state = model.data.social else { return }
        working = true
        defer { working = false }
        do {
            _ = try await backend.signIn()
            let profile = PublicProfile.make(
                uid: state.uid, displayName: state.displayName, friendCode: state.friendCode,
                data: model.data, today: model.today, at: model.now
            )
            try await backend.saveProfile(profile)
            self.profile = profile

            requests = try await backend.incomingRequests(state.uid).sorted { $0.sentAt > $1.sentAt }

            var cards: [FriendCard] = []
            for friend in try await backend.friends(state.uid) {
                cards.append(FriendCard(friend: friend, profile: try? await backend.profile(friend.uid)))
            }
            friends = cards.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            var seen = Set<String>()
            var offs: [TeachOffCard] = []
            for challenge in try await backend.challenges(for: state.uid) where !seen.contains(challenge.id) {
                seen.insert(challenge.id)
                let mine = try? await backend.result(challengeID: challenge.id, uid: state.uid)
                let other = challenge.other(than: state.uid)
                let theirs = mine == nil ? nil : (try? await backend.result(challengeID: challenge.id, uid: other.uid))
                offs.append(TeachOffCard(challenge: challenge, mine: mine, theirs: theirs))
            }
            teachOffs = offs.sorted { $0.challenge.createdAt > $1.challenge.createdAt }
            message = nil
        } catch {
            message = describe(error)
        }
    }

    // MARK: Friends

    func addFriend(code raw: String, model: AppModel) async -> Bool {
        guard let backend = backend, let state = model.data.social else { return false }
        let code = ShareCode.find(in: raw, length: ShareCode.friendLength) ?? ShareCode.normalize(raw)
        guard ShareCode.isValid(code, length: ShareCode.friendLength) else {
            message = "A friend code has 6 letters and numbers, like ABC-DEF."
            return false
        }
        guard code != state.friendCode else {
            message = "That's your own code. Send it to a friend instead."
            return false
        }
        working = true
        defer { working = false }
        do {
            guard let uid = try await backend.uid(forFriendCode: code) else {
                message = "No one has that code. Check it with your friend."
                return false
            }
            if friends.contains(where: { $0.id == uid }) {
                message = "You're already friends."
                return false
            }
            // They already asked you: accept instead of asking back.
            if let theirs = requests.first(where: { $0.fromUid == uid }) {
                await accept(theirs, model: model)
                return true
            }
            let request = FriendRequest(fromUid: state.uid, fromName: state.displayName, fromFishName: model.fishName, sentAt: model.now)
            do {
                try await backend.sendRequest(request, to: uid)
            } catch let error where FirestoreCode.isPermissionDenied(error) {
                message = "You've already sent them a request."
                return false
            }
            let name = (try? await backend.profile(uid))?.displayName ?? "your friend"
            message = "Request sent to \(name). They'll see it in their Friends tab."
            model.cue(.send)
            return true
        } catch {
            message = describe(error)
            return false
        }
    }

    func accept(_ request: FriendRequest, model: AppModel) async {
        guard let backend = backend, let state = model.data.social else { return }
        do {
            try await backend.accept(
                request,
                me: Friend(uid: state.uid, displayName: state.displayName, since: model.now),
                them: Friend(uid: request.fromUid, displayName: request.fromName, since: model.now)
            )
            model.cue(.correct)
            await refresh(model: model)
        } catch {
            message = describe(error)
        }
    }

    func decline(_ request: FriendRequest, model: AppModel) async {
        guard let backend = backend, let state = model.data.social else { return }
        do {
            try await backend.decline(fromUid: request.fromUid, me: state.uid)
            requests.removeAll { $0.fromUid == request.fromUid }
        } catch {
            message = describe(error)
        }
    }

    func remove(_ friend: FriendCard, model: AppModel) async {
        guard let backend = backend, let state = model.data.social else { return }
        do {
            try await backend.removeFriend(friend.id, me: state.uid)
            friends.removeAll { $0.id == friend.id }
        } catch {
            message = describe(error)
        }
    }

    // MARK: Shared chapters

    /// The chapter's share code, making one the first time. Nil if sharing failed, with a message.
    func share(chapterID: String, model: AppModel) async -> String? {
        working = true
        defer { working = false }
        do {
            let code = try await ensureShared(chapterID: chapterID, model: model)
            message = nil
            return code
        } catch {
            message = describe(error)
            return nil
        }
    }

    func stopSharing(chapterID: String, model: AppModel) async {
        guard let backend = backend, let code = model.data.sharedCodes[chapterID] else { return }
        do {
            try await backend.stopSharing(code)
            model.data.sharedCodes[chapterID] = nil
            model.scheduleSave()
            message = "That code no longer opens the chapter. Friends who opened it keep their copy."
        } catch {
            message = describe(error)
        }
    }

    private func ensureShared(chapterID: String, model: AppModel) async throws -> String {
        if let code = model.data.sharedCodes[chapterID] {
            return code
        }
        guard let backend = backend, let state = model.data.social else {
            throw SocialError(description: "Turn on friends first, in the Friends tab.")
        }
        guard let chapter = model.chapter(chapterID), let exam = model.exam(chapterID) else {
            throw SocialError(description: "That chapter is gone.")
        }
        _ = try await backend.signIn()
        // A new code is refused only if it is taken, which is very unlikely. Try a few.
        for attempt in 1...3 {
            let code = ShareCode.make(length: ShareCode.chapterLength)
            let shared = SharedChapter.make(code: code, ownerName: state.displayName, chapter: chapter, exam: exam, at: model.now)
            do {
                try await backend.share(shared, ownerUid: state.uid)
                model.data.sharedCodes[chapterID] = code
                model.scheduleSave()
                return code
            } catch let error where FirestoreCode.isPermissionDenied(error) && attempt < 3 {
                continue
            }
        }
        throw SocialError(description: "The chapter could not be shared. Try again.")
    }

    /// Opens a chapter from a code into the current deck. Returns its ID, or nil with a message.
    /// A chapter you already have, such as the sample or one you shared, is not copied again.
    func open(code raw: String, model: AppModel) async -> String? {
        guard let backend = backend else { return nil }
        let code = ShareCode.find(in: raw, length: ShareCode.chapterLength) ?? ShareCode.normalize(raw)
        guard ShareCode.isValid(code, length: ShareCode.chapterLength) else {
            message = "A chapter code has 8 letters and numbers, like ABCD-EFGH."
            return nil
        }
        working = true
        defer { working = false }
        do {
            _ = try await backend.signIn()
            guard let shared = try await backend.sharedChapter(code) else {
                message = "No chapter has that code. It may have been unshared."
                return nil
            }
            if let problem = shared.problems().first {
                message = "That chapter can't be opened: \(problem)."
                return nil
            }
            if model.chapter(shared.chapter.id) != nil {
                return shared.chapter.id
            }
            let chapter = shared.importedChapter(deckID: model.data.currentDeck?.id, at: model.now)
            // The exam is used as it is, without the fair exam check, so both phones ask the same questions.
            model.data.addChapter(chapter, exam: shared.exam)
            model.scheduleSave()
            message = nil
            return chapter.id
        } catch {
            message = describe(error)
            return nil
        }
    }

    // MARK: Teach-offs

    /// Sends a teach-off with your result already in, so your friend can see it once theirs is done.
    func startTeachOff(chapterID: String, friend: FriendCard, answers: [FishAnswer], model: AppModel) async -> String? {
        guard let backend = backend, let state = model.data.social, let chapter = model.chapter(chapterID) else { return nil }
        working = true
        defer { working = false }
        do {
            let code = try await ensureShared(chapterID: chapterID, model: model)
            let challenge = Challenge(
                id: UUID().uuidString.lowercased(), chapterCode: code, chapterID: chapterID, chapterTitle: chapter.title,
                fromUid: state.uid, fromName: state.displayName, toUid: friend.id, toName: friend.name, createdAt: model.now
            )
            let result = ChallengeResult(
                uid: state.uid, name: state.displayName, fishName: model.fishName,
                score: TeachOff.score(answers: answers, at: model.now)
            )
            try await backend.createChallenge(challenge, result: result)
            teachOffs.insert(TeachOffCard(challenge: challenge, mine: result, theirs: nil), at: 0)
            model.cue(.send)
            message = nil
            return challenge.id
        } catch {
            message = describe(error)
            return nil
        }
    }

    /// Sends your side of a teach-off, or replaces it after you improved your lesson.
    func submit(challengeID: String, answers: [FishAnswer], model: AppModel) async {
        guard let backend = backend, let state = model.data.social,
              let index = teachOffs.firstIndex(where: { $0.id == challengeID })
        else { return }
        working = true
        defer { working = false }
        let challenge = teachOffs[index].challenge
        let result = ChallengeResult(
            uid: state.uid, name: state.displayName, fishName: model.fishName,
            score: TeachOff.score(answers: answers, at: model.now)
        )
        do {
            try await backend.submit(result, challengeID: challengeID)
            let theirs = try? await backend.result(challengeID: challengeID, uid: challenge.other(than: state.uid).uid)
            teachOffs[index].mine = result
            teachOffs[index].theirs = theirs
            model.cue(.send)
            message = nil
        } catch {
            message = describe(error)
        }
    }

    func deleteTeachOff(_ challengeID: String, model: AppModel) async {
        guard let backend = backend, let state = model.data.social else { return }
        do {
            try await backend.deleteChallenge(challengeID, me: state.uid)
            teachOffs.removeAll { $0.id == challengeID }
        } catch {
            message = describe(error)
        }
    }

    // MARK: Errors

    func describe(_ error: Error) -> String {
        if let social = error as? SocialError {
            return social.description
        }
        if FirestoreCode.isOffline(error) {
            return "You're offline. Friends and sharing need a connection."
        }
        if FirestoreCode.isPermissionDenied(error) {
            return "Firebase refused that. Check that the Firestore rules are deployed and App Check knows this install (Diagnostics)."
        }
        let kind = ModelErrorKind.classify(String(describing: error))
        if kind == .offline || kind == .appCheck {
            return kind.userMessage
        }
        return "Something went wrong: \(error.localizedDescription)"
    }
}
