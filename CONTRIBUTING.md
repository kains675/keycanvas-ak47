# Contributing to KeyCanvas

Thank you for helping improve KeyCanvas. By contributing, you agree to follow
the [clean-room policy](CLEAN_ROOM.md) and to submit only material you have the
right to license under the MIT License.

## Before opening a change

- Base compatibility statements on a cited public source or a reproducible,
  read-only observation.
- Describe observations in your own words and use synthetic data in tests.
- Keep the interface independent: use project-authored SwiftUI and system
  components, not third-party branding, screenshots, layouts, or assets.
- Do not attach or link directly to firmware payloads, update tools, vendor
  binaries, extracted files, archives, or confidential material.
- Use third-party marks only for a necessary factual compatibility statement;
  never imply affiliation, endorsement, or official status.

These rules apply equally to commercial and noncommercial work.

## Read-only baseline

The current public build must not open HID devices for report traffic, read or
send HID reports, change device values, seize an interface, or perform firmware
operations. UI controls may save or exchange local profile files, but must not
claim that they changed hardware.

Do not combine a hardware-write proposal with routine feature work. Such a
proposal needs its own design discussion, an explicit default-off boundary,
clear user consent, and safety tests. Firmware update functionality remains out
of scope.

## Development checks

Run all checks before submitting a pull request:

```sh
swift build
swift test
sh Scripts/check-readonly-api.sh
sh .github/scripts/repository-scan.sh
```

The repository scan rejects common firmware, executable, and archive formats,
unreviewed binary files, and visual assets that have not been explicitly
reviewed and allowlisted. This conservative rule keeps provenance unambiguous
for the public prototype. Discuss any proposed exception before adding a file.

## Pull-request checklist

- [ ] The change is narrowly scoped and tested.
- [ ] No third-party firmware, software, branding, UI, or assets are included.
- [ ] Compatibility evidence is public or reproducible through read-only use.
- [ ] Hardware writes remain disabled by default; the current read-only check
      still passes.
- [ ] No firmware updater, flasher, or payload handling is introduced.
- [ ] Documentation and user-facing behavior accurately describe limitations.
