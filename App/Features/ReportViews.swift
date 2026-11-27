import SwiftUI
import GoldfishCore

/// The Report Card. Headline counts are computed on the phone; the lists come from the cloud.
struct ReportCardView: View {
    @Environment(AppModel.self) private var model
    let chapterID: String

    @State private var retrying = false

    var body: some View {
        if let report = model.data.reports[chapterID] {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        PixelTank(mood: .graduate, scale: 3, fishAt: UnitPoint(x: 0.3, y: 0.7), weeds: [], bubbles: 2)
                            .frame(width: 132, height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                        SpeechBubble(text: "Here's our report card!", tail: .leading, name: model.fishName)
                    }
                    SectionHeader(title: "Results")
                        .padding(.top, 8)
                    HStack(spacing: 12) {
                        headline("Your explanation covered", report.coverageCorrect, report.coverageTotal)
                        headline("You answered unaided", report.unaidedCorrect, report.unaidedTotal)
                    }
                    SectionHeader(title: "What the cloud noticed")
                        .padding(.top, 8)
                    if report.isDraft {
                        Card {
                            Label(
                                model.network.isOnline
                                    ? "This is a quick draft made on this iPhone. The full report is on its way."
                                    : "You're offline. This draft was made on this iPhone, and the full report will be written when you reconnect.",
                                systemImage: "icloud.and.arrow.up"
                            )
                            .font(.poppins(.callout))
                            Button(retrying ? "Asking the cloud…" : "Get the full report now") {
                                Task {
                                    retrying = true
                                    await model.flushPendingReports()
                                    retrying = false
                                }
                            }
                            .disabled(retrying || !model.network.isOnline)
                        }
                    } else {
                        HStack(spacing: 8) {
                            TierBadge(tier: model.firebaseReady ? .cloud : .scripted)
                            Text("Written by \(report.writtenBy)")
                                .font(.poppins(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    list("Explained well", report.explainedWell, color: Theme.correctTint.text)
                    list("Misconceptions", report.misconceptions, color: Theme.mixUpTint.text)
                    list("Review next", report.reviewNext, color: Theme.taughtTint.text)
                    NavigationLink(value: Route.map(chapterID)) {
                        Text("See the Mastery Map")
                    }
                    .buttonStyle(.primary)
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Report Card")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            FishMessage(title: "No Report Card yet", message: "Take the final exam to get one.", mood: .curious)
        }
    }

    /// A Figma stat tile: a pale card with a big purple number.
    private func headline(_ title: String, _ value: Int, _ total: Int) -> some View {
        Card(flat: true) {
            Text(title)
                .font(.poppins(.footnote))
                .foregroundStyle(Theme.ink3)
            Text("\(value)/\(total)")
                .font(.poppins(size: 30, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.link)
                .accessibilityLabel("\(value) of \(total)")
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ items: [String], color: Color) -> some View {
        if !items.isEmpty {
            Card {
                Text(title)
                    .font(.poppins(.subheadline))
                    .foregroundStyle(color)
                ForEach(items, id: \.self) { item in
                    Text(item).font(.poppins(.callout, weight: .medium))
                }
            }
        }
    }
}

/// Each concept's state. Mastery is what the student has shown, never the fish's score.
struct MasteryMapView: View {
    @Environment(AppModel.self) private var model
    let chapterID: String

    var body: some View {
        if let exam = model.exam(chapterID) {
            let counts = model.masteredCount(chapterID)
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("You've mastered \(counts.mastered) of \(counts.total) concepts")
                            .font(.poppins(.title3, weight: .bold))
                        Text("A concept is mastered when you answer it correctly yourself on three different days. \(model.fishName)'s score never counts toward mastery.")
                            .font(.poppins(.caption))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section("Concepts") {
                    ForEach(exam.concepts) { concept in
                        row(concept)
                    }
                }
                Section("What the states mean") {
                    legend(.notTaught, "The section is empty, or the fish hasn't answered from it yet.")
                    legend(.taught, "The fish answered this concept's questions correctly from your lesson.")
                    legend(.recalled, "The same, from a lesson you wrote from memory.")
                    legend(.mastered, "You answered it yourself on three different days.")
                }
            }
            .navigationTitle("Mastery Map")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            FishMessage(title: "Chapter not found", message: "It may have been deleted.")
        }
    }

    private func row(_ concept: Concept) -> some View {
        let progress = model.data.concepts[concept.id]
        let days = Set(progress?.correctDays ?? []).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                ConceptToken(state: model.data.conceptState(concept.id))
                Text(concept.name).font(.poppins(.headline))
                Spacer()
                StateChip(state: model.data.conceptState(concept.id))
            }
            HStack(spacing: 6) {
                ForEach(0..<MasteryRules.daysNeeded, id: \.self) { index in
                    Circle()
                        .fill(index < days ? Theme.brand : Theme.rule)
                        .frame(width: 10, height: 10)
                }
                Text("\(min(days, MasteryRules.daysNeeded)) of \(MasteryRules.daysNeeded) days")
                    .font(.poppins(.caption))
                    .foregroundStyle(.secondary)
                Spacer()
                if let due = progress?.dueOn {
                    Text(dueText(due)).font(.poppins(.caption)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func legend(_ state: ConceptState, _ text: String) -> some View {
        HStack(alignment: .top) {
            ConceptToken(state: state)
            StateChip(state: state)
            Text(text).font(.poppins(.caption))
        }
    }

    private func dueText(_ day: Day) -> String {
        let days = model.today.days(until: day)
        if days <= 0 { return "Your Turn due" }
        if days == 1 { return "Your Turn tomorrow" }
        return "Your Turn in \(days) days"
    }
}
