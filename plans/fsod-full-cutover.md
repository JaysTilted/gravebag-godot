# FSoD full backend -> Godot frontend

User decision (2026-10-06): retain the ENTIRE backend; replace only the frontend/art. Current toy slice may be removed after the replacement works. Partial selected-mechanic rewrites do not satisfy this.

## Architecture

- Pin full upstream C# source at references/fsod revision 6fd20aad4a7905b13f25389c68368a942a2b68cb (AGPLv3, original credits retained).
- Run original realm + account/database backend locally with Mono and an isolated MariaDB instance. No connections to existing databases, no payment/mail integrations or public listeners.
- Godot client consumes original binary protocol: framing/RC4, hello/map/create/load, update/tick acknowledgements, movement, attacks, inventory/item-use, portal reconnection.
- Original backend retains behavior database, AI, dungeon generation, damage, loot, XP/fame, inventory, class rules, death and persistence. Rendering/input/client prediction are Godot concerns only.
- Original art/Flash clients stay reference-only behind references/.gdignore. Use generated original placeholder art initially, then cohesive art pass. No runtime dependency on SWF.
- Keep current slice and git history recoverable; do not interrupt Jay's live game to test the replacement.

## Independent lanes

1. Backend Linux build + isolated DB + launch/stop/bootstrap, full original logic retained, compatibility patches scoped and documented.
2. Godot protocol/framing/encryption/codec and connection state machine with golden fixtures from source.
3. Descriptor extraction from full upstream XML for Godot object/tile/projectile/class/item metadata (no artwork).
4. Godot rendering/input frontend consuming authoritative updates, original placeholder pixel art.
5. Parent integration and real client->server->world->attack->loot->death reconnect testing.

## Acceptance

- Full original game server builds under Linux; compatibility changes don't replace AI/content/game rules.
- Isolated backend boots, Godot client connects and receives actual map/entity/tick data.
- Real commands exercise movement/shooting/damage, item pickup/equipment, XP/fame and death/respawn against that backend.
- Nexus is safe, rendering has continuous mouse aim + movement animation, no fake single-player AI posing as server integration.
- Deterministic transport tests, connection/disconnection/malformed-frame tests, and recorded real Godot frames pass.
- Scope matrix explicitly records any unimplemented original client command (guilds/trade/account flows etc.); cannot claim entire replacement complete while required game flows remain missing.

## Verified baseline

- Mono/xbuild and MariaDB executables exist on desktop.
- Existing slice verify.sh passed: 7 selftests, DIVE PASS, 6 frames; this is regression baseline only, not full-backend proof.
- Original wServer build attempted unmodified; pending actual output.
