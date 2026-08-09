# KeyCanvas security policy

## Supported scope

Security fixes target the latest revision on the repository's default branch.
Older snapshots and downstream forks may not receive fixes.

Normal discovery and diagnostics are read-only, but the public build also has a
small explicit Feature-operation allowlist. Every non-read-only action first
matches wired USB `0x0C45:0x800A`, product `Archon AK47`, `bcdDevice 0x0115`,
the complete four-collection topology, and the single FF13 command collection.
Each of the following requires its own user confirmation and a matching typed
authorization:

- synchronize the first clock slot to the Mac's current local time;
- apply one currently selected onboard lighting mode in `0...19`; or
- apply brightness and a complete table containing all 84 verified RGB
  positions exactly once.

The separate per-key F5 query also requires confirmation and reads only the
84-key RGB buffer. It does not read the current mode, brightness, speed,
direction, clock, keymap, LCD content, macros, or general settings.

The verified write state machine separates its Feature steps by 35ms. Each
asynchronous Feature operation has a 360ms timeout, and an ACK-required stage
accepts only a 64-byte response whose byte 3 signals success. Errors stop the
operation without automatic retry. There is no
output-report transmission, arbitrary-payload interface, device seizure, raw
report logging, or LCD, keymap, macro, firmware, or bootloader implementation.
Selecting or saving a local profile never transmits it automatically.

ACK validation is not exact state readback. The app cannot back up or restore
the current onboard mode parameters or clock value and cannot promise automatic
rollback after a partial failure. Only the complete per-key RGB table has the
separate F5 readback path.

Two 2026-08-09 hardware runs completed all nine 64-byte response reads. The
first parsed 84 zero RGB values; after the user changed the onboard lighting
mode, the second parsed nonzero values for all 84 keys with 24 distinct colors.
The device remained enumerated and no disconnect was observed. These results do
not identify the onboard mode or prove that every device state was unchanged.
Separate opt-in runs on 2026-08-09 completed the corrected clock transaction,
onboard modes 1 and 14, and one complete 84-key RGB apply on the exact wired
target. Required acknowledgements and postflight topology checks passed. F5
preserved the 84 key assignments but returned brightness-adjusted colors at
level 3, so it is not treated as byte-exact backup or rollback evidence.

## Trace-data boundary

The trace analyzer is offline, file-based, and decode-only. It has no public
encoder and does not perform live capture, hook or decrypt another process,
replay or inject reports, access a device, or upload input.

Treat each selected trace as untrusted. The decoder enforces document, event and
payload limits; strict keys; an allowed provenance origin; four true provenance
assertions; and relative-time limits. The first provided timestamp is zero,
later values are nondecreasing, and all are at most one hour.

Provenance assertions are not proof and do not make unsafe data suitable for
sharing. Avoid copying, persisting, or logging raw payloads. Public tests use
synthetic values. Human and JSON output omit input labels, individual and
boundary timestamps, and observed byte values; only a derived duration,
structure, lengths and changed byte offsets may be reported.

## Reporting a vulnerability

Use GitHub's **Report a vulnerability** link to open a private security advisory
for this repository. If private reporting is unavailable on a fork, contact its
maintainers privately before publishing details.

Include the affected revision, macOS and Swift versions, minimal synthetic
reproduction steps, expected and actual behavior, and likely impact.

Do not include firmware, vendor software, archives, confidential protocol
material, identifiers, raw dumps or captures, credentials, or private macro
content—even in a private report. Reproduce parser defects with a minimal
synthetic input. Do not test by capturing, replaying, writing to, or flashing
hardware.

An accidental raw-capture upload is a security incident. Report only its public
location without reattaching the data so maintainers can remove commits,
Actions logs or artifacts, and releases, then assess notification and rotation.

Nonsensitive feature requests may use the public issue tracker.
