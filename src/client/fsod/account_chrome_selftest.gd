# SPDX-License-Identifier: AGPL-3.0-only
# Account chrome acceptance. No session, entry, world, or login profile.
extends SceneTree

const Chrome = preload("res://src/client/fsod/account_chrome.gd")
const THEME_SCRIPT := "res://src/client/fsod/ui_theme.gd"

var checks := 0
var failures := 0
var reconnects := 0
var characters := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_layout_clamps()
	await _states_and_latch()
	await _input_and_diagnostics()
	var capture := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture = argument.trim_prefix("--capture-dir=")
	if capture != "":
		await _render(capture)
	print("FSOD ACCOUNT CHROME PASS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FSOD ACCOUNT CHROME FAIL: " + description)


func _layout_clamps() -> void:
	var main := Chrome.layout_for(Vector2(1280, 720), 120)
	_check(main.panel_x >= 8.0 and main.panel_w <= 360.0, "1280 panel stays compact")
	_check(main.panel_x + main.panel_w <= 1280.0 - 256.0, "1280 panel stays left of the rail")
	_check(main.panel_y >= 0.0 and main.panel_y + main.panel_h <= 720.0, "1280 panel stays on screen")
	_check(main.chip_y + main.chip_h <= 72.0, "ready chip stays above the realm guide")
	var small := Chrome.layout_for(Vector2(640, 360), 100)
	_check(small.panel_x >= 0.0 and small.panel_y >= 0.0, "small origin stays on screen")
	_check(small.panel_x + small.panel_w <= 640.0 and small.panel_y + small.panel_h <= 360.0, "small panel clamps inside 640x360")
	_check(small.panel_w <= 360.0, "small panel does not stretch")
	var large := Chrome.layout_for(Vector2(1920, 1080), 120)
	_check(large.panel_w <= 360.0 and large.panel_x <= 32.0, "letterbox-large logical layout stays a top-left strip, not a stretched card")
	_check(large.panel_x + large.panel_w <= 1920.0 - 256.0, "large panel stays left of the rail")
	_check(large.panel_w < 400.0, "large viewport does not scale the strip with the window")


