# Changelog

## Unreleased

- Added a bounded offline GIF editor with frame add/delete/duplicate/reorder,
  per-frame delay, crop/fit/fill/stretch, project-authored bitmap text and pen
  editing, animated preview, and edited-GIF export.
- Made the visible editor output canvas match the LCD's exact 240×135 (16:9)
  aspect ratio. Fit, fill/crop and stretch now update a non-destructive live
  output preview; aspect fill adds a whole-source crop map plus centered X/Y
  1-pixel and 10-pixel arrow nudges, and requires an explicit all-source-frame
  apply before export or device transfer.
- Unified Display import around one inline editor. PNG/JPEG/GIF sources open
  directly; local AVFoundation-readable MP4/MOV/M4V sources use a bounded
  start/end/FPS sampler before entering the same fit/fill/crop/text/pen flow.
  Video sources are snapshotted locally, forbid external media references,
  stay out of the asset library, and require edited-GIF export for retention.
- Added an in-sheet muted video preview with Play/Pause, a single dual-handle
  trim timeline, an independent playhead, fixed `HH:MM:SS.mmm` timecodes and
  keyboard output-sample stepping. Selected-range playback stops at the active
  end boundary, and stale seek or replaced-boundary callbacks are ignored.
- Fixed a Swift exclusivity crash when a completed video extraction dismissed
  the trimmer while its hidden keyboard responder was being dismantled. Route
  publication now occurs on the next MainActor turn, after SwiftUI graph
  teardown, with a 133-frame/14-fps extraction regression.
- Simplified the main Display surface to Import → edit → Apply and moved the
  existing library/study and device qualification/recovery tools into collapsed
  secondary sections.
- Bound local media replacement to the originating profile/session, stored the
  exact image/GIF bytes that were inspected, rejected symlinks/FIFOs through
  no-follow nonblocking regular-file reads, and disabled editor mutation and
  device Apply while an immutable import is being prepared.
- Added an independent 240×135 opaque RGB565 container encoder with a 256-byte
  header, exact 4,096-byte `0xFF`-padded pages, verified delay conversion, and
  rejection of malformed or over-ceiling projects. The 140-frame/2,215-page
  ceiling is documented as host-side software behavior, not a physical SPI
  partition guarantee.
- Added a typed LCD upload plan, transport state machine and concrete default-off
  macOS adapter. Its bootstrap accepts only one fixed project-authored
  diagnostic frame; the exact 16-page container SHA-256 is
  `312f98fd023d49711f73a677895b1bf48ac246c7dd687c813ed5642f42128bec`;
  every different bootstrap hash, frame/page shape and raw payload is rejected.
- Added a Core-owned durable qualification receipt for the separately bounded
  1...40-frame path. It requires a fresh receipt-build canonical transfer,
  visual corner attestation, observed USB disconnection, exact same-port/four-
  collection reappearance, and explicit USB-mode cable-removal/unpowered
  attestation in order. Production starts empty; historical trials have no
  import, backfill or preference-based bypass.
- Connected qualified Apply to a value copy of the current in-memory editor
  project, including unsaved edits. Core's single qualified encoder enforces the
  40-frame/2,592,768-byte budget; a final sheet displays and binds exact target,
  frame/page/byte counts, address range, SHA-256 and delay conversion to one
  authorization. Later editor/library changes cannot mutate that plan, and
  edits above 40 frames are rejected without truncation or force.
- Added durable canonical and qualified transfer leases before any HID path.
  Qualified host success now remains visual-review-pending; the review decodes
  the exact submitted RGB565 bytes. Exact visual match reopens qualification,
  while wrong or unverifiable output enters a retryable mismatch state, arms
  durable quarantine and revokes qualification. Relaunch without the immutable
  expected preview cannot create a positive attestation.
- Added fail-closed interrupted-lease reconciliation. Canonical or qualified
  leases surviving app exit block every other live HID operation; after the user
  confirms no other process is active, Core persists a retryable interruption
  state, arms the target's durable quarantine marker and invalidates
  qualification without ever restoring the old lease as success.
- Consolidated the canonical and qualified LCD Apply surfaces onto one shared
  experimental-feature risk acknowledgement and a destructive one-use Apply.
  Exact plan-bound authorization, FF13/FF68 collection selection, the one
  Feature and one Output call site, required Output-completion/input-report
  sequences, no retry, exact postflight and durable partial-transaction
  quarantine remain unchanged.
- Completed an explicitly authorized fixed-fixture macOS evidence trial: all 16
  Output completions elicited the expected input sequence, commit and exact
  postflight completed, and the user visually confirmed the red/green/blue/
  white corner positions and orientation. This predates the production receipt
  build, is evidence only, and cannot be imported or backfilled as authority.
