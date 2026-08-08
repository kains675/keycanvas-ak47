# KeyCanvas clean-room policy

KeyCanvas is independently developed from public information and reproducible
observations made through ordinary use of lawfully obtained hardware. This
policy applies to every contributor and every contribution, regardless of
whether the project or contribution is commercial or noncommercial.

## Acceptable inputs

A compatibility claim or implementation may be based on:

- public platform documentation and public technical standards;
- facts visible through ordinary, read-only use of documented macOS APIs;
- reproducible observations that do not expose confidential material; and
- synthetic fixtures and project-authored tests.

Record the public source or a reproducible observation procedure. State facts
in your own words and contribute only code and media you have the right to
license under this repository's terms.

## Material that must stay out of the project

Do not obtain for this project, use as an implementation reference, paste into
an issue, or commit any of the following:

- third-party firmware, update payloads, firmware update tools, executables,
  installers, archives, disk images, or extracted contents;
- third-party source code or decompiled, disassembled, translated, decrypted,
  or otherwise reconstructed code;
- third-party logos, icons, artwork, screenshots, interface layouts, sounds,
  fonts, animations, or other product assets;
- leaked, confidential, access-controlled, or trade-secret information;
- material subject to an NDA, license, or other obligation that prevents its
  use or public redistribution; or
- device dumps or identifiers containing personal or sensitive information.

Linking to a legitimately public reference for attribution is preferable to
copying it into the repository. A public download is not automatically
redistributable and must not be mirrored here.

## Independent presentation

The user interface must be an original macOS design. Use project-authored
components, standard system controls, and properly licensed platform symbols.
Do not trace, imitate, or recreate a third party's distinctive visual layout,
trade dress, branding, or assets.

Third-party names and marks may be used only as necessary to make a factual
compatibility statement. They must not be used in the project name, logo,
application icon, or in a way that implies source, sponsorship, endorsement,
or affiliation.

## Device-safety boundary

The public baseline is read-only. It may enumerate devices and read public
registry metadata, but it must not open a device for report traffic, retrieve
reports, send reports, seize an interface, persist a setting to hardware, or
perform a firmware operation.

Any future proposal for a hardware-setting write path requires a separate,
explicit design review. It must remain disabled by default, require an
unambiguous user action, be isolated behind an auditable interface, and include
device-safety tests. A contributor must not weaken the automated read-only
check as part of an unrelated change.

Firmware updating, flashing, payload extraction, and firmware distribution are
intentionally outside the project and are not candidates for that exception.
