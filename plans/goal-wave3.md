# Goal: GRAVEBAG wave 3 — full loop + Steam demo (clean-room)

## End state
On gravebag-godot `master`, the slice is a complete demo loop: live nexus hub
(heal, stash, realm portal) → scaling realm with 3+ enemy types → boss arena →
extract with the bag (keep the haul) or die trying (grave + fame tally).
Procedural music under the SFX. Fame bank + best-dive records persist across
runs. Studio pipeline: one writer per worktree, single-gate proof, frame review
before the human plays.

## Proof
- `bash scripts/verify.sh` prints VERIFY PASS (import, 5+ selftests, smoke,
  xvfb bot dive with kills + bags + XP + deaths, 6/6 real frames)

## Wave plan (disjoint writers)
1. Loop (owns `src/game/dive.gd`, `src/world/nexus.*`): nexus hub live, portal
   → realm → boss arena → extract gate; state machine NEXUS/DIVE/BOSS/EXTRACT.
2. Foes (owns `src/combat/variants/*` new, may extend `patterns.gd`): dasher,
   sniper, splitter + their patterns; variety table in scaling.
3. Music (owns `src/audio/music.gd` new, `src/audio/selftest.gd`): procedural
   chiptune loop (nexus calm / combat drive), crossfade helper.
4. Records (owns `src/systems/records.gd` new + selftest): fame bank, best dive
   (level, kills, bags), settings; local save/load via ConfigFile.

## Stop
Done when the loop plays end-to-end (bot reaches extract or dies trying),
frames reviewed, VERIFY PASS on master — or Jay says stop.
