# KeyCanvas design boundaries

KeyCanvas separates presentation, observable device metadata, offline trace
analysis, and any future device-changing capability.

## Current architecture

1. **Discovery** uses documented macOS HID APIs to match devices and copy public
   registry properties without opening a device.
2. **Classification** is a pure transformation of observable metadata. Unknown
   combinations remain unknown.
3. **Presentation** is an original SwiftUI app and command-line renderer using
   system components and project-authored visuals.
4. **Local profiles** store editor values in the user's Application Support
   directory. Profile operations do not call device transport.
5. **Offline trace analysis** decodes a deliberately selected, size-limited JSON
   file and performs pure summary and comparison operations. It does not encode
   trace documents, capture or hook traffic, communicate with hardware, replay
   reports, upload input, or infer commands on its own.
6. **Explicit direct report probing** opens one exact vendor collection with
   `kIOHIDOptionsTypeNone`, performs one `GetReport` away from the main actor,
   and closes it when the call returns. This
   path has no selector command, SetReport, output transmission, persistence,
   automatic retry, or firmware path. The UI runs it only after a button click.
7. **Bounded per-key RGB querying** is a separate, explicitly confirmed path.
   It requires the exact wired USB identity `0x0C45:0x800A`, product
   `Archon AK47`, `bcdDevice 0x0115`, and all four verified HID collections.
   It sends only the allowlisted F5 query and normal finish Feature commands,
   validates acknowledgements and nine 64-byte responses, and keeps
   the 84 parsed RGB values in memory.
8. **Lighting preview** shares the verified 672×226 physical canvas, 84-key
   geometry, and exact `lightIndex` mapping with Keymap. A SwiftUI
   `TimelineView` drives a project-authored approximation locally. Reactive
   modes 2, 3, 13, 14, and 15 accept key clicks or simulated input inside the
   preview; neither path calls HID transport or sends a command to the device.
9. **Confirmed device operations** share one typed, serial Feature state machine
   but require a distinct authorization for each operation. The enabled set is
   limited to clock synchronization, one currently selected onboard lighting
   mode in `0...19`, and a complete 84-key RGB table. Values are never applied
   merely by editing or saving a local profile.

The device core contains a concrete direct-`GetReport` adapter, one narrow F5
RGB query adapter, and one typed adapter for the three confirmed operations.
They target only the wired `0x0C45:0x800A`, revision `0x0115`, FF13 Feature
collection after validating the complete four-collection topology. The typed
write state machine paces its steps by 35ms, each asynchronous Feature operation
has a 360ms timeout, and every ACK-required stage accepts only a 64-byte
response whose byte 3 signals success. There is no automatic retry, output
report, raw-payload API,
persistence, or raw report logging. The trace surface remains decode-only and
isolated from live HID access. Normal automated tests use synthetic values
without connected hardware.

## Verified wired observation

On 2026-08-09, one explicitly initiated transaction completed on the exact
wired identity above. The four required collections were:

| Usage page / usage | Input | Output | Feature |
| --- | ---: | ---: | ---: |
| `0x0001 / 0x0006` | 8 | 1 | 0 |
| `0x000C / 0x0001` | 16 | 1 | 1 |
| `0xFF13 / 0x0001` | 64 | 64 | 64 |
| `0xFF68 / 0x0061` | 64 | 4096 | 0 |

All nine 64-byte response reports passed validation and produced 84 RGB entries.
The first run returned zero for every channel. The user separately identified
the keyboard's next selection as mode 14, named `Launch` in both the Windows
resource and KeyCanvas. One query after that change returned nonzero colors
for all 84 keys with 24 distinct RGB values. This establishes that the buffer
changes with current lighting state, but the response itself has no mode ID and
one instantaneous snapshot cannot establish the firmware's motion formula,
effect direction, brightness, or speed. The device remained enumerated after
both runs, and no disconnect was observed.

Separate opt-in runs on 2026-08-09 completed the corrected clock transaction,
onboard `Static` (1), onboard `Launch` (14), and one complete 84-key RGB apply
on the exact wired target. Required acknowledgements and the four-collection
postflight check passed. The RGB query preserved all 84 key assignments after
the write, but returned three brightness-adjusted colors at level 3 rather than
the original RGB bytes. This supports an output-buffer interpretation; it is
not proof of byte-exact stored-table readback or automatic rollback.

The animated Lighting view therefore does not claim pixel- or time-exact
firmware reproduction. Its mode names, ordering, capabilities, and spatial key
mapping are based on the separately verified facts above; its temporal motion
is an original visualization that can be replaced as bounded observations make
individual effects reproducible. Preview animation, clicks, and simulated
inputs remain presentation-only and never trigger the RGB query or any other
device operation.

## Trust and data boundaries

- Device strings and registry properties are untrusted display data.
- Raw report bytes are transient and must not be persisted, logged, exported,
  or copied into a local profile by the diagnostic path.
- Imported profiles are untrusted and remain local unless the user explicitly
  exports a file or separately confirms one supported lighting operation. Saving
  or selecting a profile never transmits it automatically.
- Imported traces are untrusted. Strict keys, indices, provenance assertions,
  timestamps, payload lengths, aggregate size, and hexadecimal encoding are
  validated before analysis.
- Provenance origin is `synthetic` or `authorized-private-observation`; the four
  authorization and sanitization assertions must be true. They are attestations,
  not proof.
- The first provided relative timestamp is zero, later values are
  nondecreasing, and all are within one hour.
- Human and JSON output omit labels, individual and boundary timestamps, and
  observed bytes. They may report duration, structure, lengths and changed byte
  offsets.
- No vendor executable, firmware, UI, logo, or asset is a dependency, and the
  package has no third-party source dependency or required network service.

## Write policy

Hardware-setting writes remain default-deny. A write begins only after an
operation-specific confirmation creates an authorization of the same kind. The
adapter rejects a different authorization, an ambiguous collection, any target
other than the exact wired revision above, incomplete 84-key RGB input, and
out-of-range lighting or clock values. It also verifies the exact topology again
after the session closes.

The allowlist contains only:

- the current local date and time for the first clock slot;
- one selected onboard lighting value in mode `0...19`; and
- brightness plus all 84 verified per-key RGB positions exactly once.

The state machine waits 35ms before each Feature SET and before every required
ACK GET. Each asynchronous operation is limited to 360ms; an ACK is accepted
only when its 64-byte response has byte 3 equal to the success value. Any error
ends the attempt without retry. There is no output-report path and no LCD,
keymap, macro, firmware, or bootloader operation.

An ACK does not provide an exact state backup. The device exposes no implemented
readback for onboard mode, brightness, speed, direction, or clock values, so the
app cannot promise automatic rollback to the previous setting. Only the full
84-key RGB buffer has the separate, confirmed F5 query path. It is not a general
settings readback command.

Any additional settings transport requires separate security and device-safety
review, remains disabled by default, requires explicit user action, and needs
target, range, cancellation, error-handling, and recovery tests. The current
allowlist is not precedent for an arbitrary selector or payload.

Firmware updating, bootloader access, flashing, extraction, and payload
distribution remain outside the repository's design scope.

## Automated enforcement

CI builds and tests the Swift package on macOS. The repository scan invokes the
HID API boundary check, which permits SetReport only in the reviewed F5 query
adapter and typed verified-operation adapter and continues to reject
output-report writes, device-value writes, and interface seizure. The scan also
rejects firmware, executables, archives, unreviewed binary and visual assets,
raw-capture paths and extensions,
and all tracked JSON without an exact reviewed allowlist entry. Checks supplement
review; they do not establish provenance or legal rights.
