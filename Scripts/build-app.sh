#!/bin/sh
set -eu

# Builds a clean KeyCanvas.app and ZIP archive. The default is a Universal 2
# binary (arm64 + x86_64). Set KEYCANVAS_UNIVERSAL=0 for the host architecture.

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${KEYCANVAS_CONFIGURATION:-release}
version=${KEYCANVAS_VERSION:-0.1.0}
build_number=${KEYCANVAS_BUILD_NUMBER:-1}
universal=${KEYCANVAS_UNIVERSAL:-1}
distribution_dir="$project_root/dist"
app_bundle="$distribution_dir/KeyCanvas.app"
source_svg="$project_root/Artwork/keycanvas-mark.svg"

case "$configuration" in
    debug|release) ;;
    *)
        printf 'KEYCANVAS_CONFIGURATION must be debug or release.\n' >&2
        exit 2
        ;;
esac

case "$version" in
    ''|*[!0-9A-Za-z._-]*)
        printf 'KEYCANVAS_VERSION contains unsupported filename characters.\n' >&2
        exit 2
        ;;
esac

case "$build_number" in
    ''|*[!0-9.]*)
        printf 'KEYCANVAS_BUILD_NUMBER must contain only digits and periods.\n' >&2
        exit 2
        ;;
esac

case "$universal" in
    0|1) ;;
    *)
        printf 'KEYCANVAS_UNIVERSAL must be 0 or 1.\n' >&2
        exit 2
        ;;
esac

for required_tool in swift plutil sips iconutil codesign lipo ditto shasum; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        printf 'Required packaging tool is unavailable: %s\n' "$required_tool" >&2
        exit 1
    fi
done

if [ ! -f "$source_svg" ]; then
    printf 'Project-authored icon source is missing: %s\n' "$source_svg" >&2
    exit 1
fi

if [ "$universal" = "1" ]; then
    swift build \
        --package-path "$project_root" \
        --configuration "$configuration" \
        --arch arm64 \
        --arch x86_64 \
        --product keycanvas

    binary_dir=$(swift build \
        --package-path "$project_root" \
        --configuration "$configuration" \
        --arch arm64 \
        --arch x86_64 \
        --show-bin-path)
    archive_suffix=universal
else
    native_arch=$(uname -m)
    case "$native_arch" in
        arm64|x86_64) ;;
        *)
            printf 'Unsupported native macOS architecture: %s\n' "$native_arch" >&2
            exit 1
            ;;
    esac

    swift build \
        --package-path "$project_root" \
        --configuration "$configuration" \
        --product keycanvas

    binary_dir=$(swift build \
        --package-path "$project_root" \
        --configuration "$configuration" \
        --show-bin-path)
    archive_suffix=$native_arch
fi

built_binary="$binary_dir/keycanvas"
if [ ! -x "$built_binary" ]; then
    printf 'SwiftPM did not produce the expected executable: %s\n' "$built_binary" >&2
    exit 1
fi

if [ "$universal" = "1" ]; then
    lipo "$built_binary" -verify_arch arm64 x86_64
else
    lipo "$built_binary" -verify_arch "$native_arch"
fi

mkdir -p "$distribution_dir"
work_dir=$(mktemp -d "$distribution_dir/.keycanvas-app.XXXXXX")

cleanup() {
    if [ -n "${work_dir:-}" ] && [ -d "$work_dir" ]; then
        rm -rf -- "$work_dir"
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

staged_app="$work_dir/KeyCanvas.app"
contents_dir="$staged_app/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
iconset_dir="$work_dir/KeyCanvas.iconset"
source_png="$work_dir/KeyCanvas-1024.png"
staged_archive="$work_dir/KeyCanvas-$version-macos-$archive_suffix.zip"
archive="$distribution_dir/KeyCanvas-$version-macos-$archive_suffix.zip"
staged_archive_checksum="$staged_archive.sha256"
archive_checksum="$archive.sha256"

mkdir -p "$macos_dir" "$resources_dir" "$iconset_dir"
install -m 755 "$built_binary" "$macos_dir/KeyCanvas"
install -m 644 "$project_root/Packaging/Info.plist" "$contents_dir/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$contents_dir/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$contents_dir/Info.plist"
plutil -lint "$contents_dir/Info.plist" >/dev/null

# sips uses the system CoreSVG renderer and avoids copying any pre-rendered or
# vendor-provided image into the application bundle.
sips -s format png "$source_svg" --out "$source_png" >/dev/null
if [ ! -s "$source_png" ]; then
    printf 'Could not rasterize the project-authored SVG icon.\n' >&2
    exit 1
fi

make_icon() {
    size=$1
    filename=$2
    sips -z "$size" "$size" "$source_png" --out "$iconset_dir/$filename" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png
iconutil -c icns "$iconset_dir" -o "$resources_dir/KeyCanvas.icns"

if [ -n "${KEYCANVAS_CODESIGN_IDENTITY:-}" ]; then
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$KEYCANVAS_CODESIGN_IDENTITY" \
        "$staged_app"
    signing_mode="identity: $KEYCANVAS_CODESIGN_IDENTITY"
else
    codesign --force --sign - "$staged_app"
    signing_mode='ad-hoc (not notarized)'
fi

codesign --verify --deep --strict --verbose=2 "$staged_app"
ditto -c -k --sequesterRsrc --keepParent "$staged_app" "$staged_archive"
archive_digest=$(shasum -a 256 "$staged_archive")
archive_digest=${archive_digest%% *}
printf '%s  %s\n' "$archive_digest" "$(basename "$archive")" \
    > "$staged_archive_checksum"
(cd "$work_dir" && shasum -a 256 -c "$(basename "$staged_archive_checksum")" >/dev/null)

publish_artifact() {
    source_path=$1
    destination_path=$2
    backup_name=$3
    backup_path="$work_dir/$backup_name"

    if [ -e "$destination_path" ] || [ -L "$destination_path" ]; then
        mv "$destination_path" "$backup_path"
    fi
    if mv "$source_path" "$destination_path"; then
        return 0
    fi
    if [ -e "$backup_path" ] || [ -L "$backup_path" ]; then
        mv "$backup_path" "$destination_path"
    fi
    return 1
}

publish_artifact "$staged_app" "$app_bundle" previous-KeyCanvas.app
publish_artifact "$staged_archive" "$archive" previous-KeyCanvas.zip
publish_artifact \
    "$staged_archive_checksum" \
    "$archive_checksum" \
    previous-KeyCanvas.zip.sha256

(cd "$distribution_dir" && shasum -a 256 -c "$(basename "$archive_checksum")" >/dev/null)

built_architectures=$(lipo "$app_bundle/Contents/MacOS/KeyCanvas" -archs)
printf 'Built %s\n' "$app_bundle"
printf 'Architectures: %s\n' "$built_architectures"
printf 'Signing: %s\n' "$signing_mode"
printf 'Archived %s\n' "$archive"
printf 'Checksum %s\n' "$archive_checksum"
