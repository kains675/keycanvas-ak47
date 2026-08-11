# KeyCanvas source and interoperability boundary

This file keeps its historical `CLEAN_ROOM.md` name, but KeyCanvas does not
claim a strict two-team clean-room process. Some minimum functional facts were
obtained through local interoperability analysis of hardware and software that
an authorized contributor lawfully possessed, then restated independently for
the public implementation. The public repository must contain only original
source, original UI and independently constructed tests: never copied vendor
code, binary regions, media or a firmware-backed emulator.

This boundary applies to every contribution, whether commercial or
noncommercial. It is a project policy, not a conclusion that a particular act
of analysis or distribution is lawful in every jurisdiction. Contributors are
responsible for complying with applicable law and the terms governing material
they use.

## Acceptable public implementation inputs

A compatibility claim or implementation may be based on:

- public platform documentation and public technical standards;
- reproducible observations made through ordinary use of lawfully controlled
  hardware;
- minimum, functional interoperability facts independently restated after an
  authorized local analysis;
- facts from an explicitly initiated, narrowly bounded device query or
  operation that follows the device-safety rules below; and
- project-authored fixtures and synthetic tests.

Record the public source or reproducible procedure when practical. A retained
fact should describe only behavior needed for interoperability, such as a
dimension, range, field meaning, simple field encoding, marker/default constant,
required ordering or state transition. A functional rule may be implemented
independently when compatibility requires it. Do not copy source code,
substantial expressive algorithms, wholesale vendor tables, prose, UI
structure, artwork or other protected expression.
Before a firmware- or executable-informed fact enters public code or
documentation, another contributor should review that it is minimal,
independently expressed and covered by synthetic tests.

## Material prohibited from the public project

Never commit, upload, attach, paste or publish any of the following in this
repository, its Issues, pull requests, Discussions, security reports, Actions
logs or artifacts, or Releases:

- vendor firmware, update payloads, firmware tools, executables, installers,
  libraries, archives, disk images, or extracted contents;
- decompiled or disassembled listings, reconstructed vendor source, symbol
  maps, wholesale vendor lookup tables, or copied implementation algorithms;
- a private firmware-backed emulator, its firmware image, instruction traces,
  memory dumps, or results that reproduce vendor binary code/data regions;
- packet captures, HID report streams, USB monitoring logs, device dumps, or
  derivatives that preserve captured payload bytes;
- vendor logos, icons, screenshots, interface layouts, fonts, sounds, default
  GIFs, animations, or other product assets;
- leaked, confidential, access-controlled, trade-secret or NDA material; or
- anything whose provenance, authorized use or redistribution rights are not
  established.

A file being publicly downloadable does not make it redistributable. Hashing,
trimming, redacting, re-encoding or reformatting prohibited bytes does not turn
them into a public test fixture.

## Local interoperability analysis

An authorized contributor may keep lawfully obtained vendor material and a
firmware-backed test harness in access-controlled local storage outside the
repository. That private workspace must not be a package dependency, CI input,
release input or prerequisite for a public test. Do not upload it to a private
GitHub report as a workaround.

Only the minimum functional conclusions needed for compatibility may cross
into the public project. Restate them without copied binary regions or
expressive details, and validate the resulting public implementation with newly
constructed synthetic fixtures. A fixture may independently encode a minimal
field constant, default marker or required command ordering; it must not be a
trimmed/reformatted capture, unexplained bulk payload or extracted binary data.
Public tests must not execute, embed, fetch or reconstruct vendor firmware.
Private emulator success is evidence about the modeled handlers only; it is not
hardware validation, proof of physical flash behavior, or a recovery guarantee.

## Authorized private observations and offline traces

An authorized contributor may also make a raw observation from hardware and
software they lawfully control and keep it locally for analysis. Raw captures
must remain access-controlled and be deleted when no longer needed. They may
not be shared with the public implementation as captured payload bytes.

The repository's trace analyzer is offline, file-based and decode-only. It
must not capture live traffic, hook another program, decrypt protected traffic,
replay or inject reports, communicate with a device, upload input, or encode a
trace document.

Every accepted trace document contains a strict `provenance` object. Its
`origin` is `synthetic` or `authorized-private-observation`, and
`authorizedUse`, `identifiersRemoved`, `absoluteTimestampsRemoved`, and
`firmwareTrafficExcluded` must all be `true`. These fields are attestations,
not automated proof of rights or sanitization.

