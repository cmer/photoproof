// RunLog.swift
// Lists past verification runs by reading CSV files from
// Application Support/PhotoProof/Runs/. Filenames are written by
// VerificationRun.writeRunLog() in the format "<yyyy-MM-dd-HHmmss>-<album>.csv".

import Foundation

struct RunLogEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let timestamp: Date
    let albumTitle: String
    let fileSize: Int64

    var id: URL { url }
}

enum RunLog {

    /// Application Support/PhotoProof/Runs/
    static func runsDirectory() -> URL? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return nil }
        return appSupport
            .appending(path: "PhotoProof", directoryHint: .isDirectory)
            .appending(path: "Runs", directoryHint: .isDirectory)
    }

    static func entries() -> [RunLogEntry] {
        guard let dir = runsDirectory() else { return [] }
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var out: [RunLogEntry] = []
        for url in urls where url.pathExtension.lowercased() == "csv" {
            guard let entry = parse(url: url) else { continue }
            out.append(entry)
        }
        // Newest first.
        return out.sorted { $0.timestamp > $1.timestamp }
    }

    /// Filename format: yyyy-MM-dd-HHmmss-<album-title>.csv. Falls back to
    /// the file's modification date if the filename can't be parsed.
    private static func parse(url: URL) -> RunLogEntry? {
        let attrs = (try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]))
        let fileSize = Int64(attrs?.fileSize ?? 0)
        let modDate = attrs?.contentModificationDate ?? .distantPast

        let stem = url.deletingPathExtension().lastPathComponent
        // Split into <yyyy-MM-dd-HHmmss>-<rest>
        let parts = stem.split(separator: "-", maxSplits: 5, omittingEmptySubsequences: false)
        guard parts.count >= 5 else {
            return RunLogEntry(url: url, timestamp: modDate, albumTitle: stem, fileSize: fileSize)
        }
        let stampString = parts[0..<5].joined(separator: "-")
        let title = parts.count > 5 ? String(parts[5]) : "Untitled"

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let parsed = fmt.date(from: stampString) ?? modDate

        return RunLogEntry(
            url: url,
            timestamp: parsed,
            albumTitle: title,
            fileSize: fileSize
        )
    }
}
