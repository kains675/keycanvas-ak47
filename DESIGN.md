# KeyCanvas design boundaries

KeyCanvas is structured so presentation, observable device metadata, and any
future device-changing capability have clear boundaries.

## Current architecture

1. **Discovery** uses documented macOS HID APIs to match devices and copy public
   registry properties. The manager and devices are not opened for report
   traffic.
2. **Classification** is a pure transformation of observable metadata. Unknown
   combinations stay unknown rather than being guessed.
3. **Presentation** consists of an original SwiftUI app and a command-line
   renderer. The app uses standard controls, platform symbols, and
   project-authored visuals.
4. **Local profiles** store editor values as JSON in the user's Application
   Support directory and support JSON import and export. Profile operations do
   not call a device transport, persist to hardware, or claim successful device
   configuration.

The core also defines capability-gated request types and an in-memory mock so
default denial can be unit-tested. It supplies no macOS report-I/O adapter.
This arrangement lets the UI and classification logic be tested with synthetic
fixtures without connected hardware.

## Trust and data boundaries

- Device and report-size properties are treated as untrusted input. UI and CLI
  output must handle absent, unexpected, and oversized values safely.
- Human-readable device strings are display data, not instructions or trusted
  identifiers.
- Imported profiles are untrusted input. Decoding must fail safely, and profile
  data must remain local unless the user explicitly exports a file.
- No vendor executable, firmware, UI, logo, or asset is a runtime or build-time
  dependency.
- The package has no third-party source dependencies and does not require a
  network service for its core behavior.

## Write policy

There is no concrete hardware-write transport in the current public build, and
the capability policy denies writes by default. If a future settings feature is
proposed, the transport must be isolated from discovery, disabled by default,
activated only by explicit user action, and covered by tests for target
validation, length and range checks, cancellation, and error handling. Adding
it requires a focused security and device-safety review.

Firmware updating, bootloader access, flashing, firmware extraction, and
firmware payload distribution are permanently outside this repository's design
scope.

## Automated enforcement

Continuous integration builds and tests the Swift package on macOS. A separate
repository scan invokes the existing HID API boundary check and rejects common
firmware, executable, installer, and archive formats as well as unreviewed
binary files. Visual assets are denied unless a project-authored original has
been explicitly reviewed and allowlisted. Automated checks supplement review;
they do not establish provenance or legal rights.
