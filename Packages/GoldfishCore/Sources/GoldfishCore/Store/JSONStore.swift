import Foundation

public enum StoreLoad: Equatable {
    /// No file yet.
    case fresh
    case loaded
    /// The file could not be read. It was moved aside under this name and the app started empty.
    case recovered(String)
}

/// Saves `GoldfishData` as one JSON file in Application Support.
public final class JSONStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return base.appendingPathComponent("Goldfish", isDirectory: true)
            .appendingPathComponent("goldfish.json")
    }

    public func load() -> (data: GoldfishData, outcome: StoreLoad) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else {
            return (GoldfishData(), .fresh)
        }
        do {
            let bytes = try Data(contentsOf: fileURL)
            let data = try JSONDecoder().decode(GoldfishData.self, from: bytes)
            return (data, .loaded)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("goldfish-damaged-\(stamp).json")
            try? manager.moveItem(at: fileURL, to: backup)
            return (GoldfishData(), .recovered(backup.lastPathComponent))
        }
    }

    public func save(_ data: GoldfishData) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(data)
        try bytes.write(to: fileURL, options: .atomic)
    }

    public func reset() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
