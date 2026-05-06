# MacMule

[![CI](https://github.com/IonAlfaro/MacMule/actions/workflows/ci.yml/badge.svg)](https://github.com/IonAlfaro/MacMule/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-lightgrey)]()

A native macOS eD2k/eMule client built with SwiftUI, backed by a standalone `MacMuleCore` Swift package and a local daemon process.

## Features

### Downloads
- eD2k peer-to-peer transfers with `.part` persistence and atomic completion
- Per-transfer hashset verification (eD2k/MD4 + `p=` AICH)
- Range scheduler with rarity-aware part selection
- Source discovery via server `GetSources`, peer Source Exchange v2/v4, and Kad
- Automatic peer failover, range reservations, and retry cooldowns
- Corruption blackbox with malicious source detection

### Search
- eD2k server search with file-type filter pills
- Kad keyword and source-by-hash search
- Search results with availability, sources, and one-click download

### Servers
- Preconfigured eD2k server list with manual add/remove/import (`server.met`)
- Automatic failover between servers without losing active transfers
- LowID support with UPnP/NAT-PMP port mapping for better connectivity
- Server status, ping, and user counts

### Kad
- Kademlia DHT with routing table, bootstrap from `nodes.dat` and peers
- Keyword and source search independent of eD2k servers
- Firewalled Kad callbacks for LowID users
- Dedicated Kad view with node status and active searches

### Uploads & Sharing
- Upload queue with slots, waiting clients, and credit-based scoring
- Shared file list with eD2k hashing and request tracking
- Bandwidth limits and speed tracking per slot

### Security
- IP filter with range/CIDR parsing and import
- Secure Identification (Curve25519)
- Protocol obfuscation layer
- Credit system with upload/download tracking

### Interface
- Sidebar navigation with 9 tabs: Downloads, Search, Servers, Kad, Uploads, Shared, Statistics, Logs, Settings
- Live dual-line throughput chart with 60-sample rolling history
- Source inspector with per-peer state, queue rank, and score
- `ed2k://` URL scheme handling (paste, drag-and-drop, Cmd+Shift+D)
- Local web interface for remote monitoring

### Automation
- Scheduler with time-based bandwidth limits, connection, and category actions
- Automatic reconnect and resume after daemon restart
- Daemon-side checkpoint with atomic crash recovery

## Architecture

```
MacMule.app (SwiftUI)
    │
    │  JSON-RPC / Unix socket
    ▼
macmule-core-daemon (SwiftPM executable)
    │
    ▼
MacMuleCore (Swift package)
 ├── ED2KServerTCPConnection    ── eD2k server sessions (search, sources, server list)
 ├── ED2KPeerTCPConnection      ── Peer-to-peer block downloads
 ├── ED2KPeerTCPListener        ── Incoming peer handshakes
 ├── KadService                  ── Kad DHT (routing, search, bootstrap)
 ├── CoreTransferStore           ── .part persistence, chunk tracking, completion
 ├── CoreUploadQueue             ── Upload slots, waiting clients, scoring
 ├── CoreSharedFileList          ── Shared folder scanning and hashing
 ├── CoreScheduler               ── Time-based automation
 ├── CoreIPFilter                ── IP range filtering
 ├── CoreSecureIdent             ── Curve25519 identity
 ├── CoreObfuscationLayer        ── Stream encryption/decryption
 ├── CoreCreditsList             ── Upload/download credit tracking
 └── CoreWebServer               ── Embedded monitoring web UI
```

## Requirements

- macOS 15 or newer
- Xcode 16 or newer
- Swift 6 toolchain

## Quick Start

```bash
git clone https://github.com/IonAlfaro/MacMule.git
cd MacMule
open MacMule.xcodeproj
```

Select the `MacMule` scheme and press **Run** (⌘R).

## Build

```bash
xcodebuild \
  -project MacMule.xcodeproj \
  -scheme MacMule \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

## Test

```bash
cd MacMuleCore
swift test
```

## Release

Push a version tag to trigger an automatic DMG build via GitHub Actions:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

The `.dmg` will be attached to the release on the [Releases](https://github.com/IonAlfaro/MacMule/releases) page.

## Project Structure

```
MacMule/
├── MacMule.xcodeproj/          Xcode project
├── MacMule/                    macOS app (SwiftUI views, models, core client)
├── MacMuleCore/                Swift package (protocol engine, daemon, tests)
│   ├── Sources/MacMuleCore/    Core library
│   ├── Sources/MacMuleCoreDaemon/  Daemon entry point
│   ├── Sources/MacMuleZlib/    Zlib C bridge
│   └── Tests/                  Unit tests
├── Docs/                       Implementation notes (local only)
└── .github/workflows/          CI and release automation
```

## Roadmap

| Area | Status |
|------|--------|
| eD2k server protocol (login, search, sources, server list) | Done |
| Peer-to-peer downloads (.part persistence, hashset, range scheduling) | Done |
| Kad DHT (routing table, bootstrap, keyword/source search) | In progress |
| Upload queue and shared file hashing | Core done, end-to-end in progress |
| Security (IP filter, Secure Ident, obfuscation, credits) | Core done |
| Notarized DMG and Sparkle auto-updates | Planned |

## License

MIT — see [LICENSE](LICENSE).