Sanitization removes serial and location identifiers, host and user names,
paths, absolute timestamps, real keystrokes, macros and profile names,
credentials, tokens, cryptographic material, third-party UI or media data,
firmware, updater or bootloader traffic, and unexplained bulk payloads. Public
repository test data is always newly and independently constructed. It may
exercise independently restated functional protocol rules, but must not be
derived by copying or transforming a captured stream and must not include real
identifiers, user data, unexplained payload regions or extracted firmware data.

Trace timestamps are optional. If present, the first supplied value is zero,
later values are nondecreasing, and no value exceeds one hour. Human and JSON
output omit input labels, individual timestamps, boundary timestamps and
observed byte values. A derived duration and changed-byte offsets are allowed.

## Independent presentation

The user interface is an original macOS design made from project-authored
components, standard system controls and properly licensed platform symbols.
Do not trace or recreate a third party's distinctive layout, trade dress,
branding or assets.

Third-party names and marks are used only when necessary to identify factual
compatibility. They must not appear in the project name, logo or application
icon, or imply sponsorship or affiliation.

## Device-safety boundary

Normal discovery and diagnostics enumerate devices, read public registry
metadata, or perform an explicitly initiated `GetReport` on an exact vendor
collection. The reviewed F5 exception may query only the current 84-key RGB
buffer after a separate confirmation; it is not general settings readback.

The executable Feature-operation allowlist contains only:

- clock synchronization for the first clock slot;
- one selected onboard lighting mode in `0...19`;
- brightness and a complete 84-position per-key RGB table.

A separate, default-off LCD bootstrap exception permits only the project's fixed
one-frame fixture: an opaque 240×135 black image with 32×32 red, green, blue and
white corner blocks. Its encoded container is exactly 16 pages of 4,096 bytes
and has SHA-256
`312f98fd023d49711f73a677895b1bf48ac246c7dd687c813ed5642f42128bec`.
The bootstrap adapter must reject every other image, hash, frame count, page
count and payload.

Policy v2 keeps the general qualified path locked after the canonical receipt.
It first accepts only an immutable, currently edited, exact 140-frame/2,215-page
boundary value. The receipt must begin with a fresh canonical transfer under the
receipt-enabled build, a separate visible-corner attestation, observed USB
disconnection, exact same-location/four-collection reappearance, and an explicit
statement that cable removal visibly unpowered the LCD, LEDs and device. A
validated exact v1 qualified receipt may migrate only that canonical and ordered
recovery provenance into policy v2's boundary-waiting state; it cannot migrate
140-frame success authority. Earlier evidence-only trials cannot be imported or
backfilled. A one-use authorization binds the exact target, encoded SHA-256,
frame/page/byte counts and address range shown by the UI. This remains a typed
project-content path, not a raw-payload API.

Boundary host completion is not qualification. The user must compare the actual
LCD against the exact submitted RGB565 preview, then repeat USB-mode cable
removal, real absence, same-port exact-four reappearance and the unpowered
attestation. Only that full sequence unlocks ordinary immutable 1...140-frame
plans for the exact target. The production KeyCanvas trial completed this full
sequence: 2,215 expected input sequences, commit and exact postflight passed;
full playback, loop, color and frame order matched; cable removal produced real
absence; same-port reconnection produced exactly four collections; and the
animation persisted. Its policy-v2 receipt is qualified for 140 frames.

The repository also contains a pure, non-executable dry-run risk model for
three categories: function settings, per-key RGB and onboard lighting. It
exposes only operation/ACK counts and page-risk counts, never raw steps or
default payload bytes. Base/Fn keymaps, macros and LCD remain visibly blocked.
Its preflight describes seven
statically inferred internal-flash erase/program transactions across four
distinct pages. The private emulator does not verify the
global-persistence helper's physical side effect. Because complete backup and
rollback are unavailable, the public app does not expose a live restore path;
the model must not be described as a complete factory reset or recovery tool.

Every query or executable write must match wired USB `0x0C45:0x800A`, product
`Archon AK47`, `bcdDevice 0x0115`, and the complete expected four-collection
topology. The LCD diagnostic additionally requires exactly one FF13 command
collection with 64-byte input/output/Feature reports and exactly one FF68 bulk
collection with 64-byte input and 4,096-byte output reports. Operations use
`kIOHIDOptionsTypeNone`, reject ambiguous matches, serialize access, close
promptly and verify topology again after a write.
Feature steps use 35 ms pacing, bounded asynchronous operations and required
64-byte ACK validation. Errors end the attempt without automatic retry.
The process lock serializes KeyCanvas instances only. Because FF13 is opened
non-exclusively, a vendor utility, Windows VM, debugger or other HID client can
still intervene; all such clients must be fully stopped before the user confirms
an F5, Feature or LCD diagnostic operation.

