# DropNest security model

DropNest is designed for a trusted host computer, a household LAN, and short ad-hoc sharing with known people. It deliberately has no user accounts or remote cloud storage.

## Recommended modes

| Need | Run | Exposure |
| --- | --- | --- |
| This computer only | `dropnest serve` | Binds to `127.0.0.1` |
| Family Wi-Fi | `dropnest serve --lan --pin family-owl-72` | Binds to the selected LAN interface |
| Two temporary visitors | `dropnest serve --tunnel --pin family-owl-72` | Outbound Cloudflare Quick Tunnel to localhost |
| Long-running public host | HTTPS reverse proxy plus `--public-url https://…` | Proxy owns TLS and Internet policy |

Do not forward DropNest's plain HTTP port directly from a router. A direct port forward exposes access keys and file contents in transit. Keep the origin port private and terminate HTTPS in a maintained reverse proxy or tunnel.

## Controls

- LAN and tunnel modes require an 8–128 character access key.
- Access keys are HMAC-verified with constant-time comparison. Browsers receive an opaque HttpOnly, SameSite session token, never the key.
- Public invite tokens are random and only their keyed HMAC digests are compared.
- Temporary invites expire after 15 minutes and admit two distinct visitor fingerprints.
- The fingerprint is a keyed, in-memory digest of the proxy-provided address and normal request traits; raw identifying values are not stored, and session cookies are bound to it.
- CSRF tokens protect all mutations, and cross-site browser POSTs are rejected before multipart bodies are parsed.
- Unlock, invite, upload, text, and other write routes have fixed-window per-fingerprint rate limits.
- A nonce-based Content Security Policy blocks unapproved scripts and styles. Responses also disable framing, MIME sniffing, referrers, caching, and unnecessary browser permissions.
- Generated 32-character IDs select stored files. Supplied filenames never become paths and control characters are sanitized before download headers.
- SHA-256 is recorded for every new text/file drop. File downloads recalculate it and fail with `409` if content changed.
- Metadata replacement is atomic and concurrent mutations are serialized. Corrupt metadata is preserved as a timestamped backup before reset.
- Receive/data directories use mode `0700` and stored files/metadata use `0600` on platforms supporting Unix permissions.
- Upload size, total stored file bytes, text size, and drop count have hard limits.

## Important boundaries

- SHA-256 provides integrity, not encryption. Files and text are readable to the host user and anyone with filesystem access. Use full-disk encryption when needed.
- Cloudflare terminates TLS for Quick Tunnels and can technically observe traffic. This is encrypted transport, not end-to-end encryption between browser and DropNest.
- Quick Tunnels are a third-party temporary service without an uptime guarantee. If one stops, DropNest logs a warning and local/LAN operation remains available.
- A capability link can be forwarded. Anyone holding it can try to claim one of the two visitor slots before it expires.
- Fingerprints are rate-limit signals, not perfect identity. VPN changes, shared NAT, browser updates, or deliberate evasion can change or merge identities.
- Host compromise, malicious files, malware scanning, content moderation, backups, and operating-system patching remain the operator's responsibility.

## Always-on checklist

1. Run DropNest as an unprivileged dedicated user.
2. Keep `dropnest.conf` mode `0600` and use a long unique access key.
3. Put data and receive directories on a volume with adequate space, backups, and encryption.
4. Set `--max-upload-mb`, `--max-storage-mb`, and a finite default expiration appropriate to the host.
5. For public operation, use a maintained named tunnel or TLS reverse proxy with its own connection, bandwidth, and abuse limits.
6. Keep the origin port firewalled from the Internet.
7. Keep Erlang, DropNest, the proxy/tunnel client, and the operating system updated.