- Recorded only minimum interoperability facts from authorized-private Windows
  success observations on the exact `bcdDevice 0x0115` target. Windows observed
  FF13 on `MI_03`, FF68 on `MI_02`, endpoint `0x03` OUT and `0x84` IN. macOS
  directly verifies IORegistry interface 3/interface 2 ancestry and a common
  physical USB parent, but does not select or observe numeric endpoint 0x03/0x84.
- Added a pure dry-run risk inspector for function settings, per-key RGB and
  onboard-lighting categories. It exposes only operation/ACK and page-risk
  counts, with no raw steps, default payload bytes or HID execution path.
  Base/Fn keymaps, macros, and LCD remain blocked, so it is not a factory reset
  or recovery tool.
- Reported seven statically inferred internal-flash erase/program transactions
  across four distinct pages for the non-executable three-group dry-run plan.
  The physical side effect of the global-persistence helper is not validated by
  the private firmware-backed emulator, and no backup or automatic rollback is
  claimed.
- Clarified the public/private interoperability boundary: the project does not
  claim a strict two-team clean-room process, and vendor binaries, firmware,
  assets, default GIFs, raw captures, and the private firmware-backed emulator
  are prohibited from the repository. Public tests use synthetic data only.
- Added a target-specific durable write-ahead quarantine marker before F5,
  confirmed Feature transactions and the fixed LCD diagnostic. It stores
  identity only, uses atomic local persistence plus file/directory `fsync`,
  survives relaunch, and blocks a possibly partial target transaction without
  retrying it.
- Made marker clearing staged and fail-closed: the old identities are first
  synchronized to a `.pending-clear` sibling, the primary receives a durable
  empty-array receipt, and loading unions both records until the staged file is
  removed and its directory entry is synchronized.
- Added a conservative recovery handshake: one process must observe the target
  absent, then see the same exact four-collection identity reappear, after which
  the user must explicitly attest that the selector stayed in USB mode while
  cable removal fully powered down the LCD, LEDs and device before reconnection
  at the original USB location. Moving to 2.4G/Bluetooth is not recovery.
  Relaunching resets those observations but does not remove the marker.
- Documented that the process lock serializes KeyCanvas instances only: vendor
  utilities, Windows VMs and other HID clients must be stopped before confirmed
  operations because the FF13 collection remains non-exclusive. Without a
  serial, exact recovery reappearance requires the original USB location.
- Reorganized Lighting into separate onboard-effect and per-key RGB workspaces,
  made all 20 choices including `LED Off` visible in one adaptive selector, and
  separated local profile saving from contextual, confirmed device apply.
- Rebuilt the per-key editor around a direct selected-color/off toggle: one
  click alternates a key between the brush color and black RGB, while a drag
  locks its first key's target across the stroke. Added lit/off counts,
  one-shot color sampling, all-color/all-off actions, one-step undo, responsive
  layout, and accessible presets. Editing still performs no HID operation.
- Added a visible shared 1–5 brightness control for per-key RGB. Sparse local
  profiles are completed as 84 verified device slots with missing keys sent as
  black RGB, while unknown imported slots remain local and are never sent.
- Replaced the three generic lighting scenes with the 19 identified AK47
  non-PRO onboard mode IDs, separate local off state, verified per-mode control
  capabilities, stable profile identifiers, and legacy profile fallbacks.
- Displayed all onboard mode names with the exact spelling from the Windows
  1033/1042 language resources, including `SingleOn`, `SingleOff`, and `LED Off`.
- Reused Keymap's verified 672×226, 84-key physical geometry and exact
  `lightIndex` mapping for a stateful integer Lighting preview. It independently
  expresses minimum movement-topology, persistent-state and ordered reactive
  event facts for all 19 modes; modes 2, 3, 13, 14, and 15 support local key
  clicks and deterministic demo taps without sending HID commands. Monotonic
  30 Hz playback, pacing, brightness/color curves, palette and optics remain
  project-authored presentation choices rather than firmware-exact claims.
- Matched the directly observed `Rotating` Colorful presentation: all 84 keys
  stay lit while an angular color field revolves around the keyboard, instead
  of reducing the colorful variant to a narrow rotating ribbon.
- Rewrote the project README in Korean.
- Added reproducible clean-staging Universal 2 application, ZIP, and
  drag-and-drop DMG packaging with code-signature, architecture, image, and
  SHA-256 verification. Current artifacts are explicitly marked as ad-hoc
  signed, unnotarized developer previews.
- Documented DMG/ZIP/source installation, safe per-app first launch, complete
  uninstall scope, and the independent project's AS-IS warranty and liability
  boundary.
