# DropNest

DropNest is a small, self-hosted sharing nest for a household or a few friends. run it on one computer, open the shown address from another phone or laptop, then send a file or a chunk of text without making an account or storing the payload in a cloud drive.

the computer running DropNest remains the host and source of truth. uploads land in the folder you choose, text drops stay in local metadata, and every payload gets a SHA-256 integrity fingerprint. local mode stays on the computer, LAN mode works across the same Wi-Fi, and optional tunnel mode creates a short-lived HTTPS invite for two visitor fingerprints.

![DropNest homepage preview](docs/dropnest-preview.svg)

## what it does

- starts in local-only mode unless you ask for LAN mode
- opens to your network with `--lan` and requires an 8+ character access key
- creates an optional 15-minute, two-visitor HTTPS friend invite with `--tunnel`
- regenerates that friend invite from localhost without stopping the server
- keeps the public tunnel outbound-only, so it does not change router or firewall rules
- lets you choose the receive folder with `--dir`
- can read defaults from `dropnest.conf`
- saves uploaded files on the host computer, not on the device that uploaded them
- accepts pasted text, links, commands, notes, and clipboard bits
- adds local drops from the CLI with `send` and `send-text`
- shows a fully offline QR code for quick phone setup
- supports drag-and-drop file upload in the browser
- lets each drop expire after 15 minutes, 1 hour, 1 day, 1 week, or never
- shows recent drops with copy, download, and delete actions
- calculates and displays SHA-256 checksums and refuses to download a changed file
- stores metadata locally in `data/metadata.json`
- stores uploaded file content under the receive directory
- cleans up expired drops automatically
- serializes concurrent metadata changes and caps stored data at 10 GB by default
- uses HttpOnly, SameSite sessions, CSRF tokens, request fingerprint rate limits, and restrictive browser security headers
- uses plain server-rendered HTML and CSS, so there is no frontend build step

the app is written in Gleam and runs on Erlang/BEAM through Wisp and Mist. release builds do not need Gleam installed, but they do need Erlang.

## install a release

DropNest releases are shipped as a Gleam Erlang shipment archive. the installer downloads the archive, verifies the checksum when available, and creates a small `dropnest` wrapper in your install directory.

the commands below install from the upstream GitHub releases. if you publish a fork under another GitHub account or organization, set `GITHUB_OWNER` and `GITHUB_REPO` before running the installer.

safer install, because you can read the script first:

```sh
curl -fsSL https://raw.githubusercontent.com/RobertFlexx/dropnest/main/install.sh -o install.sh
sh install.sh
```

one-line install, if you are comfortable piping the installer straight into `sh`:

```sh
curl -fsSL https://raw.githubusercontent.com/RobertFlexx/dropnest/main/install.sh | sh
```

the installer puts `dropnest` in `$HOME/.local/bin` unless you set `INSTALL_DIR`.

installing from a fork looks like this:

```sh
GITHUB_OWNER=your-github-user GITHUB_REPO=dropnest sh install.sh
```

```sh
dropnest serve
```

to use it from another device on your wi-fi:

```sh
dropnest serve --lan --pin family-owl-72 --dir ~/Downloads/DropNest
```

then open one of the shown addresses from the other device. if DropNest cannot detect a usable local address and shows `<your-computer-ip>`, replace it with the host computer's local network IP address.

## erlang requirement

release builds need Erlang because DropNest is a Gleam/BEAM app. they do not need Gleam.

common install commands:

```sh
# debian or ubuntu
sudo apt install erlang

# fedora
sudo dnf install erlang

# arch
sudo pacman -S erlang

# macos
brew install erlang
```

temporary friend links also need Cloudflare's `cloudflared` executable. it is optional; local and LAN modes do not use it.

```sh
# macOS or Linuxbrew
brew install cloudflared
```

