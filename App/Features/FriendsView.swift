import SwiftUI
import UIKit
import GoldfishCore

/// The Friends tab. Your profile and friend code, requests, teach-offs, and opening a shared chapter.
/// Friends are opt-in: nothing about you is in the cloud until you turn them on.
struct FriendsView: View {
    @Environment(AppModel.self) private var model

    @State private var name = ""
    @State private var friendCode = ""
    @State private var chapterCode = ""
    @State private var removing: FriendCard?

    var body: some View {
        let social = model.social
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Friends")
                        .font(.poppins(.title))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Teach the same chapter. See whose fish learns more.")
                        .font(.poppins(.callout, weight: .medium))
                        .foregroundStyle(Theme.ink3)
                }
                .padding(.top, 10)

                if !social.available {
                    FishMessage(
                        title: "Friends need Firebase",
                        message: "This build has no Firebase config, so profiles and sharing are off. See the README to add one.",
                        mood: .shrug
                    )
                } else if model.data.social == nil {
                    intro(working: social.working)
                } else {
                    profileCard
                    addFriendCard(working: social.working)
                    if !social.requests.isEmpty {
                        requestsSection(social.requests)
                    }
                    teachOffsSection(social.teachOffs)
                    friendsSection(social.friends)
                }

                if social.available {
                    openChapterCard(working: social.working)
                }

