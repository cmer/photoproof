// HashingPipeline.swift
// SHA1 the original bytes of each ResourceItem, with bounded concurrency,
// streaming events back as work completes.
//
// Why SHA1: Immich indexes assets by SHA1 (yes, cryptographically broken — but
// content addressing only). Our job is to produce hashes that match Immich's,
// so the algorithm choice is forced. CryptoKit's `Insecure.SHA1` is the right
// tool, and the name doubles as a reminder.

import Foundation
import CryptoKit
import Photos

enum HashingPipeline {
    static let concurrency = 8

    static func run(
        items: [ResourceItem],
        onEvent: @escaping @MainActor @Sendable (HashEvent) -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()

            // Prime the pump with up to `concurrency` in-flight tasks.
            for _ in 0..<min(concurrency, items.count) {
                guard let item = iterator.next() else { break }
                group.addTask { await hashOne(item, onEvent: onEvent) }
            }

            // Each time a task finishes, queue the next one.
            while await group.next() != nil {
                if Task.isCancelled { break }
                if let item = iterator.next() {
                    group.addTask { await hashOne(item, onEvent: onEvent) }
                }
            }
        }
    }

    // MARK: - Private

    private static func hashOne(
        _ item: ResourceItem,
        onEvent: @escaping @MainActor @Sendable (HashEvent) -> Void
    ) async {
        await onEvent(.started(itemID: item.id))

        if Task.isCancelled { return }

        guard let resource = AssetScanner.resolve(item) else {
            await onEvent(.failed(itemID: item.id, message: "Resource is no longer available."))
            return
        }

        do {
            let result = try await streamSHA1(of: resource)
            await onEvent(.hashed(itemID: item.id, sha1: result.sha1, sizeBytes: result.size))
        } catch {
            await onEvent(.failed(itemID: item.id, message: error.localizedDescription))
        }
    }

    private static func streamSHA1(of resource: PHAssetResource) async throws -> (sha1: String, size: Int64) {
        // PHAssetResourceManager invokes its dataReceivedHandler sequentially
        // from a private queue, so the hasher state inside Box doesn't need
        // synchronization — but we mark it @unchecked Sendable to satisfy the
        // closure's escaping capture rules.
        final class Box: @unchecked Sendable {
            var hasher = Insecure.SHA1()
            var size: Int64 = 0
        }
        let box = Box()

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { chunk in
                    box.hasher.update(data: chunk)
                    box.size += Int64(chunk.count)
                },
                completionHandler: { error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            )
        }

        let digest = box.hasher.finalize()
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return (hex, box.size)
    }
}