- Added a strict, size-limited offline HID trace schema and validator.
- Added trace summary and index-aligned byte-difference analysis.
- Added the `keycanvas-trace` CLI for local summary and diff output.
- Added a bounded, read-only importer for Windows AK47 local profiles and
  validated LCD frame layers, preserving source dimensions and frame delays in
  local GIFs while keeping the device canvas at 240×135.
- Added an explicitly confirmed, one-shot current per-key RGB query for the
  exact wired USB `0x0C45:0x800A` `Archon AK47` with `bcdDevice 0x0115` and its
  four verified HID collections.
- Limited every asynchronous RGB Feature operation to 360ms and excluded
  automatic retry, output reports, persistence, profile mutation, and raw report
  logging. Only the allowlisted F5 query and normal finish commands are sent.
- Added three separately confirmed, typed Feature operations for the exact
  wired revision: clock synchronization, one currently selected onboard mode
  in `0...19`, and brightness plus a complete 84-key RGB table.
- Added a physical 84-key RGB painter with per-key toggle, fill, all-off, and
  color-sampling actions. The verified 84-slot device payload is always
  complete because unpainted keys are represented as black RGB.
- Serialized each verified operation with 35ms pacing, a 360ms limit per
  asynchronous Feature call, 64-byte ACK byte-3 validation where required,
  immediate failure without retry, and preflight/postflight topology checks.
- Kept keymap/macro writes, arbitrary payloads, firmware and bootloader
  operations outside the executable adapters. LCD bootstrap is hard-locked to
  the one project-authored diagnostic fixture; qualified current-editor content
  is bounded to 1...40 frames and an exact durable receipt/plan authorization.
  Onboard mode parameters and clock values have no exact readback or automatic
  rollback; only the complete per-key RGB buffer has the separate F5 query.
- Added operation-specific opt-in hardware tests; the normal suite skips them
  without the exact authorization phrase.
- Completed separate 2026-08-09 hardware runs for the corrected clock
  transaction, onboard `Static` mode 1, onboard `Launch` mode 14, and one
  complete 84-key RGB table on the exact wired target. Required ACKs and
  postflight topology checks passed. F5 preserved all key assignments after the
  RGB write but returned three brightness-adjusted colors at level 3 rather
  than the original RGB bytes, so it is not treated as byte-exact backup.
- Completed two hardware validations on 2026-08-09. The first parsed 84 zero
  RGB entries. After the user separately identified the new selection as mode
  14 (`Launch` in both the Windows resource and KeyCanvas), one instantaneous
  query found all 84 entries nonzero with 24 distinct colors. The response
  contains no mode ID or exact motion formula; the device remained enumerated
  with no observed disconnect, while complete state invariance remains
  unverified.
- Rekeyed imported JSON profiles before local persistence and reject active
  SQLite sidecars so backup imports cannot escape local storage or silently
  ignore pending Windows data.
- Documented trace provenance and sanitization rules and blocked common raw
  capture formats from the public repository.
- Kept live capture, process hooking, report replay, hardware-setting writes
  beyond the established Feature operations and bounded LCD paths, all factory/
  default restore, arbitrary raw LCD output, and firmware operations outside the
  executable public-app boundary.

Known limitation: this development version applies only the clock, one selected
onboard lighting value, a complete 84-key RGB table, the exact one-frame LCD
bootstrap, or a qualified immutable 1...40-frame current-editor plan after
separate confirmation. The evidence-only diagnostic trial
completed 16/16 expected sequences, commit, exact postflight and user visual
corner validation on macOS; ordered cable-removal absence and same-location
exact-four reappearance were also observed. Because that trial predates the
production receipt build, it cannot unlock anything. Qualified use requires a
fresh fixed-fixture run under the new Core receipt path and the complete ordered
qualification; the production store starts empty. Every qualified host success
also requires exact visual review before authority reopens. 140 frames remains
an offline format ceiling. The three-group
default plan is inspection-only and cannot write hardware. The app does not
read current onboard mode parameters, clock, keymaps, LCD content, macros, or
general settings and cannot automatically restore their prior state. Firmware
reading, extraction, updating, and flashing are not included.

## 0.1.0 — 2026-08-08

- Added the original KeyCanvas SwiftUI application and visual identity.
- Added Korean and English UI text.
- Added read-only discovery and inspection for the supported USB identity.
- Added physical HID collection grouping and conservative channel candidates.
- Added 84-key Base/Fn profile editing with keyboard and media assignments.
- Added local lighting, validated macro, 240×135 display, and settings drafts.
- Added validated JSON profile storage, import, and export.
- Added a default-deny transport abstraction and synthetic frame codecs for
  future compatibility research; no concrete hardware report transport ships.
- Added a Universal 2 macOS app packaging script and original vector app icon.
- Added MIT licensing, contribution, security, provenance, and CI policies.
