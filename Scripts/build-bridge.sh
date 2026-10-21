#!/bin/sh
# Builds the Rust backend bridge (RailwayBridge) and places the static library where the linker finds it.
# Run by Xcode as a build phase; can also be run by hand from the repository root.
# Builds for the platform and architectures Xcode is building (macOS, iOS/iPadOS device or Simulator).
set -eu

export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

SRCROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CONFIGURATION="${CONFIGURATION:-Debug}"
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-$SRCROOT/build}"
PLATFORM_NAME="${PLATFORM_NAME:-macosx}"
ARCHS="${ARCHS:-$(uname -m)}"

if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo not found. Install Rust (https://rustup.rs or 'brew install rust') to build the Railway backend."
    exit 1
fi

# Keep the (large) Cargo build directory out of the project folder, which may be synced by iCloud.
export CARGO_TARGET_DIR="${RAILWAY_CARGO_TARGET_DIR:-$HOME/Library/Caches/RailwayBridge/target}"

if [ "$CONFIGURATION" = "Release" ]; then
    PROFILE=release
    PROFILE_FLAG=--release
else
    PROFILE=debug
    PROFILE_FLAG=
fi

rust_target() {
    case "$PLATFORM_NAME/$1" in
        macosx/arm64) echo aarch64-apple-darwin ;;
        macosx/x86_64) echo x86_64-apple-darwin ;;
        iphoneos/arm64) echo aarch64-apple-ios ;;
        iphonesimulator/arm64) echo aarch64-apple-ios-sim ;;
        iphonesimulator/x86_64) echo x86_64-apple-ios ;;
        *) echo "error: unsupported platform/architecture: $PLATFORM_NAME/$1" >&2; exit 1 ;;
    esac
}

cd "$SRCROOT/RailwayBridge"

LIBS=
for ARCH in $ARCHS; do
    TARGET=$(rust_target "$ARCH")
    if [ ! -d "$(rustc --print sysroot)/lib/rustlib/$TARGET" ]; then
        echo "error: the Rust standard library for $TARGET is not installed. Install Rust with rustup (https://rustup.rs) and run 'rustup target add $TARGET'."
        exit 1
    fi
    cargo build --target "$TARGET" $PROFILE_FLAG
    LIBS="$LIBS $CARGO_TARGET_DIR/$TARGET/$PROFILE/librailway_bridge.a"
done

mkdir -p "$BUILT_PRODUCTS_DIR"
# shellcheck disable=SC2086
lipo -create $LIBS -output "$BUILT_PRODUCTS_DIR/librailway_bridge.a"
