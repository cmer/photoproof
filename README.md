# PhotoProof

A native macOS app that helps you free up space in Apple Photos and iCloud Photos by **verifying every photo is already safely backed up to your self-hosted Immich server before Photos moves it to Recently Deleted**.

PhotoProof is intentionally read-only against Immich and reversible-only against Photos. The most destructive thing it can do is move items to Recently Deleted, where Apple's built-in 30-day timer is the safety net.

---

## What it does

The primary workflow is intentionally simple:

1. Click **Start a smart cleanup** and choose age, size, and media filters.
2. Review the matches and deselect anything you want to keep.
3. Click **Create album & verify**. PhotoProof automatically creates a date-stamped staging album in Photos and immediately starts verification.
4. PhotoProof reads every original resource, computes its SHA1, and asks Immich whether it exists and is not in Immich's trash.
5. Review **Safe to remove** and **Needs attention**. Items that do not pass every check stay in Photos.
6. Click **Move to Recently Deleted** to move only verified items. PhotoProof asks for confirmation, writes a CSV log, and then Photos shows its own system prompt.
7. If the staging album is empty afterward, PhotoProof offers to delete the album too.

Already have an album prepared in Photos? Choose it from the secondary
**Verify an existing album** section on the dashboard.

PhotoProof never permanently deletes anything itself. Everything moved is recoverable from Photos → Recently Deleted for 30 days, and Apple Photos reclaims the storage when Recently Deleted is cleared.

### Managing empty albums

PhotoProof keeps empty albums out of the existing-album menu. When it finds
deletable, user-created albums with no photos or videos, a compact review link
appears in that dashboard section. Select individual albums or use **Select
All**, then confirm the deletion.

The same screen is available from **Library → Manage Empty Albums…**. Before
deleting each album, PhotoProof re-fetches it and confirms that it still
exists, is still empty, and can still be deleted. Albums that no longer pass
those checks are skipped and reported. Deleting an album never deletes photos
or videos, but the album deletion is synchronized through iCloud Photos.

### Building a staging album from filters

Click **Start a smart cleanup** on the dashboard. PhotoProof opens a guided
workspace where you can:

- filter by **age** (text field + days/months/years toggle)
- filter by **minimum file size** (text field + MB/GB toggle)
- choose **photos, videos, or both**
- skip favorites and hidden items

PhotoProof scans your library (read-only — nothing is moved or modified),
shows the matches in a thumbnail grid sorted by size, and lets you click
thumbnails to deselect anything you want to keep. Click **Create album &
verify** and PhotoProof creates a date-stamped user album containing the
selection, then starts verification immediately. Photos albums are tags rather
than folders, so assets remain in every other album they already belong to.

---

## Safety guarantees

These are non-negotiable invariants of the codebase:

- **An asset is "verified" only if every one of its original resources** (photo + Live Photo MOV companion if present) **has a SHA1 that exists in Immich and is not in Immich's trash.** Partial matches are never enough. The check lives in `AssetVerification.isFullyVerified` (`PhotoProof/Verification/AssetTypes.swift`).
- **The delete button is gated on that flag.** Only `verifiedAssets` are passed to `PHAssetChangeRequest.deleteAssets`.
- **PhotoProof uses `deleteAssets`, not `removeAssets(_:from:)`.** The latter would only un-file the asset from the album while leaving it in the library — an easy footgun the spec calls out by name.
- **Two confirmations.** PhotoProof shows its own dialog (count + filename sample + 30-day reminder), then macOS shows its own automatic system confirmation. Both must be confirmed.
- **CSV log written first.** Before any destructive action, the entire run (verified + needs-attention) is written to `~/Library/Application Support/PhotoProof/Runs/<timestamp>-<album>.csv`. If that write fails, the delete is aborted.
- **No telemetry.** The only network calls PhotoProof makes are to your configured Immich server.
- **API key is never in cleartext on disk.** It lives in the macOS Keychain under service `com.carlmercier.PhotoProof.immich-api-key`.

