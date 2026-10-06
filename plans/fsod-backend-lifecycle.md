# Original FSoD lifecycle infrastructure overlay

## Scope and provenance

Source remains immutable at `6fd20aad4a7905b13f25389c68368a942a2b68cb`.
`backend.py build` archives that revision into its private build tree, applies
`linux-isolation.patch`, then `lifecycle.patch`, and records both SHA-256 hashes
in the manifest. No submodule edits, frontend delays, replacement game rules,
AI rewrites, content changes, or production/shared DB access are involved.

This is an intentional backend compatibility/lifecycle deviation, **not** a
claim that every original source byte or scheduling bug remains unchanged.
The parent owns runtime installation and the genuine Godot portal/combat replay.
This worker only compiles isolated snapshots and drives a controlled C# fixture.

## Original failure and disposal trace

Parent evidence: `/home/jay/gravebag-godot/scripts/fsod_backend/.state/wServer-runtime.log:133-151`
contains `System.NullReferenceException`, `RealmManager.Disconnect ... [0x000a7]`,
`AsyncMethodBuilderCore.<ThrowAsync>` and `FATAL UNHANDLED EXCEPTION` after joining
world 1. The parent reports the actual Nexus portal `0x0712`, character 2, and
`MapInfo` for `NexusPortal.Golem`; this worker did not independently replay them.

Original pinned source findings (line numbers are for the immutable revision):

- `wServer/realm/RealmManager.cs:175-182`: `public async void Disconnect`,
  `client.Disconnect();`, `await client.Save();`, followed by
  `Clients.TryRemove(client.Account.AccountId, out dummy)` and `client.Dispose()`.
  Account identity is read **after** an asynchronous suspension, and removal
  uses only the account key. An older completion can remove a replacement client.
- `wServer/networking/Client.cs:113-124,163-179`: `Disconnect` queues
  `DisconnectFromRealm`; that callback calls both `Save();` and
  `Manager.Disconnect(this);`. A direct manager disconnect first calls
  `client.Disconnect()`, which can queue another manager disconnect. Consequently
  multiple saves/manager continuations can exist for one client. `Reconnect`
  separately calls `Save(); SendPacket(pkt);` without waiting for the save.
- `Client.cs:130-159,213-228`: save callbacks read mutable `Player`, `Character`,
  and `Account`; public `Dispose` immediately clears these references. The only
  original direct **client** disposal caller found in wServer is
  `RealmManager.Disconnect`. The evidence does not establish an independent
  packet-handler call to `Client.Dispose`; the competing manager continuations
  themselves explain early disposal while another save/continuation is pending.
- `wServer/realm/NetworkTicker.cs:51-58`: a queued packet for a disconnected
  client removes the account key before save completion. It does not dispose
  the client, but can expose the key to a newer session early.
- `RealmManager.cs:327-341`: `TryConnect` removes an existing client based on
  `!Socket.Connected`, not persistence completion, then inserts the new one.
- `wServer/realm/entities/player/Player.cs:746-766`: both removal/disconnected
  Tick branches separately schedule `db.UnlockAccount(Client.Account)`.
  These fire-and-forget unlocks can outlive the source client/session.
- `wServer/networking/IPacketHandler.cs:24-42,51-68`: handlers are singletons;
  `Handle` overwrites `this.client`, while `Manager` reads that mutable field.
  It does not dispose a client. `HelloHandler.cs:41-43,169` reads this implicit
  manager from its asynchronous DB callback. Hello now captures its explicit
  client's manager and tracks that DB work behind the teardown barrier.
- `HelloHandler.cs:75-108`: a verified but rejected/in-use login can still have
  `Account` populated before disconnect. It must not unlock/remove an existing
  session just because it has verified account data.
- `wServer/networking/NetworkHandler.cs:72,84,96,139,210` and
  `Client.cs:109` route policy/EOF/socket/packet errors through `Disconnect`.
  Gameplay handlers, timers, Program's exception path, Server.Stop, and
  RealmManager.Stop also disconnect; none is a second direct client disposer.
- `wServer/networking/Server.cs:56-65` has a second `async void` shutdown tail;
  `RealmManager.cs:307-320` terminates loops and separately unlocks accounts
  without waiting for that tail. Shutdown now shares the same lifecycle owner.

## Changed lifecycle semantics

1. Account ownership is captured under the per-client lifecycle lock only when
   registration succeeds. Verified-but-unregistered sessions cannot persist,
   unlock, or unregister someone else's session. Registration and packet handling
   cannot race teardown's admission decision; disconnected clients cannot revive.