Before the first HID report call in the confirmed F5, Feature-write or LCD
diagnostic transaction, the app must durably arm a target-specific write-ahead
marker at
`~/Library/Application Support/KeyCanvas/ak47-device-quarantine-v1.json`.
The marker stores only the target identity, never report contents. Clearing is
staged in a sibling `.pending-clear` identity record; loading uses the union of
both files, and a successful clear leaves a durable `[]` receipt in the primary.
If marker state cannot be atomically saved and synchronized, no report is
submitted and the process remains fail-closed. A submitted report followed by
failure, unconfirmed cancellation or failed postflight keeps the marker across
app relaunches; it indicates uncertain state, not a backup or rollback record.

A marker retained because transaction state is uncertain may enter that staged
durable clear sequence through the recovery UI only after a successful hardware
enumeration observes the marked target completely absent, a later enumeration
sees the same identity with the exact four-collection topology, and the user
explicitly confirms that the selector stayed in USB mode while the cable was
disconnected until the LCD, LEDs and device fully powered down, before wired
power was restored at the original USB location. Moving the selector to 2.4G
or Bluetooth is not recovery. These
absence/reappearance observations are process-local and must be repeated after
relaunch. The app cannot electrically verify the user's power-removal statement.
Without a serial number, exact reappearance requires the original USB location,
while the active marker conservatively blocks every otherwise compatible AK47.
Deleting the marker or application data is not device recovery and must not be
presented as one.

The project contains an independently written 240×135 GIF editor, RGB565
container encoder and narrowly typed LCD transport. Authorized-private Windows
success observations on a lawfully controlled `bcdDevice 0x0115` unit
established only the minimum ordering, report lengths, completed-Output/input-
report sequences and descriptor roles needed for interoperability. The raw
captures and their payloads remain private and are not public fixtures.

The concrete macOS adapter remains default-off. Its bootstrap path accepts only
the fixed project-authored fixture above after an exact-target preflight, one
explicit experimental-feature risk acknowledgement and a matching one-use
destructive Apply. Its qualified path uses the same single acknowledgement and
independently requires the completed durable receipt plus an exact one-use
editor-snapshot authorization. Both submit each
page once, require the completed Output to elicit one valid 64-byte input report
before continuing, perform no automatic retry and provide no readback, backup
or rollback. Any submitted-but-uncertain transaction remains under the durable
quarantine and wired-power-removal recovery rules above. Input reports have no
page index and do not prove flash persistence.

The private Windows observation associated FF13 with interface `MI_03`, FF68
with `MI_02`, USB endpoint `0x03` with output and `0x84` with input. On macOS,
the adapter directly verifies IORegistry ancestry: FF13 must resolve to
`bInterfaceNumber 3`, FF68 to `bInterfaceNumber 2`, and both must share the same
exact physical USB parent and identity. IOHID does not select or observe the
numeric `0x03`/`0x84` endpoints. Each of 16 completed Output calls must elicit
the expected input-report sequence, followed by exact postflight; this must not
be described as a direct macOS endpoint capture or as page/flash acceptance.

The 140-frame/2,215-page host-format ceiling is not a proven physical boundary.
Policy v2 exposes it only through the exact boundary trial above; a completed
host sequence alone never creates live allowance. The production store is
fail-closed. Boundary and later qualified host sequences finish in a durable
visual-review-pending state. The user must compare the retained immutable
expected animation with the actual LCD. Wrong or unverifiable output revokes
authority and arms durable quarantine. Relaunching without the expected preview
cannot create a positive attestation.

The successful production KeyCanvas result is distinct from the separate
authorized-private Windows observations. Neither result provides LCD readback,
an ACK-carried page index, physical-partition proof or rollback.

A canonical or qualified transfer lease that survives interruption is never
cleared or restored to success. While no other transfer process is active, the
UI may call the target-bound reconciliation API; it first persists an
interrupted-quarantine-pending phase, then retries the shared durable marker and
ends with invalidated qualification. The pending phase is idempotent across
relaunch, blocks other device operations and exposes no manual clear.

No executable path may expose arbitrary raw payloads, send 41...139 frames before
final policy-v2 qualification, exceed 140 frames, seize an interface, write
keymaps or macros, or read, update, extract, flash or distribute firmware or
bootloader state. Raw report bytes must
not be persisted or logged. Any broader LCD selector, readback or write requires
a separate design and safety review, default-off behavior, unambiguous user
action, an auditable typed interface and synthetic boundary tests.
