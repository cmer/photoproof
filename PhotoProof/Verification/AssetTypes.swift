// AssetTypes.swift
// Shared value types for the verification pipeline. All Sendable so they can
// be passed across actor boundaries and used in TaskGroups.

import Foundation
import Photos

struct AlbumSummary: Identifiable, Hashable, Sendable {
    let id: String          // PHAssetCollection.localIdentifier
    let title: String
    let photoCount: Int
    let videoCount: Int

    var totalCount: Int { photoCount + videoCount }
}

/// Scanner metadata about a single PHAsset — enough to render results
/// without re-querying PhotoKit.
struct ScannedAsset: Identifiable, Hashable, Sendable {
    let id: String          // PHAsset.localIdentifier
    let displayFilename: String
    let creationDate: Date?
    let kind: Kind

    enum Kind: String, Sendable {
        case photo
        case livePhoto
        case video
        case other
    }
}

/// One file PhotoProof needs to hash. A regular photo produces one item;
/// a Live Photo produces two (the still image + the .MOV).
struct ResourceItem: Identifiable, Hashable, Sendable {
    let id: String          // "<assetLocalID>::<resourceIndex>"
    let assetLocalID: String
    let resourceIndex: Int  // index into PHAssetResource.assetResources(for:)
    let filename: String
    let kind: Kind
    let estimatedSize: Int64?

    enum Kind: String, Sendable {
        case photo
        case video
        case livePhotoVideo

        var label: String {
            switch self {
            case .photo: return "Photo"
            case .video: return "Video"
            case .livePhotoVideo: return "Live Photo video"
            }
        }
    }
}

enum HashStatus: Equatable, Sendable {
    case pending
    case hashing
    case hashed(sha1: String, sizeBytes: Int64)
    case failed(message: String)

    var isTerminal: Bool {
        switch self {
        case .hashed, .failed: return true
        case .pending, .hashing: return false
        }
    }
}

struct HashedItem: Identifiable, Equatable, Sendable {
    let resource: ResourceItem
    var status: HashStatus
    var id: String { resource.id }
}

enum HashEvent: Sendable {
    case started(itemID: String)
    case hashed(itemID: String, sha1: String, sizeBytes: Int64)
    case failed(itemID: String, message: String)

    var itemID: String {
        switch self {
        case .started(let id): return id
        case .hashed(let id, _, _): return id
        case .failed(let id, _): return id
        }
    }
}

/// Per-resource verification outcome from the Immich check.
enum ResourceVerification: Equatable, Sendable {
    case pending
    case notInImmich
    case inImmich(assetID: String)
    case inImmichTrash(assetID: String)
    case lookupFailed(message: String)

    var isVerified: Bool {
        if case .inImmich = self { return true }
        return false
    }
}

/// Per-asset roll-up. Built after every resource has finished bulk-check and
/// (where applicable) trash-check.
struct AssetVerification: Identifiable, Equatable, Sendable {
    let asset: ScannedAsset
    let resources: [HashedItem]
    let resourceStatuses: [String: ResourceVerification]  // keyed by ResourceItem.id
    let totalSizeBytes: Int64

    var id: String { asset.id }

    /// SAFETY-CRITICAL: an asset is verified only if every tracked resource
    /// is hashed AND inImmich (not trashed). Partial matches are never enough.
    /// This is the property that lets us be sure a delete is reversible-only.
    var isFullyVerified: Bool {
        guard !resources.isEmpty else { return false }
        for r in resources {
            guard case .hashed = r.status else { return false }
            guard case .inImmich = resourceStatuses[r.id] ?? .pending else { return false }
        }
        return true
    }

    /// User-facing reason(s) why the asset isn't in the verified bucket.
    var attentionReasons: [String] {
        var seen = Set<String>()
        var reasons: [String] = []
        func add(_ s: String) {
            if seen.insert(s).inserted { reasons.append(s) }
        }
        for r in resources {
            switch r.status {
            case .pending, .hashing:
                add("Verification incomplete")
            case .failed(let msg):
                add("Hash failed: \(msg)")
            case .hashed:
                switch resourceStatuses[r.id] ?? .pending {
                case .pending:
                    add("Verification incomplete")
                case .notInImmich:
                    if r.resource.kind == .livePhotoVideo {
                        add("Live Photo video (.MOV) is not in Immich")
                    } else {
                        add("Not found in Immich")
                    }
                case .inImmichTrash:
                    add("Found in Immich, but it's in your Immich trash")
                case .lookupFailed(let msg):
                    add("Immich lookup error: \(msg)")
                case .inImmich:
                    break
                }
            }
        }
        return reasons.isEmpty ? ["Unknown reason"] : reasons
    }
}

/// Events emitted by the verification engine back to the run for UI updates.
enum VerifyEvent: Sendable {
    case bulkChecked(itemID: String, action: String)
    case trashChecked(itemID: String, status: ResourceVerification)
}
