# CLAUDE.md

Project context and conventions for Claude Code (and any contributor) working
in this repo. Keep edits to this file small and self-contained — the entire
file is loaded into context every session.

## What this is

PhotoProof is a native macOS SwiftUI/PhotoKit app that verifies photos are
backed up to a self-hosted [Immich](https://immich.app) server before moving
them to Recently Deleted. See `README.md` for the user-facing description and
`/Users/carl/code/photoproof/README.md` for the full feature list.

The project is a single Xcode app target with no SPM dependencies, written
entirely in Swift, targeting macOS 14+.

## Building

Use the scripts in `scripts/`. Both work from any cwd inside the repo.

```sh
./scripts/build-dev.sh    # Debug build, ad-hoc signed, auto-launches the app
./scripts/build-prod.sh   # Release build, copies to ./build/PhotoProof.app
```

Direct `xcodebuild` works too:

```sh
xcodebuild -project PhotoProof.xcodeproj -scheme PhotoProof \
    -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` is fine for local builds — the app uses ad-hoc
signing. Distribution to other Macs would require Developer ID signing +
notarization (out of scope for this project).

If `xcodebuild` errors with `IDESimulatorFoundation` plugin failures,
run `sudo xcodebuild -runFirstLaunch` once.

## Releasing

`./scripts/release.sh <version>` drives the entire release end-to-end:

```sh
./scripts/release.sh 1.1.0           # full release
./scripts/release.sh 1.1.0 --dry-run # preview the version bump + changelog
```

The script:
1. Validates the working tree is clean and `gh` is authenticated.
2. Updates `MARKETING_VERSION` in `PhotoProof.xcodeproj/project.pbxproj` and
   bumps `CURRENT_PROJECT_VERSION` (build number).
3. Regenerates `CHANGELOG.md` from git history via `git-cliff`.
4. Commits the bump as `chore(release): <version>` and tags `v<version>`.
5. Runs `build-prod.sh`, zips the .app to `build/PhotoProof-<version>.zip`.
6. Pushes the commit and tag to `origin`.
7. Creates a GitHub release with the new CHANGELOG.md section as release notes
   and the zip attached.

Tooling needed (one-time): `brew install git-cliff` and `gh auth login`.

## Commit conventions

This repo uses [Conventional Commits](https://www.conventionalcommits.org/).
The first line of each commit is what appears in `CHANGELOG.md`, so write
subject lines as if a user will read them — because they will.

**Prefixes that show up in the changelog** (configured in `cliff.toml`):

| Prefix      | Section         | Use for                                  |
|-------------|-----------------|------------------------------------------|
| `feat:`     | Features        | new user-visible behavior                |
| `fix:`      | Bug Fixes       | bug fixes                                |
| `perf:`     | Performance    | optimisations users will notice          |
| `refactor:` | Refactor        | non-behavioral code changes              |
| `docs:`     | Documentation   | README, comments, this file              |
| `build:`    | Build           | build scripts, project config            |
| `chore:`    | Chores          | dependency bumps, housekeeping           |

**Prefixes hidden from the changelog**:
- `chore(release):` — version-bump commits made by `release.sh`
- `style:` / `test:` / `ci:` — non-user-facing churn

Anything without a recognised prefix lands in an "Other" section so it's not
silently dropped.

**Do not edit `CHANGELOG.md` by hand.** It's regenerated from git history on
every release. If you need to fix a previous entry, amend the underlying
commit (only safe before pushing) or live with it.

## Project layout

```
PhotoProof/
├── PhotoProofApp.swift           — @main entry, App scene, About panel, History command
├── Support/AppState.swift        — Photos auth, persisted server URL, connected user
├── Services/                     — non-UI building blocks (Keychain, Immich, PhotoKit, CSV, RunLog, Thumbnailer, Exporter)
├── Verification/                 — value types, scanner, hashing pipeline, Immich engine, run state, candidate search
└── Views/                        — all SwiftUI views

tools/generate_icon.swift          — one-off: regenerates the AppIcon PNGs
scripts/                           — build-dev.sh, build-prod.sh, release.sh
cliff.toml                         — git-cliff config for changelog generation
```

When adding a new file, put it in the directory whose responsibility matches.
The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (objectVersion
77), so new files in `PhotoProof/` are picked up automatically without
editing `project.pbxproj`.

## Code conventions

- **Every source file starts with a 1–3 line `//` header** explaining the
  file's responsibility. Match the existing style.
- **Comments justify WHY, not what.** Hidden constraints, subtle invariants,
  or workarounds for specific issues warrant a comment. Code that's
  self-evident from names doesn't.
- **Swift Concurrency only.** No Combine, no GCD callbacks. `async`/`await`,
  `actor`, `TaskGroup`, `@MainActor`.
- **No SPM dependencies.** Everything is in-house.
- **Prefer value types** (struct, enum). Use classes only when reference
  semantics or `ObservableObject` are required.
- **Keep `View`s small.** Extract subviews when a body grows past ~30 lines.
  Reusable cells live alongside their parent unless they're used by 3+
  parents (e.g. `AssetThumbnailer` is shared, `AssetCell` is not).

## Safety invariants

These are the rules that keep users from losing photos. **Any deviation is
a bug, not a feature.**

1. An asset is "verified" only if **every** one of its tracked
   `PHAssetResource`s (`.photo`, `.video`, `.pairedVideo`) has a SHA1 that
   exists in Immich and is not in Immich's trash. Partial matches are never
   enough. The check is `AssetVerification.isFullyVerified` in
   `PhotoProof/Verification/AssetTypes.swift`.
2. Only assets where `isFullyVerified == true` are passed to
   `PHAssetChangeRequest.deleteAssets`. The delete button is gated on this.
3. PhotoProof uses `deleteAssets`, not `removeAssets(_:from:)`. The latter
   only un-files an asset from an album; the former moves it to Recently
   Deleted (the reversible action we depend on).
4. A CSV log is written to `~/Library/Application Support/PhotoProof/Runs/`
   **before** any destructive action. If the log write fails, the delete is
   aborted.
5. Two confirmations are mandatory before items move: PhotoProof's own
   alert, then macOS's automatic system prompt.
6. No telemetry, no analytics, no network calls except to the user's
   configured Immich server.

If a change touches the verification or delete pipeline, re-read these
invariants and verify the change preserves them.

## Testing

There is no XCTest suite yet. Verification is manual:

- `./scripts/build-dev.sh` to confirm the project compiles cleanly.
- Walk the Verify flow against a small album whose contents you know are in
  Immich; confirm the Verified count matches.
- Walk the Find Candidates flow; confirm filtered results match the
  underlying filters.

If you add a unit-testable helper, prefer pure functions over methods on
view types; tests can come later.

## When in doubt

- README is the source of truth for user-facing behavior.
- The reference implementation in the conversation history (Node.js
  `verify_deleted.mjs`, since removed from the repo) was the source of truth
  for the Immich verification logic. The current Swift implementation
  matches its semantics — batch sizes (200), retry/backoff (250ms / 1s / 4s,
  3 attempts on transient errors), and the bulk-then-trash double-check.
- Apple's PhotoKit docs are authoritative for asset/resource handling.
