// QuickLookPresenter.swift
// Bridges to QLPreviewPanel. We intentionally set the panel's data source
// directly rather than going through the responder chain — simpler, and the
// panel keeps working as long as the app stays the active window.

import Quartz
import AppKit

final class QuickLookPresenter: NSObject {
    static let shared = QuickLookPresenter()

    /// Mutated and read on the main thread (QLPreviewPanel callbacks fire on main).
    private var urls: [URL] = []

    private override init() { super.init() }

    @MainActor
    func show(urls: [URL], startingAt index: Int = 0) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.delegate = self
        panel.dataSource = self
        panel.currentPreviewItemIndex = max(0, min(index, urls.count - 1))
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }
}

extension QuickLookPresenter: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}

extension QuickLookPresenter: QLPreviewPanelDelegate {}