                if let message = social.message {
                    Label(message, systemImage: "info.circle")
                        .font(.poppins(.footnote))
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await model.social.refresh(model: model)
        }
        .task {
            await model.social.refresh(model: model)
        }
        .confirmationDialog(
            "Remove \(removing?.name ?? "this friend")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove friend", role: .destructive) {
                if let friend = removing {
                    Task { await model.social.remove(friend, model: model) }
                }
                removing = nil
            }
        } message: {
            Text("You both leave each other's list. Teach-offs you already shared stay.")
        }
    }

    // MARK: Off

    private func intro(working: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PixelTank(mood: .curious, scale: 3, fishAt: UnitPoint(x: 0.5, y: 0.62), weeds: [0.04, 0.9], bubbles: 3)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
            SpeechBubble(
                text: "In a teach-off, you and a friend each teach me the same chapter. My cousin learns from your friend. We both take the same questions, and you see whose lesson worked.",
                tail: .top,
                name: model.fishName
            )
            Card {
                Text("What friends see")
                    .font(.poppins(.headline))
                privacyLine("person.fill", "Your name and \(model.fishName)'s name")
                privacyLine("flame.fill", "Your fire and how many ideas you've mastered")
                privacyLine("lock.fill", "Never your lessons or answers. They stay on this iPhone")
            }
            LabeledField(label: "Your name for friends") {
                TextField("First name or nickname", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            Button {
                Task { await model.social.turnOn(displayName: name, model: model) }
            } label: {
                if working {
                    BubbleDots()
                } else {
                    Text("Turn on friends")
                }
            }
            .buttonStyle(.primary)
            .disabled(working || PublicProfile.cleanName(name).isEmpty)
            Text("You can turn friends off in Settings, which deletes your profile.")
                .font(.poppins(.caption))
                .foregroundStyle(Theme.ink3)
        }
    }

    private func privacyLine(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.poppins(.callout))
            .foregroundStyle(Theme.ink2)
    }

    // MARK: On

    private var profileCard: some View {
        let state = model.data.social
        let fire = FireStreak.compute(model.data.teachingDays, today: model.today)
        let code = ShareCode.display(state?.friendCode ?? "")
        return Card {
            HStack(spacing: 12) {
                FishView(mood: .happy, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state?.displayName ?? "")
                        .font(.poppins(.headline))
                        .foregroundStyle(Theme.ink)
                    Text("and \(model.fishName)")
                        .font(.poppins(.footnote))
                        .foregroundStyle(Theme.ink3)
                }
                Spacer()
                FireBadge(streak: fire)
            }
            Divider()
            Text("YOUR FRIEND CODE")
                .font(.poppins(.caption2))
                .tracking(0.6)
                .foregroundStyle(Theme.ink3)
            Text(code)
                .font(.poppins(size: 30, weight: .bold).monospaced())
                .foregroundStyle(Theme.link)
                .textSelection(.enabled)
                .accessibilityLabel("Your friend code: \(code.map { String($0) }.joined(separator: " "))")
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = code
                    model.cue(.select)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.secondary)
                ShareLink(item: "Add me on Goldfish so we can have a teach-off. My friend code is \(code).") {
                    Label("Send", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.secondary)
            }
        }
    }

    private func addFriendCard(working: Bool) -> some View {
        Card {
            Text("Add a friend")
                .font(.poppins(.headline))
            HStack(spacing: 10) {
                TextField("Their code, like ABC-DEF", text: $friendCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.poppins(.callout, weight: .medium).monospaced())
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                            .strokeBorder(Theme.brand2, lineWidth: 1)
                    )
                Button("Add") {
                    Task {
                        if await model.social.addFriend(code: friendCode, model: model) {
                            friendCode = ""
                        }
                    }
                }
                .buttonStyle(.primaryCompact)
                .disabled(working || friendCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func requestsSection(_ requests: [FriendRequest]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Requests", detail: "\(requests.count)")
            ForEach(requests) { request in
                Card {
                    Text("\(request.fromName) and \(request.fromFishName) want to be friends.")
                        .font(.poppins(.callout, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 10) {
                        Button("Accept") {
                            Task { await model.social.accept(request, model: model) }
                        }
                        .buttonStyle(.primary)
                        Button("Decline") {
                            Task { await model.social.decline(request, model: model) }
                        }
                        .buttonStyle(.secondary)
                    }
                }
            }
        }
    }

    private func teachOffsSection(_ cards: [TeachOffCard]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Teach-offs", detail: cards.isEmpty ? nil : "\(cards.count)")
            if cards.isEmpty {
                Text("Start one from any chapter: open it and choose \"Teach-off with a friend\".")
                    .font(.poppins(.footnote))
                    .foregroundStyle(Theme.ink3)
            }
            ForEach(cards) { card in
                NavigationLink(value: Route.teachOff(card.id)) {
                    ListCard(card.challenge.chapterTitle) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.link)
                    } detail: {
                        HStack(spacing: 8) {
                            Text("with \(card.challenge.other(than: model.data.social?.uid ?? "").name)")
                                .font(.poppins(.footnote))
                                .foregroundStyle(Theme.ink3)
                            stagePill(card)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stagePill(_ card: TeachOffCard) -> Pill {
        switch card.stage {
        case .yourTurn:
            return Pill(text: "Your turn", tint: Theme.Tint(text: Theme.link, fill: Theme.lavender))
        case .waiting:
            return Pill(text: "Waiting", tint: Theme.gapTint)
        case .done:
            let mine = card.mine?.score.right ?? 0
            let theirs = card.theirs?.score.right ?? 0
            return Pill(text: "\(mine) to \(theirs)", tint: Theme.correctTint)
        }
    }

    private func friendsSection(_ friends: [FriendCard]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Friends", detail: friends.isEmpty ? nil : "\(friends.count)")
            if friends.isEmpty {
                Text("Send your code to a friend, or add theirs above.")
                    .font(.poppins(.footnote))
                    .foregroundStyle(Theme.ink3)
            }
            ForEach(friends) { friend in
                HStack(spacing: 12) {
                    FishView(mood: .happy, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(friend.name)
                            .font(.poppins(.headline))
                            .foregroundStyle(Theme.ink)
                        Text(friendLine(friend))
                            .font(.poppins(.footnote))
                            .foregroundStyle(Theme.ink3)
                    }
                    Spacer()
                    if let profile = friend.profile {
                        FireBadge(streak: profile.fire)
                    }
                    Menu {
                        Button("Remove friend", role: .destructive) {
                            removing = friend
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Options for \(friend.name)")
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                        .strokeBorder(Theme.line)
                )
            }
        }
    }

    private func friendLine(_ friend: FriendCard) -> String {
        guard let profile = friend.profile else { return "Profile not loaded" }
        return "\(profile.fishName) · \(profile.mastered) idea\(profile.mastered == 1 ? "" : "s") mastered"
    }

    // MARK: Opening a shared chapter

    private func openChapterCard(working: Bool) -> some View {
        Card {
            Text("Open a shared chapter")
                .font(.poppins(.headline))
            Text("Paste the message or type the code. It goes into your current deck.")
                .font(.poppins(.footnote))
                .foregroundStyle(Theme.ink3)
            HStack(spacing: 10) {
                TextField("Code, like ABCD-EFGH", text: $chapterCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.poppins(.callout, weight: .medium).monospaced())
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                            .strokeBorder(Theme.brand2, lineWidth: 1)
                    )
                Button("Open") {
                    Task {
                        if let id = await model.social.open(code: chapterCode, model: model) {
                            chapterCode = ""
                            model.path.append(.chapter(id))
                        }
                    }
                }
                .buttonStyle(.primaryCompact)
                .disabled(working || chapterCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
