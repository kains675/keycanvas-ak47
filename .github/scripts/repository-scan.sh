#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$project_root"

sh Scripts/check-readonly-api.sh

is_allowlisted_json() {
    case "$1" in
        # Add only exact, lowercased paths reviewed for provenance and content.
        # path/to/reviewed-project-authored.json) return 0 ;;
        *) return 1 ;;
    esac
}

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    file_list=$({
        git ls-files
        git ls-files --others --exclude-standard
    } | LC_ALL=C sort -u)
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
        *.bin|*.hex|*.uf2|*.dfu|*.rom|*.fw|*.cap|\
        *.pcap|*.pcapng|*.usbmon|*.etl|*.trace|*.log)
            echo "Repository boundary violation: disallowed artifact: $path" >&2
            exit 1
            ;;
        *.json)
            if ! is_allowlisted_json "$normalized"; then
                echo "Repository boundary violation: JSON is not explicitly allowlisted: $path" >&2
                exit 1
            fi
            ;;
        *.png|*.jpg|*.jpeg|*.gif|*.bmp|*.tif|*.tiff|*.webp|*.ico|*.icns|*.svg|*.ai|*.psd)
            if [ "$normalized" != "artwork/keycanvas-mark.svg" ]; then
                echo "Repository boundary violation: unreviewed visual asset: $path" >&2
                exit 1
            fi
            ;;
    esac

    case "/$normalized/" in
        */analysis/*|*/firmware/*|*/vendor/*|*/extracted/*|*/device-dumps/*|*/reverse-engineering/*|\
        */raw-capture/*|*/raw-captures/*)
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