func _states_and_latch() -> void:
	var chrome = Chrome.new()
	root.add_child(chrome)
	chrome.reconnect_requested.connect(func(): reconnects += 1)
	chrome.new_character_requested.connect(func(): characters += 1)
	var before := reconnects + characters
	chrome.refresh({})
	_check(reconnects + characters == before, "empty refresh emits nothing")
	_check(chrome.ui_diagnostics().actions.is_empty(), "empty snapshot has no action")
	var dead := {
		"state": "dead",
		"status": "YOU DIED · character saved by server",
		"name": "Nope",
		"class": "Nope",
		"character_name": "Uoro",
		"class_name": "Wizard",
	}
	var dead_copy := dead.duplicate(true)
	chrome.refresh(dead)
	_check(dead == dead_copy, "refresh does not mutate the snapshot")
	var action := chrome.get_node("AccountChromePanel/AccountColumn/AccountAction") as Button
	var name_label := chrome.get_node("AccountChromePanel/AccountColumn/AccountName") as Label
	var class_label := chrome.get_node("AccountChromePanel/AccountColumn/AccountClass") as Label
	_check(name_label.text == "Uoro" and class_label.text == "Wizard", "exact character_name and class_name are shown")
	_check(not name_label.text.contains("Nope") and not class_label.text.contains("Nope"), "generic name/class keys are ignored")
	_check(action.visible and not action.disabled and action.text == "New character", "death shows an enabled New character button")
	_check(chrome.ui_diagnostics().actions == ["new_character"], "death action id is new_character")
	await _click(action)
	_check(characters == 1 and reconnects == 0, "death click emits new_character once")
	_check(action.disabled, "press sets Button.disabled, not only a fade")
	chrome.refresh(dead)
	_check(action.disabled and characters == 1, "same snapshot does not re-enable or emit again")
	action.pressed.emit()
	_check(characters == 1, "direct pressed while latched does not emit again")
	await _click(action)
	_check(characters == 1, "second click while disabled does not emit")
	chrome.refresh({"state": "connecting", "status": "GRAVEBAG — connecting"})
	_check(not action.visible and action.disabled, "connecting hides the button")
	_check(chrome.ui_diagnostics().actions.is_empty(), "connecting has no command")
	_check((chrome.get_node("AccountChromePanel/AccountColumn/AccountStatus") as Label).text == "GRAVEBAG — connecting", "status is the entry string, not a countdown")
	var status_before: String = (chrome.get_node("AccountChromePanel/AccountColumn/AccountStatus") as Label).text
	for _i in 30:
		chrome._process(0.05)
	_check((chrome.get_node("AccountChromePanel/AccountColumn/AccountStatus") as Label).text == status_before, "fade frames do not invent a countdown")
	_check(characters == 1 and reconnects == 0, "fade frames emit no commands")
	chrome.refresh(dead)
	_check(not action.disabled, "a real state change re-arms New character")
	await _click(action)
	_check(characters == 2, "re-armed death emits once more")
	chrome.refresh({"state": "offline", "status": "GRAVEBAG — offline", "error": "Could not start local backend connection (code 1)"})
	_check(action.visible and not action.disabled and action.text == "Reconnect", "offline shows Reconnect")
	await _click(action)
	_check(reconnects == 1 and characters == 2, "offline emits reconnect once")
	chrome.refresh({"state": "offline", "status": "GRAVEBAG — offline", "error": "Could not start local backend connection (code 1)"})
	_check(action.disabled and reconnects == 1, "repeated offline snapshot stays latched")
	chrome.refresh({"state": "failed", "status": "Server rejected connection", "error": "Server rejected connection"})
	_check(not action.disabled and action.text == "Reconnect", "failed is a new state and shows Reconnect")
	_check((chrome.get_node("AccountChromePanel/AccountColumn/AccountError") as Label).text == "", "error identical to status is not duplicated")
	chrome.refresh({"state": "failed", "status": "GRAVEBAG — failed", "error": "Server rejected connection"})
	_check((chrome.get_node("AccountChromePanel/AccountColumn/AccountError") as Label).text == "Server rejected connection", "distinct error text is shown verbatim")
	await _click(action)
	_check(reconnects == 2, "failed emits reconnect")
	for busy in ["authenticating", "loading_character", "reconnecting"]:
		chrome.refresh({"state": busy, "status": "GRAVEBAG — " + busy.replace("_", " ")})
		_check(not action.visible and chrome.ui_diagnostics().actions.is_empty(), busy + " has no button")
	chrome.refresh({"state": "playing", "ready": false, "status": "Entering the world…"})
	_check(not action.visible and chrome.get_node("AccountChromePanel").visible, "playing before READY shows status and no button")
	chrome.refresh({"state": "playing", "ready": 1, "status": "GRAVEBAG · original backend"})
	_check(chrome.get_node("AccountChromePanel").visible, "non-bool ready is not READY")
	chrome.refresh({
		"state": "playing",
		"ready": true,
		"status": "GRAVEBAG · original backend",
		"character_name": "Uoro",
		"class_name": "Wizard",
	})
	var chip := chrome.get_node("AccountReadyStatus") as Label
	_check(chip.visible and chip.mouse_filter == Control.MOUSE_FILTER_IGNORE, "READY chip is visible and ignores the mouse")
	_check(chip.text.contains("Uoro") and chip.text.contains("Wizard"), "READY chip shows real character_name and class_name")
	_check(chrome.get_node("AccountChromePanel").mouse_filter == Control.MOUSE_FILTER_IGNORE, "READY panel does not catch clicks")
	_check(chrome.ui_diagnostics().actions.is_empty(), "READY has no command")
	chrome.refresh({"state": "victory", "status": ""})
	_check(not action.visible and not chip.visible, "unknown state invents no success panel")
	chrome.refresh({"state": "dead", "status": "YOU DIED", "class_name": 782, "character_name": 7})
	_check(name_label.text == "" and class_label.text == "", "non-string metadata is not stringified")
	var box := chrome.get_node("AccountChromePanel").get_theme_stylebox("panel") as StyleBoxFlat
	_check(box != null and box.get_corner_radius(0) == 0, "panel corners stay 0")
	var ink := ""
	if box != null:
		ink = box.bg_color.to_html(false)
	print("FSOD ACCOUNT CHROME THEME: %s" % ink)
	if ResourceLoader.exists(THEME_SCRIPT):
		# Compare with whatever theme file is installed (real v2 or the test's stub), not a fixed stub color.
		var theme_void: Variant = load(THEME_SCRIPT).tokens().get("void", "")
		_check(box.bg_color.is_equal_approx(Color(theme_void)), "theme file void token retints ink")
	else:
		_check(box.bg_color.is_equal_approx(Color("#1a1a1a")), "standalone fallback ink is void #1a1a1a")
	chrome.queue_free()
	await process_frame


