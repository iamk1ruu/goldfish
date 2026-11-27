import SwiftUI
import GoldfishCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var reminderOn = false
    @State private var cue = FeedingTime.cues[0]
    @State private var customCue = ""
    @State private var time = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var reminderStatus: String?
    @State private var loaded = false
    @State private var confirmFriendsOff = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Your fish") {
                FishView(mood: .happy, size: 84)
                    .frame(maxWidth: .infinity)
                TextField("Name", text: $model.data.fishName)
                    .onChange(of: model.data.fishName) { model.scheduleSave() }
            }

            // "When I ___, I'll teach Finn."
            Section {
                Toggle("Daily reminder", isOn: $reminderOn)
                if reminderOn {
                    Picker("When I…", selection: $cue) {
                        ForEach(FeedingTime.cues, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Or write your own cue", text: $customCue)
                    DatePicker("At", selection: $time, displayedComponents: .hourAndMinute)
                    Text("When I \(chosenCue), I'll teach \(model.fishName).")
                        .font(.poppins(.callout))
                        .italic()
                }
                Button("Save reminder") {
                    Task { await saveReminder() }
                }
                if let status = reminderStatus {
                    Text(status).font(.poppins(.caption)).foregroundStyle(.secondary)
                }
            } header: {
                Text("Feeding Time")
            } footer: {
                Text("Tying study to something you already do each day makes it easier to remember.")
            }

            // Sounds follow the silent switch.
            Section {
                Toggle("Sounds", isOn: $model.data.preferences.sounds)
                Toggle("Haptics", isOn: $model.data.preferences.haptics)
            } header: {
                Text("Sounds and haptics")
            } footer: {
                Text("8-bit sounds when \(model.fishName) answers and when you master an idea. The silent switch mutes them.")
            }
            .onChange(of: model.data.preferences) { model.scheduleSave() }

            // Turning friends off deletes the profile in the cloud.
            if let social = model.data.social {
                Section {
                    LabeledContent("Name", value: social.displayName)
                    LabeledContent("Friend code", value: ShareCode.display(social.friendCode))
                    Button("Turn off friends", role: .destructive) {
                        confirmFriendsOff = true
                    }
                    .disabled(model.social.working)
                } header: {
                    Text("Friends")
                } footer: {
                    Text("Deletes your profile, your friend code, your friend links and the chapters you shared. Your chapters and lessons on this iPhone stay.")
                }
            }

            Section("How Goldfish works") {
                Text("\(model.fishName) answers on this iPhone with Apple's on-device model, so quizzes work offline and cost nothing. Gemini in the cloud reads your chapter, writes the hidden exam and writes your Report Card. Both run through Firebase AI Logic.")
                    .font(.poppins(.callout))
            }

            Section {
                Text(versionLine)
                    .font(.poppins(.callout).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onLongPressGesture {
                        model.path.append(.diagnostics)
                    }
                    .accessibilityHint("Long press to open Diagnostics")
            } footer: {
                Text("Built for the #BuildHybridAI hackathon.")
            }
        }
        .navigationTitle("Settings")
        .onAppear(perform: loadReminder)
        .confirmationDialog("Turn off friends and delete your profile?", isPresented: $confirmFriendsOff, titleVisibility: .visible) {
            Button("Turn off and delete", role: .destructive) {
                Task { await model.social.turnOff(model: model) }
            }
        }
    }

    private var chosenCue: String {
        let custom = customCue.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? cue : custom
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Goldfish \(version) (\(build))"
    }

    private func loadReminder() {
        guard !loaded else { return }
        loaded = true
        guard let plan = model.data.reminder else { return }
        reminderOn = plan.enabled
        if FeedingTime.cues.contains(plan.cue) {
            cue = plan.cue
        } else {
            customCue = plan.cue
        }
        time = Calendar.current.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: Date()) ?? time
    }

    private func saveReminder() async {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let plan = ReminderPlan(cue: chosenCue, hour: parts.hour ?? 19, minute: parts.minute ?? 0, enabled: reminderOn)
        model.data.reminder = plan
        model.scheduleSave()
        let ok = await FeedingTime.schedule(plan, fishName: model.fishName, dueChapter: model.dueChapters().first?.title)
        if !reminderOn {
            reminderStatus = "Reminder off."
        } else if ok {
            reminderStatus = String(format: "Reminder set for %02d:%02d every day.", plan.hour, plan.minute)
        } else {
            reminderStatus = "Notifications are off for Goldfish. Turn them on in the Settings app."
        }
    }
}
