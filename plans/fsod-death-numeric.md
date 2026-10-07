# Original FSoD numeric death.accId compatibility overlay

## Scope and provenance

Source remains immutable at `6fd20aad4a7905b13f25389c68368a942a2b68cb`.
`backend.py build` archives that revision into its private build tree, applies
`linux-isolation.patch`, then `lifecycle.patch`, and records both SHA-256 hashes
in the manifest. No submodule edits, parent `.state` start/stop, frontend
delays, replacement game rules, AI rewrites, content changes, death-row wipes,
or production/shared DB access are involved.

This is an intentional backend compatibility deviation, **not** a claim that
every original source byte remains unchanged. The parent owns runtime
installation and the genuine combat/death/new-character replays (plus the newer
READY readback requiring local HP/entity/tiles rather than CREATE_SUCCESS
alone). This worker only patches the isolated build snapshot and drives
controlled C# plus isolated-build proof.

## Original failure

Parent evidence: `wServer-runtime.log:206` shows `InvalidCastException` at
`MySql.Data.MySqlClient.MySqlDataReader.GetString(string)`, reached via
`Player.IsUserInLegends` from `Player.List.cs` into the `Player` ctor, leaving
partial-null player state. Proven global only after the FIRST REAL PERMADEATH:
once the `death` table holds even one row, every new player construction fails
and only CREATE_SUCCESS is returned with no stats/world.

Original pinned source findings (line numbers are for the immutable revision):

- `wServer/realm/entities/player/Player.List.cs:35,45,54`: all three
  leaderboard windows (week/month/alltime) compare
  `rdr.GetString("accId") == AccountId`.
- `db/rotmgprod.sql` (`death` table): `` `accId` int(11) NOT NULL `` — the
  column is numeric, so the read is a numeric-to-string coercion.
- `db/Models.cs:142`: `AccountId` is `string`; `db/Database.cs:206,392,412`
  already coerce the numeric account `id` with `Convert.ToString(rdr["id"])`.
- Driver change: MySql.Data 6.9.6 coerced numerics in `GetString`; the pinned
  8.4.0 overlay (`dependencies.lock.json`) performs a strict cast and throws.
  The existing linux overlay converted the account reads but missed these
  three death-table sites.

## Fix (in `linux-isolation.patch` only)

- Added `using System;` and `using System.Globalization;` to `Player.List.cs`.
- All three sites now read
  `Convert.ToString(rdr.GetValue(rdr.GetOrdinal("accId")), CultureInfo.InvariantCulture) == AccountId`,
  preserving original string-compare semantics in a locale-independent form.
- Unchanged: all three leaderboard SQL strings, ordering, LIMITs, glow
  assignment, XP/fame/death calculations, exception flow (no catch added),
  and every death row (no DELETE/TRUNCATE anywhere in the overlay).

## Proof

- `scripts/fsod_backend/tests/NumericAccountFixture.cs`: compiled real C#
  against an 8.4-strict reader shim (boxed `Int32` from `GetValue`,
  `InvalidCastException` from `GetString`). Negative control proves the
  original expression throws per window; the canonical expression matches a
  numeric `AccountId` safely, plus empty-window, non-matching, string-typed,
  `int.MaxValue`, and NULL cases — each window under invariant plus tr-TR,
  ar-EG, de-DE, fr-FR, ja-JP cultures (150 cases).
- `tests/fsod-backend-numeric.test.mjs`: pins the revision, proves the bug
  exists upstream (3 strict reads, numeric schema column), applies the real
  overlay hunk to a pristine copy with zero fuzz, asserts only the two usings
  plus three comparison lines differ with SQL byte-identical, cross-binds the
  fixture to the canonical expression, runs the compiled PASS line, rejects a
  regressed fixture, and runs an isolated full original build (temp runner,
  parent `.state` untouched) proving `wServer.exe` compiles with the overlay.

## Parent handoff

Rebuild the private backend WITHOUT resetting the DB (death rows must survive
as the regression population), then run the waiting live combat/death replays:
real permadeath followed by new-character creation must reach READY with local
HP/entity/tiles, not CREATE_SUCCESS alone. Lower-priority readiness changes
are out of scope for this branch.
