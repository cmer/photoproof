// VerificationRun.swift
// Live state for one run of the verification flow. Drives the pipeline
// scanning → hashing → bulk-check → trash-check → completed, and aggregates
// results into per-asset verifications for the results screen. Also handles
// the post-verification "move to Recently Deleted" action.

import Foundation
import Photos
import SwiftUI

@MainActor
final class VerificationRun: ObservableObject {

    enum Stage: Equatable {
        case scanning
        case hashing
        case checkingBulk
        case checkingTrash
        case completed
        case cancelled
        case error(String)

        var isTerminal: Bool {
            switch self {
            case .completed, .cancelled, .error: return true
            default: return false
            }
        }
    }

    /// Sub-state for the optional post-verification deletion. Only meaningful
    /// when `stage == .completed`.
    enum DeleteState: Equatable {
        case idle
        case writingLog
        case deleting
        case finished(count: Int, bytes: Int64, logURL: URL?)
        case failed(String)

        var isInProgress: Bool {
            switch self {
            case .writingLog, .deleting: return true
            default: return false
            }
        }
    }

    /// Sub-state for the follow-up "the album is empty, delete it too?" prompt.
    enum AlbumDeleteState: Equatable {
        case idle
        case deleting
        case deleted
        case failed(String)
    }

    let album: AlbumSummary

    @Published private(set) var stage: Stage = .scanning

    // Per-stage progress counters.
    @Published private(set) var items: [HashedItem] = []
    @Published private(set) var hashedCount: Int = 0
    @Published private(set) var hashFailedCount: Int = 0
    @Published private(set) var bulkCheckedCount: Int = 0
    @Published private(set) var bulkTotal: Int = 0
    @Published private(set) var trashCheckedCount: Int = 0
    @Published private(set) var trashTotal: Int = 0

    @Published private(set) var resourceStatuses: [String: ResourceVerification] = [:]
    @Published private(set) var assetVerifications: [AssetVerification] = []
    @Published private(set) var hashDetail: String = "Reading album…"
    @Published private(set) var deleteState: DeleteState = .idle
    @Published private(set) var albumIsEmpty: Bool = false
    @Published private(set) var albumDeleteState: AlbumDeleteState = .idle

    private let appState: AppState
    private var scannedAssets: [ScannedAsset] = []
    private var task: Task<Void, Never>?

    init(album: AlbumSummary, appState: AppState) {
        self.album = album
        self.appState = appState
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.runPipeline()
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: - Computed

    var totalCount: Int { items.count }

    var hashFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(hashedCount + hashFailedCount) / Double(totalCount)
    }

    var bulkFraction: Double {
        guard bulkTotal > 0 else { return 0 }
        return Double(bulkCheckedCount) / Double(bulkTotal)
    }

    var trashFraction: Double {
        guard trashTotal > 0 else { return 0 }
        return Double(trashCheckedCount) / Double(trashTotal)
    }

    var verifiedAssets: [AssetVerification] {
        assetVerifications.filter { $0.isFullyVerified }
    }

    var needsAttentionAssets: [AssetVerification] {
        assetVerifications.filter { !$0.isFullyVerified }
    }

    // MARK: - Pipeline

