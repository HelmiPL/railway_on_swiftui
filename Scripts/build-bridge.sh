#!/bin/sh
# Builds the Rust backend bridge (RailwayBridge) and places the static library where the linker finds it.
# Run by Xcode as a build phase; can also be run by hand from the repository root.
set -eu

export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

SRCROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CONFIGURATION="${CONFIGURATION:-Debug}"
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-$SRCROOT/build}"

if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo not found. Install Rust (https://rustup.rs or 'brew install rust') to build the Railway backend."
    exit 1
fi

# Keep the (large) Cargo build directory out of the project folder, which may be synced by iCloud.
export CARGO_TARGET_DIR="${RAILWAY_CARGO_TARGET_DIR:-$HOME/Library/Caches/RailwayBridge/target}"

if [ "$CONFIGURATION" = "Release" ]; then
    PROFILE=release
    set -- --release
else
    PROFILE=debug
    set --
fi

cd "$SRCROOT/RailwayBridge"
cargo build "$@"

mkdir -p "$BUILT_PRODUCTS_DIR"
cp "$CARGO_TARGET_DIR/$PROFILE/librailway_bridge.a" "$BUILT_PRODUCTS_DIR/librailway_bridge.a"
