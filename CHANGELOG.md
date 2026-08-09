# Changelog

## Unreleased

- Replaced the three generic lighting scenes with the 19 identified AK47
  non-PRO onboard mode IDs, separate local off state, verified per-mode control
  capabilities, stable profile identifiers, and legacy profile fallbacks.
- Displayed all onboard mode names with the exact spelling from the Windows
  1033/1042 language resources, including `SingleOn`, `SingleOff`, and `LED Off`.
- Reused Keymap's verified 672×226, 84-key physical geometry and exact
  `lightIndex` mapping for a continuously animated, project-authored Lighting
  preview. Reactive modes 2, 3, 13, 14, and 15 support local key clicks and
  simulated input without sending HID commands.
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
- Added a physical 84-key RGB painter with per-key paint, fill, and clear
  actions. Device apply remains disabled until every verified light position is
  present exactly once.
- Serialized each verified operation with 35ms pacing, a 360ms limit per
  asynchronous Feature call, 64-byte ACK byte-3 validation where required,
  immediate failure without retry, and preflight/postflight topology checks.
- Kept output reports, LCD/keymap/macro writes, arbitrary payloads, firmware and
  bootloader operations outside the adapter. Onboard mode parameters and clock
  values have no exact readback or automatic rollback; only the complete
  per-key RGB buffer has the separate F5 query.
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
  beyond the three typed operations, and firmware operations outside the
  implementation.

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

Known limitation: this release applies only the clock, one selected onboard
lighting value, or a complete 84-key RGB table after separate confirmation. It
does not read current onboard mode parameters, clock, keymaps, LCD content,
macros, or general settings and cannot automatically restore their prior state.
It does not include firmware reading, extraction, updating, or flashing.
