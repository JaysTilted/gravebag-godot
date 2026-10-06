# GRAVEBAG

Godot 4.6 frontend with original pixel art, replacing the Flash frontend of the complete FSoD backend.

## Cutover status

**In progress, not yet playable against the server.** The old single-player slice remains available until the replacement passes real client/server tests.

- Complete upstream source: `references/fsod`, pinned to `6fd20aad4a7905b13f25389c68368a942a2b68cb`.
- Backend: original C# realm/account/database, AI, dungeon generation, items, loot, XP/fame, persistence and multiplayer logic. Not a selected-mechanics GDScript rewrite.
- Frontend: Godot binary-protocol client, renderer/input, original art. Original SWF and bundled upstream artwork are reference-only, excluded from Godot imports.
- Full cutover plan: [`plans/fsod-full-cutover.md`](plans/fsod-full-cutover.md).

Restore backend source:

```bash
git submodule update --init references/fsod
```

Run the **old slice** (not the server-connected replacement):

```bash
Godot_v4.6-stable_linux.x86_64 --path .
```

Regression proof for that slice:

```bash
bash scripts/verify.sh
```

Successful visual captures are saved under `reports/verify-frames/`. Parallel verification uses isolated temporary paths. A green slice test is not proof of full backend integration.

## License and tooling

AGPLv3; see [`LICENSE`](LICENSE) and [`THIRD_PARTY.md`](THIRD_PARTY.md) for FSoD provenance and credits. Claude Code Game Studios tooling is retained under its original MIT notices in `third_party/licenses/CCGS-MIT.txt`; studio agents/skills live under `.claude/`.