func _input_and_diagnostics() -> void:
	root.size = Vector2i(1280, 720)
	var chrome = Chrome.new()
	root.add_child(chrome)
	var counts := [0, 0]
	chrome.reconnect_requested.connect(func(): counts[0] += 1)
	chrome.new_character_requested.connect(func(): counts[1] += 1)
	chrome.refresh({"state": "dead", "status": "YOU DIED · character saved by server", "character_name": "Uoro", "class_name": "Wizard"})
	var action := chrome.get_node("AccountChromePanel/AccountColumn/AccountAction") as Button
	_check(not action.disabled, "command is available before the fade finishes")
	await _click(action)
	_check(counts[1] == 1, "click at fade 0 still emits")
	for _i in 8:
		chrome._process(1.0 / 60.0)
	_check(counts[1] == 1 and counts[0] == 0, "cosmetic fade does not emit")
	var info: Dictionary = chrome.ui_diagnostics()
	_check(info.schema == "gravebag.ui_diagnostics.v1", "diagnostics schema")
	_check(info.viewport.w == 1280 and info.viewport.h == 720, "diagnostics viewport is the logical size")
	_check(info.state == "dead" and info.focus.traps_gameplay == false, "latched death does not trap gameplay keys")
	_check(info.mouse_ignore.outside == true and info.mouse_ignore.ready_chip == true, "outside clicks and the chip ignore the mouse")
	var panel_region := _region(info, "panel")
	_check(panel_region.rect.x >= 0.0 and panel_region.rect.y >= 0.0, "panel rect is on screen")
	_check(panel_region.rect.x + panel_region.rect.w <= 1280.0 - 256.0, "live panel stays left of the rail")
	_check(panel_region.rect.y + panel_region.rect.h <= 720.0, "live panel stays inside 720")
	_check(not Rect2(panel_region.rect.x, panel_region.rect.y, panel_region.rect.w, panel_region.rect.h).has_point(Vector2(640, 360)), "center playfield is outside the chrome")
	var probe := Button.new()
	probe.position = Vector2(600, 340)
	probe.size = Vector2(80, 40)
	probe.text = "world"
	var hits := 0
	probe.pressed.connect(func(): hits += 1)
	root.add_child(probe)
	await process_frame
	_push_click(Vector2(640, 360))
	await process_frame
	_check(counts[1] == 1 and counts[0] == 0, "center click does not emit a chrome command")
	_check(chrome.ui_diagnostics().mouse_ignore.outside == true, "chrome has no full-viewport mouse catcher")
	for keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_R, KEY_SPACE, KEY_E, KEY_F, KEY_V]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.physical_keycode = keycode
		key.pressed = true
		root.push_input(key)
	await process_frame
	_check(counts[1] == 1 and counts[0] == 0, "gameplay keys do not emit chrome commands")
	_check(chrome.ui_diagnostics().focus.traps_gameplay == false, "chrome does not keep keyboard focus")
	_check(chrome.diagnostics().schema == info.schema, "diagnostics is the ui_diagnostics alias")
	probe.queue_free()
	chrome.queue_free()
	await process_frame


