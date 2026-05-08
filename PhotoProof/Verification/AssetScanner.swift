// AssetScanner.swift
// Walks a Photos album and produces a flat list of ResourceItem rows — one
// per file PhotoProof needs to hash — plus per-asset metadata used in the
// results screen.
//
// We deliberately pick only the *original* resource for each asset:
//   - .photo            — original still image
//   - .pairedVideo      — Live Photo .MOV companion (original)
//   - .video            — original video
//
// We skip .fullSizePhoto / .fullSizePairedVideo / .fullSizeVideo, which are
// the *adjusted* (edited) variants. Immich uploads the original by default,
// so those are what the SHA1 must match.

import Foundation
import Photos

struct ScanResult: Sendable {
    let assets: [ScannedAsset]
    let items: [ResourceItem]
}

enum AssetScanner {

    static func scan(albumLocalID: String) -> ScanResult {
        let collFetch = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumLocalID],
            options: nil
        )
        guard let collection = collFetch.firstObject else {
            return ScanResult(assets: [], items: [])
        }

        let assets = PHAsset.fetchAssets(in: collection, options: nil)
        var scannedAssets: [ScannedAsset] = []
        var items: [ResourceItem] = []
        scannedAssets.reserveCapacity(assets.count)
        items.reserveCapacity(assets.count)

        assets.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)

            var indexed: [(index: Int, resource: PHAssetResource, kind: ResourceItem.Kind)] = []
            for (index, resource) in resources.enumerated() {
                guard let kind = mappedKind(for: resource.type) else { continue }
                indexed.append((index, resource, kind))
            }
            guard !indexed.isEmpty else { return }

            // Display filename: prefer the photo or video original over the
            // Live Photo MOV companion.
            let primary = indexed.first(where: { $0.kind != .livePhotoVideo }) ?? indexed[0]

            scannedAssets.append(ScannedAsset(
                id: asset.localIdentifier,
                displayFilename: primary.resource.originalFilename,
                creationDate: asset.creationDate,
                kind: kindFor(asset: asset)
            ))

            for entry in indexed {
                items.append(ResourceItem(
                    id: "\(asset.localIdentifier)::\(entry.index)",
                    assetLocalID: asset.localIdentifier,
                    resourceIndex: entry.index,
                    filename: entry.resource.originalFilename,
                    kind: entry.kind,
                    estimatedSize: estimatedSize(of: entry.resource)
                ))
            }
        }

        return ScanResult(assets: scannedAssets, items: items)
    }

    /// Resolves a ResourceItem back to its PHAssetResource. Stable as long as
    /// the asset still exists and its resource list hasn't been edited.
    static func resolve(_ item: ResourceItem) -> PHAssetResource? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [item.assetLocalID], options: nil)
        guard let asset = fetch.firstObject else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        guard item.resourceIndex < resources.count else { return nil }
        return resources[item.resourceIndex]
    }

    // MARK: - Helpers

    private static func mappedKind(for type: PHAssetResourceType) -> ResourceItem.Kind? {
        switch type {
        case .photo: return .photo
        case .video: return .video
        case .pairedVideo: return .livePhotoVideo
        default: return nil
        }
    }

    static func kindFor(asset: PHAsset) -> ScannedAsset.Kind {
        if asset.mediaSubtypes.contains(.photoLive) { return .livePhoto }
        switch asset.mediaType {
        case .image: return .photo
        case .video: return .video
        case .audio: return .other
        default: return .other
        }
    }

    /// PHAssetResource exposes `fileSize` only via KVC. It can be missing for
    /// iCloud-only originals; in that case we return nil and fall back to the
    /// streamed byte count once hashing finishes.
    static func estimatedSize(of resource: PHAssetResource) -> Int64? {
        if let n = resource.value(forKey: "fileSize") as? NSNumber {
            return n.int64Value
        }
        return nil
    }
}
