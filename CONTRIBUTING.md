# Contributing to KeyCanvas

By contributing, you agree to follow [CLEAN_ROOM.md](CLEAN_ROOM.md) and submit
only material you have the right to license under the MIT License. These rules
apply equally to commercial and noncommercial work.

## Before opening a change

- Base compatibility statements on a cited public source or a reproducible,
  authorized observation that follows the clean-room separation rules.
- Describe facts independently and use synthetic values in tests.
- Use project-authored SwiftUI and system components, not third-party branding,
  screenshots, layouts, or assets.
- Do not attach or link to firmware, update tools, vendor binaries, extracted
  files, archives, confidential material, or raw captures.
- Use third-party marks only for necessary factual compatibility statements;
  never imply affiliation, endorsement, or official status.

## Read-only baseline

The public build may open one exact vendor collection for an explicitly
initiated `GetReport` read. Such reads must reject ambiguous matches, close
promptly, avoid retries, and never persist or log raw bytes. It must not call
SetReport, transmit output data or selector commands, change device values,
seize an interface, or perform firmware operations. UI controls may save local
profile files but must not claim to have changed hardware.

Do not combine a hardware-write proposal with routine feature work. Such a
proposal requires a separate design discussion, an explicit default-off
boundary, clear user consent, and safety tests. Firmware update functionality
remains out of scope.

## Offline trace-analyzer contributions

The offline analyzer decodes only a local file selected by its user. Do not add
a public trace encoder, live capture, process hooking, traffic interception or
decryption, report replay or injection, device I/O, or trace upload. Diagnostics,
tests, and CI must not retain or print raw payloads.

Each trace input contains `provenance.origin` set to `synthetic` or
`authorized-private-observation`. The `authorizedUse`, `identifiersRemoved`,
`absoluteTimestampsRemoved`, and `firmwareTrafficExcluded` fields must all be
`true`. These assertions are not proof; the observation record and second-person
review remain required.

When timestamps are present, the first provided value is zero, later provided
values are nondecreasing, and no value exceeds one hour. Human and JSON output
must omit input labels, individual and boundary timestamps, and observed byte
values. A derived duration and changed byte offsets are permitted.

Do not attach a raw capture to a commit, issue, pull request, discussion,
security report, Actions log or artifact, or release. Do not provide a delivery
link. Tests and examples use newly authored, non-replayable synthetic values,
not excerpts, redactions, hashes, encodings, or reformattings of a capture.

A pull request based on an authorized private observation includes a text
provenance note with the observer's authorization, environment and tool
versions, controlled action, retained facts, sanitization steps, and reviewer.
Never include the raw file or captured bytes. Implementers must receive only
independently stated facts and synthetic test data.

Tracked JSON is denied by default. Do not force-add a JSON file unless its exact
path has received provenance review and is added as an explicit exception in
the repository scan. Prefer synthetic values constructed directly in test code.

If raw data is uploaded accidentally, do not repost it or open a public cleanup
issue. Report only its location through the private security channel so
maintainers can remove history, Actions artifacts, or releases and assess
notification or secret rotation.

## Development checks

```sh
swift build
swift test
sh Scripts/check-readonly-api.sh
sh .github/scripts/repository-scan.sh
```

The repository scan rejects firmware, executables, archives, raw-capture
formats and directories, unreviewed binary or visual files, and tracked JSON
without an exact allowlist entry.

## Pull-request checklist

- [ ] The change is narrowly scoped and tested.
- [ ] No third-party firmware, software, branding, UI, assets, or raw capture is
      included.
- [ ] Compatibility evidence is public or follows the authorized-observer
      separation and provenance rules.
- [ ] Trace provenance has an allowed origin and all four assertions are true.
- [ ] Timestamps start at zero, are nondecreasing, and remain within one hour.
- [ ] Trace test data is synthetic and contains no captured payload bytes.
- [ ] Output contains no label, raw timestamp, or observed byte value.
- [ ] No encoder, capture, hook, replay, upload, device-I/O, or firmware path was
      added.
- [ ] The read-only and repository-boundary checks pass.
