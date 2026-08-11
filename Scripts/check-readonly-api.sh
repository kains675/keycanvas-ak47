#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
allowed_rgb_query_file="$project_root/Sources/AK47InspectorCore/AK47PerKeyRGBQueryAdapter.swift"
allowed_verified_write_file="$project_root/Sources/AK47InspectorCore/AK47DeviceWriteAdapter.swift"
allowed_lcd_upload_file="$project_root/Sources/AK47InspectorCore/AK47LCDUploadAdapter.swift"
forbidden_pattern='IOHIDDeviceSetValue|IOHIDQueue|IOHIDTransaction|kIOHIDOptionsTypeSeizeDevice'

if grep -R -n -E "$forbidden_pattern" "$project_root/Sources"; then
    echo "HID boundary violation: a value write, transaction, queue, or seize API appears in Sources." >&2
    exit 1
fi

set_report_violations=$(find "$project_root/Sources" -type f -name '*.swift' \
    ! -path "$allowed_rgb_query_file" \
    ! -path "$allowed_verified_write_file" \
    ! -path "$allowed_lcd_upload_file" \
    -exec grep -n -H -E 'IOHIDDeviceSetReport' {} + 2>/dev/null || true)
if [ -n "$set_report_violations" ]; then
    printf '%s\n' "$set_report_violations" >&2
    echo "HID boundary violation: SetReport is only allowed in the three reviewed adapters." >&2
    exit 1
fi

if [ ! -f "$allowed_rgb_query_file" ]; then
    echo "HID boundary violation: reviewed RGB query adapter is missing." >&2
    exit 1
fi

if [ ! -f "$allowed_verified_write_file" ]; then
    echo "HID boundary violation: verified write adapter is missing." >&2
    exit 1
fi

if [ ! -f "$allowed_lcd_upload_file" ]; then
    echo "HID boundary violation: reviewed bounded LCD adapter is missing." >&2
    exit 1
fi

set_report_count=$(grep -o 'IOHIDDeviceSetReport' "$allowed_rgb_query_file" | wc -l | tr -d ' ')
if [ "$set_report_count" -ne 1 ]; then
    echo "HID boundary violation: RGB query adapter must contain exactly one SetReport call site." >&2
    exit 1
fi

verified_write_set_report_count=$(grep -o 'IOHIDDeviceSetReport' "$allowed_verified_write_file" | wc -l | tr -d ' ')
if [ "$verified_write_set_report_count" -ne 1 ]; then
    echo "HID boundary violation: verified write adapter must contain exactly one SetReport call site." >&2
    exit 1
fi

lcd_upload_set_report_count=$(grep -o 'IOHIDDeviceSetReport' "$allowed_lcd_upload_file" | wc -l | tr -d ' ')
if [ "$lcd_upload_set_report_count" -ne 2 ]; then
    echo "HID boundary violation: bounded LCD adapter must contain exactly two SetReport call sites." >&2
    exit 1
fi

# Classify only the report type argument belonging to each async SetReport call.
# Any variable or newly introduced report type remains unresolved and fails the
# exact allowlist below.
classify_async_set_reports() {
    awk '
        /IOHIDDeviceSetReportWithCallback[[:space:]]*\(/ {
            if (pending) { unresolved += 1 }
            pending = 1
        }
        pending && /kIOHIDReportTypeFeature/ {
            feature += 1
            pending = 0
            next
        }
        pending && /kIOHIDReportTypeOutput/ {
            output += 1
            pending = 0
            next
        }
        pending && /kIOHIDReportType/ {
            other += 1
            pending = 0
            next
        }
        END {
            if (pending) { unresolved += 1 }
            printf "%d %d %d %d\n", feature + 0, output + 0, other + 0, unresolved + 0
        }
    ' "$1"
}

set -- $(classify_async_set_reports "$allowed_rgb_query_file")
if [ "$1" -ne 1 ] || [ "$2" -ne 0 ] || [ "$3" -ne 0 ] || [ "$4" -ne 0 ]; then
    echo "HID boundary violation: RGB query adapter must have exactly one async Feature SetReport call." >&2
    exit 1
fi

set -- $(classify_async_set_reports "$allowed_verified_write_file")
if [ "$1" -ne 1 ] || [ "$2" -ne 0 ] || [ "$3" -ne 0 ] || [ "$4" -ne 0 ]; then
    echo "HID boundary violation: verified write adapter must have exactly one async Feature SetReport call." >&2
    exit 1
fi

set -- $(classify_async_set_reports "$allowed_lcd_upload_file")
if [ "$1" -ne 1 ] || [ "$2" -ne 1 ] || [ "$3" -ne 0 ] || [ "$4" -ne 0 ]; then
    echo "HID boundary violation: bounded LCD adapter must have one async Feature and one async Output SetReport call." >&2
    exit 1
fi

if grep -n -E 'kIOHIDReportTypeOutput|kIOHIDOptionsTypeSeizeDevice' "$allowed_rgb_query_file"; then
    echo "HID boundary violation: RGB query adapter may use only nonexclusive Feature reports." >&2
    exit 1
fi


if grep -n -E 'kIOHIDReportTypeOutput|kIOHIDOptionsTypeSeizeDevice' "$allowed_verified_write_file"; then
    echo "HID boundary violation: verified write adapter may use only nonexclusive Feature reports." >&2
    exit 1
fi

if grep -n -E 'kIOHIDOptionsTypeSeizeDevice' "$allowed_lcd_upload_file"; then
    echo "HID boundary violation: bounded LCD adapter must remain nonexclusive." >&2
    exit 1
fi

echo "HID API boundary check passed."
