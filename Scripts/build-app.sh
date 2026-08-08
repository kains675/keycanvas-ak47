#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${KEYCANVAS_CONFIGURATION:-release}
version=${KEYCANVAS_VERSION:-0.1.0}
build_number=${KEYCANVAS_BUILD_NUMBER:-1}
universal=${KEYCANVAS_UNIVERSAL:-1}
distribution_dir="$project_root/dist"
app_bundle="$distribution_dir/KeyCanvas.app"
contents_dir="$app_bundle/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
source_svg="$project_root/Artwork/keycanvas-mark.svg"

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
    swift build \
        --package-path "$project_root" \
        --configuration "$configuration" \
        --product keycanvas

    binary_dir=$(swift build \
        --package-path "$project_root" \
        --configuration "$configuration" \
        --show-bin-path)
    archive_suffix=$(uname -m)
fi

mkdir -p "$macos_dir" "$resources_dir"
cp "$binary_dir/keycanvas" "$macos_dir/KeyCanvas"
cp "$project_root/Packaging/Info.plist" "$contents_dir/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$contents_dir/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$contents_dir/Info.plist"

icon_work_dir=$(mktemp -d /tmp/keycanvas-icon.XXXXXX)
iconset_dir="$icon_work_dir/KeyCanvas.iconset"
mkdir -p "$iconset_dir"
qlmanage -t -s 1024 -o "$icon_work_dir" "$source_svg" >/dev/null 2>&1
source_png="$icon_work_dir/$(basename "$source_svg").png"

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
        "$app_bundle"
else
    codesign --force --deep --sign - "$app_bundle"
fi

archive="$distribution_dir/KeyCanvas-$version-macos-$archive_suffix.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive"

printf 'Built %s\n' "$app_bundle"
printf 'Archived %s\n' "$archive"
