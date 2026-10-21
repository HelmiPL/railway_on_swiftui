# Railway for macOS

A native SwiftUI version of [Railway](https://gitlab.com/schmiddi-on-mobile/railway) for macOS 27, with the same
features and general UX as the original GNOME app.

## Layout

| Path | Contents |
| --- | --- |
| `RailwayApp/` | The SwiftUI app (models, state, views, assets). |
| `RailwayBridge/` | A small Rust static library exposing Railway's backend crates (`railway-api`) through a C ABI with JSON payloads. All networks (HAFAS profiles, search.ch, Transitous, DB) behave exactly as in Railway. |
| `railway/` | The original Railway source code, for reference. Not part of the build. |
| `Scripts/` | `build-bridge.sh` (run by Xcode) and `make-dmg.sh` (packages a built app into `build/Railway.dmg`). |

## Building

Requirements: Xcode 27 and a Rust toolchain (`brew install rust` or [rustup](https://rustup.rs)).

Open `Railway.xcodeproj` and run the *Railway* scheme. The first build compiles the Rust backend, which takes a
few minutes; its build directory is kept in `~/Library/Caches/RailwayBridge` (override with
`RAILWAY_CARGO_TARGET_DIR`) so it stays out of iCloud.

Change `PRODUCT_BUNDLE_IDENTIFIER` (currently `com.example.Railway`) and set a development team before distributing.

## Development helpers

Debug builds understand a few environment variables, see `RailwayApp/App/DebugAutomation.swift`, e.g.
`RAILWAY_DEMO="Berlin Hbf|München Hbf"` to run a search on launch.

## License

GPL-3.0-or-later, like Railway.
