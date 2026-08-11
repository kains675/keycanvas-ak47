# KeyCanvas security policy

## Supported scope

Security fixes target the latest revision on the default branch. Older
snapshots and downstream forks may not receive fixes.

Normal discovery and direct report diagnostics are read-only. Every executable
device-changing action first matches wired USB `0x0C45:0x800A`, product
`Archon AK47`, `bcdDevice 0x0115`, the complete expected four-collection
topology and the FF13 command collection. Each action needs its own explicit
confirmation and a matching one-use typed authorization.

The executable Feature-operation allowlist is limited to:

- synchronizing the first clock slot to the Mac's current local time;
- applying one selected onboard lighting mode in `0...19`;
- applying brightness and all 84 verified RGB positions exactly once.

A separate experimental LCD transport is present but default-off. Its bootstrap
accepts only the project-authored 240×135 black four-corner diagnostic fixture
whose encoded container is exactly one frame, 16×4,096-byte pages and SHA-256
`312f98fd023d49711f73a677895b1bf48ac246c7dd687c813ed5642f42128bec`.
Every other bootstrap image, hash, frame count, page count or arbitrary payload
is rejected. After a fresh Core-owned durable qualification sequence, a separate
path accepts only an immutable current-editor plan of 1...40 frames. The exact
target, both unique FF13/FF68 collection roles, durable lease and matching one-
use plan authorization are revalidated before submission. Visible risk
acknowledgements cover overwrite, missing readback/rollback, other-client
shutdown and prepared USB-mode cable-removal recovery; a separate final
destructive confirmation creates each one-use authorization.

The repository can inspect a pure dry-run risk model for function settings,
per-key RGB and onboard lighting. It exposes counts and page-risk metadata only,
without raw steps or default payload bytes. It has no live adapter or
StudioModel execution path and is not part of the allowlist above. Base/Fn
keymaps, macros and LCD content are visibly blocked. Its model reports seven
inferred internal-flash erase/program transactions
across four distinct pages based on static analysis; the physical effect of the
global-persistence helper has not been validated by the private emulator or
on-device flash readback. It must not be presented as a complete factory reset,
firmware recovery or safe executable restore.

The separate F5 query also requires confirmation and reads only the current
84-key RGB buffer. It does not read the current mode, brightness, speed,
direction, clock, keymap, LCD content, macros or general settings. Its values
may already have brightness applied and are not treated as an exact backup.

Feature steps use 35 ms pacing and bounded asynchronous operations. Required
64-byte ACKs must signal success in byte 3. Errors stop without automatic retry.
ACK validation confirms only the expected protocol response; it does not prove
the visible result, flash durability, atomicity or rollback safety.

KeyCanvas uses a file lock to serialize its own app processes only. FF13 remains
non-exclusive, so a vendor utility, Windows VM, USB/HID debugger or another
client can interleave reports without being controlled by this lock. Fully quit
those programs and VMs before confirming any F5, clock, lighting, RGB or LCD
diagnostic action.

## Partial-transaction quarantine and recovery

The F5 query, all three executable Feature-write paths and the LCD diagnostic
path arm a durable, target-specific write-ahead marker before their first HID
report call. It is
stored at
`~/Library/Application Support/KeyCanvas/ak47-device-quarantine-v1.json` using
atomic replacement, mode `0600`, and `fsync` of the file and parent directory.
Clear operations use the sibling
`ak47-device-quarantine-v1.json.pending-clear` as a staged rollback record, and
the process lock is `ak47-device-quarantine-v1.lock`. Loading takes the union of
the primary and staged identities, so either record keeps the target blocked.
When creating its parent KeyCanvas directory, the app requests mode `0700`; it
does not claim to tighten permissions on a directory that already exists. The
marker, staged record and process-lock files request mode `0600`. Storage
directories are opened without following symlinks and synchronized along with
their parent entries before use. The marker state contains only
VID/PID, product, location, revision and an optional serial; it contains no
report bytes, settings, image, macro or firmware data.

If the marker cannot be loaded or saved, the process fails closed. A save
failure before the first report means no report is submitted. Once a report has
been submitted, any transaction failure, unconfirmed cancellation or failed
postflight retains the marker because the keyboard may already be partially
changed. A fully successful transaction clears the active identities only by
first durably staging the old set, writing a durable `[]` receipt to the primary
file, then removing and synchronizing the staged record. If staged-record
removal or its directory `fsync` fails, the implementation restores the old
identities to the staged record and returns an error so relaunch still blocks
the target. A failure before any report may enter this clear sequence only after
session cancellation and exact postflight both succeed. Absolute storage or
hardware failure remains outside any software durability guarantee.

