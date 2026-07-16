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
#   5. Build, Developer ID sign, notarize, staple, and package the app.
#   6. Push the commit and tag to origin.
#   7. Create the GitHub release and update the Homebrew cask.

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
APP_NAME="PhotoProof"
APP_PATH="build/$APP_NAME.app"
ZIP="build/$APP_NAME-$VERSION.zip"
GH_REPO="${GH_REPO:-cmer/photoproof}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
TAP_REPO="${TAP_REPO:-cmer/homebrew-tap}"
CASK_NAME="${CASK_NAME:-photoproof}"

is_interactive() {
    [ -t 0 ] && [ -t 1 ]
}

choose_developer_id_identity() {
    if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
        return
    fi

    local identities=()
    local identity
    while IFS= read -r identity; do
        identities+=("$identity")
    done < <(
        security find-identity -v -p codesigning |
            sed -n 's/^ *[0-9]*) [A-F0-9]* "\(Developer ID Application: .*\)"/\1/p'
    )

    case "${#identities[@]}" in
        0)
            echo "✗ No Developer ID Application signing identity was found." >&2
            echo "  Install the certificate, then check: security find-identity -v -p codesigning" >&2
            exit 1
            ;;
        1)
            DEVELOPER_ID_APPLICATION="${identities[0]}"
            echo "→ Using signing identity: $DEVELOPER_ID_APPLICATION"
            ;;
        *)
            if ! is_interactive; then
                echo "✗ Multiple Developer ID Application identities found." >&2
                echo "  Set DEVELOPER_ID_APPLICATION to the exact identity to use." >&2
                exit 1
            fi

            echo "Choose a Developer ID Application signing identity:"
            local index
            for index in "${!identities[@]}"; do
                printf "  %d) %s\n" "$((index + 1))" "${identities[$index]}"
            done

            local choice
            read -r -p "Signing identity number: " choice
            if ! [[ "$choice" =~ ^[0-9]+$ ]] ||
                [ "$choice" -lt 1 ] || [ "$choice" -gt "${#identities[@]}" ]; then
                echo "✗ Invalid signing identity selection." >&2
                exit 1
            fi
            DEVELOPER_ID_APPLICATION="${identities[$((choice - 1))]}"
            ;;
    esac
}

choose_notary_profile() {
    if [ -n "$NOTARY_PROFILE" ]; then
        return
    fi

    local default_profile="bloomworks-notary"
    if is_interactive; then
        local entered_profile
        read -r -p "Notary keychain profile [$default_profile]: " entered_profile
        NOTARY_PROFILE="${entered_profile:-$default_profile}"
    else
        NOTARY_PROFILE="$default_profile"
    fi
}

confirm_release() {
    if [ "${SKIP_RELEASE_CONFIRMATION:-}" = "1" ] || ! is_interactive; then
        return
    fi

    echo
    echo "Release configuration:"
    echo "  Version: $VERSION"
    echo "  Tag: $TAG"
    echo "  GitHub repo: $GH_REPO"
    echo "  Signing identity: $DEVELOPER_ID_APPLICATION"
    echo "  Notary profile: $NOTARY_PROFILE"
    if [ -n "$TAP_REPO" ] && [ "${SKIP_CASK_UPDATE:-}" != "1" ]; then
        echo "  Homebrew tap: $TAP_REPO (cask: $CASK_NAME)"
    fi
    echo

    local answer
    read -r -p "Build, notarize, and publish this release? [y/N] " answer
    case "$answer" in
        y | Y | yes | YES) ;;
        *)
            echo "Release canceled."
            exit 0
            ;;
    esac
}

update_homebrew_cask() {
    # Publishing has already succeeded at this point, so tap failures are
    # reported without turning a valid GitHub release into a failed release.
    local sha
    sha="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
    echo "→ Release zip sha256: $sha"

    if [ -z "$TAP_REPO" ] || [ "${SKIP_CASK_UPDATE:-}" = "1" ]; then
        echo "→ Skipping Homebrew cask update."
        return
    fi

    local tap_dir cask_path
    tap_dir="$(mktemp -d)"
    cask_path="$tap_dir/Casks/$CASK_NAME.rb"

    if ! git clone --depth 1 "https://github.com/$TAP_REPO.git" "$tap_dir" >/dev/null 2>&1; then
        echo "⚠ Could not clone $TAP_REPO. Update the cask manually:" >&2
        echo "  version \"$VERSION\" / sha256 \"$sha\"" >&2
        rm -rf "$tap_dir"
        return
    fi

    if [ ! -f "$cask_path" ]; then
        local template_path="Casks/$CASK_NAME.rb"
        if [ ! -f "$template_path" ]; then
            echo "⚠ $CASK_NAME.rb not found in the tap or this repository." >&2
            echo "  version \"$VERSION\" / sha256 \"$sha\"" >&2
            rm -rf "$tap_dir"
            return
        fi
        mkdir -p "$(dirname "$cask_path")"
        cp "$template_path" "$cask_path"
    fi

    /usr/bin/sed -i '' \
        -e "s/^\( *version \).*/\1\"$VERSION\"/" \
        -e "s/^\( *sha256 \).*/\1\"$sha\"/" \
        "$cask_path"

    if git -C "$tap_dir" diff --quiet -- "Casks/$CASK_NAME.rb"; then
        echo "→ Cask $CASK_NAME is already at $VERSION."
        rm -rf "$tap_dir"
        return
    fi

    git -C "$tap_dir" add "Casks/$CASK_NAME.rb"
    if git -C "$tap_dir" commit -q -m "Update $CASK_NAME to $VERSION" &&
        git -C "$tap_dir" push -q; then
        echo "✓ Updated $TAP_REPO cask $CASK_NAME to $VERSION."
    else
        echo "⚠ Failed to push the cask update. Update it manually:" >&2
        echo "  version \"$VERSION\" / sha256 \"$sha\"" >&2
    fi
    rm -rf "$tap_dir"
}

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "✗ Version must be semver X.Y.Z (got: $VERSION)"
    exit 1
fi

# --- Preflight ---

for tool in git-cliff gh xcrun codesign ditto spctl; do
    if ! command -v "$tool" >/dev/null; then
        echo "✗ Required tool not found: $tool"
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

if [ "$DRY_RUN" = false ] && ! xcrun notarytool --version >/dev/null 2>&1; then
    echo "✗ Xcode notarytool is required. Install Xcode and select it with xcode-select."
    exit 1
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

if [ "$DRY_RUN" = false ] && gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
    echo "✗ GitHub release $TAG already exists in $GH_REPO."
    exit 1
fi

if [ "$DRY_RUN" = false ]; then
    choose_developer_id_identity
    choose_notary_profile
    confirm_release
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

# --- Build + sign + notarize ---

echo "→ Building Release..."
./scripts/build-prod.sh >/dev/null

echo "→ Signing with Developer ID"
codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" \
    "$APP_PATH"

echo "→ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

rm -f "$ZIP"
echo "→ Creating notarization upload"
ditto -c -k --keepParent "$APP_PATH" "$ZIP"

echo "→ Notarizing with profile $NOTARY_PROFILE"
xcrun notarytool submit "$ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "→ Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "→ Repackaging stapled app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP_PATH" "$ZIP"

echo "→ Assessing Gatekeeper acceptance"
spctl --assess --type execute --verbose=4 "$APP_PATH"

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
    --repo "$GH_REPO" \
    --target "$BRANCH" \
    --title "$VERSION" \
    --notes-file - \
    "$ZIP"

update_homebrew_cask

echo
echo "✓ Released $VERSION"
echo "  https://github.com/$GH_REPO/releases/tag/$TAG"
