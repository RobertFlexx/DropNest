# Changelog

## 2.1.1 - 2026-09-01

### Fixed

- Made the friend-invite QR code render larger at an exact integer pixel scale, with a roomier quiet zone, so phone cameras scan it reliably instead of failing on the small pixelated version.

## 2.1.0 - 2026-09-01

### Added

- Added authenticated localhost-only friend-link regeneration. It atomically invalidates the old invite, resets the 15-minute/two-visitor allowance, and keeps the DropNest server and established sessions running.

## 2.0.0 - 2026-09-01

DropNest 2.0.0 turns the local drop server into a safer family and small-group sharing service while preserving local ownership of every file.

### Highlights

- Added LAN mode with copyable local-network links and QR codes.
- Added temporary Cloudflare Quick Tunnel links for sharing outside the LAN.
- Limited public invites to two fingerprinted visitor sessions and a 15-minute admission window.
- Bound authenticated sessions to visitor fingerprints and added unlock rate limiting.
- Added SHA-256 checksums, integrity checks before download, atomic metadata writes, startup recovery, storage ceilings, and upload timeouts.
- Refreshed the interface with a simpler responsive design and clearer security status.

### Breaking changes

- LAN, tunnel, and custom public URL modes now require an access key of at least eight characters.
- Public link mode requires a trusted proxy and only accepts validated Cloudflare proxy metadata.
- Configuration includes new tunnel, public URL, upload-timeout, and maximum-storage settings.
- The unauthenticated metadata endpoint has been removed.

See [SECURITY.md](SECURITY.md) for the deployment threat model and [RELEASING.md](RELEASING.md) for release verification steps.
