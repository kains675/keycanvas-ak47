#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
allowed_rgb_query_file="$project_root/Sources/AK47InspectorCore/AK47PerKeyRGBQueryAdapter.swift"
allowed_verified_write_file="$project_root/Sources/AK47InspectorCore/AK47DeviceWriteAdapter.swift"
forbidden_pattern='IOHIDDeviceSetValue|IOHIDQueue|IOHIDTransaction|kIOHIDOptionsTypeSeizeDevice'

if grep -R -n -E "$forbidden_pattern" "$project_root/Sources"; then
    echo "HID boundary violation: a value write, transaction, queue, or seize API appears in Sources." >&2
    exit 1
fi

set_report_violations=$(find "$project_root/Sources" -type f -name '*.swift' \
    ! -path "$allowed_rgb_query_file" \
    ! -path "$allowed_verified_write_file" \
    -exec grep -n -H -E 'IOHIDDeviceSetReport' {} + 2>/dev/null || true)
if [ -n "$set_report_violations" ]; then
    printf '%s\n' "$set_report_violations" >&2
    echo "HID boundary violation: SetReport is only allowed in the reviewed RGB query and verified write adapters." >&2
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

if grep -n -E 'kIOHIDReportTypeOutput|kIOHIDOptionsTypeSeizeDevice' "$allowed_rgb_query_file"; then
    echo "HID boundary violation: RGB query adapter may use only nonexclusive Feature reports." >&2
    exit 1
fi


if grep -n -E 'kIOHIDReportTypeOutput|kIOHIDOptionsTypeSeizeDevice' "$allowed_verified_write_file"; then
    echo "HID boundary violation: verified write adapter may use only nonexclusive Feature reports." >&2
    exit 1
fi

echo "HID API boundary check passed."
