# KeyCanvas design and safety boundaries

KeyCanvas separates original presentation, local authoring, observable device
metadata, narrowly typed device operations and private interoperability
research. See [CLEAN_ROOM.md](CLEAN_ROOM.md) for the public/private source
boundary; this is not presented as a strict two-team clean-room project.

## Current architecture

1. **Discovery** uses documented macOS HID APIs to match devices and copy public
   registry properties without opening a device.
2. **Classification** is a pure transformation of observable metadata. Unknown
   combinations remain unknown.
3. **Presentation** is an original SwiftUI app and command-line renderer using
   system components and project-authored visuals.
4. **Local profiles** store editor values in Application Support. Selecting,
   editing or saving a profile does not call device transport.
5. **Display authoring** uses one inline workspace for bounded local
   PNG/JPEG/GIF and movie input. Images open directly; a movie first selects a
   time range and integer frame rate, then enters the same frame editor. It
   edits order, delay, crop/fit/fill/stretch, simple project-authored bitmap text
   and pen strokes, and exports an edited GIF. The visible output is always the
   exact 240×135 (16:9) device canvas; library/study and device-recovery tools
   remain collapsed secondary panels. The independent device-container encoder
   composites opaque 240×135 frames, writes little-endian RGB565 after a
   256-byte header, and pads exact 4,096-byte pages with `0xFF`. Source delays
   must be `0...511` ms and the encoder rejects byte wrapping. The 140-frame and
   2,215-page limits are host-side software ceilings, not proven physical flash
   boundaries. Editing and file export perform no HID I/O. Image/GIF storage
   uses the exact immutable bytes that were inspected. Video is copied from a
   nonblocking no-follow regular-file descriptor to a private snapshot, forbids
   referenced media, validates every track, and applies raw and retained decode
   work limits before the snapshot can enter the editor.
6. **Offline trace analysis** decodes a deliberately selected, size-limited
   JSON file and performs pure summary and comparison. It does not capture,
   hook, replay, communicate with hardware, upload input or infer commands.
7. **Explicit direct report probing** opens one exact vendor collection with
   `kIOHIDOptionsTypeNone`, performs one `GetReport` away from the main actor,
   and closes it. It sends no selector or `SetReport`, persists no raw report,
   and never retries automatically.
8. **Bounded per-key RGB querying** is a separate confirmed path for the exact
   wired identity and four verified collections. It sends only the allowlisted
   F5 query and finish Feature commands, validates nine 64-byte responses, and
   keeps 84 parsed RGB values in memory.
9. **Lighting preview** shares Keymap's 672×226 physical canvas, 84-key geometry
   and verified `lightIndex` mapping. A local integer state machine independently
   implements minimum movement-topology and reactive-event facts; overlapping
   down/up events remain ordered. Presentation pacing, brightness/color curves,
   palette seed and optics are project-authored. Clicks and deterministic demo
   input never call HID transport.
10. **Confirmed Feature operations** share one typed, serialized state machine.
    Separate one-use authorizations permit the first clock slot, one selected
    onboard mode in `0...19`, or one complete 84-key RGB table. Local edits are
    not authorization.
11. **Default-restore inspection** is a pure, non-executable dry-run risk model
    for function settings, per-key RGB and onboard lighting. It exposes only
    operation/ACK counts and page-risk counts; raw steps and default payload
    bytes are absent. Base/Fn keymaps, macros and LCD are visibly blocked
    instead of silently skipped. No StudioModel or HID adapter path can execute
    this model.
12. **LCD transport** has narrowly typed state machines, immutable plans,
    synthetic mock-session tests and one concrete default-off macOS adapter. Its
    bootstrap accepts only one project-authored 240×135 four-corner frame with
    an exact container hash and 16 pages. A separate Core-owned durable receipt
    may qualify only the current editor's immutable 1...40-frame plan after the
    ordered visual and USB cable-removal recovery evidence. Physical partition
    bounds, readback, backup and rollback remain unverified.
13. **Durable transaction quarantine** arms a target-specific marker before the
    first HID report call of an F5 query, confirmed Feature write or LCD
    diagnostic. A failure after submission or unconfirmed cancellation keeps
    the marker across relaunches and blocks later operations for that target. No
    raw report is stored.