2. Ordinary saves are serialized per client. Original `Player.SaveToCharacter`
   executes before asynchronous DB persistence; account/character/world inputs
   are captured rather than reread after disposal. Ordinary saves no longer
   unlock the account: departure owns that operation.
3. Reconnect seals persistence once, waits for all earlier tracked work and the
   final source character save, unlocks once, then schedules the unchanged
   reconnect packet on the logic loop. Additional gameplay packets after transfer
   intent are ignored. Duplicate reconnect/logout/dispose requests are inert.
4. Disconnect exposes one stable `Task`, not `async void`. Public Dispose requests
   teardown and cannot immediately clear account/character/player state.
   Final cleanup runs on the logic loop after persistence finishes. The world
   entity is detached before its client fields are cleared. Cleanup failures are
   logged independently so one failure cannot prevent other fields being freed.
5. Removal is an atomic `(accountId, exactClient)` compare-and-remove. Only a
   completed reconnect persistence barrier permits replacement of an old client;
   a closed socket alone does not. The old client's later logout reuses its
   sealed barrier, so it cannot issue another save/unlock against a new session.
6. NetworkTicker only discards packets; it never unregisters clients. Player.Tick
   retains its original departure branches but requests the lifecycle owner
   instead of dispatching independent account unlocks.
7. DB callback failures are explicitly conveyed out of the original ticker's
   callback-swallowing boundary. Failed persistence is logged; reconnect is not
   sent and no success unlock occurs. Teardown still frees resources; normal
   original account-lock expiry/recovery remains necessary after such a failure.
8. Server.Stop synchronously closes acceptance and requests departure. Manager
   shutdown rejects new admissions and waits up to 15 seconds for the same
   save/unlock/disposal tasks while logic remains alive, before stopping tickers.
   A drain timeout is logged, not converted into an unconditional account unlock.
9. A crash-cleaned missing/refused supervisor control socket produces structured
   `verify` not-ready (exit 1) and idempotent `stop: already_stopped` (exit 0).
   A matching still-live startup supervisor instead yields `stop: unavailable`
   (exit 1). Exact state-bound argv prevents treating a reused PID as this launch.
   No fallback signals or parent-state repairs are performed.

## Fidelity limits and proof

Character identity, HP, experience, equipment, last-seen and original save field
mapping are retained. Arena owner ID `-6` still excludes character persistence;
its terminal departure now unlocks instead of leaking the session lock. Save
and unlock are ordered, **not** a newly introduced DB transaction. Original DTO
objects and SQL/model code remain in use; this overlay does not promise immutable
per-save DTO snapshots or repair every independent gameplay DB callback. Death,
guild/pet/gift operations and other handlers' implicit-context patterns are not
rewritten or claimed safe by this scoped portal lifecycle proof.

`tests/fsod-backend-lifecycle.test.mjs` compiles the patched original Client,
NetworkTicker and Server, plus verbatim patched RealmManager disconnect/registry/
shutdown methods. Controlled DB/transport/world fixtures force eleven cases:
blocked save + account nulling + Dispose, duplicate logout, same-account newer
client, reconnect save-before-send/handoff, serialized saves, stale queued packets,
save callback/acquisition/snapshot failures, arena/unauthenticated cleanup,
rejected same-account login, pending auth/disposal, and bounded shutdown drain.
The persistence fixture checks character values and save-before-unlock ordering.
Two compiled negative controls restore key-only removal and early field disposal;
the same probes must reject each with its specific expected failing assertion.

A separate test uses the **normal backend.py build pipeline** in a temporary
private state tree to compile original wServer/server/terrain with real pinned
dependencies, recording both patch hashes. Eleven selected AI/content/generation/
portal source files remain byte-identical. The Player patch is also compared
against the original with exactly its two lifecycle unlock lines replaced.
No listener, database runtime, existing DB, or parent `.state` is used.

Run: `node --test tests/fsod-backend-lifecycle.test.mjs`.
Tools: git, patch, Python 3, Mono/mcs/xbuild, bwrap and the backend's offline
pinned dependencies (hash-checked `/home/jay/.nuget/packages`); source is the
pinned initialized submodule or explicit immutable `/home/jay/fsod-ref` fixture.
Verification must also pass from a fresh clone with isolated HOME; none of the
checks consult the operator's plans/config. This proves compiled lifecycle
interleavings and build fidelity, **not** live portal → realm → combat success.
