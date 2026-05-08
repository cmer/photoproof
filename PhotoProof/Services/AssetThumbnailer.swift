// AssetThumbnailer.swift
// In-memory thumbnail cache backed by PHCachingImageManager. Returns NSImages
// suitable for display in a SwiftUI grid.

import Foundation
import Photos
import AppKit

@MainActor
final class AssetThumbnailer {
    static let shared = AssetThumbnailer()

    private let manager = PHCachingImageManager()
    private var cache: [String: NSImage] = [:]
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    private init() {}

    /// Loads (or returns cached) thumbnail. `points` is in points; PHKit gets
    /// 2x for retina screens. Returns nil if Photos couldn't provide an image.
    func thumbnail(for assetLocalID: String, points: CGFloat) async -> NSImage? {
        let key = "\(assetLocalID)::\(Int(points))"
        if let img = cache[key] { return img }
        if let task = inflight[key] { return await task.value }

        let task = Task<NSImage?, Never> { [weak self] in
            await self?.fetch(assetLocalID: assetLocalID, points: points) ?? nil
        }
        inflight[key] = task
        defer { inflight.removeValue(forKey: key) }
        let image = await task.value
        if let image { cache[key] = image }
        return image
    }

    private func fetch(assetLocalID: String, points: CGFloat) async -> NSImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalID], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .fast
        opts.isSynchronous = false

        let target = CGSize(width: points * 2, height: points * 2)

        return await withCheckedContinuation { (cont: CheckedContinuation<NSImage?, Never>) in
            manager.requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: opts
            ) { image, _ in
                cont.resume(returning: image)
            }
        }
    }
}
