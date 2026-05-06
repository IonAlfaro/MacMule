# MacMule

MacMule is a native macOS eD2k/eMule-style client built with SwiftUI, backed by a standalone `MacMuleCore` Swift package and a local daemon process.

## Current state

- SwiftUI desktop app with downloads, search, Kad, network, statistics, logs, and settings views.
- `MacMuleCore` package with protocol, storage, daemon, and test coverage.
- Real `.part` persistence, daemon-backed snapshots, source discovery, peer block downloads, and transfer progress tracking.
- Modernized downloads UI and eMule-style download speed smoothing.

## Requirements

- macOS 15 or newer
- Xcode 16 or newer

## Open in Xcode

1. Open `MacMule.xcodeproj`.
2. Select the `MacMule` scheme.
3. Build or run the app on macOS.

## Build

```bash
xcodebuild -project MacMule.xcodeproj -scheme MacMule -configuration Debug -destination 'platform=macOS' build
```

## Build DMG

```bash
./Scripts/build-dmg.sh [version]
```

The version argument is optional and defaults to a date-based snapshot.

## Test the core package

```bash
cd MacMuleCore
swift test
```

## Project structure

- `MacMule/`: macOS app target
- `MacMuleCore/`: reusable core package and daemon
- `Scripts/`: build and distribution scripts
- `Docs/`: implementation notes and parity plans

## License

MIT — see [LICENSE](LICENSE).
