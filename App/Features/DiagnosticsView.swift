import SwiftUI
import UIKit
import GoldfishCore

/// There is no debugger or console on a sideloaded app, so the app carries its own.
/// Opened with a long press on the version number in Settings. Keep it off camera in the demo.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    @State private var fishCheck = FishCheckModel()
    @State private var gradingCheck = GradingCheckModel()
    @State private var showToken = false
    @State private var confirmReset = false
    @State private var copied: String?

    var body: some View {
        List {
            buildSection
            modelSection
            appCheckSection
            fishCheckSection
            gradingCheckSection
            callsSection
            timeMachineSection
            settingsSection
            dataSection
            logSection
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Erase all chapters, lessons and progress?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset everything", role: .destructive) { model.resetAll() }
        }
    }

    // MARK: Sections

    private var buildSection: some View {
        Section("Build") {
            row("Bundle ID", Bundle.main.bundleIdentifier ?? "?")
            row("Version", "\(info("CFBundleShortVersionString")) (\(info("CFBundleVersion")))")
            row("Device", DeviceInfo.description)
            row("Firebase", model.firebaseReady ? "Configured" : "Not configured (no GoogleService-Info.plist)")
            row("Fish", model.usesScriptedFish ? "Scripted stand-in" : "Hybrid: Apple's model, then \(model.settings.fishCloudModel)")
            row("Network", model.network.isOnline ? "Online" : "Offline")
        }
    }

    private var modelSection: some View {
        Section("Apple's model") {
            Text(model.firebaseReady ? AppleModelStatus.summary : "Unknown until Firebase is configured")
                .font(.poppins(.callout))
        }
    }

    private var appCheckSection: some View {
        Section {
            if let token = model.firebaseReady ? FirebaseSetup.debugToken() : nil {
                Text(showToken ? token : String(repeating: "•", count: 24) + token.suffix(4))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                HStack {
                    Button(showToken ? "Hide" : "Show") { showToken.toggle() }
                    Spacer()
                    Button("Copy token") {
                        UIPasteboard.general.string = token
                        copied = "Token copied. Register it in the Firebase console under App Check."
                    }
                }
            } else {
                Text("No debug token. Firebase is not configured.").font(.poppins(.callout))
            }
            if let copied = copied {
                Text(copied).font(.poppins(.caption)).foregroundStyle(.secondary)
            }
        } header: {
            Text("App Check debug token")
        } footer: {
            Text("Never commit this token or show it in the demo video.")
        }
    }

    private var fishCheckSection: some View {
        Section {
            Picker("Fish", selection: $fishCheck.source) {
                ForEach(FishCheckModel.Source.allCases) { source in
                    Text(source.label).tag(source)
                }
            }
            Stepper("Repeats: \(fishCheck.repeats)", value: $fishCheck.repeats, in: 1...3)
            Text("\(FidelityRunner.plan(repeats: fishCheck.repeats).count) prompts: 20 cell-biology questions with a good, gapped, wrong and empty lesson.")
                .font(.poppins(.caption))
                .foregroundStyle(.secondary)
            if fishCheck.running {
                ProgressView(value: Double(fishCheck.done), total: Double(max(fishCheck.total, 1))) {
                    Text("\(fishCheck.done) of \(fishCheck.total)")
                }
                Text(fishCheck.lastLine).font(.caption.monospaced()).foregroundStyle(.secondary)
                Button("Stop", role: .destructive) { fishCheck.stop() }
            } else {
                Button("Run the Fish Check") {
                    Task { await fishCheck.run(model: model) }
                }
            }
            if let message = fishCheck.message {
                Text(message).font(.poppins(.caption)).foregroundStyle(.orange)
            }
            if let report = fishCheck.report {
                Text(fishCheck.verdictTitle ?? "").font(.poppins(.headline))
                Text(report)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                HStack {
                    Button("Copy summary") {
                        UIPasteboard.general.string = report
                        copied = "Fish Check summary copied."
                    }
                    Spacer()
                    ShareLink(item: report) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        } header: {
            Text("Fish Check")
        } footer: {
            Text("The go or no-go test from the plan. Run it with Apple's model only, so the cloud cannot hide failures. Keep the app open: on-device inference stops in the background.")
        }
    }

    /// Graded recall goes on only if Apple's model grades the twelve test answers well enough.
    private var gradingCheckSection: some View {
        Section {
            row("Graded recall", model.gradesRecall ? "On" : "Off")
            if let record = model.data.gradingCheck {
                row("Last check", "\(record.passed ? "Passed" : "Failed"): \(record.agreed) of \(record.total), \(record.harmful) harmful")
            }
            if gradingCheck.running {
                ProgressView(value: Double(gradingCheck.done), total: Double(GradingCheck.cases.count)) {
                    Text("\(gradingCheck.done) of \(GradingCheck.cases.count)")
                }
                Button("Stop", role: .destructive) { gradingCheck.stop() }
            } else {
                Button("Run the Grading Check") {
                    Task { await gradingCheck.run(model: model) }
                }
            }
            if let message = gradingCheck.message {
                Text(message).font(.poppins(.caption)).foregroundStyle(.orange)
            }
            if let report = gradingCheck.report {
                Text(report)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                HStack {
                    Button("Copy summary") {
                        UIPasteboard.general.string = report
                        copied = "Grading Check summary copied."
                    }
                    Spacer()
                    ShareLink(item: report) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            if model.data.gradingCheck != nil && !gradingCheck.running {
                Button("Forget the result", role: .destructive) {
                    model.data.gradingCheck = nil
                    model.scheduleSave()
                }
            }
        } header: {
            Text("Grading Check")
        } footer: {
            Text("Apple's model grades 12 typed answers, with no cloud. Graded recall goes on for this iPhone if at least \(GradingCheck.required) match a teacher's grade and none calls a wrong answer right or a right one wrong. To turn it on for everyone after a pass, set short_answer_grading to true in Remote Config.")
        }
    }

    private var callsSection: some View {
        Section("Recent answers (\(model.diagnostics.calls.elements.count))") {
            if model.diagnostics.calls.elements.isEmpty {
                Text("No model calls yet.").font(.poppins(.callout)).foregroundStyle(.secondary)
            }
            ForEach(model.diagnostics.calls.elements.reversed()) { call in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(call.lane).font(.poppins(.caption, weight: .semibold))
                        if let tier = call.tier {
                            TierBadge(tier: tier)
                        }
                        Spacer()
                        Text("\(call.latencyMs) ms").font(.poppins(.caption2).monospacedDigit())
                        Image(systemName: call.ok ? "checkmark.circle" : "xmark.octagon")
                            .foregroundStyle(call.ok ? Color.green : Color.red)
                    }
                    Text(call.modelVersion.isEmpty ? "-" : call.modelVersion)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    if !call.detail.isEmpty {
                        Text(call.detail).font(.poppins(.caption2)).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
        }
    }

    private var timeMachineSection: some View {
        Section {
            Stepper(
                "Days ahead: \(model.timeOffsetDays)",
                value: Binding(get: { model.timeOffsetDays }, set: { model.setTimeOffset($0) }),
                in: 0...60
            )
            row("App date", model.now.formatted(date: .abbreviated, time: .shortened))
            Button("Back to today") { model.setTimeOffset(0) }
                .disabled(model.timeOffsetDays == 0)
        } header: {
            Text("Time machine")
        } footer: {
            Text("Moves the app's clock forward to test Fresh Water and spaced reviews.")
        }
    }

    private var settingsSection: some View {
        Section {
            ForEach(GoldfishSettings.remoteKeys, id: \.self) { key in
                row(key + (model.remoteChanges.contains(key) ? " (remote)" : ""), model.settings.value(forKey: key))
            }
        } header: {
            Text("Settings in effect")
        } footer: {
            Text("Values come from Remote Config when set there, otherwise from built-in defaults.")
        }
    }

    private var dataSection: some View {
        Section("Data") {
            Button("Load the sample chapter") { model.loadSample() }
            if let chapterID = model.data.chapters.first(where: { !$0.isSample })?.id {
                Button("Run the fair exam check on the newest chapter") {
                    Task { await model.runFairCheck(chapterID: chapterID) }
                }
            }
            Button("Reset everything", role: .destructive) { confirmReset = true }
        }
    }

    private var logSection: some View {
        Section {
            ShareLink(item: model.diagnostics.text) {
                Label("Share the log", systemImage: "square.and.arrow.up")
            }
            ForEach(Array(model.diagnostics.lines.elements.suffix(120).reversed().enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption2.monospaced())
            }
        } header: {
            Text("Log (\(model.diagnostics.lines.elements.count) lines)")
        }
    }

    // MARK: Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.poppins(.callout))
            Spacer()
            Text(value)
                .font(.poppins(.callout))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func info(_ key: String) -> String {
        Bundle.main.infoDictionary?[key] as? String ?? "?"
    }
}

/// Runs the Fish Check on the phone and produces a copyable report.
@MainActor
@Observable
final class FishCheckModel {
    enum Source: String, CaseIterable, Identifiable {
        case onDevice
        case hybrid
        case cloud
        case scripted

        var id: String { rawValue }

        var label: String {
            switch self {
            case .onDevice: return "Apple's model only"
            case .hybrid: return "Hybrid (as shipped)"
            case .cloud: return "Cloud only"
            case .scripted: return "Scripted (checks the check)"
            }
        }
    }

    var source: Source = .onDevice
    var repeats = 2
    var running = false
    var done = 0
    var total = 0
    var lastLine = ""
    var report: String?
    var verdictTitle: String?
    var message: String?

    @ObservationIgnored private var stopFlag = StopFlag()

    func run(model: AppModel) async {
        guard !running else { return }
        message = nil
        if source != .scripted && !model.firebaseReady {
            message = "Firebase is not configured in this build, so only the scripted fish can run."
            return
        }
        if source == .onDevice && !AppleModelStatus.isAvailable {
            message = "Apple's model is not available: \(AppleModelStatus.summary)"
            return
        }

        running = true
        report = nil
        verdictTitle = nil
        done = 0
        total = FidelityRunner.plan(repeats: repeats).count
        let flag = StopFlag()
        stopFlag = flag

        let engine = makeEngine(cloudModel: model.settings.fishCloudModel)
        let started = Date()
        model.diagnostics.log("Fish Check started: \(source.label), \(repeats) repeats")
        let result = await FidelityRunner(engine: engine).run(
            repeats: repeats,
            shouldStop: { flag.isStopped },
            onProgress: { [weak self] done, total, trial in
                let line = "\(trial.itemID) \(trial.condition.rawValue): \(trial.pick.rawValue), \(trial.latencyMs) ms"
                Task { @MainActor in
                    self?.done = done
                    self?.total = total
                    self?.lastLine = line
                }
            }
        )

        let meta = FidelityMeta(
            source: "\(source.label), cloud model \(model.settings.fishCloudModel)",
            device: DeviceInfo.description,
            repeats: repeats,
            date: Date()
        )
        report = FidelityReport.text(result, meta: meta)
        verdictTitle = result.summary.verdict.title
        model.diagnostics.record(ModelCallRecord(
            lane: "fishCheck", tier: source == .onDevice ? .onDevice : nil,
            modelVersion: source.label, latencyMs: AppModel.ms(since: started), ok: true,
            detail: "\(result.summary.verdict.code.rawValue), \(result.trials.count) trials, p50 \(result.summary.latencyP50) ms"
        ))
        running = false
    }

    func stop() {
        stopFlag.stop()
    }

    private func makeEngine(cloudModel: String) -> FishEngine {
        switch source {
        case .onDevice: return FirebaseFishEngine(route: .onDeviceOnly, cloudModel: cloudModel)
        case .hybrid: return FirebaseFishEngine(route: .hybrid, cloudModel: cloudModel)
        case .cloud: return FirebaseFishEngine(route: .cloudOnly, cloudModel: cloudModel)
        case .scripted: return ScriptedFidelityEngine(persona: .ideal)
        }
    }
}

/// Runs the Grading Check on Apple's model only and saves the verdict, which turns graded recall
/// on or off for this phone.
@MainActor
@Observable
final class GradingCheckModel {
    var running = false
    var done = 0
    var report: String?
    var message: String?

    @ObservationIgnored private var stopFlag = StopFlag()

    func run(model: AppModel) async {
        guard !running else { return }
        message = nil
        guard model.firebaseReady else {
            message = "Firebase is not configured in this build, so there is no model to test."
            return
        }
        guard AppleModelStatus.isAvailable else {
            message = "Apple's model is not available: \(AppleModelStatus.summary)"
            return
        }
        running = true
        report = nil
        done = 0
        let flag = StopFlag()
        stopFlag = flag
        let started = Date()
        model.diagnostics.log("Grading Check started on Apple's model")
        let result = await GradingCheck.run(
            engine: FirebaseFishEngine(route: .onDeviceOnly, cloudModel: model.settings.fishCloudModel),
            shouldStop: { flag.isStopped },
            onProgress: { [weak self] done, _ in
                Task { @MainActor in
                    self?.done = done
                }
            }
        )
        running = false
        guard result.trials.count == GradingCheck.cases.count else {
            message = "Stopped before the end, so nothing was saved."
            return
        }
        model.data.gradingCheck = GradingCheckRecord(result, at: model.now)
        model.scheduleSave()
        report = GradingCheck.report(result, source: "Apple's model only", device: DeviceInfo.description, date: Date())
        model.diagnostics.record(ModelCallRecord(
            lane: "gradingCheck", tier: .onDevice, modelVersion: result.modelVersion,
            latencyMs: AppModel.ms(since: started), ok: true,
            detail: "\(result.passed ? "pass" : "fail"), \(result.agreed)/\(result.trials.count) agreed, \(result.harmful) harmful"
        ))
    }

    func stop() {
        stopFlag.stop()
    }
}

@MainActor
enum DeviceInfo {
    /// For example "iPhone18,1, iOS 26.1".
    static var description: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { buffer -> String in
            let bytes = buffer.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return "\(machine.isEmpty ? UIDevice.current.model : machine), iOS \(UIDevice.current.systemVersion)"
    }
}