DropNest starts `cloudflared` only when `--tunnel` is present. Quick Tunnels are a third-party convenience service with no uptime guarantee; see [public friend links](#public-friend-links) before enabling one.

## build from source

```sh
git clone https://github.com/RobertFlexx/DropNest
cd DropNest
gleam deps download
gleam build
gleam run -- serve
```

## everyday use

local-only mode is the default and is only reachable from the host computer:

```sh
gleam run -- serve
```

show help:

```sh
gleam run -- help
gleam run -- serve --help
```

choose where files are saved:

```sh
gleam run -- serve --dir ~/DropNest
```

open it to your Wi-Fi, require an access key, and save uploads in a dedicated folder:

```sh
gleam run -- serve --lan --pin family-owl-72 --dir ~/Downloads/DropNest
```

create a temporary public HTTPS invite that can admit two visitor fingerprints during its first 15 minutes:

```sh
gleam run -- serve --tunnel --pin family-owl-72 --dir ~/Downloads/DropNest
```

set the host and port yourself:

```sh
gleam run -- serve --lan --host 0.0.0.0 --port 7070 --dir ~/Downloads/DropNest
```

## options

- `serve` starts the web server
- `--lan` binds to `0.0.0.0` unless `--host` is also set; an access key is required
- `--tunnel` keeps the server on localhost and starts an outbound Cloudflare Quick Tunnel
- `--host <host>` chooses the bind host
- `--port <port>` chooses the port, defaulting to `7070`
- `--pin <access-key>` turns on HMAC-verified session protection and must contain 8–128 characters
- `--public-url <https-url>` tells DropNest it is behind your own HTTPS reverse proxy
- `--dir <path>` chooses the receive folder, defaulting to `./DropNestDrops`
- `--data-dir <path>` chooses where metadata is written, defaulting to `./data`
- `--max-upload-mb <number>` sets the upload limit, defaulting to `100`
- `--max-storage-mb <number>` caps total stored file bytes, defaulting to `10240`

DropNest lists usable local IPv4 addresses in LAN mode. if more than one address is shown, use the one that belongs to the same wi-fi or wired network as your other device.

## config file

DropNest reads `./dropnest.conf` when it exists. pass `--config <path>` if you want to keep it somewhere else. command-line options win over config-file values.

```conf
lan=true
pin=family-owl-72
tunnel=false
dir=/home/you/Downloads/DropNest
data_dir=/home/you/.local/share/dropnest
host=0.0.0.0
port=7070
max_upload_mb=250
max_storage_mb=10240
expires=1440
```

`expires=0` keeps drops forever. because the access key can live in this file, local `dropnest.conf` files are ignored by git. restrict its permissions to your user (for example, `chmod 600 dropnest.conf`) and use `dropnest.example.conf` as the template.

## cli sends

these commands add drops directly to the configured local DropNest storage. they do not need the web server to be running.

```sh
dropnest send-text "open this on the other machine"
dropnest send ./archive.zip --dir ~/Downloads/DropNest
```

## where files go

by default DropNest writes this shape of data next to where you started it:

```text
data/
  metadata.json

DropNestDrops/
  <generated-id>
  <generated-id>
```

original filenames are kept for display and download names. stored files use generated IDs, so a browser upload cannot choose the final path on disk.

## public friend links

`--tunnel` asks the installed `cloudflared` executable for a random `https://*.trycloudflare.com` Quick Tunnel. the connection is outbound from the host to Cloudflare: DropNest stays bound to `127.0.0.1`, and no router port is opened.

after unlocking the local host page, copy the friend link shown at the top. it contains a random capability token and behaves as follows:

- the invite expires 15 minutes after it is generated
- it admits at most two distinct visitor fingerprints
- an admitted visitor gets a 12-hour HttpOnly, Secure, SameSite session
- revisiting from the same admitted browser does not consume another slot
- the authenticated localhost page can regenerate the link without stopping DropNest; this invalidates the old invite, resets its timer and two visitor slots, and leaves existing sessions connected
- restarting DropNest creates a new tunnel hostname, token, HMAC key, counters, and sessions

the visitor fingerprint is a keyed HMAC over the tunnel-provided client address and ordinary HTTP browser traits. raw IP addresses and user-agent strings are never stored. sessions are bound to this fingerprint, so copying a cookie to a different fingerprint does not authenticate it. this is rate-limit identity, not advertising fingerprinting, and it cannot be perfectly stable across VPN, browser, or network changes.

the invite token is compared through a server-side HMAC digest. anyone who receives the complete link can attempt to use one of its two slots, so send it as you would send a password. Cloudflare terminates public TLS and can technically observe traffic passing through its service; DropNest's tunnel is encrypted in transit but is not end-to-end encrypted from browser to host.

Cloudflare documents Quick Tunnels as a testing/development service without an SLA. for an always-on public deployment, use a named tunnel or an HTTPS reverse proxy, set `--public-url https://your-name.example`, add upstream rate limits, and keep port `7070` private. never forward the plain HTTP port directly to the Internet.

## routes

- `GET /` shows the homepage
- `POST /drops/file` uploads a file
- `POST /drops/text` creates a text drop
- `GET /drops/:id/download` downloads a file drop
- `POST /drops/:id/delete` deletes a drop
- `POST /unlock` creates a hashed session without putting the access key in a cookie
- `POST /logout` removes that browser session
- `POST /invite/regenerate` rotates the invite from an authenticated localhost session
- `GET /i/:token` claims a temporary two-visitor friend invite
- `GET /health` returns a basic health check

## safety notes

see [SECURITY.md](SECURITY.md) for the threat model and always-on deployment checklist.

- DropNest binds to `127.0.0.1` by default
- LAN access only happens when you pass `--lan`
- LAN and tunnel modes refuse to start without an 8–128 character access key
- the access key is HMAC-compared in constant time; the browser cookie contains only a server-derived session token
- state-changing forms require a random CSRF token and reject browser cross-site posts
- repeated unlocks, invites, and writes are rate-limited by an in-memory keyed visitor fingerprint
- responses set a nonce-based Content Security Policy, no-store caching, frame denial, MIME sniffing denial, a no-referrer policy, and restrictive permissions
- uploaded filenames are never used as storage paths
- control characters are removed from download filenames
- browser clients cannot choose final filesystem paths
- file content is served by generated drop ID
- user-controlled text is escaped before it is rendered in HTML
- files and text receive SHA-256 checksums; changed files fail closed instead of downloading
- data directories use user-only permissions where the operating system supports Unix modes
- concurrent metadata writes are serialized and replaced atomically
- text drops, drop count, upload size, and total file storage are bounded
- expired and deleted file drops remove stored file content
- do not use `/`, `.`, or a broad project folder as the receive directory
- files are not encrypted at rest; use host disk encryption if that is part of your threat model
- no localhost application can make direct plain-HTTP router port forwarding safe; use `--tunnel` or a correctly configured TLS reverse proxy

## troubleshooting

if your phone cannot open DropNest, make sure both devices are on the same wi-fi, start with `--lan`, use the host computer's real local IP address, and check the host firewall.

if `--dir ~/Downloads/DropNest` is rejected, pass it unquoted so your shell expands `~`, or use an absolute path like `/home/you/Downloads/DropNest`.

if uploads fail, check that the receive directory can be created and written by your user, check the upload limit on the homepage, or restart with a larger limit like `--max-upload-mb 250`.

if `--lan` or `--tunnel` refuses to start, use an access key containing at least eight characters. a short numeric PIN is intentionally rejected.

if `--tunnel` reports that `cloudflared` is missing, install it and make sure `cloudflared --version` works in the same terminal. if a Quick Tunnel cannot start, check outbound network access and Cloudflare's service status; local and LAN sharing do not depend on it.

if metadata gets corrupted, DropNest backs it up as `metadata.corrupt.<timestamp>.json` and starts with fresh metadata.

## release build

release builders need Gleam, Erlang, and Rebar3.

```sh
scripts/package-release.sh
scripts/verify-release.sh
```

artifacts are written to `dist/`.

## manual test list

```text
[ ] gleam deps download
[ ] gleam build
[ ] gleam run -- serve
[ ] local homepage opens
[ ] gleam run -- serve --lan --pin family-owl-72 --dir ~/Downloads/DropNest
[ ] LAN homepage opens from another device
[ ] gleam run -- serve --tunnel --pin family-owl-72
[ ] first two public visitor fingerprints are admitted and a third receives 410
[ ] invite expires after 15 minutes
[ ] localhost can regenerate the friend link without stopping DropNest
[ ] regenerated link rejects the old token and admits two new fingerprints
[ ] tunnel visitors cannot see or call the regeneration control
[ ] receive directory is created
[ ] homepage shows receive directory
[ ] file upload from another device saves on host
[ ] uploaded file appears in recent drops
[ ] file downloads with original filename
[ ] file delete removes metadata and stored file
[ ] text drop submits
[ ] blank text drop is rejected
[ ] copy button works
[ ] oversized file is rejected
[ ] total storage ceiling rejects the next file safely
[ ] modified stored file returns 409 instead of downloading
[ ] sixth bad unlock attempt receives 429
[ ] expired drops are cleaned
[ ] missing file download gives a friendly error
```

## project layout

```text
.github/workflows/release.yml  GitHub release packaging workflow
CHANGELOG.md                   release history and upgrade notes
docs/dropnest-preview.svg      README preview image
SECURITY.md                    threat model and always-on checklist
scripts/package-release.sh     local release archive builder
scripts/verify-release.sh      release archive verification
gleam.toml
dropnest.example.conf          config template
src/dropnest.gleam             cli entrypoint
src/dropnest/config.gleam      defaults and argument parsing
src/dropnest/drop.gleam        drop model and JSON encoding/decoding
src/dropnest/net.gleam         LAN address helpers
src/dropnest/server.gleam      Wisp/Mist server and routes
src/dropnest/storage.gleam     safe local storage and expiration cleanup
src/dropnest/view.gleam        plain HTML/CSS/QR rendering
src/dropnest_ffi.erl           small Erlang network interface helper
test/dropnest_test.gleam       smoke and regression tests
```

## later ideas

- upload progress polish
- CLI helpers for listing and cleaning drops
- optional device names
- search and tags
- burn-after-download
- systemd user service example
- broader automated tests
