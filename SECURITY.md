# KeyCanvas security policy

## Supported scope

Security fixes target the latest revision on the repository's default branch.
Older snapshots and downstream forks may not receive fixes.

The current public build is read-only with respect to hardware. It enumerates
HID registry metadata and does not open a device for report traffic, retrieve
or send reports, persist hardware settings, or update firmware. The app can
store and exchange local JSON profile files; those files are never sent to the
device. Hardware writes are disabled by default and no concrete hardware write
implementation is shipped. A firmware updater is intentionally excluded.

## Reporting a vulnerability

Use GitHub's **Report a vulnerability** link to open a private security advisory
for this repository. If private reporting is not enabled on a fork, contact that
fork's maintainers privately before publishing details.

Please include:

- the affected revision;
- macOS and Swift versions;
- minimal reproduction steps using public APIs or synthetic data;
- expected and actual behavior; and
- an assessment of user or device impact.

Do not include firmware, vendor software, archives, confidential protocol
material, serial numbers, raw device dumps, credentials, private macro content,
or other sensitive artifacts. Treat imported profiles as untrusted data and
redact them or use a synthetic reproduction. Do not test by writing to or
flashing hardware. Coordinate disclosure with the maintainers and allow
reasonable time for a fix.

General feature requests and compatibility observations that contain no
sensitive information may use the public issue tracker.
