#!/bin/sh
set -eu

APP_NAME="dropnest"
DIST_DIR="dist"
VERSION="${VERSION:-}"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    echo "Install Gleam, Erlang, and Rebar3 before packaging DropNest." >&2
    exit 1
  fi
}

read_version() {
  if [ -n "$VERSION" ]; then
    printf '%s\n' "$VERSION"
    return 0
  fi

  if [ -f gleam.toml ]; then
    sed -n 's/^version = "\(.*\)"/\1/p' gleam.toml | sed -n '1p'
    return 0
  fi

  printf '0.0.0\n'
}

checksum_file() {
  file="$1"
  out="$2"
  dir=$(dirname "$file")
  base=$(basename "$file")

  if command -v sha256sum >/dev/null 2>&1; then
    (
      cd "$dir"
      sha256sum "$base" > "$(basename "$out")"
    )
  elif command -v shasum >/dev/null 2>&1; then
    (
      cd "$dir"
      shasum -a 256 "$base" > "$(basename "$out")"
    )
  else
    echo "Neither sha256sum nor shasum was found. Cannot create checksum." >&2
    exit 1
  fi
}

check_shipment_export() {
  if gleam export --help | grep -Eq '^[[:space:]]+erlang-shipment([[:space:]]|$)'; then
    return 0
  fi

  echo "This Gleam installation does not support 'gleam export erlang-shipment'." >&2
  echo "Update Gleam and run this script again." >&2
  exit 1
}

need_cmd gleam
need_cmd erl
need_cmd rebar3
need_cmd tar
check_shipment_export

version=$(read_version)
unix_latest="$DIST_DIR/$APP_NAME-unix.tar.gz"
unix_versioned="$DIST_DIR/$APP_NAME-v$version-unix.tar.gz"
windows_latest="$DIST_DIR/$APP_NAME-windows.zip"
windows_versioned="$DIST_DIR/$APP_NAME-v$version-windows.zip"

echo "Packaging DropNest $version as a Gleam Erlang shipment."
echo "Users need Erlang installed to run the result."
echo ""

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

gleam deps download
gleam build
gleam export erlang-shipment

tar -C build -czf "$unix_latest" erlang-shipment
cp "$unix_latest" "$unix_versioned"
checksum_file "$unix_latest" "$unix_latest.sha256"
checksum_file "$unix_versioned" "$unix_versioned.sha256"

if command -v zip >/dev/null 2>&1; then
  (
    cd build
    zip -qr "../$windows_latest" erlang-shipment
  )
  cp "$windows_latest" "$windows_versioned"
  checksum_file "$windows_latest" "$windows_latest.sha256"
  checksum_file "$windows_versioned" "$windows_versioned.sha256"
fi

echo ""
echo "DropNest package complete."
echo ""
echo "Artifacts:"
echo "  $unix_latest"
echo "  $unix_latest.sha256"
echo "  $unix_versioned"
echo "  $unix_versioned.sha256"
if [ -f "$windows_latest" ]; then
  echo "  $windows_latest"
  echo "  $windows_latest.sha256"
  echo "  $windows_versioned"
  echo "  $windows_versioned.sha256"
fi
