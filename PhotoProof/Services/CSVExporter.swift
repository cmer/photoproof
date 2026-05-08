// CSVExporter.swift
// Writes verification results to a CSV file. The schema mirrors the CLI
// reference implementation (verify_deleted.mjs) so reports from PhotoProof
// can be diffed against CLI runs over the same data.

import Foundation
import AppKit

enum CSVExporter {

    /// One CSV row per *resource* (so a Live Photo produces two rows). The
    /// `note` column carries the human-readable reason the row didn't verify,
    /// matching the CLI's behaviour.
    static func write(_ verifications: [AssetVerification], to url: URL) throws {
        let header = [
            "asset_local_id", "kind", "filename", "sha1",
            "in_immich", "immich_asset_id", "immich_trashed", "size_bytes", "note",
        ]
        var lines: [String] = [header.map(escape).joined(separator: ",")]

        for av in verifications {
            for r in av.resources {
                let sha1: String
                let size: Int64
                var note: String = ""
                switch r.status {
                case .hashed(let h, let s):
                    sha1 = h
                    size = s
                case .failed(let msg):
                    sha1 = ""
                    size = 0
                    note = "hash failed: \(msg)"
                case .pending, .hashing:
                    sha1 = ""
                    size = 0
                    note = "not hashed"
                }

                let status = av.resourceStatuses[r.id] ?? .pending
                let inImmich: String
                let assetID: String
                let trashed: String
                switch status {
                case .pending:
                    inImmich = ""; assetID = ""; trashed = ""
                case .notInImmich:
                    inImmich = "false"; assetID = ""; trashed = ""
                    if note.isEmpty {
                        note = r.resource.kind == .livePhotoVideo
                            ? "Live Photo video (.MOV) is not in Immich"
                            : "checksum not in Immich"
                    }
                case .inImmich(let id):
                    inImmich = "true"; assetID = id; trashed = "false"
                case .inImmichTrash(let id):
                    inImmich = "false"; assetID = id; trashed = "true"
                    if note.isEmpty { note = "found in Immich but it's in Immich's trash — NOT safe" }
                case .lookupFailed(let msg):
                    inImmich = "false"; assetID = ""; trashed = ""
                    if note.isEmpty { note = "lookup error: \(msg)" }
                }

                let row = [
                    av.asset.id,
                    r.resource.kind.rawValue,
                    r.resource.filename,
                    sha1,
                    inImmich,
                    assetID,
                    trashed,
                    size > 0 ? String(size) : "",
                    note,
                ]
                lines.append(row.map(escape).joined(separator: ","))
            }
        }

        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Show an NSSavePanel and return the chosen URL (or nil if cancelled).
    @MainActor
    static func promptForSaveURL(suggestedFilename: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let response = await panel.beginSheetModal()
        return response == .OK ? panel.url : nil
    }

    private static func escape(_ s: String) -> String {
        if s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }
}

private extension NSSavePanel {
    @MainActor
    func beginSheetModal() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                self.beginSheetModal(for: window) { cont.resume(returning: $0) }
            } else {
                cont.resume(returning: self.runModal())
            }
        }
    }
}
