# FSoD inventory rail

## Direction
A quiet field-kit rail, not a numeric debug ledger. Ink `#101a2b`, slate
`#26354b`, muted steel `#8996af`, parchment `#dce3ef`, game gold `#efcf7a`,
potion rose `#cc8290`. Godot's bundled sans is deliberate here: small readable
source names, 16px section titles, 10px tile captions. Four columns align the
four equipment positions, eight pack positions and eight nearby bag positions.
Original small pixel silhouettes are the only decorative emphasis. No external
art, source textures or animations. Selection is a gold inset; keyboard focus
is a separate pale outline. Empty positions retain a quiet role/empty mark.

```
Equipment       [weapon][ability][armor][ring]
Inventory       [    ][    ][    ][    ]
                [    ][    ][    ][    ]
Backpack        [    ][    ][    ][    ]   only wire HasBackpack = 1
                [    ][    ][    ][    ]
Nearby loot     [    ][    ][    ][    ]   only container ID >= 0
                [    ][    ][    ][    ]
                interaction/status help
```

The dark palette is required by the game, not a generic landing-page choice.
Cut tier badges and decorative numbering: source item names and slot roles are
what matters. Full names and use eligibility remain in the tooltips.

## Public contract
`src/client/fsod/inventory_panel.gd` extends `PanelContainer`.

- `set_snapshot(player_id:int, player_stats:Dictionary, container_id:int,
  container_stats:Dictionary, descriptors:Dictionary)` accepts **complete merged**
  wire-stat maps with integer or numeric-string keys. Absent stats are unknown,
  never assumed vacant. Call before or after adding to the scene.
- `swap_requested(source_object_id:int, source_slot:int, dest_object_id:int,
  dest_slot:int)` requests a server swap; it never changes an item locally.
- `use_requested(slot:int)` refers only to the local player's slot.
- `selection_changed(container_slot:int)` identifies a selected nearby-bag slot;
  `-1` clears bag selection (including selecting a player item).

Metadata accepts exported `items` (`ObjectId`, `SlotType`, `Usable`, `Consumable`)
and optionally `objects` (`id` or `name`) for name fallback. A top-level
`SlotTypes` array may be supplied for tooltip slot roles; it is not a client
permission rule. Parent owns session/world/entry integration and server checks.

Slots 0–11 map to stats 8–19, backpack 12–19 to 71–78. Backpack is visible only
for authoritative boolean true or integer 1 at stat 79. Bag exposes exactly 8
positions. Wire -1 and 65535 are empty. Invalid/missing values are unavailable.

## Interaction and authority
Click an occupied item, then another slot to request a swap. Drag/drop uses the
same validation and rejects stale snapshot drag payloads. Double click an item
marked `Usable` or `Consumable` requests use on a player slot only. Shift-click
bag loot requests the first **known-empty** player inventory position starting
at slot 4, including enabled backpack positions, never an equipment position.
Full inventory emits no swap and retains bag loot. Equipment eligibility and all
backend effects remain server-owned. Keyboard arrows/Tab use Control focus;
Enter/Space select/swap and Shift+Enter on bag loot picks up. Tooltips explain
use eligibility. Snapshot replacement, vanished containers and vanished selected
items invalidate selection without optimistic removal. A pending request is
only a status message; it is not an authoritative success or a slot lock.

## Verification
`node --test tests/fsod-inventory-ui.test.mjs` stages only the component, owned
SceneTree selftest and exported metadata into an isolated temporary Godot
project/HOME. It needs Godot 4.6 (`GODOT_BIN` override, otherwise `godot` on PATH
or the established Linux binary) and xvfb-run for the rendered frame. No
project-wide import, network, live service, gameplay rewrite or window restart.
The script tests signal arguments, readonly authority, 12/20-slot layout,
backpack gating, first-empty/full pickup, use guards, stale drag rejection,
selection invalidation and actual GUI mouse/key handlers. It renders a real
960×760 frame via xvfb; set `FSOD_INVENTORY_PROOF_DIR` to an existing evidence
directory to retain its PNG for visual inspection. Clean-clone verification
uses an isolated HOME as well. Generated test projects are removed in finally.

## Limits
Generated glyphs are semantic silhouettes, not unique portraits for all 1281
items. Unknown metadata uses a pouch silhouette and “Unknown item”, never a
programmer ID. The server is responsible for gear mismatch rejection, use
eligibility beyond descriptor flags, nearby-bag range and accepted swaps.
