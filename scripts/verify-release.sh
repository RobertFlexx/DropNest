#!/bin/sh
set -eu

ARCHIVE="dist/dropnest-unix.tar.gz"
SUM="dist/dropnest-unix.tar.gz.sha256"

if [ ! -f "$ARCHIVE" ]; then
  echo "Missing release archive: $ARCHIVE" >&2
  exit 1
fi

if [ ! -f "$SUM" ]; then
  echo "Missing checksum file: $SUM" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  (
    cd dist
    sha256sum -c dropnest-unix.tar.gz.sha256
  )
elif command -v shasum >/dev/null 2>&1; then
  expected=$(awk '{print $1}' "$SUM")
  actual=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
  if [ "$expected" != "$actual" ]; then
    echo "Checksum verification failed." >&2
    exit 1
  fi
else
  echo "Neither sha256sum nor shasum was found. Cannot verify checksum." >&2
  exit 1
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

tar -xzf "$ARCHIVE" -C "$tmp_dir"

ENTRYPOINT="$tmp_dir/erlang-shipment/entrypoint.sh"
if [ ! -x "$ENTRYPOINT" ]; then
  echo "Shipment entrypoint is missing or not executable: $ENTRYPOINT" >&2
  exit 1
fi

"$ENTRYPOINT" run --help >/dev/null
"$ENTRYPOINT" run serve --help >/dev/null

echo "Release verification passed."
echo "Server startup is not tested here. Run manual LAN tests before publishing."
