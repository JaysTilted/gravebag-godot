# Isolated live QA: walking and realm entry

Runtime base `10e973a0cc1cbdc6d982bea4f3659f4e00f4c61d` plus this branch's walking cleanup and QA driver. The client that captured the frames was staged from that working tree. Godot `9995532a9ddb6fc81bb510546fcb5b780175e766096f9be3e58cf403258f4898`.

## Isolation

QA state `/home/jay/gravebag-wt/fsod-walking-realm-live/scripts/fsod_backend/.state`. Inner supervisor netns `net:[4026533866]`. Jay's still-running supervisor pid 2438472 stayed on `net:[4026533098]` before and after. No restart, focus, or input to that process. Fresh account and owner-only profile lived only inside the QA state. Ports stayed on the private loopback. Xvfb was display `:99` inside that namespace, not the player window.

NVIDIA's EGL vendor crashes Xvfb in this user namespace. The render used Mesa software GL (`LIBGL_ALWAYS_SOFTWARE=1`) so frames could be captured offscreen. Shipped game sources were not patched for that.

## What the live session showed

Server map changed `Nexus` to `NexusPortal.Sprite` after one real E press. Guide prompt was `E · Enter realm Sprite (0/85)`. `interaction_target_id` and the shipped `interact_requested` id were both 1329, type 1810. Reconnect stayed on loopback. Prediction snapped on entry (`entry_snap` true). Frames: `proof/01-nexus-realm-portal.png` (gold portal label and E prompt) and `proof/02-realm-after-entry.png` (HUD `NexusPortal.Sprite`, different terrain).

Held east 1.2s at speed 4.75 through shipped prediction/render and MOVE sending: 72 physics frames, 24 server ticks, 25 `move_requested`, 24 wire MOVE frames, prediction/display +5.696 tiles, auth +5.3 and trailing (72 samples, max lead 0.87). Backward steps 0, rewinds 0, release delta 0. Turn +2.531, reverse +2.294.

The driver process printed `FAIL realm_entry_missing` only because its judge rejected any map name containing "nexus". `NexusPortal.Sprite` is the original realm world name. That judge line is corrected in the driver; it does not change the captured session.

## Gaps

Collider: a streamed NoWalk cell was not entered, but the short walk ended about 5 tiles short of it. No contact clip was proved. A later rerun with the corrected judge did not reach E before its 180s deadline; it is not this proof.

The realm frame still shows the Nexus explore hint. That is `realm_guide.gd` treating any map containing "nexus" as Nexus, including `NexusPortal.Sprite`. Not changed here.
