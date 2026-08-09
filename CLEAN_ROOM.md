# KeyCanvas clean-room policy

KeyCanvas is independently developed from public information and reproducible
observations made through ordinary use of lawfully obtained hardware. This
policy applies to every contributor and every contribution, regardless of
whether the project or contribution is commercial or noncommercial.

## Acceptable inputs

A compatibility claim or implementation may be based on:

- public platform documentation and public technical standards;
- facts visible through ordinary, read-only use of documented macOS APIs;
- minimum structural facts from an explicitly authorized, narrowly bounded
  device query or operation that follows the device-safety rules below;
- minimum facts independently stated by an authorized private observer under
  the separation rules below; and
- synthetic fixtures and project-authored tests.

Record the public source or reproducible observation procedure. State facts in
your own words and contribute only material you have the right to license under
this repository's terms.

## Material that is always prohibited

The following vendor or third-party material is never acceptable as an input,
implementation reference, issue attachment, or repository content:

- vendor firmware, update payloads, firmware update tools, executables,
  installers, archives, disk images, or extracted contents;
- third-party source code or decompiled, disassembled, translated, decrypted,
  or otherwise reconstructed code;
- third-party logos, icons, artwork, screenshots, interface layouts, sounds,
  fonts, animations, or other product assets;
- leaked, confidential, access-controlled, or trade-secret information;
- material subject to an NDA, license, or other obligation that prevents its
  use or public redistribution; or
- captures or device dumps supplied by a vendor or third party, or whose lawful
  provenance and authorized use cannot be established.

The authorized-observer allowance below does not create an exception for any
of these materials. A public download is not automatically redistributable and
must not be mirrored here.

## Authorized private observation

An authorized observer may make a raw capture from hardware and software they
lawfully control and use it locally for offline analysis. This is the only raw
capture permitted by the project policy. It does not permit decompilation,
disassembly, process hooking, decryption, access-control bypass, NDA material,
confidential sources, vendor-supplied files, or third-party dumps.

Only the authorized observer may possess the raw capture. It must remain local
and access-controlled, must not be shared with implementers, and must be deleted
when it is no longer needed. Implementers receive only an independently stated
minimum-facts record and synthetic test data, never captured payload bytes.

Raw captures include packet captures, HID report streams, USB monitoring logs,
vendor-application traffic, and derivatives that preserve captured payload
bytes. Never commit or upload one to this repository, an issue, pull request,
discussion, private security report, GitHub Actions log or artifact, or release.

## Offline trace analysis

The analyzer may decode a deliberately selected, local trace file. It must not
capture or intercept live traffic, hook another program, decrypt protected
traffic, replay or inject reports, communicate with a device, upload input, or
encode a trace document.

Every accepted trace document contains a strict `provenance` object. Its
`origin` is either `synthetic` or `authorized-private-observation`, and
`authorizedUse`, `identifiersRemoved`, `absoluteTimestampsRemoved`, and
`firmwareTrafficExcluded` must all be `true`. These fields are attestations,
not automated proof of rights or sanitization.

Any public specification or implementation derived from an authorized private
observation also needs a text provenance record stating:

- that the observer controlled and was authorized to use the hardware and
  software involved;
- that no prohibited material or access-control bypass supplied the facts;
- the date, environment and observation-tool versions, relevant hardware and
  software versions, interface and traffic direction, and controlled action;
  and
- which facts were retained or transformed, the sanitization procedure, and
  who performed the second-person review.

Sanitization removes serial and location identifiers, host and user names,
paths, absolute timestamps, real keystrokes, macros and profile names,
credentials, tokens, cryptographic material, third-party UI or media data,
firmware, updater or bootloader traffic, and unexplained bulk payloads. Retain
only the minimum structural facts needed for interoperability and restate them
independently.

Repository test data must be newly constructed and synthetic. A trimmed,
redacted, encoded, hashed, or reformatted raw capture is not synthetic.
Synthetic data must contain no captured payload bytes, must not replay a real
transaction, and requires provenance and sanitization review before merge.

Trace timestamps are optional. If present, the first provided value is zero,
later provided values are nondecreasing, and no value exceeds one hour. Human
and JSON output omit input labels, individual timestamps, first and last
timestamps, and observed byte values. A derived duration and changed byte
offsets are permitted.

## Independent presentation

The user interface must be an original macOS design. Use project-authored
components, standard system controls, and properly licensed platform symbols.
Do not trace or recreate a third party's distinctive layout, trade dress,
branding, or assets.

Third-party names and marks may be used only where necessary for a factual
compatibility statement. They must not be used in the project name, logo,
application icon, or in a way that implies sponsorship or affiliation.

## Device-safety boundary

Normal discovery and diagnostics may enumerate devices, read public registry
metadata, and perform an explicitly initiated `GetReport` on an exact vendor
collection. The reviewed F5 exception may query only the current 84-key RGB
buffer after a separate confirmation; it is not a general settings-readback
path.

The reviewed write allowlist contains only clock synchronization, one selected
onboard lighting mode in `0...19`, and a complete table of all 84 per-key RGB
positions. Each operation requires its own confirmation and a matching typed
authorization. Saving or selecting a local profile is never authorization.

Every query or write must match wired USB `0x0C45:0x800A`, product `Archon
AK47`, `bcdDevice 0x0115`, the complete four-collection topology, and the single
FF13 Feature collection. It must use `kIOHIDOptionsTypeNone`, reject ambiguous
matches, serialize access, close promptly, and verify the topology again after a
write. Verified write steps use 35ms pacing, each asynchronous Feature operation
is limited to 360ms, and every required 64-byte ACK must signal success in byte 3. Errors end
the attempt without automatic retry.

No path may expose arbitrary payloads, transmit output reports, seize an
interface, or write LCD content, keymaps, macros, firmware, or bootloader state.
Raw report bytes must not be persisted or logged. The offline trace component
remains decode-only and isolated from live HID transport.

ACKs are not an exact backup. Onboard mode, brightness, speed, direction, and
clock values have no implemented readback or automatic rollback. Only the full
84-key RGB table has the separate F5 query. Any additional selector, readback,
or write requires a separate design review, must remain disabled by default,
require unambiguous user action, be isolated behind an auditable interface, and
include device-safety tests. Firmware updating, flashing, extraction, and
distribution remain outside the project.
