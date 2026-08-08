#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_root"

sh Scripts/check-readonly-api.sh

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    file_list=$(git ls-files)
else
    file_list=$(find . -type f \
        ! -path './.git/*' \
        ! -path './.build/*' \
        ! -path './.swiftpm/*' \
        ! -path './dist/*' \
        ! -name '.DS_Store' \
        -print | sed 's|^./||')
fi

saved_ifs=$IFS
IFS='
'
for path in $file_list; do
    normalized=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')
    case "$normalized" in
        .ds_store|*/.ds_store)
            echo "Repository boundary violation: Finder metadata: $path" >&2
            exit 1
            ;;
        *.exe|*.dll|*.sys|*.msi|*.dmg|*.pkg|*.zip|*.rar|*.7z|*.tar|*.tgz|*.gz|*.bz2|*.xz|\
        *.bin|*.hex|*.uf2|*.dfu|*.rom|*.fw|*.cap)
            echo "Repository boundary violation: disallowed artifact: $path" >&2
            exit 1
            ;;
        *.png|*.jpg|*.jpeg|*.gif|*.bmp|*.tif|*.tiff|*.webp|*.ico|*.icns|*.svg|*.ai|*.psd)
            if [ "$normalized" != "artwork/keycanvas-mark.svg" ]; then
                echo "Repository boundary violation: unreviewed visual asset: $path" >&2
                exit 1
            fi
            ;;
    esac

    case "/$normalized/" in
        */firmware/*|*/vendor/*|*/extracted/*|*/device-dumps/*|*/reverse-engineering/*)
            echo "Repository boundary violation: disallowed material directory: $path" >&2
            exit 1
            ;;
    esac

    if [ -s "$path" ] && ! LC_ALL=C grep -I -q '' -- "$path"; then
        echo "Repository boundary violation: unreviewed binary file: $path" >&2
        exit 1
    fi

    lfs_marker='version https://git-lfs.github.com/spec/'"v1"
    if [ -f "$path" ] && grep -I -q -F "$lfs_marker" -- "$path"; then
        echo "Repository boundary violation: Git LFS pointer found: $path" >&2
        exit 1
    fi
done
IFS=$saved_ifs

echo "Repository boundary scan passed."
