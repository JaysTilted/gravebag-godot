# fsod-orphan-control — stale private control-socket recovery

## Objective

`backend.py stop` returns `already_stopped` but leaves a stale private
`control.sock` behind when the recorded supervisor is dead, so the next
`start` refuses with `control socket exists: verify or stop first`.
The normal pipeline must safely recover a positively-dead OWNED
supervisor's stale private Unix socket so a subsequent `start` works.

## Output

- `scripts/fsod_backend/backend.py`: fail-closed orphan recovery in
  `lifecycle_control` (`stop` path only) plus `_supervisor_status`,
  `_argv_binds_state`, `_is_owned_private_socket`,
  `_try_recover_orphan_socket` helpers.
- `tests/fsod-backend-lifecycle.test.mjs`: focused owner tests through
  the normal pipeline (recovery; alive/reused/unknown/non-socket/
  symlink preservation; canonical STATE-alias live identity; cold stop).

## Boundaries

- Unlink ONLY when ALL hold: `stop` command, `connect()` refused,
  recorded PID positively dead (`/proc/<pid>/cmdline` absent —
  FileNotFoundError), PID not alive, path is not a symlink, is a socket,
  socket uid == STATE dir uid == euid. Never on unavailable/unknown/
  live/reused-PID, never on permission/unknown transport errors
  (fail closed), never via `verify`.
- No signaling of any PID (`/proc` read only); no `SQL`/save/reset/build
  changes; no marker-string adjustment (realpath equivalence only for
  the liveness check, never inferred death from a raw string mismatch).
- No `.state` operations on the live tree from this lane; no C#/client
  changes; launcher helper scope only.

## Done-when

- Dead-owned supervisor + stale socket: `stop` → `already_stopped` +
  `orphan_socket: recovered`, socket gone, next `start` guard passes.
- Alive/unavailable/refused, reused-PID, non-owned/non-socket/symlink,
  permission-unknown controls: preserved, prior statuses unchanged.
- Absent control: cold `stop` stays `already_stopped`, `verify` not ready.
- Targeted lifecycle checks green; commit pushed on
  `fix/fsod-orphan-control`.
