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

## Release

Push a version tag to trigger the DMG build:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

The `.dmg` will be attached to the GitHub release automatically via Actions.

## Test the core package

```bash
cd MacMuleCore
swift test
```

## Project structure

- `MacMule/`: macOS app target
- `MacMuleCore/`: reusable core package and daemon
- `Docs/`: implementation notes and parity plans (local only)

## License

MIT — see [LICENSE](LICENSE).
