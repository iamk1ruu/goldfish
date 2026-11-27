import Foundation

/// A fixed-size list that drops the oldest entries.
public struct RingBuffer<Element> {
    public let capacity: Int
    public private(set) var elements: [Element] = []

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public mutating func append(_ element: Element) {
        elements.append(element)
        if elements.count > capacity {
            elements.removeFirst(elements.count - capacity)
        }
    }

    public mutating func removeAll() {
        elements.removeAll()
    }
}

/// One model call, for the Diagnostics "Recent answers" list.
public struct ModelCallRecord: Identifiable, Equatable {
    public let id: UUID
    public let at: Date
    /// Which job: fish, fishCheck, exam, report, grading, fairCheck.
    public let lane: String
    public let tier: FishTier?
    public let modelVersion: String
    public let latencyMs: Int
    public let ok: Bool
    public let detail: String

    public init(lane: String, tier: FishTier?, modelVersion: String, latencyMs: Int, ok: Bool, detail: String = "", at: Date = Date()) {
        self.id = UUID()
        self.at = at
        self.lane = lane
        self.tier = tier
        self.modelVersion = modelVersion
        self.latencyMs = latencyMs
        self.ok = ok
        self.detail = detail
    }
}

/// Sorts model errors into cases, from their printed description.
/// String matching avoids depending on SDK error types that are not documented yet.
public enum ModelErrorKind: String, Equatable {
    case offline
    case rateLimited
    case appCheck
    case refused
    case unavailable
    case other

    public static func classify(_ description: String) -> ModelErrorKind {
        let text = description.lowercased()
        if text.contains("429") || text.contains("resource_exhausted") || text.contains("quota")
            || text.contains("rate limit") || text.contains("too many requests") {
            return .rateLimited
        }
        if text.contains("app check") || text.contains("appcheck") || text.contains("permission_denied")
            || text.contains("403") {
            return .appCheck
        }
        if text.contains("-1009") || text.contains("-1005") || text.contains("-1001") || text.contains("offline")
            || text.contains("not connected") || text.contains("network connection was lost") {
            return .offline
        }
        if text.contains("guardrail") || text.contains("refus") || text.contains("unsafe")
            || text.contains("safety") || text.contains("blocked") {
            return .refused
        }
        if text.contains("unavailable") || text.contains("not available") || text.contains("not ready")
            || text.contains("notready") || text.contains("noteligible") || text.contains("notenabled") {
            return .unavailable
        }
        return .other
    }

    public var userMessage: String {
        switch self {
        case .offline:
            return "You're offline, and the fish can't think without Apple Intelligence or a connection."
        case .rateLimited:
            return "The cloud is busy right now. Try again in a minute."
        case .appCheck:
            return "The cloud refused the request (App Check). See Settings, then Diagnostics."
        case .refused:
            return "The model declined this request."
        case .unavailable:
            return "The model is not available on this device right now."
        case .other:
            return "Something went wrong talking to the model."
        }
    }
}
