# eMule Parity Plan

Objective: preserve the network behavior of eMule 0.72 and put a modern SwiftUI interface on top. MacMule must not depend on being connected to a specific server to continue a download; the server only kicks off searches and sources, while the actual exchange happens between peers and, later, Kad.

## Architecture map

- `CServerConnect` / `CServerSocket` -> `ED2KServerTCPConnection`, `ED2KServerSession`, `CoreService`.
- `CDownloadQueue` / `CPartFile` -> `CoreTransferStore`, range scheduler, source queue.
- `CUpDownClient` / `CClientReqSocket` -> `ED2KPeerTCPConnection`, `ED2KPeerSession`.
- `ListenSocket` / `UploadQueue` / `SharedFiles` -> pending shared files and real uploads module.
- `Kademlia` -> separate UDP module with `nodes.dat`, routing table, keyword search, and source search.
- Preferences, credits, security, and IP filter -> persistent core configuration, not UI.
- MFC windows -> SwiftUI views: Search, Downloads, Servers, Kad, Shared, Uploads, Statistics, Logs, and Settings.

## Phase 1: Stable eD2k

- Modern eMule login with proper capabilities to avoid rejection for outdated client.
- Preconfigured and editable server list.
- Failover between servers without losing searches or active transfers.
- Functional LowID: keep the session accepted, use server callback, and do not treat low IDs as direct IPs.
- Local `GetSources` queue like eMule: enqueue transfers, send limited batches, and avoid repeating recent requests.
- Source retries when a download has no direct endpoints or when all peers fail.
- Persist remembered sources, cooldowns, range reservations, and resume state.

## Phase 2: Downloads like eMule

- Per-peer source states: connecting, on queue, downloading, no needed parts, too many connections, banned/error.
- Part selector by rarity and availability, not just next free range.
- A4AF: a single source announcing multiple files must be assigned to the most useful file.
- Full hashset verification, corrupt chunk recovery, and atomic promotion to Incoming.
- Client-to-client Source Exchange to request sources from already known peers.
- Request queue for file/name/status/parts per peer with limits and backoff.

## Phase 3: Uploads and sharing

- Shared folder scanning with incremental eD2k hashing.
- Respond to `file status`, `hashset`, `file name`, `start upload`, and `request parts`.
- Upload queue with slots, priorities, credits, and bandwidth limits.
- Publish shared files to the connected server and, later, to Kad.

## Phase 4: Kad

- UDP listener, bootstrap from `nodes.dat` and from peers.
- Kademlia table with buckets, expiration, and persistence.
- Keyword and source-by-hash search.
- Firewalled Kad callbacks for LowID/firewalled users.
- Dedicated UI with nodes, bootstrap status, and Kad searches.

## Phase 5: Security and compatibility

- IP filter and list import.
- Secure Identification and credits.
- Obfuscation when the server/peer supports it.
- eMule-compatible preferences where relevant: ports, limits, folders, priorities, servers.

## Phase 6: Modern SwiftUI

- The UI only orchestrates; the core decides network, persistence, and transfers.
- Dense, operational views: downloads with real columns, source inspector, filterable logs, and visible network status.
- Expected actions: delete servers, import lists, reconnect, search without being connected by queuing the search, pause/resume/remove downloads.
- Clear diagnostics for LowID, occupied ports, UPnP/NAT-PMP failure, and server rejection due to version.

## Executed in this session

- A local `GetSources` request queue inspired by `CDownloadQueue::ProcessLocalRequests` is added.
- Active transfers are re-enqueued after login and processed in batches of up to 15 requests.
- The core avoids repeating a recent request except for events that must force it, such as download addition/resume or peer exhaustion.
- When pausing or deleting a download, its pending source search state is cleaned up.
- Peer negotiation now sends Source Exchange v2/v4 (`OP_REQUESTSOURCES2`) and consumes `OP_ANSWERSOURCES2` replies to bootstrap additional direct sources without depending solely on the server.
