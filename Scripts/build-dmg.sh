#!/bin/sh
set -eu

# Builds a drag-and-drop DMG containing only KeyCanvas.app and an Applications
# symlink. By default this first runs build-app.sh, whose default is Universal 2.
# Set KEYCANVAS_BUILD_APP=0 to package an already validated dist/KeyCanvas.app.

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
distribution_dir="$project_root/dist"
app_bundle="$distribution_dir/KeyCanvas.app"
build_app=${KEYCANVAS_BUILD_APP:-1}

case "$build_app" in
    0|1) ;;
    *)
        printf 'KEYCANVAS_BUILD_APP must be 0 or 1.\n' >&2
        exit 2
        ;;
esac

for required_tool in hdiutil plutil codesign lipo ditto shasum; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        printf 'Required DMG tool is unavailable: %s\n' "$required_tool" >&2
        exit 1
    fi
done

if [ "$build_app" = "1" ]; then
    "$project_root/Scripts/build-app.sh"
fi

if [ ! -d "$app_bundle" ]; then
    printf 'Application bundle is missing: %s\n' "$app_bundle" >&2
    exit 1
fi

info_plist="$app_bundle/Contents/Info.plist"
app_binary="$app_bundle/Contents/MacOS/KeyCanvas"
if [ ! -f "$info_plist" ] || [ ! -x "$app_binary" ]; then
    printf 'Application bundle is incomplete: %s\n' "$app_bundle" >&2
    exit 1
fi

plutil -lint "$info_plist" >/dev/null
codesign --verify --deep --strict --verbose=2 "$app_bundle"

if lipo "$app_binary" -verify_arch arm64 x86_64 >/dev/null 2>&1; then
    architecture_suffix=universal
elif lipo "$app_binary" -verify_arch arm64 >/dev/null 2>&1; then
    architecture_suffix=arm64
elif lipo "$app_binary" -verify_arch x86_64 >/dev/null 2>&1; then
    architecture_suffix=x86_64
else
    printf 'The app does not contain a supported macOS architecture.\n' >&2
    exit 1
fi

version=$(plutil -extract CFBundleShortVersionString raw -expect string "$info_plist")
case "$version" in
    ''|*[!0-9A-Za-z._-]*)
        printf 'The bundle version is unsafe for a DMG filename: %s\n' "$version" >&2
        exit 1
        ;;
esac

mkdir -p "$distribution_dir"
work_dir=$(mktemp -d "$distribution_dir/.keycanvas-dmg.XXXXXX")

cleanup() {
    if [ -n "${work_dir:-}" ] && [ -d "$work_dir" ]; then
        rm -rf -- "$work_dir"
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

staging_dir="$work_dir/staging"
staged_dmg="$work_dir/KeyCanvas-$version-macos-$architecture_suffix.dmg"
dmg="$distribution_dir/KeyCanvas-$version-macos-$architecture_suffix.dmg"
staged_dmg_checksum="$staged_dmg.sha256"
dmg_checksum="$dmg.sha256"

mkdir -p "$staging_dir"
ditto "$app_bundle" "$staging_dir/KeyCanvas.app"
ln -s /Applications "$staging_dir/Applications"

if [ "$(readlink "$staging_dir/Applications")" != "/Applications" ]; then
    printf 'Applications symlink validation failed.\n' >&2
    exit 1
fi

hdiutil create \
    -quiet \
    -volname KeyCanvas \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$staged_dmg"
hdiutil verify "$staged_dmg" >/dev/null
dmg_digest=$(shasum -a 256 "$staged_dmg")
dmg_digest=${dmg_digest%% *}
printf '%s  %s\n' "$dmg_digest" "$(basename "$dmg")" > "$staged_dmg_checksum"
(cd "$work_dir" && shasum -a 256 -c "$(basename "$staged_dmg_checksum")" >/dev/null)

backup_dmg="$work_dir/previous-KeyCanvas.dmg"
backup_dmg_checksum="$work_dir/previous-KeyCanvas.dmg.sha256"
if [ -e "$dmg" ] || [ -L "$dmg" ]; then
    mv "$dmg" "$backup_dmg"
fi
if ! mv "$staged_dmg" "$dmg"; then
    if [ -e "$backup_dmg" ] || [ -L "$backup_dmg" ]; then
        mv "$backup_dmg" "$dmg"
    fi
    exit 1
fi
if [ -e "$dmg_checksum" ] || [ -L "$dmg_checksum" ]; then
    mv "$dmg_checksum" "$backup_dmg_checksum"
fi
if ! mv "$staged_dmg_checksum" "$dmg_checksum"; then
    if [ -e "$backup_dmg_checksum" ] || [ -L "$backup_dmg_checksum" ]; then
        mv "$backup_dmg_checksum" "$dmg_checksum"
    fi
    exit 1
fi

(cd "$distribution_dir" && shasum -a 256 -c "$(basename "$dmg_checksum")" >/dev/null)

printf 'Built %s\n' "$dmg"
printf 'Checksum %s\n' "$dmg_checksum"
printf 'Drag KeyCanvas.app onto Applications after opening the image.\n'
printf 'Architectures: %s\n' "$(lipo "$app_binary" -archs)"
if [ -n "${KEYCANVAS_CODESIGN_IDENTITY:-}" ]; then
    printf 'App signing: identity %s (notarization is a separate release step)\n' \
        "$KEYCANVAS_CODESIGN_IDENTITY"
else
    printf 'App signing: ad-hoc (not notarized; Gatekeeper distribution requires Developer ID and notarization)\n'
fi
