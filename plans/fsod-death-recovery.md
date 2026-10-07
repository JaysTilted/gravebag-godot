# Original FSoD death → new-HELLO persistence/registration barrier

## Scope and provenance

Source remains immutable at `6fd20aad4a7905b13f25389c68368a942a2b68cb`.
`backend.py build` archives that revision into its private build tree, applies
`linux-isolation.patch`, then `lifecycle.patch`, and records both SHA-256 hashes
in the manifest. No submodule edits, Linux-isolation changes, Godot frontend
changes, parent `.state` start/stop, client delays/retries, account kicks,
unlock-before-save, death-row wipes, or gameplay changes are involved.

This is an intentional backend lifecycle deviation, **not** a claim that every
original scheduling byte remains unchanged. The parent owns runtime
installation and the genuine Godot portal/combat/death/new-HELLO replays. This
worker only patches the isolated build snapshot and drives controlled C# plus
isolated-build proof. Future verification tree remains until receipt accepted;
parent will not retire early.

## Original failure

Parent filtered facts: real Godot bot reaches realm, source HP 100→65→15→5→
DEATH, next immediate UI-equivalent restart (GameId -2, Key 0, char -1, CLASS
Wizard 782) sends new HELLO. Then authenticating → offline (no Failure packet),
never next MAPINFO/CREATE. Latest old-current exec `7a232b54` result exit 1
bounded deadline. Real server `.state/wServer-runtime.log` shows only
IOException after socket closed (line 96 socket-shutdown event = old cleanup
only, no SaveException). Numeric `accId` bug is already fixed/merged/compiled
(150 cases) with normal spawn; frontend transport replacement
`on_disconnected` + bot fallthrough is already `cf8039a`. Parent stopped the
fixture backend until patch ready; all accounts/death rows/IDs preserved.

Original pinned source findings (immutable revision):

- `wServer/realm/entities/player/Player.cs:444 Death`: queues
  `DoActionAsync(SaveCharacter+Death, no unlock)`, sends DeathPacket, arms
  `WorldTimer(1000, Client.Disconnect)`, `LeaveWorld`. Departure unlock/save/
  removal runs only via Disconnect.
- `wServer/networking/Client.cs:113 Disconnect + DisconnectFromRealm` and
  `wServer/realm/RealmManager.cs:175 async void Disconnect`: `Socket.Close`
  immediate, `Save (SaveCharacter+Unlock)` on `DatabaseTicker` pool,
  key-only `TryRemove`, `Dispose`. New HELLO races DB unlock + dict removal.
- `wServer/networking/handlers/HelloHandler.cs:41 Verify`,
  `:75 CheckAccountInUse BEFORE TryConnect`, `:327 TryConnect
  Socket.Connected gate then TryAdd`. `db/Database.cs:1311
  CheckAccountInUse` returns true (reject Account in use) while
  `accountInUse=1` and `600-(UtcNow-lastSeen)>0`, else `UnlockAccount` +
  false. `Player.cs:603 Init` later `LockAccount`s on world entry.
- Existing `lifecycle.patch` keeps both gates but only solves portal
  Reconnect handoff: `TryConnect` replaces only if
  `previous.CanReplaceAfterReconnect (reconnecting && sealed &&
  RanToCompletion)`. Normal DEATH/Disconnect never sets `reconnecting`, so
  still rejects. `CheckAccountInUse` still sees `1` because old `Persist`
  unlock has not completed. Hence N authenticating → offline before MapInfo.

## Fix (in `lifecycle.patch` only)

- `Client.cs`: `MarkDeathDeparting()` at exact original DEATH moment (never HP0-inferred,
  never kicks living), `IsDeparting (disposed||disconnectQueued||reconnecting||
  sealed||deathDeparting||Stage==Disconnected)`,
  `IsPortalReconnectOnly (reconnecting && !disconnectQueued && !disposed)`,
  `PersistenceBarrier (saveTask)`. No timing assumption: EARLY HELLO before
  read-loop EOF/Disconnect joins via `deathDeparting`, not Verify latency.
