# FSoD UI Live Proof — isolated original-backend acceptance (Objective ONE)

## Objective
Prepare isolated, original-backend LIVE acceptance of the actual new-UI production
composition (`src/game/fsod_entry.gd` + production `src/client/fsod/*`), not synthetic
fixture claims. This tree (`feat/rotmg-ui-live-proof`, base `eec653a`) owns ONLY:

- `scripts/fsod_ui_live.py`
- `src/game/fsod_ui_live_probe.gd` (+ `.uid`)
- `tests/fsod-ui-live-proof.test.mjs`
- `plans/fsod-ui-live-proof.md` (this file)

All existing UI files (header/guide/offline/death/640 bars, chrome/feedback),
`primary/play`, `STATE`, `master` are owned by integrator `generalist-muympzno1`.
This seat never edits those.

## Reuse (existing, read-only)
- Actual production entry: `src/game/fsod_entry.gd` (432 lines) — loads
  `res://src/net/fsod/client.gd`, `res://src/client/fsod/frontend.tscn`,
  `src/data/fsod/*.json`, binds `src/game/fsod_session.gd` +
  `src/game/fsod_view_adapter.gd`, optional `realm_guide.gd`,
  `combat_feedback.gd`, `account_chrome.gd`. Login via `--fsod-login-file=`.
- Original probes: `src/game/fsod_live_probe.gd` (402 lines, SceneTree bot:
  `--fsod-bot-realm/injury/loot/death-cycle`, `--fsod-deadline-ms=`, frame dir
  `/state/live-frames`, PASS lines `FSOD LIVE COMBAT/DAMAGE/LOOT/RECOVERY PASS`),
  `src/game/fsod_close_loot_probe.gd` (75 lines, 0.55-tile loot driver).
- Normal backend helpers: `scripts/fsod_backend/backend.py` (`REVISION =
  "6fd20aad4a7905b13f25389c68368a942a2b68cb"`), `scripts/fsod_play/verify.py`
  (pins `source_revision == 6fd20…`, pins `linux-isolation.patch` +
  `lifecycle.patch` SHAs, checks staged client == tested source, requires 4
  PASS patterns + `04/05/06/07-original-*.png`, rejects `SCRIPT ERROR|…`),
  `scripts/fsod_qa/run_isolated.py` (asserts QA `.state` resolves inside this
  worktree, refuses `/home/jay/gravebag-godot/scripts/fsod_backend/.state`,
  snapshots Jay supervisor pid/ns, uses `Input.parse_input_event` + RealmGuide).
- UI contract: `scripts/fsod_ui_proof/contract.json`
  (`gravebag.ui_diagnostics.v1`, frozen, viewport units, sample_hz is harness
  interval, no guessed UI rate).

## Architecture (owned helpers)
- `scripts/fsod_ui_live.py`: isolated orchestrator. Refuses Jay/primary/shared
  state (non-symlink, resolves nowhere under `gravebag-godot` or
  `accepted-play-ab8`), refuses auth/profile fallback and shared STATE,
  fail-closed. Prefers READONLY reuse/copy of PUBLIC compiled
  DLL/GameXML/catalog runtime artifacts (never DB/account/profile/private
  config) into own QA `.state` to prove source-immutable runtime-hash equality
  (`source_revision 6fd20…` + owned patchset unchanged, UI-only new source).
  Never bypasses `verify.py`, never rewrites fake receipts. Bootstraps fresh
  private QA instance via normal pipeline, generates QA-only profile without
  printing credentials. Runs GAME as UID 1000 only, private Xvfb display
  (never `:1`), `LP_NUM_THREADS>=2`, `nice 10`. Event-driven liveness with
  explicit deadline/max-attempts/frame-count watch (no blocking bash loop).
  Records GUI pid/uid/netns, source HEAD + file hashes, backend pin `6fd20…`,
  runtime hashes (DLL/MVID/GameXML), genuine frame-delta/time sampling
  (easing fills vs actual source values, never fixed `1/60` fake FPS),
  readable frames + diagnostics at 1280×720 and compact contract size.
  One fresh round per runtime: stages the fresh UI client (`verify.py stage`),
  runs the same 4 combat/damage/loot/recovery probes
  (`--fsod-bot-realm/injury/loot/death-cycle`) via owned backend `exec` under
  private `xvfb-run` (Mesa software GL, `nice -n 10`), then `verify.py`
  `collect`+`verify` (PASS patterns + 1280x720 frames + runtime-hash equality).
  Then two UI-probe rounds at 1280x720 and 640x360 asserting `FSOD UI LIVE PASS`,
  readable PNG dimensions, genuine delta series, diagnostics schema and
  bar-fill bounds (fill-vs-source series reported; change is informational).
  Provenance recorded: source HEAD + file hashes, runtime DLL/MVID/GameXML
  hashes, backend pin, exec IDs, GUI pid/uid/netns, Jay pid 629784
  before/after (read-only), viewport+camera per size.
  Death→New-character and offline→Reconnect via actual production state wiring
  with real client proof for NEW QA account only. Backend TTL-bounded, cleanup
  owns ONLY own QA state after proof, no original IPC.