func _render(capture_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(capture_dir)
	_apply_view(1280, 720, 1280, 720)
	var background := ColorRect.new()
	background.color = Color("#0c0c14")
	background.size = Vector2(1920, 1080)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	var chrome = Chrome.new()
	root.add_child(chrome)
	chrome.refresh({"state": "offline", "status": "GRAVEBAG — offline", "error": "Could not start local backend connection (code 1)"})
	await _shot(chrome, capture_dir, "sequence-0.png", "sequence")
	for _i in 4:
		chrome._process(1.0 / 60.0)
		await process_frame
	await _shot(chrome, capture_dir, "sequence-1.png", "sequence")
	for _i in 16:
		chrome._process(1.0 / 60.0)
		await process_frame
	await _shot(chrome, capture_dir, "sequence-2.png", "offline")
	var settled := _load_png(capture_dir.path_join("sequence-2.png"))
	var panel := _region(chrome.ui_diagnostics(), "panel")
	var sample := Vector2i(int(panel.rect.x) + 12, int(panel.rect.y) + 10)
	var pixel := settled.get_pixel(sample.x, sample.y)
	var void_ink := Color("#1a1a1a")
	_check(absf(pixel.r - void_ink.r) < 0.04 and absf(pixel.g - void_ink.g) < 0.04 and absf(pixel.b - void_ink.b) < 0.04, "offline panel is void #1a1a1a, not a wash (got %s at %s)" % [pixel, sample])
	chrome.refresh({"state": "dead", "status": "YOU DIED · character saved by server", "character_name": "Uoro", "class_name": "Wizard"})
	for _i in 8:
		chrome._process(1.0 / 60.0)
		await process_frame
	await _shot(chrome, capture_dir, "state-dead.png", "dead")
	chrome.refresh({"state": "connecting", "status": "GRAVEBAG — connecting"})
	await _shot(chrome, capture_dir, "state-busy.png", "busy")
	chrome.refresh({"state": "playing", "ready": true, "status": "GRAVEBAG · original backend", "character_name": "Uoro", "class_name": "Wizard"})
	for _i in 16:
		chrome._process(1.0 / 60.0)
		await process_frame
	_check(chrome.get_node("AccountChromePanel").mouse_filter == Control.MOUSE_FILTER_IGNORE, "ready render does not keep a blocking panel")
	await _shot(chrome, capture_dir, "state-ready.png", "ready")
	_apply_view(640, 360, 640, 360)
	background.size = Vector2(640, 360)
	await process_frame
	await process_frame
	chrome.refresh({"state": "dead", "status": "YOU DIED · character saved by server"})
	await process_frame
	chrome._layout()
	await process_frame
	var small := chrome.ui_diagnostics()
	var small_panel := _region(small, "panel")
	_check(small.viewport.w <= 640.0 and small.viewport.h <= 360.0, "small fixture viewport clamps")
	_check(small_panel.rect.x >= -1.0 and small_panel.rect.y >= -1.0 and small_panel.rect.x + small_panel.rect.w <= small.viewport.w + 1.0 and small_panel.rect.y + small_panel.rect.h <= small.viewport.h + 1.0, "small live panel stays inside the viewport (rect %s viewport %s)" % [small_panel.rect, small.viewport])
	await _shot(chrome, capture_dir, "state-small.png", "small")
	_apply_view(1920, 1080, 1280, 720)
	background.size = Vector2(1920, 1080)
	chrome.refresh({"state": "offline", "status": "GRAVEBAG — offline"})
	await process_frame
	await process_frame
	var letter := chrome.ui_diagnostics()
	var letter_panel := _region(letter, "panel")
	_check(letter.viewport.w <= 1280.0 and letter.viewport.h <= 720.0, "letterbox keeps the logical viewport")
	_check(letter_panel.rect.w <= 360.0 and letter_panel.rect.x <= 32.0, "letterbox does not stretch the strip")
	var window := DisplayServer.window_get_size()
	print("FSOD ACCOUNT CHROME LETTERBOX: viewport=%dx%d window=%dx%d panel_w=%.0f" % [int(letter.viewport.w), int(letter.viewport.h), window.x, window.y, letter_panel.rect.w])
	await _shot(chrome, capture_dir, "state-letterbox.png", "letterbox")
	chrome.queue_free()
	background.queue_free()


func _shot(chrome: Node, capture_dir: String, file_name: String, label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image != null and not image.is_empty() and image.get_width() >= 640, "renderer returned real pixels for " + label)
	if image == null or image.is_empty():
		return
	var path := capture_dir.path_join(file_name)
	_check(image.save_png(path) == OK, "saved " + file_name)
	print("FSOD ACCOUNT CHROME FRAME: %dx%d %s %s" % [image.get_width(), image.get_height(), label, file_name])


func _load_png(path: String) -> Image:
	var image := Image.new()
	image.load(path)
	return image


func _apply_view(window_w: int, window_h: int, view_w: int, view_h: int) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(view_w, view_h)
	root.size = Vector2i(window_w, window_h)
	DisplayServer.window_set_size(Vector2i(window_w, window_h))


func _region(info: Dictionary, id: String) -> Dictionary:
	for region in info.regions:
		if region.id == id:
			return region
	return {"rect": {"x": -1, "y": -1, "w": 0, "h": 0}, "visible": false}


func _click(button: Button) -> void:
	await process_frame
	var rect := button.get_global_rect()
	_check(rect.size.x > 1.0 and rect.size.y > 1.0, "button has a real hit rect")
	# Headless does not deliver viewport picks to Button. pressed.emit() is the
	# signal a real click raises; disabled/latched must ignore it either way.
	button.pressed.emit()


func _push_click(position: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = position
	down.global_position = position
	root.push_input(down)
	var up := down.duplicate()
	up.pressed = false
	up.position = position
	up.global_position = position
	root.push_input(up)