A crash between marker creation and submission can therefore leave a
conservative stale marker; this is preferable to silently forgetting a possibly
submitted transaction.

The marker persists across relaunch and is not cleared by reconnecting alone.
Recovery requires all of the following in one app process:

1. A successful Device Inspector refresh observes zero collections for the
   marked target while it is physically absent.
2. A later successful refresh observes the same target identity with the exact
   four-collection topology.
3. The user explicitly confirms that the selector remained in USB mode while
   cable removal fully powered down the LCD, LEDs and device before wired power
   was restored at the original USB location. Switching to 2.4G or Bluetooth
   does not satisfy recovery.

If the keyboard does not expose a serial number, the exact reappearance check
requires its original USB location; reconnect it to the same Mac USB port. The
active marker otherwise blocks all compatible AK47 units conservatively because
the process cannot distinguish a second physical keyboard reliably.

Relaunching loses the two in-memory observations, so the absence and exact
reappearance must be observed again. The app can verify enumeration, but cannot
electrically prove that cable removal fully powered down the LCD, LEDs and
device; the final condition is a user attestation. The marker is only an
interlock, not state readback, backup,
rollback or proof that the keyboard recovered. Deleting or editing the marker,
resetting application data, or reinstalling the app may bypass the interlock
but does not recover device state. Do not use those actions as recovery.
Closing a handle, relaunching the app, quickly reconnecting USB, or moving the
selector to 2.4G/Bluetooth is likewise not recovery.

## Display editor and bounded LCD transport boundary

The inline Display editor and RGB565 container encoder operate on bounded local
image, GIF and movie input. They produce full composited 240×135 frames, a 256-byte header and exact
4,096-byte `0xFF`-padded pages. Structurally valid output is not proof of a safe
hardware transfer.

A narrowly typed state machine, immutable plan and concrete macOS adapter exist
for the fixed diagnostic bootstrap and the separately qualified 1...40-frame
editor-snapshot path. Authorized-private successful Windows observations on the
exact `bcdDevice 0x0115` target established the minimum command ordering,
descriptor roles, report lengths and completed-Output/input-report sequence.
The private captures, vendor media and captured payloads are not repository
content.

The Windows observation associated FF13 with interface `MI_03`, FF68 with
`MI_02`, interrupt OUT endpoint `0x03` and interrupt IN endpoint `0x84`. The
macOS adapter directly walks IORegistry ancestry and requires FF13 on
`bInterfaceNumber 3`, FF68 on `bInterfaceNumber 2`, and one common exact
physical USB parent/identity. IOHID does not select or directly observe numeric
endpoint `0x03` or `0x84`. Exactly 16 completed Output calls must each elicit
the expected input-report sequence before exact postflight. This is not a macOS
endpoint capture. An evidence-only macOS trial recorded all 16 sequences,
commit, exact postflight and the user's visual confirmation of the four corner
positions and orientation. It predates the production receipt build and cannot
be imported or backfilled as authorization.

The operation consumes one exact authorization, sends 16 pages once, never
retries, and provides no current-content readback, backup, rollback or recovery
guarantee. A failure after submission, unconfirmed cancellation or failed
postflight retains durable quarantine. The ordered USB cable-removal recovery
sequence is required before treating the target as recovered.

IOHID report ID `0` is passed as a separate API argument: Feature and input
buffers are exactly 64 bytes and each Output buffer is exactly 4,096 bytes,
without a prepended report-ID byte. Command stages retain 35 ms pacing,
asynchronous report calls are bounded at 360 ms, and each post-Output input wait
is bounded at 300 ms. After a completed Output, the next input report must
have report ID `0`, exact 64-byte length and the independently restated
`01 5A 02` prefix. A mismatched, short or timed-out input stops before commit;
the adapter neither retries nor emits an additional `0xF0` finalize command.

Sixteen sequences show only that 16 completed Output calls each elicited an
input report with the expected ID, length and prefix. The input carries no page
index and is not LCD readback, page acceptance, flash-integrity evidence, proof
of visible orientation/color, or proof that 40 frames fit safely. The app
requests protection against idle system sleep and sudden/automatic termination
during the attempt, but cannot eliminate power loss, forced quit, a user-
initiated sleep/shutdown or interference from another nonexclusive HID client.

