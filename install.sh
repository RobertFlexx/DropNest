#!/bin/sh
set -eu

GITHUB_OWNER="${GITHUB_OWNER:-RobertFlexx}"
GITHUB_REPO="${GITHUB_REPO:-dropnest}"
BINARY_NAME="dropnest"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
INSTALL_PATH="$INSTALL_DIR/$BINARY_NAME"
SHIPMENT_PATH="$INSTALL_DIR/dropnest-shipment"
BASE_URL="https://github.com/$GITHUB_OWNER/$GITHUB_REPO/releases/latest/download"
ARCHIVE_NAME="dropnest-unix.tar.gz"
CHECKSUM_NAME="dropnest-unix.tar.gz.sha256"

usage() {
  cat <<'EOF'
DropNest installer

Usage:
  sh install.sh
  sh install.sh --uninstall
  sh install.sh --help

Environment:
  INSTALL_DIR=/some/path   Install directory. Default: $HOME/.local/bin
  GITHUB_OWNER=name        GitHub owner for release downloads. Default: RobertFlexx
  GITHUB_REPO=name         GitHub repository for release downloads. Default: dropnest

DropNest is distributed as a Gleam Erlang shipment.
It does not require Gleam to run, but it does require Erlang.
Temporary public links additionally require the optional cloudflared executable.
EOF
}

need_downloader() {
  if command -v curl >/dev/null 2>&1; then
    echo "curl"
  elif command -v wget >/dev/null 2>&1; then
    echo "wget"
  else
    echo "Neither curl nor wget was found. Install one and run this installer again." >&2
    exit 1
  fi
}

need_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

download() {
  url="$1"
  out="$2"
  tool="$3"

  if [ "$tool" = "curl" ]; then
    curl -fsSL "$url" -o "$out"
  else
    wget -q "$url" -O "$out"
  fi
}

check_erlang() {
  if command -v erl >/dev/null 2>&1; then
    return 0
  fi

  cat >&2 <<'EOF'
Erlang was not found.

DropNest is a Gleam/BEAM application, so it needs Erlang installed.
Install Erlang, then run this installer again.

Examples:
  Debian/Ubuntu: sudo apt install erlang
  Fedora:        sudo dnf install erlang
  Arch:          sudo pacman -S erlang
  macOS:         brew install erlang
EOF
  exit 1
}

verify_checksum() {
  file="$1"
  sum_file="$2"

  if [ ! -f "$sum_file" ]; then
    echo "Checksum file was not downloaded. Skipping verification."
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    (
      cd "$(dirname "$file")"
      sha256sum -c "$(basename "$sum_file")"
    )
  elif command -v shasum >/dev/null 2>&1; then
    expected=$(awk '{print $1}' "$sum_file")
    actual=$(shasum -a 256 "$file" | awk '{print $1}')
    if [ "$expected" != "$actual" ]; then
      echo "Checksum verification failed." >&2
      exit 1
    fi
  else
    echo "No SHA256 tool found. Skipping checksum verification."
  fi
}

write_wrapper() {
  cat > "$INSTALL_PATH" <<EOF
#!/bin/sh
exec "$SHIPMENT_PATH/entrypoint.sh" run "\$@"
EOF
  chmod +x "$INSTALL_PATH"
}

warn_path() {
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) return 0 ;;
    *)
      echo ""
      echo "Warning: $INSTALL_DIR is not in your PATH."
      echo "Add this to your shell profile if 'dropnest' is not found:"
      echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
      ;;
  esac
}

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --uninstall)
    rm -f "$INSTALL_PATH"
    rm -rf "$SHIPMENT_PATH"
    echo "DropNest removed from $INSTALL_DIR"
    exit 0
    ;;
  "") ;;
  *)
    echo "Unknown option: $1" >&2
    echo "Run: sh install.sh --help" >&2
    exit 1
    ;;
esac

check_erlang
need_tool tar
tool=$(need_downloader)

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

archive="$tmp_dir/$ARCHIVE_NAME"
checksum="$tmp_dir/$CHECKSUM_NAME"

echo "Downloading DropNest from GitHub Releases..."
download "$BASE_URL/$ARCHIVE_NAME" "$archive" "$tool"

if download "$BASE_URL/$CHECKSUM_NAME" "$checksum" "$tool"; then
  verify_checksum "$archive" "$checksum"
else
  echo "Checksum not available. Continuing without checksum verification."
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$tmp_dir/extract" "$SHIPMENT_PATH"
mkdir -p "$tmp_dir/extract"
tar -xzf "$archive" -C "$tmp_dir/extract"
mv "$tmp_dir/extract/erlang-shipment" "$SHIPMENT_PATH"
write_wrapper

echo ""
echo "DropNest installed."
echo ""
echo "Run:"
echo "  dropnest serve"
echo ""
echo "LAN mode:"
echo "  dropnest serve --lan --pin family-owl-72 --dir ~/Downloads/DropNest"
echo ""
echo "Temporary friend link (requires cloudflared):"
echo "  dropnest serve --tunnel --pin family-owl-72 --dir ~/Downloads/DropNest"
warn_path
