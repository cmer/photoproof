// VerificationEngine.swift
// Drives the two Immich-side stages: bulk-upload-check (in batches of 200,
// up to 4 concurrent requests) and per-duplicate trash check.
//
// Bulk failures are fatal — they usually mean a configuration problem the
// user needs to fix. Trash-check failures are per-item: we mark that one
// resource as "lookup failed" and keep going so the user still gets results.

import Foundation

enum VerificationEngine {

    static let httpConcurrency = 4

    /// Run /api/assets/bulk-upload-check across all hashed items and emit one
    /// `bulkChecked` event per item. Throws if any batch fails after retries.
    static func runBulkCheck(
        client: ImmichClient,
        items: [HashedItem],
        onEvent: @escaping @MainActor @Sendable (VerifyEvent) -> Void
    ) async throws {
        let pairs: [(id: String, sha1: String)] = items.compactMap { item in
            if case .hashed(let sha1, _) = item.status {
                return (id: item.id, sha1: sha1)
            }
            return nil
        }
        guard !pairs.isEmpty else { return }

        let batches = stride(from: 0, to: pairs.count, by: ImmichClient.bulkBatchSize)
            .map { Array(pairs[$0..<min($0 + ImmichClient.bulkBatchSize, pairs.count)]) }

        var iterator = batches.makeIterator()
        try await withThrowingTaskGroup(of: [String: String].self) { group in
            for _ in 0..<min(httpConcurrency, batches.count) {
                guard let batch = iterator.next() else { break }
                group.addTask { try await client.bulkUploadCheck(batch) }
            }
            while let result = try await group.next() {
                for (id, action) in result {
                    await onEvent(.bulkChecked(itemID: id, action: action))
                }
                if Task.isCancelled { break }
                if let batch = iterator.next() {
                    group.addTask { try await client.bulkUploadCheck(batch) }
                }
            }
        }
    }

    /// Run /api/search/metadata for each "duplicate" hit. Per-item errors are
    /// caught and surfaced as `.lookupFailed`; the run continues.
    static func runTrashCheck(
        client: ImmichClient,
        toCheck: [(itemID: String, sha1: String)],
        onEvent: @escaping @MainActor @Sendable (VerifyEvent) -> Void
    ) async {
        guard !toCheck.isEmpty else { return }

        var iterator = toCheck.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(httpConcurrency, toCheck.count) {
                guard let work = iterator.next() else { break }
                group.addTask {
                    let status = await singleTrashCheck(client: client, sha1: work.sha1)
                    await onEvent(.trashChecked(itemID: work.itemID, status: status))
                }
            }
            while await group.next() != nil {
                if Task.isCancelled { break }
                if let work = iterator.next() {
                    group.addTask {
                        let status = await singleTrashCheck(client: client, sha1: work.sha1)
                        await onEvent(.trashChecked(itemID: work.itemID, status: status))
                    }
                }
            }
        }
    }

    private static func singleTrashCheck(client: ImmichClient, sha1: String) async -> ResourceVerification {
        do {
            guard let asset = try await client.findAssetByChecksum(sha1) else {
                // Bulk-check said duplicate, but search returned nothing.
                // Treat as not safely verified and surface a clear note.
                return .lookupFailed(message: "bulk-check said duplicate but search returned no asset")
            }
            if asset.isTrashed {
                return .inImmichTrash(assetID: asset.id)
            }
            return .inImmich(assetID: asset.id)
        } catch is CancellationError {
            return .lookupFailed(message: "cancelled")
        } catch let error as ImmichError {
            return .lookupFailed(message: error.errorDescription ?? "unknown error")
        } catch {
            return .lookupFailed(message: error.localizedDescription)
        }
    }
}
