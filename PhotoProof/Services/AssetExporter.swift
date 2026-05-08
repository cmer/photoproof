// AssetExporter.swift
// Writes the original bytes of a PHAsset to a temp file so QuickLook (or any
// other consumer that wants a real file URL) can read it. Files are cached
// in a per-session directory under NSTemporaryDirectory and reused across
// previews. Works for iCloud-only originals too — the resource manager
// downloads on demand because isNetworkAccessAllowed is true.

import Foundation
import Photos

enum AssetExporterError: Error, LocalizedError {
    case assetNotFound
    case noPrimaryResource
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetNotFound: return "This photo isn't available in Photos."
        case .noPrimaryResource: return "Couldn't find the original file for this asset."
        case .readFailed(let m): return "Couldn't read the photo: \(m)"
        }
    }
}

@MainActor
final class AssetExporter {
    static let shared = AssetExporter()

    private let tempDir: URL
    private var inflight: [String: Task<URL, Error>] = [:]

    private init() {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "PhotoProof-Preview", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.tempDir = dir
    }

    /// Returns a stable local file URL containing the asset's original bytes.
    /// Calls for the same asset return the same URL and reuse the file on disk.
    func exportForPreview(assetLocalID: String) async throws -> URL {
        if let task = inflight[assetLocalID] { return try await task.value }
        let task = Task<URL, Error> { try await self.doExport(assetLocalID: assetLocalID) }
        inflight[assetLocalID] = task
        defer { inflight.removeValue(forKey: assetLocalID) }
        return try await task.value
    }

    private func doExport(assetLocalID: String) async throws -> URL {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalID], options: nil)
        guard let asset = fetch.firstObject else { throw AssetExporterError.assetNotFound }

        let resources = PHAssetResource.assetResources(for: asset)
        let primary = resources.first(where: { $0.type == .photo || $0.type == .video })
            ?? resources.first
        guard let primary else { throw AssetExporterError.noPrimaryResource }

        let safeID = assetLocalID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let outURL = tempDir.appending(path: "\(safeID)-\(primary.originalFilename)")
        if FileManager.default.fileExists(atPath: outURL.path) { return outURL }

        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: primary, toFile: outURL, options: opts) { error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume() }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: outURL)
            throw AssetExporterError.readFailed(error.localizedDescription)
        }
        return outURL
    }
}
