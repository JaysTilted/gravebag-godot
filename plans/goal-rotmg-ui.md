# RotMG-style UI and buttery presentation

Status: ACTIVE — goal de393f, confirmed by goal_get. Paste validated, copied and exact-readback verified. Initial gates below remain baseline until enhanced proof is delivered.

## Requested outcome
Jay: "okay looks good now i want the ui better and butterly like real rotmg i dont want you to stop make a goal until our game looks like the real rotmg watch youtube videos on gameplay".

Ship a cohesive RotMG-inspired Godot interface and smooth presentation, grounded in actually inspected YouTube gameplay frames/timecodes. Preserve GRAVEBAG's pixel-art identity, original FSoD server rules, saves and semantic projectile/contact authority. No interruption to Jay's running game.

## Acceptance
- Reference evidence: public video URLs, titles/dates, timecodes, inspected visual captures; distinguish Exalt/classic and observations from inference. Never call search snippets/transcripts watched footage. Researcher report /home/jay/.pi/agent/runs/researcher-muyf6k0g6/evidence/report.md inspected real YouTube auto-stills for27i_SbFan6Y, hESX0tqPsSI, JXKXf0m2nTA; parent independently inspected classic maxres and2Exalt frames. Full playback/motion NOT watched: deliberate hosts focus block; parent requested Jay's permission for temporary YouTube unblock while other work continues. Do not bypass/change host block without that reply. Research report's legacy src/ui/hud.gd current-code claims are discarded; live target is world_view.gd as scout confirmed.
- Compact coherent right rail with readable minimap, world/player identity, HP/MP and XP bars, equipment and inventory, nearby loot and item tooltips. No clipped essential text or scrolling the core equipment/backpack at the main viewport.
- Cohesive restrained pixel-game theme; responsive layout at 1280x720 and additional usable small/large viewports; keyboard/mouse focus/input behavior preserves gameplay.
- Buttery render-rate health/mana/XP and action feedback, inventory/tooltip affordances and motion; authoritative values/actions unchanged; no tick sawtooth or stale UI; no smoothing projectile hitboxes or mandatory interaction delays.
- Real rendered before/after snapshots and sequence/frame evidence for Nexus, realm/combat, inventory/loot/tooltips, offline/death states. Report fixtures vs original-backend live proof separately.
- Fresh layout geometry/motion/input acceptance and all gameplay regressions at integrated exact HEAD; independent visual review compares new captures against observed RotMG references before completion.
- Commit/push/install through normal repo pipeline. New visible player build only after save-safe acceptance and when it does not interrupt the current fight.

## Proof
`node --test /home/jay/gravebag-godot/tests/layout.test.mjs` must pass real Godot UI geometry/render/motion scenarios and produce reviewable exact-source frame evidence.
`bash /home/jay/gravebag-godot/scripts/verify.sh` must print VERIFY PASS with preserved gameplay checks.
`node --test /home/jay/gravebag-godot/tests/fsod-walking.test.mjs /home/jay/gravebag-godot/tests/fsod-session.test.mjs /home/jay/gravebag-godot/tests/fsod-inventory-wire.test.mjs /home/jay/gravebag-godot/tests/fsod-play-verifier.test.mjs` must pass authority/protocol/play-gate regressions.
Initial layout entry point only composes existing guide/inventory regressions: baseline smoke, NOT final visual-parity acceptance. All three baseline command groups ran: composed layout 2 tests pass; VERIFY PASS with 19 selftests and6/6 dive frames; preserved gameplay 5 tests pass, wire269checks39families, walking41checks rewinds0. Output /home/jay/.pi/agent/runs/tasks/shell-muyfcaxr1zy.output. Expand during goal; do not complete using baseline-only tests.

## Parallel plan and ownership
1. Researcher watches actual gameplay frames while scout maps local UI seams, proof scripts and disjoint file ownership.
2. Dispatched all independent units on medium: HUD/theme/minimap + world/entry host (generalist-muyffh0z9), inventory/loot/tooltips (generalist-muyfgckba), render/motion proof (generalist-muyfdjoj8), new source-grounded combat feedback (generalist-muyfiu4gb), new account/session chrome (generalist-muyfjpf7c). Research researcher-muyf6k0g6; scout scout-muyf730t7. Trees under /home/jay/gravebag-wt/rotmg-ui-{hud,inventory,proof,feedback,account}. Only HUD writer edits world_view.gd/fsod_entry.gd; other UI modules stay disjoint. Rail contract 256px at logical 1280x720; HP wire1/0, MP4/3, XP6/5, level7, fame57, potions69/70, unknown values —. Theme and readonly diagnostics contracts being pinned via parent. Push branches, retain through receipt verification.
3. Parent is single integration/CI coordinator. Integrate, run fresh render/geometry/motion/input and gameplay tests, critique frames against references, repair gaps instead of declaring partial completion.
4. Preserve runtime/window during source work. Independently isolated fresh QA accounts for real gameplay evidence. No profile contents, DB resets, public services or backend rule edits.

## Bounds and stop
Default six-hour no-verified-progress stall window; 200 goal turns. Continue while verified progress lands, not an arbitrary elapsed deadline. Stop only on user stop/pause/clear, exhausted runtime bounds or genuine blocker requiring human decision; report precise gaps. Network/video research bounded12minutes/max25probes per discovery pass, each subprocess bounded. Watches have deadlines+attempt counts.