- `src/game/fsod_ui_live_probe.gd`: QA SceneTree helper that instantiates
  production `fsod_entry` and inspects private fields readonly / drives real
  `InputEvent` (`Input.parse_input_event`, key + mouse-button) while loading
  normal QA login file; actual production normal handlers, never forced fake
  authoritative state. W key alternates press/release; death→New-character
  and offline→Reconnect click the production chrome regions from
  `ui_diagnostics` with real mouse events (never signal emits). Persists
  `frame-deltas.json` (genuine `Time.get_ticks_msec` series), `ui-diagnostics.jsonl`
  snapshots, viewport-texture PNGs (up to 6), and `ui-live-meta.json`
  (pid/mode/viewport+camera/click flags). PASS requires playing observed,
  genuine deltas, exact `gravebag.ui_diagnostics.v1` schema, ≥1 PNG.
  Never copies entry into helper; requests parent if shared-file API change is
  needed (shared ownership).
- `tests/fsod-ui-live-proof.test.mjs`: fail-closed contract. Fails if
  auth/profile fallback, shared STATE, fixed FPS, manual stats/fill/fakeNPC,
  Chrome labels, copied entry, or missing isolation markers are present.
  Intermediate HEAD: asserts prep readiness; final live capture asserts only
  when `FSOD_UI_LIVE_FINAL=1` with frozen HEAD + approved frames present.
  Otherwise reports `pending-final-freeze` and passes prep.

## Isolation / safety
- Own `.state` unique, owned, non-symlink, resolves nowhere under primary
  `/home/jay/gravebag-godot` or `accepted-play-ab8` (Jay live backend pid
  629784). No DB reset/shared DB/account-source/profile reads/public servers.
- No staging/rebuild/live-window of any primary files. Existing
  original-client/source-protocol/gamerules C# unchanged. No hotpatch or
  entry-copy into helper.

## Sequencing (per parent)
- Intermediate HEAD (now): prep architecture + fail-closed helper scoped
  tests only. No full-repo CI (owner: integrator). No final UI acceptance
  claim until parent provides NEW frozen reviewed UI HEAD; parent merges that
  into this tree. New frozen UI candidate `4c21b5d2f566bddeddd7b3e11713ee799b…`
  (`feat/rotmg-ui-integration`) to be merged into this tree by this seat when
  helper commit is safe (no existing-UI edits), to avoid simultaneous writers.
- Final HEAD (later): `committed-helpers + merged-4c (+ any parent admin fix
  before final snapshot)`. Wait parent UI frame approval before full 4-probe /
  UI live capture. Final merge HEAD must include all helper/docs/admin commits
  BEFORE capturing final UI 4 proofs + frames. No fake FPS/manual mutations.
- Runtime DLL/MVID hash equality: recompiling identical C# may yield different
  hashes than Jay's existing backend, so reuse public compiled artifacts
  readonly; if normal helpers lack safe reuse, report exact existing-file API
  dependency to parent (backend helper writer owns that side).

## Done-when
Verifiable live UI proof at final merged exact HEAD plus retained clean pushed
tree, or exact material blocker reported. Goal: approved UI acceptance, not
handoff/user game until parent + Jay ready.
