import Foundation
import Network
import Observation
import PDFKit
import UserNotifications
import GoldfishCore

/// Launch arguments used by scripts/screenshots.sh and for testing.
struct LaunchOptions {
    /// `-GoldfishScreen today` opens one screen with fixture data and no saving.
    var screen: String?
    /// `-GoldfishScripted` plays the fish with the scripted stand-in even when Firebase is set up.
    var scriptedFish: Bool

    var screenshotMode: Bool {
        screen != nil
    }

    static var current: LaunchOptions {
        let arguments = ProcessInfo.processInfo.arguments
        var screen: String? = nil
        if let index = arguments.firstIndex(of: "-GoldfishScreen"), index + 1 < arguments.count {
            screen = arguments[index + 1]
        }
        return LaunchOptions(screen: screen, scriptedFish: arguments.contains("-GoldfishScripted"))
    }
}

/// Text extraction on the phone.
enum ChapterImport {
    struct Imported {
        let title: String
        let text: String
        let pdfData: Data?
    }

    struct ImportError: Error, CustomStringConvertible {
        let description: String
    }

    static func load(_ url: URL) throws -> Imported {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        let title = url.deletingPathExtension().lastPathComponent
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(data: data) else {
                throw ImportError(description: "That PDF could not be opened.")
            }
            let text = (document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard TextNormalizer.wordCount(text) >= 100 else {
                throw ImportError(description: "This PDF has almost no selectable text, so it may be a scan. Paste the text instead.")
            }
            return Imported(title: title, text: text, pdfData: nil)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ImportError(description: "That file is not plain text.")
        }
        return Imported(title: title, text: text, pdfData: nil)
    }
}

/// A daily local notification at the student's chosen time.
enum FeedingTime {
    static let identifier = "goldfish.feeding-time"

    static let cues = [
        "finish dinner",
        "get home",
        "sit down at my desk",
        "make my morning coffee",
        "get on the bus",
    ]

    /// Replaces the scheduled reminder. Returns false if notifications are not allowed.
    static func schedule(_ plan: ReminderPlan, fishName: String, dueChapter: String?) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard plan.enabled else { return true }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Feeding Time"
        if let chapter = dueChapter {
            content.body = "\(fishName) forgot \(chapter). Five minutes to re-teach?"
        } else {
            content.body = "You said: when I \(plan.cue), I'll teach \(fishName). Five minutes?"
        }
        content.sound = .default

        var components = DateComponents()
        components.hour = plan.hour
        components.minute = plan.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            return true
        } catch {
            return false
        }
    }
}

/// Online or offline, for the hybrid meter and offline messages.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "goldfish.network"))
    }
}

/// The log and recent model calls shown in Diagnostics. There is no console on a sideloaded app.
@MainActor
@Observable
final class DiagnosticsLog {
    private(set) var lines = RingBuffer<String>(capacity: 500)
    private(set) var calls = RingBuffer<ModelCallRecord>(capacity: 50)

    @ObservationIgnored private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    func log(_ message: String) {
        lines.append("\(formatter.string(from: Date())) \(message)")
    }

    func record(_ call: ModelCallRecord) {
        calls.append(call)
        let tier = call.tier?.rawValue ?? "-"
        log("[\(call.lane)] \(call.ok ? "ok" : "failed") tier=\(tier) model=\(call.modelVersion) \(call.latencyMs)ms \(call.detail)")
    }

    var text: String {
        lines.elements.joined(separator: "\n")
    }
}

/// A stop flag the Fish Check can read from off the main thread.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}