- `RealmManager.cs`: `DepartureTaskFor(accountId,newcomer)` returns null if
  no previous/self/alive (alive still rejects immediately; never wait, kick,
  or unlock-before-save). Portal-only returns `PersistenceBarrier` (never
  dispose portal owner). Normal DEATH returns `CompleteDisconnect` (idempotent
  join of save+unlock+pair-Remove+DisposeCore, save-before-unlock preserved,
  old cannot remove new).
- `Player.cs` Death: tracks DeathRow (`SaveCharacter+Death`) via `RunSessionAction`
  behind the teardown barrier so departing terminal Save joins after it (fixes
  untracked Death race vs Disconnect Save). Preserves DeathPacket/1s WorldTimer/
  LeaveWorld/Dead/Save mapping; fallback raw `DoActionAsync` only if scheduling fails.
- `HelloHandler.cs`: two-phase, no DB held across await, never blocks
  Logic/DB queues. Phase1 `RunSessionAction(Verify+guest)` (tracked). Then
  pool continuation peeks `DepartureTaskFor`, `WhenAny(departure,15s timeout)`,
  then Phase2 `RunSessionAction(CheckAccountInUse→TryConnect→world→MapInfo)`.
  Captured `manager/guid/password/buildVersion/gameId/key/mapInfo`; portal-key,
  whitelist, guest, world, MapInfo, Failure texts unchanged. Save-fail remains
  locked (Check still true); timeout still rejects (no hang).
- Unchanged: death rows/SQL, `SaveToCharacter` mapping, arena `-6` exclusion
  (now unlocks via departure), `NetworkTicker` never removes, pair-remove,
  shutdown 15 s bound, `Server.Stop` synchrony.

## Proof

- `scripts/fsod_backend/tests/LifecycleRegression.cs`: 15 forced interleavings
  (existing 11 + `DeathHelloBarrier`, `HelloLiveReject`, `HelloSaveFailLocked`,
  `EarlyDeathHelloBeforeDisconnect`). `Early` forces HELLO before Disconnect/EOF
  (only `deathDeparting`, Logic 0) with pending DeathRow, proving deterministic
  ordering without delay: DeathRow first, terminal after, then registration.
  `DeathHelloBarrier` forces immediate DEATH new-HELLO while Save pending:
  no premature unlock/registration, unlock then removal gating, old cannot
  remove new, save-before-unlock + identity preserved. `HelloLiveReject`
  proves alive returns null and still rejects with no save/unlock.
  `HelloSaveFailLocked` proves failed save stays locked despite empty dict.
  Fixture `db.Database` adds `Locks/Lock/CheckAccountInUse` mirroring
  original `accountInUse` semantics; `New` + `Lock` models entered-world lock.
- `tests/fsod-backend-lifecycle.test.mjs`: pins revision, applies real overlay,
  compiles patched Client/NetworkTicker/Server + verbatim manager methods +
  fixture, asserts `PASS (14 forced interleavings)`, asserts
  `DepartureTaskFor/IsDeparting/Task.WhenAny/CheckAccountInUse/RunSessionAction`
  present, rejects three negative controls (key-only removal, early field
  disposal, missing departure join), checks Player hunk is only two unlock→
  Disconnect lines, and runs isolated full original build (temp runner,
  parent `.state` untouched) with both overlay hashes.
- Run: `node --test tests/fsod-backend-lifecycle.test.mjs`. Tools: git, patch,
  Python 3, Mono/mcs, bwrap, offline pinned `/home/jay/.nuget/packages`;
  source is pinned submodule or `/home/jay/fsod-ref`. Verification must also
  pass from fresh clone with isolated HOME. This proves compiled lifecycle +
  build fidelity, **not** live portal → realm → combat.

## Parent handoff

Rebuild the private backend WITHOUT resetting the DB (accounts/death rows/IDs
must survive), then run the waiting live replays: real permadeath → immediate
UI-equivalent restart (GameId -2, Wizard 782) must pass authenticating →
MAPINFO/CREATE (not offline, no Account-in-use/Failed-to-connect), plus the
other 3 live proofs before Jay window. Lower-priority readiness changes out
of scope. Tree stays until receipt accepted.