The public package has no third-party source dependency or required network
service. Normal automated tests use only project-authored synthetic values and
do not require hardware, vendor software or firmware.

## Verified wired observations

On 2026-08-09, explicitly initiated operations targeted wired USB
`0x0C45:0x800A`, product `Archon AK47`, `bcdDevice 0x0115`. Its required
collection topology was:

| Usage page / usage | Input | Output | Feature |
| --- | ---: | ---: | ---: |
| `0x0001 / 0x0006` | 8 | 1 | 0 |
| `0x000C / 0x0001` | 16 | 1 | 1 |
| `0xFF13 / 0x0001` | 64 | 64 | 64 |
| `0xFF68 / 0x0061` | 64 | 4096 | 0 |

Two confirmed F5 queries each returned nine valid 64-byte responses and 84 RGB
entries. The first result contained zero for every channel. After the user
selected mode 14 (`Launch`), one later snapshot contained nonzero colors for all
84 keys and 24 distinct RGB values. The response has no mode ID and a single
snapshot cannot establish motion, direction, brightness or speed. No disconnect
was observed.

Separate opt-in runs completed the corrected clock transaction, onboard
`Static` (1), onboard `Launch` (14), and one complete 84-key RGB apply. Required
ACKs and four-collection postflight checks passed. F5 preserved all key
assignments after the RGB write but returned brightness-adjusted colors at level
3 instead of the submitted bytes. F5 is therefore not byte-exact stored-table
backup or rollback evidence.

No macOS LCD upload had been validated by those 2026-08-09 observations. A
direct 4,096-byte LCD output `GET_REPORT` stalled, so the app cannot read or
back up the current LCD content. The physical external-flash partition boundary
and a rollback path remain unknown.

On 2026-08-11, authorized-private Windows success captures from a lawfully
controlled exact `bcdDevice 0x0115` unit established the minimum LCD wire facts:
the unique FF13 64-byte command collection and FF68 4,096-byte-output/64-byte-
input collection, ordered setup, an expected input report after each completed
4,096-byte Output, and final commit. One-, two- and three-frame transfers
completed in that Windows environment. The private captures, identifiers and
payloads are excluded from this repository; public tests use only the
independently authored diagnostic fixture.

Those Windows observations associated FF13 with interface `MI_03`, FF68 with
`MI_02`, interrupt OUT endpoint `0x03` and interrupt IN endpoint `0x84`. On
macOS, descriptor selection is followed by a direct IORegistry ancestry check:
FF13 must resolve to `bInterfaceNumber 3`, FF68 to `bInterfaceNumber 2`, and
both must share the same exact physical USB parent/identity. IOHID does not
select or directly observe numeric endpoint `0x03` or `0x84`. The adapter's
existence is not a successful macOS hardware observation; that claim requires
an explicit user trial in which 16 completed Outputs each elicit the expected
input-report sequence and the visible result is recorded.

The non-executable default-restore plan statically accounts for seven inferred
internal-flash erase/program transactions across four distinct pages. This
count is a protocol-derived preflight estimate, not a measurement of physical
flash. A private firmware-backed handler harness does not verify the physical
side effect of the global-persistence helper and is not part of this repository.

## Approximation and implementation claims

Lighting mode names, ordering and control capabilities are compatibility facts.
The preview also independently implements minimum functional facts about each
mode's movement topology, persistent state and reactive input behavior. It does
not execute or embed firmware. Its monotonic 30 Hz presentation scheduler,
absolute pacing, intensity/color curves, deterministic palette seed and optical
rendering are original visualization choices, so it does not claim pixel-,
wall-clock- or revision-exact firmware reproduction.

The RGB565 display encoder implements a bounded container format independently.
Passing its structural validation proves only that the local file matches those
rules. It does not prove that a particular keyboard has enough physical flash,
that every firmware version interprets the file identically, or that an
interrupted transfer can be recovered.

The only live diagnostic fixture is a 240×135 black frame with 32×32 red,
green, blue and white corner blocks. Its 16-page encoded container has SHA-256
`312f98fd023d49711f73a677895b1bf48ac246c7dd687c813ed5642f42128bec`.
That asymmetric project-authored image diagnoses orientation, channel and byte-
order mistakes without copying a vendor asset.

Private firmware and a firmware-backed emulator may be used only outside this
repository under [CLEAN_ROOM.md](CLEAN_ROOM.md). Public source and tests contain
independently restated functional facts and synthetic bytes, not vendor code,
firmware, assets or execution traces.