    private func runPipeline() async {
        // Stage 1: scan.
        let albumID = album.id
        let scan = await Task.detached(priority: .userInitiated) {
            AssetScanner.scan(albumLocalID: albumID)
        }.value

        if Task.isCancelled { stage = .cancelled; return }

        if scan.items.isEmpty {
            stage = .error("That album is empty, or its assets aren't available locally.")
            return
        }

        scannedAssets = scan.assets
        items = scan.items.map { HashedItem(resource: $0, status: .pending) }
        bulkTotal = items.count
        stage = .hashing
        hashDetail = "Hashing 0 of \(items.count)…"

        // Stage 2: hash.
        await HashingPipeline.run(items: scan.items) { [weak self] event in
            self?.applyHashEvent(event)
        }

        if Task.isCancelled { stage = .cancelled; return }

        // Stage 3: bulk-upload-check on hashed items.
        let client: ImmichClient
        do {
            client = try appState.makeImmichClient()
        } catch {
            stage = .error("Couldn't read your Immich credentials: \(error.localizedDescription)")
            return
        }

        stage = .checkingBulk
        do {
            try await VerificationEngine.runBulkCheck(client: client, items: items) { [weak self] event in
                self?.applyVerifyEvent(event)
            }
        } catch is CancellationError {
            stage = .cancelled
            return
        } catch let error as ImmichError {
            stage = .error("Couldn't check Immich: \(error.errorDescription ?? "unknown error")")
            return
        } catch {
            stage = .error("Couldn't check Immich: \(error.localizedDescription)")
            return
        }

        if Task.isCancelled { stage = .cancelled; return }

        // Stage 4: trash-check on duplicates only.
        let toCheck: [(itemID: String, sha1: String)] = items.compactMap { item in
            guard case .hashed(let sha1, _) = item.status else { return nil }
            guard case .inImmich = resourceStatuses[item.id] ?? .pending else { return nil }
            return (item.id, sha1)
        }
        trashTotal = toCheck.count
        if !toCheck.isEmpty {
            stage = .checkingTrash
            await VerificationEngine.runTrashCheck(client: client, toCheck: toCheck) { [weak self] event in
                self?.applyVerifyEvent(event)
            }
        }

        if Task.isCancelled { stage = .cancelled; return }

        assetVerifications = buildAssetVerifications()
        stage = .completed
    }

    // MARK: - Event apply

    private func applyHashEvent(_ event: HashEvent) {
        guard let idx = items.firstIndex(where: { $0.id == event.itemID }) else { return }
        switch event {
        case .started:
            items[idx].status = .hashing
            hashDetail = formatHashStartDetail(items[idx].resource)
        case .hashed(_, let sha1, let size):
            items[idx].status = .hashed(sha1: sha1, sizeBytes: size)
            hashedCount += 1
            hashDetail = "Hashed \(hashedCount + hashFailedCount) of \(totalCount)"
        case .failed(_, let message):
            items[idx].status = .failed(message: message)
            hashFailedCount += 1
            hashDetail = "Hashed \(hashedCount + hashFailedCount) of \(totalCount)"
        }
    }

    private func applyVerifyEvent(_ event: VerifyEvent) {
        switch event {
        case .bulkChecked(let id, let action):
            switch action {
            case "reject":
                // SHA1 already exists in Immich somewhere. We'll trash-check it next.
                resourceStatuses[id] = .inImmich(assetID: "")
            case "accept":
                resourceStatuses[id] = .notInImmich
            default:
                resourceStatuses[id] = .lookupFailed(message: "Unexpected Immich action: \(action)")
            }
            bulkCheckedCount += 1
        case .trashChecked(let id, let status):
            resourceStatuses[id] = status
            trashCheckedCount += 1
        }
    }

    // MARK: - Aggregation

    private func buildAssetVerifications() -> [AssetVerification] {
        let resourcesByAsset = Dictionary(grouping: items, by: { $0.resource.assetLocalID })
        var out: [AssetVerification] = []
        for asset in scannedAssets {
            let resources = resourcesByAsset[asset.id] ?? []
            let statuses = resources.reduce(into: [String: ResourceVerification]()) {
                $0[$1.id] = resourceStatuses[$1.id] ?? .pending
            }
            let totalSize = resources.reduce(Int64(0)) { acc, r in
                if case .hashed(_, let s) = r.status { return acc + s }
                return acc + (r.resource.estimatedSize ?? 0)
            }
            out.append(AssetVerification(
                asset: asset,
                resources: resources,
                resourceStatuses: statuses,
                totalSizeBytes: totalSize
            ))
        }
        return out.sorted {
            ($0.asset.creationDate ?? .distantFuture) < ($1.asset.creationDate ?? .distantFuture)
        }
    }

    // MARK: - Formatters

    // MARK: - Delete (Phase 4)

