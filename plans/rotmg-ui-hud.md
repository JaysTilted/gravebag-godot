# RotMG UI HUD

Live rail is `world_view.gd` `AuthoritativeRail`, not `src/ui/hud.gd`. Theme contract is `fsod-ui-theme/2`. Palette is the sampled classic dock plus sprite gold. v1 names are aliases of those same colors.

## Owned surface

- `ui_theme.gd`: static `tokens()`, new `panel_style()` / `slot_style()`, `inventory_host_rect(rail_size)`.
- `hud_panel.gd`: right-dock presentation. Text jumps to wire values. Bar fills ease only in the panel `_process`.
- `world_view.gd`: hosts the panel, keeps prediction / camera / physics untouched, keeps hidden `_summary` / `_inventory` text for the existing fixture.
- `fsod_entry.gd`: optional `ResourceLoader.exists` bridges only. Missing scripts leave the old entry path unchanged.

## Wire

HP 1/0, MP 4/3, XP 6/5, level 7, fame 57, potions 69/70. Missing text is `—`. Level >= 20 draws the third bar in fame orange and does not invent a fame max. `bars.xp` still reports the XP source.

## Layout

Rail constant stays 256 so camera framing is unchanged. The dock is flush to the right edge. Inner controls keep a 2px margin. The inventory host is the measured backpack block (`224x467`) and is not a `ScrollContainer`. The potion strip is outside that host. Proof reads the control rect from `ui_diagnostics()`, schema `gravebag.ui_diagnostics.v1`.

## Host bridges

`combat_feedback.gd`, when present: CanvasLayer 80, `initialize`, `refresh(session, frontend)`, `clear` or `reset` only when state, map, or player id actually changes. `account_chrome.gd`, when present: `refresh(snapshot)` with `state`, `ready`, `status`, `error` (failed only), `character_name`, `class_name`. Signals `new_character_requested` and `reconnect_requested` call the existing session methods. Legacy `_status` / `_action` stay as properties and are hidden only after chrome attaches.

## Not claimed

Fixture frames are not live play. YouTube motion was not watched. Enemy nameplates, quests, chat, and shops are not added.