## Trust and data boundaries

- Device strings and registry properties are untrusted display data.
- Raw report bytes are transient and are not persisted, logged, exported or
  copied into a profile by diagnostics.
- Imported profiles and images are untrusted and remain local unless the user
  explicitly exports a file. Saving or selecting them never transmits data.
- Imported traces are untrusted. Strict keys, provenance assertions, indices,
  timing, payload and aggregate-size limits are validated before analysis.
- Human and JSON trace output omits labels, individual and boundary timestamps,
  and observed bytes. It may report duration, structure, lengths and changed
  byte offsets.
- No vendor executable, firmware, UI, logo, default GIF or other asset is a
  dependency or permitted repository content.
- The quarantine marker stores the matching target's VID/PID, product,
  location, revision and optional serial locally in Application Support. It
  contains no report bytes, settings or user content.

## Executable device-write policy

Hardware-setting writes are default-deny. A write begins only after an exact
target preflight and an operation-specific, one-use authorization. The adapters
reject a different authorization, ambiguous collections, any target other than
the exact wired revision, incomplete 84-key input and out-of-range values. They
serialize device access and verify the topology again after the session.

The executable Feature allowlist contains:

- current local date and time for the first clock slot;
- one selected onboard lighting value in `0...19`;
- brightness plus all 84 verified per-key RGB positions exactly once.

Feature steps use 35 ms pacing and bounded asynchronous operations. Required
64-byte ACKs must report success in byte 3. Any error ends the attempt without
automatic retry. ACK receipt is not state readback and does not make a partial
write atomic.

The file lock prevents concurrent KeyCanvas processes, not unrelated software.
The FF13 collection is deliberately opened non-exclusively, so a vendor utility,
Windows VM, debugger or other HID client can interleave traffic. The confirmation
boundary requires the user to stop those clients before F5, clock, lighting,
RGB or LCD diagnostic work; the app cannot enforce that condition outside its
own processes.

The write-ahead marker is saved before the first report submission. A complete
transaction plus postflight, or verified pre-submission cleanup with no report,
may clear its active identities. Clearing first writes the old identities to a
durable sibling `.pending-clear` record, writes `[]` as a durable receipt in the
primary `~/Library/Application Support/KeyCanvas/ak47-device-quarantine-v1.json`,
then removes and synchronizes the staged record. Loading uses the union of both
files. If staged-record removal or directory synchronization fails, the old
identities are restored to the staged record and the caller receives an error.
Atomic replacement, file/directory `fsync`, no-follow directory opens and
restrictive local permissions reduce marker-loss risk; absolute storage failure
cannot be eliminated. If marker state cannot be loaded or saved, the process
refuses later HID operations.

Recovery is deliberately not an app restart or an automatically detected
replug. In one process, Device Inspector must successfully enumerate the marked
target as absent, then enumerate the same identity with the exact expected four
collections. Only then may a separate user acknowledgement that the keyboard
selector remained in USB mode while cable removal fully powered down the LCD,
LEDs and device before reconnection at the original USB location enter the same
staged durable clear sequence. Switching to 2.4G or Bluetooth is not recovery.
Relaunching keeps active quarantine state but loses those
observations, so both must be repeated. The application cannot verify electrical
power removal; it records a conservative enumeration sequence plus the user's
explicit statement. Deleting the primary or staged state can bypass the guard
but cannot restore hardware state.
When no serial number is available, exact reappearance requires the original
USB location; meanwhile the marker conservatively blocks every otherwise
compatible AK47 because a second physical unit cannot be distinguished safely.

The default-restore dry run is not part of this executable allowlist. It cannot
be applied from the public app and is not a complete factory reset. A live
implementation would have no verified backup or rollback and could leave a
partially changed subset, so it remains an inspection-only model.

The separate default-off LCD bootstrap is not a general content-write allowlist.
A matching one-use authorization binds the exact target and fixed fixture after
four risk acknowledgements and a separate destructive confirmation. Before any
HID path, Core also claims a durable canonical-transfer lease. The adapter opens
one unique FF13 command and FF68 bulk collection non-exclusively, rejects any
other bootstrap hash/frame/page count, submits exactly 16 Output reports, and
requires each completed Output to elicit one valid 64-byte input report before
continuing. It never retries and performs an exact four-collection postflight.

