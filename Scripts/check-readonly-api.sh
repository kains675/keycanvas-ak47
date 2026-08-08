#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

forbidden_pattern='IOHIDManagerOpen|IOHIDDeviceOpen|IOHIDDeviceGetReport|IOHIDDeviceSetReport|IOHIDDeviceSetValue|IOHIDDeviceRegisterInputReportCallback|IOHIDQueue|IOHIDTransaction|kIOHIDOptionsTypeSeizeDevice'

if grep -R -n -E "$forbidden_pattern" "$project_root/Sources"; then
    echo "Read-only boundary violation: a forbidden HID API appears in Sources." >&2
    exit 1
fi

echo "Read-only API check passed."