---

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 16 or newer (for `objectVersion = 77` filesystem-synchronized groups)
- An Immich server you can reach over HTTP/HTTPS
- An Immich API key with these three scopes:
  - `user.read` — for the Test Connection check
  - `asset.upload` — for `POST /api/assets/bulk-upload-check` (the duplicate preflight)
  - `asset.read` — for `POST /api/search/metadata` (the trash double-check)

PhotoProof only reads from Immich. It never creates, modifies, or deletes anything on the server.

---

## Install

Download the latest `PhotoProof-<version>.zip` from the [Releases page](https://github.com/cmer/photoproof/releases), unzip it, and drag `PhotoProof.app` into `/Applications`.

### First-launch Gatekeeper warning

PhotoProof is **ad-hoc signed**, not notarized by Apple. When you download a release through a browser, macOS adds a quarantine attribute and Gatekeeper refuses to launch the app — usually with the misleading message *"PhotoProof is damaged and can't be opened. You should move it to the Trash."* The app isn't actually damaged. macOS just won't run an ad-hoc-signed download without you explicitly approving it.

**Fix**: open Terminal and strip the quarantine attribute. Replace the path with wherever your `.app` lives (`~/Downloads/PhotoProof.app`, `/Applications/PhotoProof.app`, etc.):

```sh
xattr -dr com.apple.quarantine /Applications/PhotoProof.app
```

Then double-click the app. It'll launch normally and Gatekeeper won't bother you again.

> Why doesn't right-click → Open work? That flow is for apps signed with a real Apple Developer ID but not notarized. Ad-hoc signing has no Developer ID to evaluate, so Gatekeeper doesn't offer the bypass — the `xattr` path is the only one. Building from source (see below) avoids the issue entirely, since locally compiled apps don't carry the quarantine flag.

---

## Build & run

Two scripts in `scripts/` cover day-to-day building:

```sh
./scripts/build-dev.sh    # Debug build, ad-hoc signed, auto-launches the app
./scripts/build-prod.sh   # Release build, copies to ./build/PhotoProof.app
```

Or open the project in Xcode and use ⌘R:

```sh
git clone https://github.com/cmer/photoproof.git
cd photoproof
open PhotoProof.xcodeproj
```

There are no SPM dependencies — everything is in-house.

If `xcodebuild` complains about `IDESimulatorFoundation` failing to load, run `sudo xcodebuild -runFirstLaunch` once.

To regenerate the app icon:

```sh
swift tools/generate_icon.swift
```

---

## First run

1. **Welcome → Grant Photos Access.** PhotoProof needs read/write access to your Photos library (read for hashing, write to move items to Recently Deleted).
2. **Connect to Immich.** Paste your server URL (with or without a trailing `/api` — PhotoProof normalizes it) and your API key. Click **Test Connection**. On success, you'll see "Connected as <your account>" and the **Save** button enables.
3. **Start a smart cleanup.** Review the matches, then create the staging album and begin verification with one action. You can still verify an existing Photos album from the dashboard.

---

## How verification works

```
For each PHAsset in the chosen album:
  1. Get its original PHAssetResource(s):
       - Regular photo  → 1 resource (.photo)
       - Live Photo     → 2 resources (.photo + .pairedVideo)
       - Regular video  → 1 resource (.video)
     We deliberately skip .fullSizePhoto / .fullSizeVideo —
     those are the *adjusted* (edited) variants, not what
     Immich indexes.
  2. SHA1 the bytes of each resource (CryptoKit's
     Insecure.SHA1; Immich uses SHA1 for content addressing).
  3. POST /api/assets/bulk-upload-check (200 items per batch,
     up to 4 concurrent batches). action="reject" means
     present, action="accept" means missing.
  4. For every "reject", POST /api/search/metadata with
     withDeleted: true to confirm isTrashed = false. The bulk
     endpoint will say "duplicate" even for assets in
     Immich's trash, which would be unsafe.
  5. Roll up to per-asset: an asset is verified only if
     every one of its tracked resources came back inImmich.
```

Transient HTTP errors (502/503/504, network drops, timeouts) are retried with 250 ms / 1 s / 4 s exponential backoff up to 3 times. Auth and 404 errors fail fast.

---

## Project layout

```
PhotoProof/
├── PhotoProofApp.swift           — @main, App scene, About panel, History command
├── Support/
│   └── AppState.swift            — Photos auth + persisted server URL + connected user
├── Services/
│   ├── KeychainStore.swift       — generic password in the login keychain
│   ├── ImmichClient.swift        — /users/me, bulk-upload-check, search/metadata, retries
│   ├── PhotoLibrary.swift        — fetches user-created albums, observes library changes
│   ├── PhotoAlbumManager.swift   — validates and deletes empty user-created albums
│   ├── AssetExporter.swift       — writes asset bytes to a temp file for QuickLook
│   ├── AssetThumbnailer.swift    — PHCachingImageManager wrapper for the grid
│   ├── CSVExporter.swift         — writes CLI-compatible CSV reports
│   └── RunLog.swift              — lists past runs from Application Support
├── Verification/
│   ├── AssetTypes.swift          — value types: ResourceItem, HashedItem, AssetVerification
│   ├── AssetScanner.swift        — walks an album, picks original resources only
│   ├── HashingPipeline.swift     — 8-way concurrent SHA1 over PHAssetResource bytes
│   ├── VerificationEngine.swift  — bulk-check + trash-check stages, 4-way HTTP concurrency
│   ├── VerificationRun.swift     — drives the whole pipeline + the delete + album cleanup
│   └── CandidateSearch.swift     — Find-photos-to-clean-up search engine + album creation
├── Views/
│   ├── RootView.swift            — onboarding → settings → main router
│   ├── OnboardingView.swift      — Photos permission flow
│   ├── SettingsView.swift        — server URL + API key + Test Connection
│   ├── MainView.swift            — cleanup dashboard + existing-album action
│   ├── PhotoProofStyle.swift      — shared visual system and surfaces
│   ├── EmptyAlbumsView.swift     — selects and deletes empty Photos albums
│   ├── RunSheetView.swift        — verification progress + results + delete + success
│   ├── FindCandidatesView.swift  — guided search, review, album, and verify flow
│   ├── HistoryView.swift         — past run logs
│   └── QuickLookPresenter.swift  — bridges to QLPreviewPanel
└── Assets.xcassets/              — app icon (regenerate with tools/generate_icon.swift)

tools/
└── generate_icon.swift            — programmatic app-icon generator
```

The reference Node.js implementation (`verify_deleted.mjs` at the repo root) was the source of truth for the API logic. PhotoProof's CSV schema matches it (`asset_local_id, kind, filename, sha1, in_immich, immich_asset_id, immich_trashed, size_bytes, note`) so you can diff outputs.

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘ , | Open Settings |
| ⌘ Y | Open Verification History |
| ↵ | Start the highlighted primary action |
| Space | Quick Look the selected result |
| ↵ | Quick Look the selected result |

---

## Known limitations

- **Edit detection.** PhotoProof verifies the original (`.photo` resource), not the edit. If you've cropped or adjusted a photo and only the edit got uploaded to Immich, PhotoProof won't see a match. Document this for yourself; in practice Immich uploads originals by default.
- **iCloud-only originals.** PhotoProof asks Photos to download originals on demand (`isNetworkAccessAllowed = true`). For very large albums, doing this from a fresh iCloud library is slow. The recommendation in the spec is to enable Photos → Settings → iCloud → "Download Originals to this Mac" first.
- **No upload.** PhotoProof does not push items to Immich. If something didn't verify, fix it in Immich (re-upload, untrash, etc.) and run PhotoProof again.

---

## License

MIT — see [LICENSE](LICENSE).