The 140-frame/2,215-page ceiling remains offline host-format behavior and must
not be treated as a physical capacity guarantee. A production receipt store
starts empty: the qualified live path remains locked until a fresh canonical
transfer records all 16 expected sequences and exact postflight, the user
confirms its visible corners, real enumeration observes USB disconnection then
the same target at the original location with exact four collections, and the
user attests that cable removal in USB mode visibly unpowered the LCD, LEDs and
device. Historical evidence cannot be imported or backfilled. Receipt load or
persistence failure remains fail-closed.

The qualified UI copies the current in-memory editor project before encoding;
later edits cannot change its plan. Its final one-use confirmation displays and
binds the exact target, frame/page/byte counts, address range, SHA-256 and delay
conversion. The adapter rejects more than 40 frames, a non-minimal padded
container, a different receipt target or plan fingerprint, and any missing or
stale qualification lease. These checks do not solve missing readback or
physical recovery.

After every qualified host transfer, Core persists a visual-review-pending
digest/frame/page identity instead of immediately reopening qualification. A
positive result is accepted only while the app retains the exact immutable
expected animation and all identities still match. A wrong or unverifiable
display result revokes qualification and arms durable operation quarantine. If
the expected preview is lost across relaunch, the UI cannot record a positive
result and offers only the mismatch/recovery path.

A durable canonical or qualified lease that remains after interruption also
blocks every other live HID operation. It is not auto-cleared. After the user
confirms no other KeyCanvas process is actually transferring, a target-bound
reconciliation saves an interrupted-quarantine-pending receipt before arming
the shared durable marker and invalidating qualification. Marker or final-
receipt failure leaves a retryable pending state; it never restores positive
authority.

Selecting, editing, saving or exporting a local profile, GIF or container never
authorizes a device write by itself. No public API exposes arbitrary raw
payloads, seizes an interface, writes keymaps or macros, or performs firmware/
bootloader operations.

## Local-file and trace boundaries

Treat imported profiles, images, GIFs, movies and traces as untrusted. Image and
GIF import uses a nonblocking no-follow descriptor, verifies a regular file,
decodes one bounded immutable byte snapshot and stores those exact bytes. Movie
import uses the same source checks, a 1 GiB source ceiling, a private local
snapshot and `forbidAll` media-reference restrictions. It checks every video
track and coded/oriented dimensions before extraction, limits source geometry
to 8,192 pixels per axis and 33,554,432 pixels, then applies the common
2,048-axis, 2-megapixel-per-frame, 32-megapixel-total and 140-frame retained
work limits. Network download and remote media references are unsupported.

Video inspection and extraction expose bounded caller deadlines and suppress
late progress or commits after cancellation. AVFoundation or a filesystem read
that never returns cannot be force-terminated in-process; a timed-out
underlying task may finish later, but its result cannot enter the editor. Media
replacement is bound to its originating profile/session and disables editor
mutation and device Apply until the immutable result commits or is cancelled.
Keep private images and imported Windows data out of bug reports unless a
minimal project-authored reproduction can replace them.

The trace analyzer is offline, file-based and decode-only. It does not perform
live capture, hook or decrypt another process, replay or inject reports, access
a device, upload input or encode trace documents. Its decoder enforces strict
keys, document/event/payload limits, provenance assertions and relative-time
limits.

Provenance assertions are not proof. Public tests use only synthetic values.
Human and JSON output omits input labels, individual and boundary timestamps,
and observed bytes; only derived duration, structure, lengths and changed-byte
offsets may be reported.

Vendor firmware, software, default GIFs, extracted assets, decompilation,
disassembly, a firmware-backed emulator, raw captures and device dumps are
prohibited repository content even in a private security report. The public
project must remain buildable and testable without them. See
[CLEAN_ROOM.md](CLEAN_ROOM.md).

## Reporting a vulnerability

Use GitHub's **Report a vulnerability** link to open a private security
advisory. If private reporting is unavailable on a fork, contact its maintainers
privately before publishing details.

Include the affected revision, macOS and Swift versions, minimal synthetic
reproduction steps, expected and actual behavior, and likely impact. For the
display pipeline, use a newly created minimal image rather than a private or
vendor asset.

Do not attach firmware, vendor software, archives, confidential protocol
material, identifiers, raw dumps or captures, credentials, private macro
content, or a firmware-backed emulator. Do not test a report by capturing,
replaying, writing to or flashing hardware.

An accidental prohibited-material upload is a security and provenance
incident. Report only its public location without reattaching the data so
maintainers can remove commits, Actions logs/artifacts and Releases, then assess
notification and rotation needs.

Nonsensitive feature requests may use the public issue tracker.
