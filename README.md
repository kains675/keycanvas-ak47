# KeyCanvas

<img src="Artwork/keycanvas-mark.svg" alt="KeyCanvas original application mark" width="160">

KeyCanvas is an independent, open-source macOS compatibility utility for
inspecting a keyboard and exploring a native settings interface. The current
compatibility target is the **ARCHON AK47 (non-PRO)** identified by USB vendor
and product IDs `0x0C45:0x800A`. Compatibility with other models, revisions, or
devices is not claimed.

KeyCanvas is not endorsed by, sponsored by, or affiliated with the device
manufacturer or any trademark owner. Product and company names are trademarks
of their respective owners and appear here only to identify compatible
hardware.

## Current status and safety boundary

This repository is a read-only public prototype:

- it enumerates matching top-level HID collections and reads public IOHID
  registry properties;
- the SwiftUI screens are independently designed and edit local JSON profiles;
  those profiles are not applied to hardware;
- hardware writes are disabled by default and the current build contains no
  concrete hardware HID report-write implementation;
- a firmware updater, firmware flashing, and firmware payload handling are
  intentionally excluded from the project.

The repository does not include vendor firmware, update tools, executables,
installers, archives, code, logos, artwork, UI screenshots, layouts, or other
vendor assets. This exclusion applies whether a use or contribution is
commercial or noncommercial. The interface is independently implemented with
standard macOS components, SF Symbols, and project-authored visuals.

## Features

- Native SwiftUI shell with Dashboard, Keymap, Lighting, Macros, Display,
  Settings, and Device Inspector sections
- Korean and English interface text, with Korean selected by default
- Local JSON editing for an 84-key Base/Fn keymap, two-color lighting scenes,
  validated macros, a 240×135 display composition, and settings drafts
- Local profile storage plus validated JSON import and export
- Read-only discovery of matching HID collections
- Conservative role classification from observable registry metadata
- A command-line inspector with human-readable and JSON output
- No third-party package dependencies

Profiles are stored under the user's `Application Support/KeyCanvas` directory.
Importing, exporting, or saving a profile changes files on the Mac only; no
setting is sent to the device.

## Requirements

- macOS 13 or newer
- Swift 5.9 or newer

## Run

Launch the app:

```sh
swift run keycanvas
```

Run the command-line inspector:

```sh
swift run ak47-inspect
swift run ak47-inspect --json
```

The command-line output includes observable properties such as product,
manufacturer, transport, location ID, usage page, usage, report-size metadata,
and an inferred collection role. A report-size property is metadata; reading
it does not transfer a HID report.

## Build and test

```sh
swift build
swift test
sh Scripts/check-readonly-api.sh
sh .github/scripts/repository-scan.sh
```

GitHub Actions runs the Swift build and tests on macOS and runs a separate
repository-boundary scan.

## Build a macOS app bundle

Create an ad-hoc signed Universal 2 application and ZIP archive:

```sh
sh Scripts/build-app.sh
```

Outputs are written under `dist/`. The default build contains both Apple
Silicon and Intel code. For local-architecture development builds, set
`KEYCANVAS_UNIVERSAL=0`. A release maintainer with a Developer ID certificate
can set `KEYCANVAS_CODESIGN_IDENTITY` before running the script; notarization
is a separate distribution step.

The source vector in [Artwork/keycanvas-mark.svg](Artwork/keycanvas-mark.svg)
and the SwiftUI mark are original KeyCanvas artwork and do not use vendor
branding or driver assets.

## Project policies

- [Changelog](CHANGELOG.md)
- [Clean-room policy](CLEAN_ROOM.md)
- [Design and safety boundaries](DESIGN.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Notices](NOTICE.md)

## License

KeyCanvas's original code and documentation are available under the
[MIT License](LICENSE). That license does not grant rights in third-party
trademarks, firmware, software, or assets.
