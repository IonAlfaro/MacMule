# MacMule Implementation Plan

## Current slice

- SwiftUI macOS shell with a modern sidebar and transfer-focused workspace.
- Observable app store backed by a replaceable `MacMuleCoreClient` boundary.
- In-memory core implementation that simulates searches, downloads, connection state, servers, shared files, settings, and statistics.
- Standalone `MacMuleCore` Swift package with tested eD2k file-link parsing, linked into the macOS app as a local package.
- Downloads view can accept a real `ed2k://` file link, validate it, and enqueue it through the core boundary.
- `macmule-core-daemon` executable target with newline-delimited JSON-RPC over stdin/stdout.
- `macmule-core-daemon --socket <path>` serves the same JSON-RPC protocol over a Unix domain socket.
- JSON-RPC commands implemented and tested: `snapshot`, `events_since`, `add_ed2k_link`, `search`, `pause`, `resume`, `remove`, `write_block`, `connect_server`, `disconnect_server`, `add_server`, `remove_server`, and `import_servers`.
- Incremental core event feed with cursor-based JSON-RPC `events_since`.
- macOS app includes a daemon-backed `MacMuleCoreClient`.
- App store polls the core event feed by cursor and applies fresh snapshots when daemon state changes.
- UI surfaces the active core runtime: external socket, bundled daemon, or local demo fallback.
- UI exposes recent core runtime logs and can restart the bundled daemon from the Network view.
- Bundled daemon launcher captures stdout, stderr, and lifecycle events for diagnostics.
- Core transfer persistence writes JSON sidecars and `.part` files under the daemon storage root.
- Transfer storage tracks normalized written byte ranges, derives eD2k-sized chunk state, and supports sparse block writes.
- Completed transfers are promoted from `.part` storage into Incoming with sanitized, collision-safe file names.
- Completed transfers are verified with eD2k/MD4 hashes before promotion; mismatches stay in Temp and become failed transfers.
- Optional eD2k `p=` hashsets are parsed, persisted with transfers, and used for per-chunk verification as chunks complete.
- Core eD2k protocol layer can encode/decode TCP packets, buffer stream reads, write login requests, encode eD2k tags, and parse server messages, server identities, and server-list payloads.
- Core eD2k protocol layer now also builds plain TCP search requests and decodes TCP search-result payloads into typed result items with descriptor tags.
- Testable eD2k server session creates login packets from configuration and maps incoming server packets into typed session events.
- TCP adapter built on Network.framework can connect to an eD2k server endpoint, send the session login, feed incoming bytes into the protocol decoder, and emit typed connection/session events.
- Core network state and daemon logs now react to real eD2k TCP session events, and the JSON-RPC surface can connect or disconnect a server session.
- Core snapshot now persists an eD2k server list, supports manual add/remove/import over JSON-RPC, and auto-imports server endpoints announced by remote `OP_SERVERLIST` packets.
- Core search state now lives in the daemon snapshot, `search` is exposed over JSON-RPC, and incoming eD2k search results flow into the macOS Search view.
- Daemon-backed eD2k sessions now use a stable persisted user hash, remember a preferred server endpoint, and can reconnect with `connect_server` even when host/port are omitted.
- The daemon now opens a real incoming peer TCP listener on the configured eD2k port, auto-replies to inbound peer `hello` handshakes, and reports LowID as a limited but still searchable connection state instead of treating it like a disconnected session.
- Automatic peer port publication now tries UPnP first and falls back to NAT-PMP when the local router supports it, improving the odds of escaping LowID on home networks without manual router setup.
- Enqueuing a transfer while connected now triggers eD2k `get sources`, and `found sources` packets update live source counts on transfers.
- Core peer-protocol groundwork now encodes/decodes eD2k `hello`, `helloanswer`, `request parts`, and `sending part` packets, and a testable peer session maps peer traffic into typed events.
- Core can now open a first peer TCP session from a discovered source, send `hello`, request an initial block range, and persist incoming `sending part` payloads through `writeBlock`.
- Peer downloads now continue requesting successive missing ranges after each received block, so a transfer can advance across multiple peer requests instead of stopping at the first block.
- Peer downloads now keep a queue of discovered endpoints, fail over to the next peer when one drops mid-transfer, and re-request fresh sources from the server when the known peer list is exhausted.
- Peer downloads now reserve block ranges per endpoint, start up to two peers in parallel for the same transfer, and avoid overlapping requests while advancing the next missing ranges.
- Reconnecting or restoring a daemon session now reboots source lookups for queued/downloading transfers automatically after login, so persisted jobs resume bootstrapping without manual nudges.
- Peer sessions now request remote part hashsets without duplicating work across active peers, retry the request on another live peer when needed, persist the hashes into transfers which started without `p=`, and retroactively fail already-complete chunks if the late hashset proves they were wrong.
- Transfer sidecars now persist remembered peer endpoints and failure counts, so a restarted daemon can immediately retry healthy remembered sources after login instead of relearning every peer from scratch.
- Transfer sidecars now also persist in-flight peer range reservations with a short lease, so a restart avoids immediately re-requesting the same block while still letting stale reservations expire back into the scheduler.
- Transfer sidecars now persist chunk-level retry cooldowns too, so repeated failures on the same range survive restarts and the scheduler can advance other missing blocks first when there is healthier work available.
- Active transfers now use an eMule-style local `GetSources` queue with bounded batches, source re-query cooldowns, and pause/remove cleanup instead of one-off source lookups.
- Peer negotiation now sends eMule Source Exchange v2/v4 requests and ingests `AnswerSources2` replies to bootstrap additional direct sources during active downloads.
- The daemon now keeps an atomic resume checkpoint plus a runtime lock marker, so an unclean restart can scrub stale runtime-only transfer state back to resumable `queued` work without losing the intent to reconnect and continue.
- Core service exposes block writes that update transfer progress and emit incremental transfer events.
- The daemon API can now accept base64-encoded block writes over JSON-RPC for transfer-engine integration tests.
- `macmule-core-daemon` restores queued transfers from Application Support by default, with optional `--storage <path>` override.
- Xcode bundles `macmule-core-daemon` into `MacMule.app/Contents/MacOS/` during app builds.
- App startup prefers `MACMULE_CORE_SOCKET`, then launches the bundled daemon on a temporary Unix socket, then falls back to the in-memory core if no daemon is available.
- Demo data constrained to legitimate/open-source examples.
- macOS sandbox entitlements for selected-file read/write and client/server networking.
- macOS app handles `ed2k://` URL scheme via `onOpenURL` and Cmd+Shift+D menu shortcut; supports paste-from-clipboard.
- App-level store (`MacMuleStore`) persists all user settings to UserDefaults across launches.
- Session duration timer updates every second and is shown in the sidebar and Statistics view.
- Rolling per-second speed history (60 samples) drives the live dual-line throughput chart in Statistics.
- Downloads view has filter pills (All / Downloading / Paused / Completed / …) and drag-and-drop for `ed2k://` links.
- Search view has file-type filter pills that narrow results by FileKind.
- Uploads view shows upload-centric row and metrics strip.
- Network view has "Add server" sheet that calls `add_server` JSON-RPC.
- Settings view uses `.fileImporter` folder picker and shows port info panel.
- Bundled daemon now accepts user-selected Incoming and Temp directories from the app, so completed downloads and `.part` storage can both live outside the daemon metadata root.
- Sidebar shows live active-download and active-upload badge counts.
- Connection status indicator shows a coloured dot instead of a full label.
- All views use `@EnvironmentObject` sourced from a single `MacMuleStore` owned by `MacMuleApp`.

## Next technical slices

1. Expand the standalone core module:
   - replace app polling with a long-lived stream for transfer and network updates.
   - add richer structured daemon log categories and export support.

2. Deepen file storage:

3. Implement eD2k phase 1:

4. Implement transfers phase 1:
   - hash validation.
   - basic upload queue.
   - global rate limits.

5. Add Kad after eD2k downloads are stable:
   - UDP transport.
   - routing table.
   - bootstrap.
   - keyword search.
   - source search.

6. Harden distribution:
   - notarized `.dmg`.
   - Sparkle updates.
   - exportable logs.
   - user-selected share folders only.
