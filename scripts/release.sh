#!/usr/bin/env bash
# Release a new version of PhotoProof.
#
# Usage:
#   ./scripts/release.sh <version>           # e.g. 1.0.0
#   ./scripts/release.sh <version> --dry-run # bump + changelog only, no commit/tag/push
#
# What this does, in order:
#   1. Validate clean working tree, tools (gh, git-cliff), and git remote.
#   2. Set MARKETING_VERSION in the .pbxproj; bump CURRENT_PROJECT_VERSION.
#   3. Regenerate CHANGELOG.md from git history via git-cliff.
#   4. Commit everything as `chore(release): X.Y.Z` and tag vX.Y.Z.
#   5. Build Release via scripts/build-prod.sh and zip ./build/PhotoProof.app.
#   6. Push the commit and tag to origin.
#   7. Create the GitHub release and upload the zip as an asset.

set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=false
if [ "${2:-}" = "--dry-run" ]; then DRY_RUN=true; fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 <version> [--dry-run]"
    echo "Example: $0 1.0.0"
    exit 1
fi

VERSION="$1"
TAG="v$VERSION"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "✗ Version must be semver X.Y.Z (got: $VERSION)"
    exit 1
fi

# --- Preflight ---

for tool in git-cliff gh zip; do
    if ! command -v "$tool" >/dev/null; then
        echo "✗ $tool not found. Install with: brew install $tool"
        exit 1
    fi
done

if [ "$DRY_RUN" = false ]; then
    if ! gh auth status >/dev/null 2>&1; then
        echo "✗ gh is not authenticated. Run: gh auth login"
        exit 1
    fi
    if ! git remote get-url origin >/dev/null 2>&1; then
        echo "✗ No git remote 'origin'. Create a GitHub repo and add it first."
        exit 1
    fi
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "✗ Working tree has uncommitted changes. Commit or stash first:"
    git status --short
    exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "✗ Tag $TAG already exists."
    exit 1
fi

# --- Bump version ---

PBXPROJ="PhotoProof.xcodeproj/project.pbxproj"
CURRENT_VERSION=$(grep -m1 "MARKETING_VERSION = " "$PBXPROJ" | sed 's/.*= //;s/;.*//')
CURRENT_BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION = " "$PBXPROJ" | sed 's/.*= //;s/;.*//')
NEW_BUILD=$((CURRENT_BUILD + 1))

echo "→ MARKETING_VERSION:      $CURRENT_VERSION → $VERSION"
echo "→ CURRENT_PROJECT_VERSION: $CURRENT_BUILD → $NEW_BUILD"

sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"

# --- Regenerate changelog ---

echo "→ Regenerating CHANGELOG.md"
git-cliff --tag "$TAG" --output CHANGELOG.md

if [ "$DRY_RUN" = true ]; then
    echo
    echo "✓ Dry run complete. Review the changes:"
    echo "  git diff"
    echo "Revert with: git checkout -- $PBXPROJ CHANGELOG.md"
    exit 0
fi

# --- Commit + tag ---

echo "→ Committing release"
git add "$PBXPROJ" CHANGELOG.md
git commit -m "chore(release): $VERSION"

echo "→ Tagging $TAG"
git tag -a "$TAG" -m "$VERSION"

# --- Build + zip ---

echo "→ Building Release..."
./scripts/build-prod.sh >/dev/null

ZIP="build/PhotoProof-$VERSION.zip"
rm -f "$ZIP"
( cd build && zip -qr "PhotoProof-$VERSION.zip" PhotoProof.app -x "*.DS_Store" )
ZIP_SIZE=$(du -sh "$ZIP" | awk '{print $1}')
echo "✓ Bundled: $ZIP ($ZIP_SIZE)"

# --- Push ---

BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "→ Pushing $BRANCH and $TAG to origin"
git push origin "$BRANCH"
git push origin "$TAG"

# --- GitHub release ---

# Extract the section for $VERSION from CHANGELOG.md as release notes.
NOTES=$(awk -v v="$VERSION" '
    $0 ~ "^## \\["v"\\]" { flag=1; next }
    flag && /^## \[/ { flag=0 }
    flag { print }
' CHANGELOG.md)

if [ -z "$NOTES" ]; then
    NOTES="See [CHANGELOG.md](CHANGELOG.md)."
fi

echo "→ Creating GitHub release $TAG"
echo "$NOTES" | gh release create "$TAG" \
    --title "$VERSION" \
    --notes-file - \
    "$ZIP"

echo
echo "✓ Released $VERSION"
echo "  https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/$TAG"