A successful canonical host transaction creates only the next durable receipt
state. Qualification additionally requires the user's exact visible-corner
attestation, a real enumeration observing absence after cable removal in USB
mode, the same target's exact four collections reappearing at the original USB
location, and the final statement that cable removal visibly powered down the
LCD, LEDs and device. These transitions persist after every step. The production
store starts empty; an earlier trial, application preference, checkbox or absent
quarantine marker cannot import, backfill or synthesize authority. Receipt load
or save failure is fail-closed.

Once qualified, the editor copies its current in-memory project as a value and
Core encodes only that immutable 1...40-frame snapshot with the qualified
2,592,768-byte budget. The final sheet displays the exact target, frame/page/
byte counts, address range, SHA-256 and delay conversion before creating a
single-use plan authorization. The adapter revalidates the same limits and
claims a target-and-plan-bound durable lease before opening HID. Later editor or
library changes cannot alter the submitted bytes. More than 40 frames is
rejected without truncation or force.

Neither path has content readback, backup, rollback or resume. The durable
write-ahead quarantine is armed before its first report, and uncertain submitted
state requires the same ordered USB-selector-held, cable-removal/unpowered
recovery flow used by the other device operations.

Native IOHID report ID `0` is supplied separately from the exact 64-byte
Feature/Input and 4,096-byte Output buffers; there is no host-side leading
report-ID byte. Command stages retain 35 ms pacing, async report calls have a
360 ms bound and each post-Output input wait has a 300 ms bound. The input must
have report ID `0`, exact 64-byte length and prefix `01 5A 02`. A failed Output
or mismatched input stops before commit. No retry, resume, extra `0xF0` finalize
or commit-on-failure path exists.

All 16 expected sequences establish only that each completed Output elicited an
input report with the expected ID, length and prefix. The reports contain no
page index and do not establish page acceptance, read the LCD back, validate
external-flash contents, confirm visible colors or orientation, or prove a
larger capacity. The adapter holds a process activity to reduce idle sleep and
automatic termination, but power loss, forced quit, user-initiated
sleep/shutdown and another nonexclusive HID client remain residual risks.

The 140-frame/2,215-page software ceiling applies only to offline encoding and
must never be described as a verified partition end or live limit. The live
bootstrap maximum is one fixed frame; the separately qualified maximum is 40.
The latter remains unreachable until the fresh ordered receipt above is
complete. A qualified host transfer does not immediately restore authority:
Core persists the submitted digest/frame/page identity in a visual-review-
pending state. The UI decodes the exact submitted RGB565 container bytes for
comparison with the actual LCD. Only an exact-match attestation bound to that
identity reopens qualification. Wrong or unverifiable output moves through a
retryable mismatch-pending state, arms durable device quarantine and invalidates
qualification. If relaunch loses the immutable expected preview, positive
attestation is unavailable; only mismatch/recovery remains.

If a canonical or qualified lease survives app termination or another
interruption, it blocks all other live operations. The user-visible reconcile
action warns the user to stop if another KeyCanvas process is still transferring.
Core first persists an interrupted-quarantine-pending phase, revokes local gate
admission, arms the exact target's shared durable marker and only then records
invalidated qualification. Any persistence failure leaves a retryable pending
state rather than clearing the lease or inferring success.

No public API exposes arbitrary raw payloads. There is no interface seizure,
keymap/macro write, firmware update, bootloader access, extraction, flashing or
payload distribution. Any new selector or device-changing operation requires a
separate security review, default-off behavior, explicit user action and
synthetic boundary tests.

## Automated enforcement

CI builds and tests the Swift package on macOS. The repository scan rejects
firmware, executables, archives, unreviewed binary and visual assets, raw
captures, analysis/vendor directories and unallowlisted JSON.

The HID boundary check allows `IOHIDDeviceSetReport` only in the F5 query
adapter, the typed Feature-write adapter and the fixed-fixture LCD diagnostic
adapter. The first two may use Feature reports only; the LCD adapter has the
single reviewed Output-report call site. Value writes, transactions, queues,
arbitrary report sites and interface seizure remain forbidden in source. These
checks
supplement human review and do not establish provenance, legal rights, hardware
safety or recovery correctness.
