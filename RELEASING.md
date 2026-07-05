# releasing DropNest

DropNest releases are Gleam Erlang shipment archives. they are not native static binaries, and they should not be described that way.

people installing a release do not need Gleam, but they do need Erlang on their machine.

## before you build

make sure these are installed:

- Gleam
- Erlang/OTP
- Rebar3

the Gleam version also needs to support Erlang shipment export:

```sh
gleam export erlang-shipment --help
```

if `erlang-shipment` is not listed under `gleam export --help`, update Gleam before packaging.

quick version check:

```sh
gleam --version
erl -version
rebar3 --version
```

## build it

from the repo root:

```sh
VERSION=1.0.0 scripts/package-release.sh
```

the script rebuilds the app, exports the shipment, writes checksums, and puts everything in `dist/`:

```text
dist/dropnest-unix.tar.gz
dist/dropnest-unix.tar.gz.sha256
dist/dropnest-windows.zip
dist/dropnest-windows.zip.sha256
dist/dropnest-v1.0.0-unix.tar.gz
dist/dropnest-v1.0.0-windows.zip
```

## verify it

```sh
scripts/verify-release.sh
```

that checks the checksum and makes sure the help commands run:

```sh
dist archive extraction
erlang-shipment/entrypoint.sh run --help
erlang-shipment/entrypoint.sh run serve --help
```

it does not start the web server. still do the LAN test by hand before publishing.

## tag it

```sh
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions builds the shipment archives and publishes the release files to GitHub Releases.

## manual release check

```text
[ ] download the release artifact
[ ] verify the checksum
[ ] install with install.sh
[ ] run dropnest serve
[ ] run dropnest serve --lan --pin 1234 --dir ~/Downloads/DropNest
[ ] open DropNest from another device
[ ] upload a file from another device
[ ] confirm the file appears on the host computer
[ ] submit a text drop
[ ] delete a file drop and confirm the stored file is removed
```

## wording to keep straight

DropNest release files require Erlang/BEAM on the user's machine.

do not call the release artifact a fully static native binary.