    /// Move the verified items to Recently Deleted. Writes a CSV log first
    /// so the user has a record even if the delete itself fails or the
    /// system confirmation is denied.
    ///
    /// SAFETY-CRITICAL: only assets where `isFullyVerified == true` are
    /// passed to `PHAssetChangeRequest.deleteAssets`. This is the gate that
    /// makes the action reversible-only — Recently Deleted holds for 30 days.
    /// We deliberately use `deleteAssets`, NOT `removeAssets(_:from:)`, which
    /// would only un-file the asset from the album.
    func deleteVerified() async {
        guard case .completed = stage else { return }
        guard !verifiedAssets.isEmpty else { return }

        let toDelete = verifiedAssets

        // 1. Write the CSV log of the run before doing anything destructive.
        deleteState = .writingLog
        let logURL: URL?
        do {
            logURL = try writeRunLog()
        } catch {
            deleteState = .failed("Couldn't write the run log: \(error.localizedDescription). No photos were modified.")
            return
        }

        // 2. Resolve PHAssets and perform the delete in a single change.
        deleteState = .deleting
        let phAssets = fetchPHAssets(for: toDelete.map(\.asset.id))
        if phAssets.isEmpty {
            deleteState = .failed("No matching photos in the library — they may have been removed already.")
            return
        }

        let deletedBytes = toDelete.reduce(Int64(0)) { $0 + $1.totalSizeBytes }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(phAssets as NSArray)
            }
            deleteState = .finished(count: phAssets.count, bytes: deletedBytes, logURL: logURL)
            // Drop the deleted assets from the verified list so they can't be
            // accidentally referenced again.
            assetVerifications = assetVerifications.filter { row in
                !toDelete.contains(where: { $0.asset.id == row.asset.id })
            }
            // If everything in the album just went to Recently Deleted, offer
            // to delete the (now empty) staging album too.
            albumIsEmpty = isSourceAlbumEmpty()
        } catch let phError as NSError where phError.domain == "NSCocoaErrorDomain" || phError.domain == PHPhotosErrorDomain {
            // The user denied the system confirmation, or Photos rejected
            // the change. Either way: nothing was moved.
            deleteState = .failed("Photos didn't perform the deletion: \(phError.localizedDescription). The CSV log is still saved.")
        } catch {
            deleteState = .failed("Couldn't move items to Recently Deleted: \(error.localizedDescription)")
        }
    }

    func dismissDeleteError() {
        if case .failed = deleteState { deleteState = .idle }
    }

    /// Delete the source album from Photos. Only call after the user confirms
    /// the follow-up prompt. Photos doesn't pop a system confirmation for
    /// album deletion (it does for asset deletion), so our in-app confirmation
    /// is the only safety net — and the album is recreatable, so the
    /// blast-radius is small.
    func deleteSourceAlbum() async {
        guard albumIsEmpty, albumDeleteState == .idle else { return }
        albumDeleteState = .deleting

        do {
            try await PhotoAlbumManager.deleteEmptyAlbum(localIdentifier: album.id)
            albumDeleteState = .deleted
            albumIsEmpty = false
        } catch {
            albumDeleteState = .failed(error.localizedDescription)
        }
    }

    /// User chose to keep the empty album.
    func dismissAlbumPrompt() {
        albumIsEmpty = false
    }

    private func isSourceAlbumEmpty() -> Bool {
        let collFetch = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [album.id],
            options: nil
        )
        guard let collection = collFetch.firstObject else { return false }
        return PHAsset.fetchAssets(in: collection, options: nil).count == 0
    }

    private func fetchPHAssets(for localIDs: [String]) -> [PHAsset] {
        guard !localIDs.isEmpty else { return [] }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: localIDs, options: nil)
        var out: [PHAsset] = []
        out.reserveCapacity(fetch.count)
        fetch.enumerateObjects { asset, _, _ in out.append(asset) }
        return out
    }

    private func writeRunLog() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport
            .appending(path: "PhotoProof", directoryHint: .isDirectory)
            .appending(path: "Runs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = fmt.string(from: Date())
        let safeTitle = album.title
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let url = dir.appending(path: "\(stamp)-\(safeTitle).csv")
        try CSVExporter.write(assetVerifications, to: url)
        return url
    }

    // MARK: - Hash detail

    private func formatHashStartDetail(_ item: ResourceItem) -> String {
        let processed = hashedCount + hashFailedCount
        var detail = "Hashing \(processed + 1) of \(totalCount)"
        let ext = (item.filename as NSString).pathExtension.uppercased()
        if !ext.isEmpty {
            detail += " (\(ext)"
            if let size = item.estimatedSize, size > 0 {
                detail += ", \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
            }
            detail += ")"
        }
        return detail
    }
}
