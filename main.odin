package main
import "core:math"
import "core:math/rand"
import "vendor:raylib"

// One piece of decorative floor scatter. Drawn flat (non-colliding) so a big
// open floor reads as terrain -- grass blades, pebbles, cracks, embers -- rather
// than a bare checkerboard.
draw_floor_mark :: proc(m: floor_mark, col: raylib.Color) {
	c := raylib.Color{col.r, col.g, col.b, 190}
	switch m.kind {
	case .GRASS:
		// Three small blades fanning out from the base.
		for k in -1 ..= 1 {
			bx := m.pos.x + f32(k) * m.size * 0.5
			raylib.DrawLineEx({bx, m.pos.y + m.size}, {bx + f32(k) * 2, m.pos.y - m.size}, 2, c)
		}
	case .PEBBLE:
		raylib.DrawCircleV(m.pos, m.size * 0.5, c)
	case .CRACK:
		// A short zigzag fracture.
		raylib.DrawLineEx({m.pos.x - m.size, m.pos.y}, {m.pos.x, m.pos.y - m.size}, 1, c)
		raylib.DrawLineEx({m.pos.x, m.pos.y - m.size}, {m.pos.x + m.size, m.pos.y}, 1, c)
	case .SNOW:
		raylib.DrawCircleV(m.pos, m.size * 0.5, c)
	case .EMBER:
		// Hot flecks get a faint glow ring so they read as glowing embers.
		raylib.DrawCircleV(m.pos, m.size * 0.4, raylib.Color{255, 200, 120, 220})
		raylib.DrawCircleV(m.pos, m.size * 0.9, raylib.Color{255, 120, 40, 60})
	}
}

// In-game settings panel (opened with Backspace during a run). A compact overlay
// over the frozen game: volume, screen shake, the visual toggles, a Resume
// button, and a Return-to-Menu button. Rows: 0 volume, 1 screen shake,
// 2 damage numbers, 3 blood, 4 hurt vignette, 5 resume, 6 return to menu.
INGAME_PANEL_ROWS :: 7

// Panel box in screen space, centered on the window.
ingame_panel_geometry :: proc() -> (x, y, w, h: f32) {
	sw := f32(raylib.GetScreenWidth())
	sh := f32(raylib.GetScreenHeight())
	w = 640
	h = 130 + f32(INGAME_PANEL_ROWS) * 46
	x = (sw - w) * 0.5
	y = (sh - h) * 0.5
	return
}

// One row's clickable rect, in screen space.
ingame_panel_row_rect :: proc(row: int) -> raylib.Rectangle {
	gx, gy, gw, _ := ingame_panel_geometry()
	ry := gy + 96 + f32(row) * 46
	return raylib.Rectangle{gx + 24, ry, gw - 48, 40}
}

// Label + current value for a row (value is empty for the two buttons).
ingame_panel_row_text :: proc(row: int) -> (label: cstring, value: cstring) {
	switch row {
	case 0:
		return "Master volume", raylib.TextFormat("%i%%", i32(settings.master_volume * 100))
	case 1:
		return "Screen shake", raylib.TextFormat("%i%%", i32(settings.screen_shake * 100))
	case 2:
		return "Damage numbers", settings.damage_numbers ? cstring("ON") : cstring("OFF")
	case 3:
		return "Blood", settings.blood ? cstring("ON") : cstring("OFF")
	case 4:
		return "Hurt vignette", settings.hurt_vignette ? cstring("ON") : cstring("OFF")
	case 5:
		return "RESUME", cstring("")
	case 6:
		return "RETURN TO MAIN MENU", cstring("")
	}
	return cstring(""), cstring("")
}

// Perform a row's action (toggle, or one of the two buttons). Shared by the
// keyboard (ENTER) and the mouse (click).
ingame_panel_activate :: proc(row: int) {
	switch row {
	case 2:
		settings.damage_numbers = !settings.damage_numbers
		settings_save()
	case 3:
		settings.blood = !settings.blood
		settings_save()
	case 4:
		settings.hurt_vignette = !settings.hurt_vignette
		settings_save()
	case 5:
		ingame_panel_open = false
	case 6:
		ingame_panel_open = false
		play(sounds.ui_select)
		end_run()
	}
}

// Keyboard handling for the panel. Runs once per frame while it's open; the world
// is frozen because the PLAYING case skips its update while the panel is up.
ingame_panel_update :: proc() {
	if raylib.IsKeyPressed(raylib.KeyboardKey.UP) || raylib.IsKeyPressed(raylib.KeyboardKey.W) {
		ingame_panel_sel = (ingame_panel_sel - 1 + INGAME_PANEL_ROWS) % INGAME_PANEL_ROWS
		play(sounds.ui_move)
	}
	if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) || raylib.IsKeyPressed(raylib.KeyboardKey.S) {
		ingame_panel_sel = (ingame_panel_sel + 1) % INGAME_PANEL_ROWS
		play(sounds.ui_move)
	}
	changed := false
	left :=
		raylib.IsKeyPressed(raylib.KeyboardKey.LEFT) || raylib.IsKeyPressed(raylib.KeyboardKey.A)
	right :=
		raylib.IsKeyPressed(raylib.KeyboardKey.RIGHT) || raylib.IsKeyPressed(raylib.KeyboardKey.D)
	if left || right {
		step := right ? 0.05 : f32(-0.05)
		switch ingame_panel_sel {
		case 0:
			settings.master_volume = clamp(settings.master_volume + step, 0, 1)
			changed = true
		case 1:
			settings.screen_shake = clamp(settings.screen_shake + step, 0, 1)
			changed = true
		case:
		}
	}
	if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) ||
	   raylib.IsKeyPressed(raylib.KeyboardKey.SPACE) {
		ingame_panel_activate(ingame_panel_sel)
	}
	if changed {
		settings_save()
	}
}

// Render the panel as a screen-space overlay over the frozen game, and handle
// mouse hover/click on the rows.
draw_ingame_panel :: proc() {
	sw := f32(raylib.GetScreenWidth())
	sh := f32(raylib.GetScreenHeight())
	raylib.DrawRectangleRec(raylib.Rectangle{0, 0, sw, sh}, raylib.Color{0, 0, 0, 160})
	gx, gy, gw, gh := ingame_panel_geometry()
	box := raylib.Rectangle{gx, gy, gw, gh}
	raylib.DrawRectangleRec(box, raylib.Color{24, 24, 34, 245})
	raylib.DrawRectangleLinesEx(box, 3, raylib.SKYBLUE)
	raylib.DrawText(cstring("PAUSED"), i32(gx + 24), i32(gy + 22), 26, raylib.WHITE)
	raylib.DrawText(cstring("in-run settings"), i32(gx + 24), i32(gy + 54), 16, raylib.DARKGRAY)
	mp := raylib.GetMousePosition()
	clicked := raylib.IsMouseButtonPressed(.LEFT)
	for row in 0 ..< INGAME_PANEL_ROWS {
		rect := ingame_panel_row_rect(row)
		selected := row == ingame_panel_sel
		bg := raylib.Color{34, 34, 48, 255}
		if selected {
			bg = raylib.Color{48, 48, 84, 255}
		}
		raylib.DrawRectangleRec(rect, bg)
		label, value := ingame_panel_row_text(row)
		raylib.DrawText(
			label,
			i32(rect.x + 14),
			i32(rect.y + 10),
			20,
			selected ? raylib.YELLOW : raylib.RAYWHITE,
		)
		if value != cstring("") {
			vw := raylib.MeasureText(value, 20)
			raylib.DrawText(
				value,
				i32(rect.x + rect.width - 14) - vw,
				i32(rect.y + 10),
				20,
				selected ? raylib.SKYBLUE : raylib.GRAY,
			)
		}
		// Value bar for the two sliders.
		if row == 0 || row == 1 {
			frac := row == 0 ? settings.master_volume : settings.screen_shake
			bw := (rect.width - 28) * clamp(frac, 0, 1)
			raylib.DrawRectangle(
				i32(rect.x + 14),
				i32(rect.y + 32),
				i32(rect.width - 28),
				4,
				raylib.DARKGRAY,
			)
			raylib.DrawRectangle(i32(rect.x + 14), i32(rect.y + 32), i32(bw), 4, raylib.SKYBLUE)
		}
		if raylib.CheckCollisionPointRec(mp, rect) {
			if clicked {
				ingame_panel_sel = row
				ingame_panel_activate(row)
			}
		}
	}
	raylib.DrawText(
		cstring("UP / DOWN to choose   -   LEFT / RIGHT to adjust   -   BACKSPACE to resume"),
		i32(gx + 24),
		i32(gy + gh - 30),
		15,
		raylib.GRAY,
	)
}

// Minimum letterbox bar width (in screen px) before the character/passive HUD is
// moved out of the canvas and into the left pillarbox bar.
CHAR_PASSIVE_MIN_BAR :: 150

// Largest font size (<= max) at which `text` still fits within `avail` pixels.
// Lets the narrow letterbox bar shrink labels instead of clipping them.
fit_font :: proc(text: cstring, avail: f32, max_fs: i32) -> i32 {
	fs := max_fs
	for fs > 7 && f32(raylib.MeasureText(text, fs)) > avail {
		fs -= 1
	}
	return fs
}

// Small value bar used by the character passives (Heart, knee charge).
draw_passive_bar :: proc(ox, oy, w: f32, frac: f32, col: raylib.Color) {
	raylib.DrawRectangle(i32(ox), i32(oy), i32(w), 8, raylib.DARKGRAY)
	raylib.DrawRectangle(i32(ox), i32(oy), i32(w * clamp(frac, 0, 1)), 8, col)
	raylib.DrawRectangleLines(i32(ox), i32(oy), i32(w), 8, raylib.GRAY)
}

// The whole character sidebar: name, passive name, the live passive bar/label,
// and the on-hit status effects. Drawn either out in the left pillarbox bar (to
// keep the gameplay canvas clear) or, on 4:3 windows with no bar, into the canvas
// top-left. Everything auto-shrinks to `avail` so it always fits the space given.
draw_sidebar_hud :: proc(ox, oy, avail: f32) {
	// Character name (big, in the character's colour).
	name := cstring(CHARACTERS[character].name)
	name_fs := fit_font(name, avail, 20)
	raylib.DrawText(name, i32(ox), i32(oy), name_fs, CHARACTERS[character].color)
	cy := oy + f32(name_fs) + 4
	// Passive name.
	pass := cstring(CHARACTERS[character].passive)
	pass_fs := fit_font(pass, avail, 13)
	raylib.DrawText(pass, i32(ox), i32(cy), pass_fs, raylib.LIGHTGRAY)
	cy += f32(pass_fs) + 5
	// Passive-specific bar / label.
	if character == .TRACER {
		draw_passive_bar(ox, cy, min(120.0, avail), traceur_charge, raylib.GOLD)
		cy += 14
	} else if character == .BUD && signature_next_charged() {
		bw := min(120.0, avail)
		draw_passive_bar(ox, cy, bw, combo_charge, raylib.ORANGE)
		cy += 14
		kc := cstring("KNEE CHARGING")
		kc_fs := fit_font(kc, avail, 13)
		raylib.DrawText(kc, i32(ox), i32(cy), kc_fs, raylib.ORANGE)
		cy += f32(kc_fs) + 4
	} else if character == .RR {
		// Vector Edge reshapes to the Adaptation, so name the form too.
		label := raylib.TextFormat(
			"ADAPT: %s (%s)",
			string(rr_adaptation_name()),
			string(RR_EDGE_NAMES[rr_adaptation]),
		)
		col := raylib.SKYBLUE
		if rr_surge > 0 {
			label = raylib.TextFormat("%s [SURGE]", label)
			col = raylib.GOLD
		}
		fs := fit_font(label, avail, 13)
		raylib.DrawText(label, i32(ox), i32(cy), fs, col)
		cy += f32(fs) + 4
	}
	// On-hit status effects: stacked one per line so they fit a narrow bar.
	if attack_effects != {} {
		cy += 6
		hdr := cstring("ON HIT:")
		hdr_fs := fit_font(hdr, avail, 13)
		raylib.DrawText(hdr, i32(ox), i32(cy), hdr_fs, raylib.LIGHTGRAY)
		cy += f32(hdr_fs) + 3
		for eff in Status_Effect {
			if eff not_in attack_effects {
				continue
			}
			sn := status_name(eff)
			fs := fit_font(sn, avail - 14, 13)
			raylib.DrawRectangle(i32(ox), i32(cy) + 2, 8, 8, status_color(eff))
			raylib.DrawText(sn, i32(ox) + 13, i32(cy), fs, status_color(eff))
			cy += f32(fs) + 3
		}
	}
	// Relics drawn from chests this run: a gold row per relic, so your build's
	// passive bonuses are always visible without opening a menu.
	if n := relic_count(); n > 0 {
		cy += 6
		hdr := raylib.TextFormat("RELICS (%i):", n)
		hdr_fs := fit_font(cstring(hdr), avail, 13)
		raylib.DrawText(cstring(hdr), i32(ox), i32(cy), hdr_fs, raylib.GOLD)
		cy += f32(hdr_fs) + 3
		for k in Relic_Kind {
			if !relic_owned(k) {
				continue
			}
			fs := fit_font(RELICS[k].name, avail - 14, 12)
			raylib.DrawRectangle(i32(ox), i32(cy) + 2, 8, 8, raylib.GOLD)
			raylib.DrawText(RELICS[k].name, i32(ox) + 13, i32(cy), fs, raylib.GOLD)
			cy += f32(fs) + 2
		}
	}
}

// Leave the shop: back to PLAYING, spawning the next wave (or noting the tutorial
// lesson if a tutorial opened it). Shared by ENTER, a click on LEAVE, and ESC.
leave_shop :: proc() {
	state = .PLAYING
	play(sounds.ui_select)
	if tutorial_mode {
		// The tutorial opened this shop to teach it; leaving is the lesson, so don't
		// spawn a real wave.
		tutorial_note(.SHOP_DONE)
	} else {
		if !debug_mode {
			new_wave(&enemies, wave)
		}
		wave += 1
	}
}

// Keyboard handler for the accept/discard relic overlay. ENTER (or R) takes the
// relic, ESC (or D) discards it; either way the world resumes.
relic_pick_update :: proc() {
	accept :=
		raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) ||
		raylib.IsKeyPressed(raylib.KeyboardKey.SPACE) ||
		raylib.IsKeyPressed(raylib.KeyboardKey.R)
	discard :=
		raylib.IsKeyPressed(raylib.KeyboardKey.ESCAPE) || raylib.IsKeyPressed(raylib.KeyboardKey.D)
	if accept {
		apply_relic(pending_relic)
		relic_pick_open = false
		play(sounds.shop_buy)
	} else if discard {
		relic_pick_open = false
		play(sounds.ui_move)
	}
}

// The accept/discard overlay: a centred card showing the drawn relic with the two
// choices, drawn over the frozen frame in the present step.
relic_pick_draw :: proc() {
	sw := f32(raylib.GetScreenWidth())
	sh := f32(raylib.GetScreenHeight())
	raylib.DrawRectangleRec(raylib.Rectangle{0, 0, sw, sh}, raylib.Color{0, 0, 0, 150})
	w: f32 = 460
	h: f32 = 240
	x := (sw - w) * 0.5
	y := (sh - h) * 0.5
	raylib.DrawRectangleRec(raylib.Rectangle{x, y, w, h}, raylib.Color{28, 24, 16, 250})
	raylib.DrawRectangleLinesEx(raylib.Rectangle{x, y, w, h}, 3, raylib.GOLD)
	r := RELICS[pending_relic]
	cx := i32(x + w * 0.5)
	draw_text_cx(cstring("RELIC CHEST"), cx, i32(y) + 20, 24, raylib.GOLD)
	draw_text_cx(r.name, cx, i32(y) + 56, 28, raylib.RAYWHITE)
	draw_text_cx(r.desc, cx, i32(y) + 96, 17, raylib.LIGHTGRAY)
	// Two buttons.
	bw: f32 = 180
	bh: f32 = 44
	by := y + h - 70
	accept_rect := raylib.Rectangle{x + 30, by, bw, bh}
	discard_rect := raylib.Rectangle{x + w - 30 - bw, by, bw, bh}
	mp := raylib.GetMousePosition()
	clicked := raylib.IsMouseButtonPressed(.LEFT)
	if raylib.CheckCollisionPointRec(mp, accept_rect) {
		raylib.DrawRectangleLinesEx(accept_rect, 3, raylib.YELLOW)
		if clicked {
			apply_relic(pending_relic)
			relic_pick_open = false
			play(sounds.shop_buy)
		}
	} else {
		raylib.DrawRectangleLinesEx(accept_rect, 2, raylib.GRAY)
	}
	if raylib.CheckCollisionPointRec(mp, discard_rect) {
		raylib.DrawRectangleLinesEx(discard_rect, 3, raylib.YELLOW)
		if clicked {
			relic_pick_open = false
			play(sounds.ui_move)
		}
	} else {
		raylib.DrawRectangleLinesEx(discard_rect, 2, raylib.GRAY)
	}
	draw_text_cx(cstring("ACCEPT"), i32(accept_rect.x + accept_rect.width * 0.5), i32(by) + 11, 22, raylib.LIME)
	draw_text_cx(cstring("DISCARD"), i32(discard_rect.x + discard_rect.width * 0.5), i32(by) + 11, 22, raylib.LIGHTGRAY)
	draw_text_cx(cstring("ENTER accept   -   ESC discard"), cx, i32(y + h) - 16, 14, raylib.DARKGRAY)
}

// Attack telegraphs, drawn on the ground under the enemies. Every boss/sniper
// wind-up paints its tell here; that's what makes those attacks dodgeable rather
// than unavoidable.
draw_telegraphs :: proc() {
	player_c := position + size * 0.5
	for e in enemies {
		ec := e.position + e.size * 0.5
		#partial switch e.kind {
		case .SNIPER:
			if e.state != .WINDUP {
				continue
			}
			// An aim line that brightens into the shot, plus a ring collapsing
			// onto it as the fuse runs out: you can see where it's going.
			k := 1 - clamp(e.state_timer / f32(SNIPER_TELEGRAPH), 0, 1)
			to_p := player_c - ec
			d := max(raylib.Vector2Length(to_p), 0.01)
			dir := to_p / d
			raylib.DrawLineEx(
				ec,
				ec + dir * d,
				f32(1 + k * 2),
				raylib.Color{255, 255, 120, u8(40 + 180 * k)},
			)
			raylib.DrawCircleLines(
				i32(ec.x),
				i32(ec.y),
				d * k,
				raylib.Color{255, 255, 120, u8(50 + 150 * k)},
			)
		case .BOSS:
			draw_boss_telegraph(e)
		}
	}
}

main :: proc() {
	windowX: i32 = 800
	windowY: i32 = 600
	raylib.InitWindow(windowX, windowY, "Roguelike")
	// Disable raylib's default ESC-to-close: ESC is UI "back" everywhere in this
	// game, and quitting is an explicit QUIT menu row (or the window X button).
	raylib.SetExitKey(raylib.KeyboardKey.KEY_NULL)
	raylib.SetTargetFPS(60)
	defer raylib.CloseWindow()
	// Load the player's settings, then match the window to the stored
	// fullscreen preference (fullscreen is the default).
	settings_load()
	refresh_run_save_presence()
	apply_fullscreen()
	defer settings_save()

	// Synthesize the whole sound bank into memory and open the audio device.
	audio_init()
	defer audio_shutdown()

	// Everything is drawn to a fixed 800x600 canvas which then gets scaled up to
	// the window. That keeps every layout coordinate (and the camera offset)
	// valid in fullscreen, letterboxed to preserve the aspect ratio.
	target := raylib.LoadRenderTexture(windowX, windowY)
	defer raylib.UnloadRenderTexture(target)

	// Run state now lives at package scope (see game.odin) so start_run/end_run
	// can reset it. Free its heap arrays on exit here.
	defer delete(cards)
	defer delete(enemies)
	defer delete(bullets)
	defer delete(enemy_bullets)
	defer delete(trail)
	defer delete(drops)
	defer delete(walls)
	defer delete(barrels)
	defer delete(props)
	defer delete(floor_marks)
	defer delete(weather)
	defer delete(explosions)
	defer delete(sparks)
	defer delete(shop_items)

	camera: raylib.Camera2D

	for !raylib.WindowShouldClose() && !quit_requested {
		dT := raylib.GetFrameTime()

		// Debug console: only meaningful during a run. Toggle with ` and, while
		// open, freeze the world (dT = 0) and sip its input instead.
		if state != .PLAYING {
			console_close()
		}
		if state == .PLAYING && raylib.IsKeyPressed(raylib.KeyboardKey.GRAVE) {
			console_toggle()
		}
		if console_open {
			dT = 0
			console_update()
		}

		// Dev cheat: Ctrl+Shift+U unlocks every map (persisted, but nothing is
		// marked as cleared). Works from any screen so you can see the whole map
		// list without grinding the progression.
		if (raylib.IsKeyDown(raylib.KeyboardKey.LEFT_CONTROL) ||
			   raylib.IsKeyDown(raylib.KeyboardKey.RIGHT_CONTROL)) &&
		   (raylib.IsKeyDown(raylib.KeyboardKey.LEFT_SHIFT) ||
			   raylib.IsKeyDown(raylib.KeyboardKey.RIGHT_SHIFT)) &&
		   raylib.IsKeyPressed(raylib.KeyboardKey.U) {
			unlock_all_maps()
			play(sounds.ui_select)
		}

		// In-game settings panel: Backspace toggles it during a run. While open the
		// world is frozen (the PLAYING case skips its update) and the panel is drawn
		// as an overlay over the last frame.
		if state == .PLAYING && raylib.IsKeyPressed(raylib.KeyboardKey.P) {
			ingame_panel_open = !ingame_panel_open
			play(sounds.ui_move)
		}

		// Auto-pause on focus loss: alt-tabbing away from the window pauses the run
		// and silences audio (audio_muted_here), so you never come back to a corpse
		// you died while switching windows. Only affects an active run.
		if state == .PLAYING {
			if !raylib.IsWindowFocused() {
				auto_paused = true
			} else {
				auto_paused = false
			}
			audio_muted_here = auto_paused
		} else {
			auto_paused = false
			audio_muted_here = false
		}

		// Hitstop: a heavy hit (kill, finisher, barrel) stalls the world for a
		// few frames so the impact lands before the player is moving again.
		// Counted in real time and scaled rather than zeroed, so it reads as
		// punch and never as input lag. Only during a run, so menus and the
		// skill-select screen are untouched.
		if hitstop > 0 && state == .PLAYING {
			hitstop -= raylib.GetFrameTime()
			dT *= 0.12
		}

		// Fit the 800x600 canvas into the (possibly fullscreen) window, keeping
		// the aspect ratio and centering it with letterbox bars.
		screen_w := f32(raylib.GetScreenWidth())
		screen_h := f32(raylib.GetScreenHeight())
		scale := min(screen_w / f32(windowX), screen_h / f32(windowY))
		view_w := f32(windowX) * scale
		view_h := f32(windowY) * scale
		view_x := (screen_w - view_w) * 0.5
		view_y := (screen_h - view_h) * 0.5
		// The mouse comes in window space; convert it to canvas space for picking.
		raw_mouse := raylib.GetMousePosition()
		mouse_pos = raylib.Vector2{(raw_mouse.x - view_x) / scale, (raw_mouse.y - view_y) / scale}
		mouse = raylib.Rectangle{mouse_pos.x, mouse_pos.y, 5, 5}
		// Hovering should only steal the keyboard selection when the mouse is
		// actually moving, or a resting cursor would freeze menu navigation.
		mouse_moved := raylib.Vector2Length(raylib.GetMouseDelta()) > 0.5

		#partial switch state {
		case .MAIN_MENU:
			// Rows: 0 continue, 1 start run, 2 missions, 3 tutorial, 4 settings,
			// 5 quit. CONTINUE is only usable when a run save exists.
			can_continue := has_run_save()
			if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
				main_menu_sel = (main_menu_sel + 1) % 6
				play(sounds.ui_move)
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
				main_menu_sel = (main_menu_sel - 1 + 6) % 6
				play(sounds.ui_move)
			}
			confirm := raylib.IsKeyPressed(raylib.KeyboardKey.ENTER)
			for key, idx in NUMBER_KEYS {
				if idx < 6 && raylib.IsKeyPressed(key) {
					main_menu_sel = idx
					confirm = true
				}
			}
			raylib.BeginTextureMode(target)
			raylib.ClearBackground(raylib.BLACK)
			draw_centered(cstring("ROGUELIKE"), 70, 64, raylib.WHITE)
			draw_centered(cstring("VECTORSHOT"), 148, 22, raylib.DARKGRAY)
			continue_col := raylib.GREEN
			if !can_continue {
				continue_col = raylib.DARKGRAY
			}
			if main_menu_sel == 0 && can_continue {
				continue_col = raylib.RAYWHITE
			}
			cont_label := cstring("CONTINUE RUN   (no saved run)")
			if can_continue {
				cont_label = cstring("CONTINUE RUN")
			}
			k0, h0 := ui_row(cont_label, 200, 30, continue_col)
			k1, h1 := ui_row(
				cstring("START RUN"),
				252,
				30,
				main_menu_sel == 1 ? raylib.RAYWHITE : raylib.GRAY,
			)
			k2, h2 := ui_row(
				cstring("MISSIONS"),
				304,
				30,
				main_menu_sel == 2 ? raylib.RAYWHITE : raylib.GRAY,
			)
			k3, h3 := ui_row(
				cstring("TUTORIAL"),
				356,
				30,
				main_menu_sel == 3 ? raylib.RAYWHITE : raylib.GRAY,
			)
			k4, h4 := ui_row(
				cstring("SETTINGS"),
				408,
				30,
				main_menu_sel == 4 ? raylib.RAYWHITE : raylib.GRAY,
			)
			k5, h5 := ui_row(
				cstring("QUIT"),
				460,
				30,
				main_menu_sel == 5 ? raylib.RAYWHITE : raylib.GRAY,
			)
			draw_centered(
				cstring("UP / DOWN to choose   -   ENTER to select"),
				525,
				18,
				raylib.DARKGRAY,
			)
			raylib.EndTextureMode()
			if mouse_moved {
				if h0 && can_continue {main_menu_sel = 0}
				if h1 {main_menu_sel = 1}
				if h2 {main_menu_sel = 2}
				if h3 {main_menu_sel = 3}
				if h4 {main_menu_sel = 4}
				if h5 {main_menu_sel = 5}
			}
			if (k0 || (confirm && main_menu_sel == 0)) && can_continue {
				if resume_run() {
					play(sounds.ui_select)
				}
			} else if k1 || (confirm && main_menu_sel == 1) {
				play(sounds.ui_select)
				active_mission = -1 // plain endless run
				state = .DIFFICULTY
			} else if k2 || (confirm && main_menu_sel == 2) {
				play(sounds.ui_select)
				mission_sel = 0
				state = .MISSION_CONTROL
			} else if k3 || (confirm && main_menu_sel == 3) {
				play(sounds.ui_select)
				tutorial_select_sel = 0
				state = .TUTORIAL_SELECT
			} else if k4 || (confirm && main_menu_sel == 4) {
				play(sounds.ui_select)
				settings_sel = 0
				state = .SETTINGS
			} else if k5 || (confirm && main_menu_sel == 5) {
				quit_requested = true
			}
		case .DIFFICULTY:
			// Official difficulty select. EASY enables the same comfort assists
			// the hidden GF mode (Ctrl+G) toggles during a run.
			if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
				difficulty = Difficulty((int(difficulty) + 1) % len(Difficulty))
				play(sounds.ui_move)
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
				difficulty = Difficulty((int(difficulty) - 1 + len(Difficulty)) % len(Difficulty))
				play(sounds.ui_move)
			}
			for key, idx in NUMBER_KEYS {
				if idx < len(Difficulty) && raylib.IsKeyPressed(key) {
					difficulty = Difficulty(idx)
					play(sounds.ui_move)
				}
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
				play(sounds.ui_select)
				skill_state = .MAIN
				state = .SKILL_SELECT
			}
			// ESC backs out to the main menu.
			if raylib.IsKeyPressed(raylib.KeyboardKey.ESCAPE) {
				play(sounds.ui_select)
				state = .MAIN_MENU
			}
			raylib.BeginTextureMode(target)
			raylib.ClearBackground(raylib.BLACK)
			draw_centered(cstring("SELECT DIFFICULTY"), 60, 50, raylib.WHITE)
			pick := false
			for d in Difficulty {
				selected := difficulty == d
				name_col := selected ? raylib.YELLOW : raylib.DARKGRAY
				desc_col := selected ? raylib.RAYWHITE : raylib.DARKGRAY
				y := 170 + i32(d) * 70
				ck, hv := ui_row(
					raylib.TextFormat("%i)  %s", int(d) + 1, difficulty_name(d)),
					y,
					30,
					name_col,
				)
				if mouse_moved && hv {
					difficulty = d
				}
				if ck {
					difficulty = d
					pick = true
				}
				draw_centered(difficulty_desc(d), y + 30, 17, desc_col)
			}
			draw_centered(cstring("1 - 3 or UP / DOWN to choose"), 400, 20, raylib.GRAY)
			draw_centered(cstring("Press ENTER to continue"), 440, 22, raylib.RAYWHITE)
			raylib.EndTextureMode()
			if pick {
				play(sounds.ui_select)
				skill_state = .MAIN
				state = .SKILL_SELECT
			}
		case .MISSION_CONTROL:
			// Grid of selectable missions ("levels"). Arrows or a click move the
			// cursor; ENTER launches the highlighted mission into difficulty pick.
			MISSION_COLS :: 3
			CARD_W: i32 = 240
			CARD_H: i32 = 100
			if raylib.IsKeyPressed(raylib.KeyboardKey.LEFT) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.A) {
				if mission_sel % MISSION_COLS > 0 {
					mission_sel -= 1
					play(sounds.ui_move)
				}
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.RIGHT) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.D) {
				if mission_sel % MISSION_COLS < MISSION_COLS - 1 &&
				   mission_sel + 1 < len(MISSIONS) {
					mission_sel += 1
					play(sounds.ui_move)
				}
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
				if mission_sel >= MISSION_COLS {
					mission_sel -= MISSION_COLS
					play(sounds.ui_move)
				}
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
				if mission_sel + MISSION_COLS < len(MISSIONS) {
					mission_sel += MISSION_COLS
					play(sounds.ui_move)
				}
			}
			confirm := raylib.IsKeyPressed(raylib.KeyboardKey.ENTER)
			back := raylib.IsKeyPressed(raylib.KeyboardKey.ESCAPE)
			raylib.BeginTextureMode(target)
			raylib.ClearBackground(raylib.BLACK)
			draw_centered(cstring("MISSION CONTROL"), 40, 40, raylib.WHITE)
			cleared := 0
			for idx in 0 ..< len(MISSIONS) {
				if mission_done(idx) {
					cleared += 1
				}
			}
			draw_centered(
				raylib.TextFormat("%i / %i CLEARED", cleared, len(MISSIONS)),
				88,
				18,
				raylib.DARKGRAY,
			)
			launch := false
			for idx in 0 ..< len(MISSIONS) {
				m := MISSIONS[idx]
				col := i32(idx % MISSION_COLS)
				row := i32(idx / MISSION_COLS)
				x := 20 + col * (CARD_W + 20)
				y := 130 + row * (CARD_H + 12)
				rect := raylib.Rectangle{f32(x), f32(y), f32(CARD_W), f32(CARD_H)}
				done := mission_done(idx)
				selected := mission_sel == idx
				// Body + border: cyan when selected, green when cleared, else gray.
				raylib.DrawRectangleRec(rect, raylib.Color{22, 22, 30, 255})
				border := raylib.DARKGRAY
				if done {
					border = raylib.GREEN
				}
				if selected {
					border = raylib.SKYBLUE
				}
				raylib.DrawRectangleLinesEx(rect, 3, border)
				name_col := selected ? raylib.YELLOW : raylib.RAYWHITE
				raylib.DrawText(m.name, x + 10, y + 8, 20, name_col)
				raylib.DrawText(mission_objective_text(m), x + 10, y + 36, 15, raylib.LIGHTGRAY)
				// Arena + wave-density modifier + payout, on one line.
				label := raylib.TextFormat("%s    +%i", string(ARENAS[m.arena].name), m.reward)
				if m.density > 1.0 {
					label = raylib.TextFormat(
						"%s  x%.1f    +%i",
						string(ARENAS[m.arena].name),
						m.density,
						m.reward,
					)
				}
				raylib.DrawText(label, x + 10, y + 60, 14, raylib.GOLD)
				if done {
					raylib.DrawText(cstring("CLEARED"), x + CARD_W - 76, y + 8, 15, raylib.GREEN)
				}
				if raylib.CheckCollisionRecs(mouse, rect) {
					if mouse_moved {
						mission_sel = idx
					}
					if raylib.IsMouseButtonPressed(.LEFT) {
						mission_sel = idx
						confirm = true
					}
				}
				if selected && confirm {
					launch = true
				}
			}
			draw_centered(
				cstring("ARROWS to browse   -   ENTER to deploy   -   ESC to go back"),
				590,
				16,
				raylib.DARKGRAY,
			)
			raylib.EndTextureMode()
			if launch {
				play(sounds.ui_select)
				active_mission = mission_sel
				state = .DIFFICULTY
			} else if back {
				play(sounds.ui_select)
				state = .MAIN_MENU
			}
		case .TUTORIAL_SELECT:
			// Pick a tutorial tier. ADVANCED then asks which character to teach.
			if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
				tutorial_select_sel = (tutorial_select_sel + 1) % 4
				play(sounds.ui_move)
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
				tutorial_select_sel = (tutorial_select_sel - 1 + 4) % 4
				play(sounds.ui_move)
			}
			if tutorial_select_sel == 2 {
				if raylib.IsKeyPressed(raylib.KeyboardKey.RIGHT) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.D) {
					tutorial_char = Character((int(tutorial_char) + 1) % len(Character))
					play(sounds.ui_move)
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.LEFT) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.A) {
					tutorial_char = Character(
						(int(tutorial_char) - 1 + len(Character)) % len(Character),
					)
					play(sounds.ui_move)
				}
			}
			for key, idx in NUMBER_KEYS {
				if idx < 4 && raylib.IsKeyPressed(key) {
					tutorial_select_sel = idx
					play(sounds.ui_move)
				}
			}
			raylib.BeginTextureMode(target)
			raylib.ClearBackground(raylib.BLACK)
			draw_centered(cstring("TUTORIALS"), 50, 50, raylib.WHITE)
			draw_centered(
				cstring("Learn by doing -- nothing here can hurt you"),
				108,
				18,
				raylib.GRAY,
			)
			t0, th0 := ui_row(
				cstring("1)  BASIC      move, shoot, reload, dash, kick"),
				170,
				28,
				tutorial_select_sel == 0 ? raylib.YELLOW : raylib.DARKGRAY,
			)
			t1, th1 := ui_row(
				cstring("2)  MEDIUM     slots, signatures, cards & the shop"),
				220,
				28,
				tutorial_select_sel == 1 ? raylib.YELLOW : raylib.DARKGRAY,
			)
			t2, th2 := ui_row(
				raylib.TextFormat(
					"3)  ADVANCED   a character's kit  <%s>",
					string(CHARACTERS[tutorial_char].name),
				),
				270,
				28,
				tutorial_select_sel == 2 ? raylib.YELLOW : raylib.DARKGRAY,
			)
			t3, th3 := ui_row(
				cstring("BACK"),
				340,
				28,
				tutorial_select_sel == 3 ? raylib.YELLOW : raylib.DARKGRAY,
			)
			draw_centered(
				cstring(
					"BASIC & MEDIUM play as Navy  -  ADVANCED: LEFT / RIGHT picks a character",
				),
				420,
				17,
				raylib.GRAY,
			)
			draw_centered(cstring("ENTER to start   -   ESC to go back"), 460, 20, raylib.RAYWHITE)
			raylib.EndTextureMode()
			if mouse_moved {
				if th0 {tutorial_select_sel = 0}
				if th1 {tutorial_select_sel = 1}
				if th2 {tutorial_select_sel = 2}
				if th3 {tutorial_select_sel = 3}
			}
			if t3 || raylib.IsKeyPressed(raylib.KeyboardKey.ESCAPE) {
				play(sounds.ui_select)
				state = .MAIN_MENU
			} else if t0 || t1 || t2 || raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
				kind: Tutorial_Kind
				switch tutorial_select_sel {
				case 1:
					kind = .MEDIUM
				case 2:
					kind = .ADVANCED
				case 3:
					kind = .BASIC
					state = .MAIN_MENU
				case:
					kind = .BASIC
				}
				if state != .MAIN_MENU {
					play(sounds.ui_select)
					char := character
					if kind == .ADVANCED {
						char = tutorial_char
					}
					tutorial_start(kind, char)
				}
			}
		case .SETTINGS:
			// Rows: 0 volume, 1 mute, 2 fullscreen, 3 difficulty, 4 assists,
			// 5 FPS, 6 damage numbers, 7 hurt vignette, 8 shake, 9 blood,
			// 10 controls, 11 back.
			if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
				settings_sel = (settings_sel + 1) % 12
				play(sounds.ui_move)
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
				settings_sel = (settings_sel - 1 + 12) % 12
				play(sounds.ui_move)
			}
			changed := false
			left :=
				raylib.IsKeyPressed(raylib.KeyboardKey.LEFT) ||
				raylib.IsKeyPressed(raylib.KeyboardKey.A)
			right :=
				raylib.IsKeyPressed(raylib.KeyboardKey.RIGHT) ||
				raylib.IsKeyPressed(raylib.KeyboardKey.D)
			if left || right {
				step := right ? f32(0.05) : f32(-0.05)
				switch settings_sel {
				case 0:
					settings.master_volume = clamp(settings.master_volume + step, 0, 1)
					changed = true
				case 3:
					difficulty = Difficulty(
						(int(difficulty) + (right ? 1 : -1) + len(Difficulty)) % len(Difficulty),
					)
					changed = true
				case 8:
					settings.screen_shake = clamp(settings.screen_shake + step, 0, 1)
					changed = true
				case:
				}
			}
			toggle_sel :=
				raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) ||
				raylib.IsKeyPressed(raylib.KeyboardKey.SPACE)
			raylib.BeginTextureMode(target)
			raylib.ClearBackground(raylib.BLACK)
			draw_centered(cstring("SETTINGS"), 36, 44, raylib.WHITE)
			// 0: volume slider.
			vol := ui_slider(
				0,
				cstring("Master volume"),
				116,
				100,
				420,
				180,
				settings.master_volume,
			)
			if vol != settings.master_volume {
				settings.master_volume = vol
				changed = true
			}
			k1, h1 := ui_setting_row(
				cstring("Mute"),
				settings.muted ? cstring("ON") : cstring("OFF"),
				142,
				settings_sel == 1,
			)
			k2, h2 := ui_setting_row(
				cstring("Fullscreen"),
				settings.fullscreen ? cstring("ON") : cstring("OFF"),
				179,
				settings_sel == 2,
			)
			k3, h3 := ui_setting_row(
				cstring("Difficulty"),
				raylib.TextFormat("%s", difficulty_name(difficulty)),
				216,
				settings_sel == 3,
			)
			k4, h4 := ui_setting_row(
				cstring("Comfort assists (GF)"),
				gf_mode ? cstring("ON") : cstring("OFF"),
				253,
				settings_sel == 4,
			)
			k5, h5 := ui_setting_row(
				cstring("Show FPS"),
				settings.show_fps ? cstring("ON") : cstring("OFF"),
				290,
				settings_sel == 5,
			)
			k6, h6 := ui_setting_row(
				cstring("Damage numbers"),
				settings.damage_numbers ? cstring("ON") : cstring("OFF"),
				327,
				settings_sel == 6,
			)
			k7, h7 := ui_setting_row(
				cstring("Hurt vignette"),
				settings.hurt_vignette ? cstring("ON") : cstring("OFF"),
				364,
				settings_sel == 7,
			)
			// 8: screen-shake slider.
			shk := ui_slider(1, cstring("Screen shake"), 116, 404, 420, 180, settings.screen_shake)
			if shk != settings.screen_shake {
				settings.screen_shake = shk
				changed = true
			}
			k9, h9 := ui_setting_row(
				cstring("Blood"),
				settings.blood ? cstring("ON") : cstring("OFF"),
				444,
				settings_sel == 9,
			)
			k10, h10 := ui_setting_row(
				cstring("Controls"),
				settings.control_scheme == .MOUSE ? cstring("MOUSE") : cstring("KEYBOARD"),
				481,
				settings_sel == 10,
			)
			k11, h11 := ui_setting_row(cstring("BACK"), cstring(""), 524, settings_sel == 11)
			draw_centered(
				cstring("UP / DOWN to choose   -   LEFT / RIGHT to adjust"),
				566,
				16,
				raylib.GRAY,
			)
			raylib.EndTextureMode()

			if mouse_moved {
				if h1 {settings_sel = 1}
				if h2 {settings_sel = 2}
				if h3 {settings_sel = 3}
				if h4 {settings_sel = 4}
				if h5 {settings_sel = 5}
				if h6 {settings_sel = 6}
				if h7 {settings_sel = 7}
				if h9 {settings_sel = 9}
				if h10 {settings_sel = 10}
				if h11 {settings_sel = 11}
			}
			// Clicking a row toggles/cycles it, except the two sliders.
			if k1 || (toggle_sel && settings_sel == 1) {
				settings.muted = !settings.muted
				changed = true
			}
			if k2 || (toggle_sel && settings_sel == 2) {
				play(sounds.ui_select)
				settings.fullscreen = !settings.fullscreen
				apply_fullscreen()
				changed = true
			}
			if k3 || (toggle_sel && settings_sel == 3) {
				difficulty = Difficulty((int(difficulty) + 1) % len(Difficulty))
				changed = true
			}
			if k4 || (toggle_sel && settings_sel == 4) {
				gf_mode = !gf_mode
				changed = true
			}
			if k5 || (toggle_sel && settings_sel == 5) {
				settings.show_fps = !settings.show_fps
				changed = true
			}
			if k6 || (toggle_sel && settings_sel == 6) {
				settings.damage_numbers = !settings.damage_numbers
				changed = true
			}
			if k7 || (toggle_sel && settings_sel == 7) {
				settings.hurt_vignette = !settings.hurt_vignette
				changed = true
			}
			if k9 || (toggle_sel && settings_sel == 9) {
				settings.blood = !settings.blood
				changed = true
			}
			if k10 || (toggle_sel && settings_sel == 10) {
				settings.control_scheme = settings.control_scheme == .MOUSE ? .KEYBOARD : .MOUSE
				changed = true
			}
			if k11 ||
			   (toggle_sel && settings_sel == 11) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.ESCAPE) {
				play(sounds.ui_select)
				state = .MAIN_MENU
			}
			if changed {
				settings_save()
			}
		case .SKILL_SELECT:
			// ESC is "back" everywhere: out of a sub-screen to the skill-select
			// summary, and out of the summary to the previous state.
			if raylib.IsKeyPressed(raylib.KeyboardKey.ESCAPE) {
				if skill_state != .MAIN {
					skill_state = .MAIN
				} else {
					state = .DIFFICULTY
				}
			}
			// Menu navigation + confirm blips, shared by every skill screen.
			if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.W) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
				play(sounds.ui_move)
			}
			for key in NUMBER_KEYS {
				if raylib.IsKeyPressed(key) {
					play(sounds.ui_move)
					break
				}
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
				play(sounds.ui_select)
			}
			#partial switch skill_state {
			case .MAIN:
				if raylib.IsKeyPressed(raylib.KeyboardKey.ONE) {
					skill_state = .CHARACTER
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.TWO) {
					skill_state = .GUN
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.THREE) {
					skill_state = .DASH
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.FOUR) {
					skill_state = .UTILITY
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.FIVE) {
					skill_state = .SECONDARY
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.SIX) {
					skill_state = .ARENA
					arena_pick_sel = int(arena)
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
					// Apply the chosen loadout and start a fresh run. A locked arena
					// (only reachable here via a mission override) falls back to the
					// always-open starter map.
					if !map_unlocked(arena) {
						arena = .GRASSLAND
					}
					start_run(start_loadout(character, gun, secondary_kind, dash_kind, utility))
				}
				raylib.BeginTextureMode(target)
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SKILL SELECT"), 50, 50, raylib.WHITE)
				q1, v1 := ui_row(
					raylib.TextFormat("1)  CHARACTER  %s", string(CHARACTERS[character].name)),
					120,
					28,
					raylib.RAYWHITE,
				)
				q2, v2 := ui_row(
					raylib.TextFormat("2)  PRIMARY    %s", string(GUNS[gun].name)),
					162,
					28,
					raylib.YELLOW,
				)
				q3, v3 := ui_row(
					raylib.TextFormat("3)  DASH       %s", string(DASHES[dash_kind].name)),
					204,
					28,
					raylib.SKYBLUE,
				)
				q4, v4 := ui_row(
					raylib.TextFormat("4)  UTILITY    %s", string(UTILITIES[utility].name)),
					246,
					28,
					raylib.GREEN,
				)
				q5, v5 := ui_row(
					raylib.TextFormat(
						"5)  SECONDARY  %s",
						string(SECONDARIES[secondary_kind].name),
					),
					288,
					28,
					raylib.ORANGE,
				)
				q6, v6 := ui_row(
					raylib.TextFormat("6)  ARENA      %s", string(ARENAS[arena].name)),
					330,
					28,
					raylib.VIOLET,
				)
				qs, _ := ui_row(cstring("START RUN  (ENTER)"), 404, 26, raylib.RAYWHITE)
				draw_centered(
					cstring("Click a slot or press 1 - 6 to change it"),
					462,
					20,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
				if q1 {skill_state = .CHARACTER}
				if q2 {skill_state = .GUN}
				if q3 {skill_state = .DASH}
				if q4 {skill_state = .UTILITY}
				if q5 {skill_state = .SECONDARY}
				if q6 {
					skill_state = .ARENA
					arena_pick_sel = int(arena)
				}
				if qs {
					if !map_unlocked(arena) {
						arena = .GRASSLAND
					}
					start_run(start_loadout(character, gun, secondary_kind, dash_kind, utility))
				}
			case .CHARACTER:
				if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
					character = Character((int(character) + 1) % len(CHARACTERS))
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
					character = Character((int(character) - 1 + len(CHARACTERS)) % len(CHARACTERS))
				}
				for key, idx in NUMBER_KEYS {
					if idx < len(CHARACTERS) && raylib.IsKeyPressed(key) {
						character = Character(idx)
					}
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
					skill_state = .MAIN
				}
				raylib.BeginTextureMode(target)
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SELECT CHARACTER"), 44, 40, raylib.WHITE)
				for ch in Character {
					selected := character == ch
					color := selected ? raylib.RAYWHITE : raylib.DARKGRAY
					y := 100 + i32(ch) * 112
					draw_character_icon(ch, {140, f32(y) + 20}, 20)
					ck, hv := ui_row(
						raylib.TextFormat("%i)  %s", int(ch) + 1, string(CHARACTERS[ch].name)),
						y,
						28,
						color,
					)
					if (mouse_moved && hv) || ck {character = ch}
					draw_centered(CHARACTERS[ch].desc, y + 28, 17, raylib.GRAY)
					draw_centered(
						raylib.TextFormat(
							"PASSIVE: %s - %s",
							string(CHARACTERS[ch].passive),
							string(CHARACTERS[ch].passive_desc),
						),
						y + 48,
						14,
						selected ? raylib.SKYBLUE : raylib.DARKGRAY,
					)
					draw_centered(
						raylib.TextFormat(
							"SPD %i   HP %i   MELEE x%.2f",
							int(CHARACTERS[ch].speed),
							int(CHARACTERS[ch].max_health),
							CHARACTERS[ch].melee_damage_mult,
						),
						y + 70,
						15,
						raylib.DARKGRAY,
					)
					draw_centered(
						raylib.TextFormat("SIGNATURE MELEE: %s", string(SIGNATURE_NAMES[ch])),
						y + 84,
						13,
						selected ? raylib.ORANGE : raylib.DARKGRAY,
					)
				}
				back, _ := ui_row(
					cstring("UP/DOWN or 1-9 to pick, ENTER / click here to go back"),
					564,
					22,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
				if back {skill_state = .MAIN}
			case .GUN:
				if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
					gun = Gun((int(gun) + 1) % len(GUNS))
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
					gun = Gun((int(gun) - 1 + len(GUNS)) % len(GUNS))
				}
				for key, idx in NUMBER_KEYS {
					if idx < len(GUNS) && raylib.IsKeyPressed(key) {
						gun = Gun(idx)
					}
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
					skill_state = .MAIN
				}
				raylib.BeginTextureMode(target)
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SELECT PRIMARY"), 40, 36, raylib.WHITE)
				for g in Gun {
					color := gun == g ? raylib.YELLOW : raylib.DARKGRAY
					y := 92 + i32(g) * 48
					tag := GUNS[g].class == .MELEE ? cstring("MELEE") : cstring("GUN")
					ck, hv := ui_row(
						raylib.TextFormat(
							"%i)  %s   [%s]",
							int(g) + 1,
							string(GUNS[g].name),
							string(tag),
						),
						y,
						24,
						color,
					)
					if (mouse_moved && hv) || ck {gun = g}
					draw_centered(GUNS[g].desc, y + 22, 16, raylib.GRAY)
				}
				back, _ := ui_row(
					cstring("UP/DOWN or 1-9 to pick, ENTER / click here to go back"),
					572,
					20,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
				if back {skill_state = .MAIN}
			case .DASH:
				if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
					dash_kind = Dash_Kind((int(dash_kind) + 1) % len(DASHES))
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
					dash_kind = Dash_Kind((int(dash_kind) - 1 + len(DASHES)) % len(DASHES))
				}
				for key, idx in NUMBER_KEYS {
					if idx < len(DASHES) && raylib.IsKeyPressed(key) {
						dash_kind = Dash_Kind(idx)
					}
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
					skill_state = .MAIN
				}
				raylib.BeginTextureMode(target)
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SELECT DASH"), 60, 40, raylib.WHITE)
				for d in Dash_Kind {
					color := dash_kind == d ? raylib.SKYBLUE : raylib.DARKGRAY
					y := 140 + i32(d) * 65
					ck, hv := ui_row(
						raylib.TextFormat("%i)  %s", int(d) + 1, string(DASHES[d].name)),
						y,
						28,
						color,
					)
					if (mouse_moved && hv) || ck {dash_kind = d}
					draw_centered(DASHES[d].desc, y + 30, 18, raylib.GRAY)
				}
				back, _ := ui_row(
					cstring("UP/DOWN or 1-9 to pick, ENTER / click here to go back"),
					510,
					22,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
				if back {skill_state = .MAIN}
			case .UTILITY:
				if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
					utility = Utility((int(utility) + 1) % len(UTILITIES))
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
					utility = Utility((int(utility) - 1 + len(UTILITIES)) % len(UTILITIES))
				}
				for key, idx in NUMBER_KEYS {
					if idx < len(UTILITIES) && raylib.IsKeyPressed(key) {
						utility = Utility(idx)
					}
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
					skill_state = .MAIN
				}
				raylib.BeginTextureMode(target)
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SELECT UTILITY"), 60, 40, raylib.WHITE)
				for u in Utility {
					color := utility == u ? raylib.GREEN : raylib.DARKGRAY
					y := 110 + i32(u) * 52
					ck, hv := ui_row(
						raylib.TextFormat("%i)  %s", int(u) + 1, string(UTILITIES[u].name)),
						y,
						26,
						color,
					)
					if (mouse_moved && hv) || ck {utility = u}
					draw_centered(UTILITIES[u].desc, y + 24, 16, raylib.GRAY)
				}
				back, _ := ui_row(
					cstring("UP/DOWN or 1-9 to pick, ENTER / click here to go back"),
					520,
					22,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
				if back {skill_state = .MAIN}
			case .SECONDARY:
				if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
					secondary_kind = Secondary((int(secondary_kind) + 1) % len(SECONDARIES))
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
					secondary_kind = Secondary(
						(int(secondary_kind) - 1 + len(SECONDARIES)) % len(SECONDARIES),
					)
				}
				for key, idx in NUMBER_KEYS {
					if idx < len(SECONDARIES) && raylib.IsKeyPressed(key) {
						secondary_kind = Secondary(idx)
					}
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
					skill_state = .MAIN
				}
				raylib.BeginTextureMode(target)
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SELECT SECONDARY"), 44, 36, raylib.WHITE)
				for s in Secondary {
					color := secondary_kind == s ? raylib.ORANGE : raylib.DARKGRAY
					y := 108 + i32(s) * 72
					tag := SECONDARIES[s].class == .MELEE ? cstring("MELEE") : cstring("GUN")
					ck, hv := ui_row(
						raylib.TextFormat(
							"%i)  %s   [%s]",
							int(s) + 1,
							string(SECONDARIES[s].name),
							string(tag),
						),
						y,
						26,
						color,
					)
					if (mouse_moved && hv) || ck {secondary_kind = s}
					draw_centered(SECONDARIES[s].desc, y + 26, 16, raylib.GRAY)
				}
				back, _ := ui_row(
					cstring("UP/DOWN or 1-9 to pick, ENTER / click here to go back"),
					560,
					20,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
				if back {skill_state = .MAIN}
			case .ARENA:
				// Grid of themed map cards (every arena visible at once), mirroring the
				// Mission Control layout so nothing falls off the bottom of the canvas.
				// Arrows / number keys move the cursor, ENTER or a click confirms an
				// unlocked map and returns to the wizard menu. Locked maps say what
				// opens them; the Ctrl+Shift+U cheat opens them all.
				ARENA_COLS :: 3
				ARENA_CW: i32 = 240
				ARENA_CH: i32 = 116
				n := len(ARENAS)
				if arena_pick_sel < 0 || arena_pick_sel >= n {
					arena_pick_sel = int(arena)
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.LEFT) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.A) {
					if arena_pick_sel % ARENA_COLS > 0 {
						arena_pick_sel -= 1
					}
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.RIGHT) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.D) {
					if arena_pick_sel % ARENA_COLS < ARENA_COLS - 1 && arena_pick_sel + 1 < n {
						arena_pick_sel += 1
					}
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
					if arena_pick_sel >= ARENA_COLS {
						arena_pick_sel -= ARENA_COLS
					}
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
					if arena_pick_sel + ARENA_COLS < n {
						arena_pick_sel += ARENA_COLS
					}
				}
				for key, idx in NUMBER_KEYS {
					if idx < n && raylib.IsKeyPressed(key) {
						arena_pick_sel = idx
					}
				}
				sel := arena_pick_sel
				locked := !map_unlocked(Arena_Kind(sel))
				confirm :=
					!locked &&
					(raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) ||
					 raylib.IsKeyPressed(raylib.KeyboardKey.SPACE))
				raylib.BeginTextureMode(target)
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SELECT ARENA"), 40, 40, raylib.WHITE)
				for ai in Arena_Kind {
					a := int(ai)
					col := i32(a) % ARENA_COLS
					row := i32(a) / ARENA_COLS
					x := 20 + col * (ARENA_CW + 20)
					y := 110 + row * (ARENA_CH + 14)
					rect := raylib.Rectangle{f32(x), f32(y), f32(ARENA_CW), f32(ARENA_CH)}
					pal := ARENAS[ai]
					selected := a == sel
					unlocked := map_unlocked(ai)
					done := settings.maps_done & (1 << u32(a)) != 0
					card_bg := raylib.Color{20, 20, 28, 255}
					if !unlocked {
						card_bg = raylib.Color{14, 14, 18, 255}
					}
					raylib.DrawRectangleRec(rect, card_bg)
					border := unlocked ? raylib.DARKGRAY : raylib.Color{52, 40, 40, 255}
					if selected {
						border = unlocked ? raylib.VIOLET : raylib.MAROON
					}
					raylib.DrawRectangleLinesEx(rect, 3, border)
					// Themed preview: floor tile, a wall bar, and a couple of cover blobs.
					sx := x + 12
					sy := y + 12
					raylib.DrawRectangle(sx, sy, ARENA_CW - 24, 46, pal.floor_dark)
					raylib.DrawRectangle(sx, sy + 36, ARENA_CW - 24, 10, pal.wall)
					raylib.DrawCircleV({f32(sx + 32), f32(sy + 22)}, 12, pal.cover)
					raylib.DrawCircleV({f32(sx + 84), f32(sy + 22)}, 12, pal.cover)
					name_col := selected ? raylib.YELLOW : raylib.RAYWHITE
					if !unlocked {
						name_col = raylib.DARKGRAY
					}
					raylib.DrawText(
						raylib.TextFormat("%i)  %s", a + 1, string(pal.name)),
						x + 12,
						y + 66,
						20,
						name_col,
					)
					if unlocked {
						if done {
							// Cleared maps get a tick so a full run-through is legible.
							raylib.DrawText("CLEARED", x + ARENA_CW - 84, y + 66, 16, raylib.GREEN)
						}
						raylib.DrawText(pal.desc, x + 12, y + 92, 13, raylib.GRAY)
					} else {
						// Locked: name what opens it (the previous map's boss).
						req: cstring = "LOCKED"
						if a > 0 {
							req = raylib.TextFormat(
								"CLEAR %s",
								string(ARENAS[Arena_Kind(a - 1)].name),
							)
						}
						raylib.DrawText(req, x + 12, y + 92, 13, raylib.MAROON)
					}
					if raylib.CheckCollisionRecs(mouse, rect) {
						if mouse_moved {
							arena_pick_sel = a
							sel = a
							locked = !unlocked
						}
						if raylib.IsMouseButtonPressed(.LEFT) && unlocked {
							arena_pick_sel = a
							sel = a
							confirm = true
						}
					}
				}
				hint := cstring("ARROWS or 1-7 to pick   -   ENTER to confirm")
				if locked {
					hint = cstring(
						"LOCKED   -   clear the previous map's boss, or press Ctrl+Shift+U",
					)
				}
				draw_centered(hint, 560, 16, locked ? raylib.MAROON : raylib.GRAY)
				raylib.EndTextureMode()
				if confirm {
					arena = Arena_Kind(sel)
					skill_state = .MAIN
					play(sounds.ui_select)
				}
			}
		case .PLAYING:
			// In-game settings panel is up: handle its input and freeze the world by
			// skipping this frame's update+draw. The canvas texture keeps the last
			// frame, which the present step redraws with the panel over it. Auto-pause
			// (focus loss) freezes the same way, minus the panel input.
			if ingame_panel_open {
				ingame_panel_update()
			}
			if relic_pick_open {
				relic_pick_update()
			}
			if ingame_panel_open || auto_paused || relic_pick_open {
				break
			}
			camera.target = position + size * 0.5
			camera.offset = {400, 300}
			camera.zoom = 1
			// Screen shake: decay the pending magnitude and convert it to a small
			// camera jitter. Applied to the camera only at draw time (below) so it
			// never perturbs the mouse->world aim conversion.
			shake_mag = max(shake_mag - SHAKE_DECAY * dT, 0)
			shake = shake_mag * settings.screen_shake
			// Count active play time for the results screen.
			run_time += dT
			// Count the boss/clear callout down to nothing.
			banner_timer = max(banner_timer - dT, 0)
			// Ambient falling snow (GLACIER). Screen-space, ticked here so it
			// freezes with the rest of the world when the panel is open.
			update_weather(dT)
			// GF mode (Ctrl+G): a hidden comfort toggle. Ctrl is read directly so
			// the plain-G debug key below can tell the two apart.
			gf_ctrl :=
				raylib.IsKeyDown(raylib.KeyboardKey.LEFT_CONTROL) ||
				raylib.IsKeyDown(raylib.KeyboardKey.RIGHT_CONTROL)
			gf_clock += dT
			if gf_ctrl && world_key_pressed(raylib.KeyboardKey.G) {
				gf_mode = !gf_mode
				play(sounds.ui_select)
			}
			// Stamp when each direction key was pressed so GF mode can resolve
			// opposite pairs by recency instead of cancelling.
			if world_key_pressed(raylib.KeyboardKey.W) {gf_t_w = gf_clock}
			if world_key_pressed(raylib.KeyboardKey.A) {gf_t_a = gf_clock}
			if world_key_pressed(raylib.KeyboardKey.S) {gf_t_s = gf_clock}
			if world_key_pressed(raylib.KeyboardKey.D) {gf_t_d = gf_clock}
			// Aim at the cursor: convert the canvas-space mouse back through the
			// camera into world space, then face that way. Firing and kicking use
			// aim_dir, so you no longer shoot wherever you happen to be moving.
			world_mouse := (mouse_pos - camera.offset) / camera.zoom + camera.target
			to_mouse := world_mouse - (position + size * 0.5)
			if raylib.Vector2Length(to_mouse) > 0.01 {
				aim_dir = raylib.Vector2Normalize(to_mouse)
				tutorial_note(.AIM)
			}
			if world_key_pressed(raylib.KeyboardKey.Q) {
				active_slot = (active_slot + 1) % SLOT_COUNT
				play(sounds.ui_move)
				tutorial_note(.CYCLE)
			}
			dir := raylib.Vector2(0)
			if assists_on() {
				dir = gf_move_dir()
			} else {
				if world_key_down(raylib.KeyboardKey.A) {dir.x -= 1}
				if world_key_down(raylib.KeyboardKey.D) {dir.x += 1}
				if world_key_down(raylib.KeyboardKey.W) {dir.y -= 1}
				if world_key_down(raylib.KeyboardKey.S) {dir.y += 1}
			}
			moving = dir != raylib.Vector2(0) || dash_timer > 0
			// Character passives: RR re-picks his adaptation live, Tracer's Heart
			// winds down when she isn't attacking, and Bud's combo closes if he
			// doesn't follow up in time.
			update_rr_adaptation()
			if character == .TRACER {
				traceur_charge = max(traceur_charge - TRACEUR_DECAY * dT, 0)
			}
			if rr_surge > 0 {
				rr_surge = max(rr_surge - dT, 0)
			}
			if combo_timer > 0 {
				combo_timer -= dT
				if combo_timer <= 0 {
					combo_index = 0
					combo_charge = 0
				}
			}
			// Charged finishers (Bud's flying knee) wind up while they're armed.
			if combo_timer > 0 && signature_next_charged() {
				combo_charge = min(combo_charge + dT / KNEE_CHARGE_TIME, 1)
			}

			if world_key_pressed(raylib.KeyboardKey.F1) {
				debug_mode = !debug_mode
			}
			if world_key_pressed(raylib.KeyboardKey.F2) {
				skill_state = .MAIN
				state = GameState.SKILL_SELECT
			}
			if dash_timer > 0 {
				dash_timer -= dT
				position += raylib.Vector2Normalize(last_dir) * DASH_SPEED * dT
				append(&trail, trail_point{position, 0.3})
				// IMPACT dash (and card upgrades that set dash_damages) hurts
				// everything it touches while active.
				if dash_damages {
					impact_rect := raylib.Rectangle{position.x, position.y, size.x, size.y}
					for i := len(enemies) - 1; i >= 0; i -= 1 {
						er := raylib.Rectangle {
							enemies[i].position.x,
							enemies[i].position.y,
							enemies[i].size.x,
							enemies[i].size.y,
						}
						if raylib.CheckCollisionRecs(impact_rect, er) {
							ec := enemies[i].position + enemies[i].size * 0.5
							apply_enemy_damage(
								&enemies[i],
								dash_damage * dT,
								position + size * 0.5 - ec,
							)
							// Bud's IMPACT synergy: his dash sends enemies flying.
							if character == .BUD && dash_kind == .IMPACT {
								away := ec - (position + size * 0.5)
								if raylib.Vector2Length(away) > 0.01 {
									enemies[i].position +=
										raylib.Vector2Normalize(away) * BUD_IMPACT_KNOCK * dT
								}
							}
							if enemies[i].hp <= 0 {
								count_kill(enemies[i].elite)
								try_spawn_health_drop(enemies[i].position, &drops)
								try_spawn_ammo_drop(enemies[i].position, &drops)
								unordered_remove(&enemies, i)
							}
						}
					}
					for i := len(barrels) - 1; i >= 0; i -= 1 {
						br := raylib.Rectangle {
							barrels[i].pos.x,
							barrels[i].pos.y,
							barrels[i].size.x,
							barrels[i].size.y,
						}
						if raylib.CheckCollisionRecs(impact_rect, br) {
							barrels[i].hp -= dash_damage * dT
						}
					}
				}
			}
			for i := len(trail) - 1; i >= 0; i -= 1 {
				trail[i].life -= dT
				if trail[i].life <= 0 {
					unordered_remove(&trail, i)
				}
			}
			for i := len(explosions) - 1; i >= 0; i -= 1 {
				explosions[i].life -= dT
				if explosions[i].life <= 0 {
					unordered_remove(&explosions, i)
				}
			}
			// Impact sparks: fly out, damp hard and fade. They live in the same
			// (paused) world clock as everything else, so hitstop freezes them too.
			for i := len(sparks) - 1; i >= 0; i -= 1 {
				sparks[i].life -= dT
				sparks[i].pos += sparks[i].vel * dT
				sparks[i].vel *= 1 - 9 * dT
				if sparks[i].life <= 0 {
					unordered_remove(&sparks, i)
				}
			}
			// The player's red wash runs on real time, not world time: it should
			// still fade during a hitstop rather than freezing the feedback.
			hurt_flash = max(hurt_flash - raylib.GetFrameTime(), 0)
			// Floating damage numbers drift up and fade.
			for i := len(damage_numbers) - 1; i >= 0; i -= 1 {
				damage_numbers[i].life -= dT
				damage_numbers[i].pos += damage_numbers[i].vel * dT
				damage_numbers[i].vel *= 1 - 3 * dT
				if damage_numbers[i].life <= 0 {
					unordered_remove(&damage_numbers, i)
				}
			}
			// Blood droplets fly out, fall under gravity and fade.
			for i := len(blood) - 1; i >= 0; i -= 1 {
				blood[i].life -= dT
				blood[i].pos += blood[i].vel * dT
				blood[i].vel.y += BLOOD_GRAVITY * dT
				blood[i].vel *= 1 - 5 * dT
				if blood[i].life <= 0 {
					unordered_remove(&blood, i)
				}
			}
			if dir != raylib.Vector2(0) && dash_timer <= 0 {
				tutorial_note(.MOVE)
				last_dir = dir
				position += raylib.Vector2Normalize(dir) * character_move_speed() * dT
			}
			if dash_cooldown > 0 {
				dash_cooldown -= dT
			}

			// Active weapon: fetch its runtime state + stat block for this frame.
			weapon_tick(&primary, dT)
			weapon_tick(&secondary, dT)
			w := active_weapon()
			ws := active_stats()
			// The signature slot has no weapon struct, so its swings are gated by
			// the shared melee cooldown instead of a per-slot timer.
			fire_ready := w.cooldown <= 0
			if active_slot == SLOT_SIGNATURE {
				fire_ready = melee_cooldown <= 0
			}
			// Mouse controls (MOUSE scheme): LMB fires and RMB drives the E
			// action (kick / RR's guard / NEEDLE). SPACE/E always work too; a
			// click on an upgrade card is left to the card handler below.
			fire_held := world_key_down(raylib.KeyboardKey.SPACE)
			kick_held := world_key_down(raylib.KeyboardKey.E)
			kick_pressed := world_key_pressed(raylib.KeyboardKey.E)
			if settings.control_scheme == .MOUSE && !console_open {
				fire_held = fire_held || (raylib.IsMouseButtonDown(.LEFT) && len(cards) == 0)
				kick_held = kick_held || raylib.IsMouseButtonDown(.RIGHT)
				kick_pressed = kick_pressed || raylib.IsMouseButtonPressed(.RIGHT)
			}
			if fire_held && fire_ready {
				if active_slot == SLOT_SIGNATURE {
					tutorial_note(.FIRE)
					tutorial_note(.SIGNATURE)
					// Combo window held this far: the chain reached its third
					// link (Bud's ELBOW) instead of resetting to the first.
					if combo_index >= 2 {
						tutorial_note(.COMBO)
					}
					// Signature combo: every press throws the next strike of the
					// character's own melee chain. The index about to land says
					// whether it is the chain's finisher, which RR's Second Wind
					// keys its blade wind off.
					is_finisher := combo_index == SIGNATURE_COUNT[character] - 1
					swing := unarmed_stats()
					melee_cooldown = swing_cooldown(swing)
					play(sounds.kick, swing.sound_pitch)
					melee_swing(swing, aim_dir, is_finisher)
				} else if ws.class == .MELEE {
					// Melee weapon in the active slot: swing it (no ammo).
					tutorial_note(.FIRE)
					if active_slot == SLOT_PRIMARY {
						play(sounds.primary[gun], ws.sound_pitch)
					} else {
						play(sounds.secondary[secondary_kind], ws.sound_pitch)
					}
					melee_swing(ws, aim_dir)
					w.cooldown = swing_cooldown(ws)
				} else if w.mag > 0 && w.reload <= 0 {
					center := position + size * 0.5 - ws.bullet_size * 0.5
					shots := ws.projectiles + bonus_projectiles
					// The shot pattern comes from the weapon, but ATTACK/PROJECTILE/
					// PIERCE/PRECISION cards feed in on top, so both slots benefit.
					spread := max(ws.min_spread, ws.spread - spread_cut)
					// Navy's Take Aim: standing still gives complete accuracy.
					if character == .NAVY && !moving {
						spread = 0
					}
					// RR's Adaptation can reinforce precision instead.
					if character == .RR && rr_adaptation == .PRECISION {
						spread *= 1 - min(RR_ADAPT_PRECISION * rr_adapt_scale(), 1)
					}
					// Bud's Unhappy passive halves his accuracy with any gun.
					unhappy := bud_unhappy()
					if unhappy {
						spread = max(spread * BUD_UNHAPPY_SPREAD_MULT, BUD_UNHAPPY_MIN_SPREAD)
					}
					// Fan shots across the gun's arc. Guns with no base spread (e.g. the
					// sniper) get an even default fan if cards add extra projectiles.
					arc := spread
					if shots > 1 && ws.spread <= 0 {
						arc = 0.12 * f32(shots - 1)
					}
					note_attack()
					// GF mode bends the shot onto a nearby enemy that's inside the
					// aim cone, so mouse aim is forgiving without feeling magnetic.
					fire_dir := aim_dir
					if assists_on() {
						fire_dir = gf_assist_aim(aim_dir)
					}
					for k in 0 ..< shots {
						offset: f32 = 0
						if shots > 1 {
							offset = (f32(k) / f32(shots - 1) - 0.5) * arc
						}
						// Random inaccuracy on top of the fan so single-shot guns like
						// the SMG/MINIGUN spray a little. Precision cards shrink this.
						offset += rand.float32_range(-spread, spread) * 0.5
						shot_dir := raylib.Vector2Rotate(fire_dir, offset)
						damage := ws.damage + bonus_damage
						if unhappy {
							damage *= BUD_UNHAPPY_DAMAGE_MULT
						}
						if character == .RR && rr_adaptation == .OFFENSE {
							damage *= 1 + RR_ADAPT_OFFENSE * rr_adapt_scale()
						}
						append(
							&bullets,
							bullet {
								position = center,
								size = ws.bullet_size,
								velocity = shot_dir * ws.bullet_speed,
								damage = damage,
								pierce = ws.pierce + bonus_pierce,
								effects = attack_effects,
							},
						)
					}
					w.cooldown = ws.cooldown
					w.mag -= 1
					muzzle_flash = MUZZLE_FLASH_TIME
					tutorial_note(.FIRE)
					if active_slot == SLOT_PRIMARY {
						play(sounds.primary[gun], rand.float32_range(0.94, 1.06))
					} else {
						play(sounds.secondary[secondary_kind], rand.float32_range(0.94, 1.06))
					}
				}
			}
			// Manual reload: R (only if you have something to load). The signature
			// slot carries nothing to load, so reloads pause while it is in hand.
			if active_slot != SLOT_SIGNATURE {
				if world_key_pressed(raylib.KeyboardKey.R) &&
				   w.reload <= 0 &&
				   w.mag < w.mag_cap &&
				   w.ammo > 0 {
					w.reload = reload_time
					play(sounds.reload)
					tutorial_note(.RELOAD)
				}
				// Auto-reload when the mag runs dry.
				if w.mag <= 0 && w.ammo > 0 && w.reload <= 0 {
					w.reload = reload_time
					play(sounds.reload)
					tutorial_note(.RELOAD)
				}
			}
			// Character signature move (E): each character has their own weapon
			// here -- claws, blade, bayonet, or Bud's Fists combo. Every one of
			// them carries the player's on-hit status effects.
			if melee_cooldown > 0 {
				melee_cooldown -= dT
			}
			if rr_blink_cd > 0 {
				rr_blink_cd -= dT
			}
			if block_flash > 0 {
				block_flash -= dT
			}
			if melee_flash > 0 {
				melee_flash -= dT
			}
			if muzzle_flash > 0 {
				muzzle_flash -= dT
			}
			// Kick (E): the universal unarmed strike, on top of whatever the
			// active slot does. Two of RR's blade forms replace it outright,
			// because neither defense nor precision would otherwise reach his
			// melee at all. Re-lit every frame so the guard drops the instant E
			// is let go.
			rr_block = false
			if character == .RR && rr_adaptation == .RESILIENCE {
				// BULWARK: hold E to guard the front. Damage arriving from ahead
				// is cancelled outright, but he is slowed while it is up. A hit
				// actually cancelled notes the tutorial's BLOCK lesson (see
				// apply_player_damage), so merely holding the guard isn't enough.
				rr_block = kick_held
			} else if character == .RR && rr_adaptation == .PRECISION {
				// NEEDLE: a short blink instead of a kick, rewarding the pick
				// with mobility.
				if kick_pressed && rr_blink_cd <= 0 {
					rr_blink_cd = RR_NEEDLE_BLINK_CD
					play(sounds.dash)
					tutorial_note(.NEEDLE)
					// Blink the way he is already moving, or along the aim if he
					// is standing still, so it repositions rather than aims.
					bd := last_dir
					if raylib.Vector2Length(bd) < 0.01 {
						bd = aim_dir
					}
					position += raylib.Vector2Normalize(bd) * RR_NEEDLE_BLINK_DIST
					resolve_obstacles(&position, size)
					inv_timer = RR_NEEDLE_BLINK_INV
					append(&trail, trail_point{position, 0.3})
				}
			} else if kick_pressed && melee_cooldown <= 0 {
				tutorial_note(.KICK)
				melee_cooldown = swing_cooldown(KICK)
				play(sounds.kick, KICK.sound_pitch)
				melee_swing(KICK, aim_dir)
			}
			if world_key_pressed(raylib.KeyboardKey.LEFT_SHIFT) && dash_cooldown <= 0 {
				tutorial_note(.DASH)
				play(sounds.dash)
				// Synergy: a Tracer SLIDE instantly refills Traceur's Heart, so
				// sliding straight into a fight keeps her at top speed.
				if character == .TRACER && dash_kind == .SLIDE {
					traceur_charge = 1
				}
				// Synergy: Navy's BLINK finishes his reload so he lands topped up.
				if character == .NAVY && dash_kind == .BLINK {
					instant_reload(active_weapon())
				}
				// Synergy: RR's BURST grants a "Second Wind" that amplifies his
				// current Adaptation for a moment.
				if character == .RR && dash_kind == .BURST {
					rr_surge = RR_SURGE_TIME
				}
				if dash_blink {
					position += raylib.Vector2Normalize(last_dir) * dash_distance
					inv_timer = 0.20
					append(&trail, trail_point{position, 0.3})
				} else {
					dash_timer = DASH_DURATION
					inv_timer = DASH_DURATION
				}
				dash_cooldown = dash_cooldown_max
			}
			// Keep the player out of walls/props after all this frame's moves.
			resolve_obstacles(&position, size)
			// Never let a dash/lunge leave the arena; resolve_obstacles alone can
			// eject an entity through the outer wall's far edge.
			clamp_to_arena(&position, size)
			if world_key_pressed(raylib.KeyboardKey.F) {
				clear(&cards)
				spawn_cards(&cards, card_choices)
			}
			if world_key_pressed(raylib.KeyboardKey.G) && !gf_ctrl {
				pop(&cards)
			}
			if world_key_pressed(raylib.KeyboardKey.I) && !debug_mode {
				new_wave(&enemies, wave)
				wave += 1
			}
			if !console_open && raylib.IsMouseButtonPressed(raylib.MouseButton.LEFT) {
				for i := len(cards) - 1; i >= 0; i -= 1 {
					card_rect := raylib.Rectangle {
						cards[i].position.x,
						cards[i].position.y,
						cards[i].size.x,
						cards[i].size.y,
					}
					if raylib.CheckCollisionRecs(mouse, card_rect) {
						picked := cards[i].name
						apply_upgrade(picked)
						play(sounds.card)
						clear(&cards)
						if tutorial_mode {
							// The tutorial dealt these cards to teach the
							// mechanic; picking one is the lesson, not a
							// genuine between-wave reward. The helper also
							// remembers the element for the status follow-up.
							tutorial_note_card(picked)
						} else {
							if !debug_mode {
								new_wave(&enemies, wave)
							}
							wave += 1
						}
						break
					}
				}
			}

			for i := len(bullets) - 1; i >= 0; i -= 1 {
				bullets[i].position += bullets[i].velocity * dT
				p := bullets[i].position
				s := bullets[i].size
				if raylib.Vector2Distance(p, position) > 1600 {
					unordered_remove(&bullets, i)
					continue
				}
				// Solid terrain stops the shot.
				if bullet_blocked_by_terrain({p.x, p.y, s.x, s.y}) {
					unordered_remove(&bullets, i)
					continue
				}
				// Barrels soak the hit and take damage.
				hit_barrel := false
				for k := len(barrels) - 1; k >= 0; k -= 1 {
					if raylib.CheckCollisionRecs(
						{p.x, p.y, s.x, s.y},
						{barrels[k].pos.x, barrels[k].pos.y, barrels[k].size.x, barrels[k].size.y},
					) {
						barrels[k].hp -= bullets[i].damage
						hit_barrel = true
						break
					}
				}
				if hit_barrel {
					unordered_remove(&bullets, i)
					continue
				}
				for j := len(enemies) - 1; j >= 0; j -= 1 {
					e := &enemies[j]
					// A burrowed boss is underground: shots fly over the mound.
					if e.kind == .BOSS && e.boss_hidden {
						continue
					}
					if bullet_hit_before(&bullets[i], e.id) {
						continue
					}
					if raylib.CheckCollisionRecs(
						{p.x, p.y, s.x, s.y},
						{e.position.x, e.position.y, e.size.x, e.size.y},
					) {
						play_enemy_hit(
							apply_enemy_damage(e, bullets[i].damage, -bullets[i].velocity),
						)
						// Shots carry the player's on-hit status effects too.
						apply_status(e, bullets[i].effects)
						bullet_register_hit(&bullets[i], e.id)
						if e.hp <= 0 {
							spawn_kill_rewards(e.position, e.elite, e.color, e.kind)
							unordered_remove(&enemies, j)
						}
						// Spend a pierce charge, or die on this hit.
						if bullets[i].pierce > 0 {
							bullets[i].pierce -= 1
						} else {
							unordered_remove(&bullets, i)
							break
						}
					}
				}
			}

			// Pop any barrels that took enough damage this frame.
			for i := len(barrels) - 1; i >= 0; i -= 1 {
				if barrels[i].hp <= 0 {
					blast := barrels[i].pos + barrels[i].size * 0.5
					unordered_remove(&barrels, i)
					explode_at(blast)
				}
			}

			// Enemy AI: steer, push off terrain, then separate from each other.
			for i in 0 ..< len(enemies) {
				e := &enemies[i]
				update_enemy(e, dT)
				// Phantom chargers pass straight through terrain mid-dash.
				if !(e.elite && e.kind == .CHARGER && e.state == .CHARGE) {
					resolve_obstacles(&e.position, e.size)
				}
				// A dash, lunge, or knockback can carry a foe deep into (or clean
				// through) a perimeter wall; resolve_obstacles then ejects it out
				// the near edge or misses it entirely. Clip everyone back in.
				clamp_to_arena(&e.position, e.size)
			}
			update_elite_abilities(&enemies, dT)
			separate_enemies()
			// Tick status effects (burn/poison damage, freeze/shock timers) and
			// clear anyone killed by a damage-over-time.
			update_status(&enemies, dT)
			// Tracer's PHASE marks decay if she leaves a target alone.
			tick_phase_marks(dT)
			// Spawn any halves queued by splitters that died this frame. Deferred
			// so the enemy array isn't mutated while the combat loops run.
			process_splits()

			if inv_timer > 0 {
				inv_timer -= dT
			}
			update_player_status(dT)
			player_rect := raylib.Rectangle{position.x, position.y, size.x, size.y}
			for i := len(enemies) - 1; i >= 0; i -= 1 {
				// A burrowed boss is underground and can't body-check you.
				if enemies[i].kind == .BOSS && enemies[i].boss_hidden {
					continue
				}
				enemy_rect := raylib.Rectangle {
					enemies[i].position.x,
					enemies[i].position.y,
					enemies[i].size.x,
					enemies[i].size.y,
				}
				if raylib.CheckCollisionRecs(player_rect, enemy_rect) {
					if inv_timer <= 0 {
						apply_player_damage(
							enemies[i].damage,
							enemies[i].position + enemies[i].size * 0.5,
						)
						inv_timer = 0.5
						if !tutorial_mode {
							play(sounds.player_hurt)
						}
					}
					if health <= 0 {
						game_over()
					}
				}
			}

			// Hostile projectiles (ranged enemies).
			for i := len(enemy_bullets) - 1; i >= 0; i -= 1 {
				b := &enemy_bullets[i]
				b.position += b.velocity * dT
				if b.boomerang {
					// Fly out to max_range, turn around, then leave play.
					b.traveled += raylib.Vector2Length(b.velocity) * dT
					if !b.returning && b.traveled >= b.max_range {
						b.returning = true
						b.velocity = -b.velocity
					} else if b.returning && b.traveled >= b.max_range * 2 {
						unordered_remove(&enemy_bullets, i)
						continue
					}
				}
				bp := b.position
				bs := b.size
				if (!b.boomerang && raylib.Vector2Distance(bp, position) > 1600) ||
				   bullet_blocked_by_terrain({bp.x, bp.y, bs.x, bs.y}) {
					unordered_remove(&enemy_bullets, i)
					continue
				}
				if raylib.CheckCollisionRecs({bp.x, bp.y, bs.x, bs.y}, player_rect) {
					if inv_timer <= 0 {
						apply_player_damage(b.damage, b.position)
						apply_player_effects(b.effects)
						inv_timer = 0.5
						if !tutorial_mode {
							play(sounds.player_hurt)
						}
					}
					unordered_remove(&enemy_bullets, i)
				}
			}

			if health <= 0 {
				game_over()
			}

			for i := len(drops) - 1; i >= 0; i -= 1 {
				drops[i].life -= dT
				if drops[i].life <= 0 {
					unordered_remove(&drops, i)
					continue
				}
				drop_rect := raylib.Rectangle {
					drops[i].position.x,
					drops[i].position.y,
					drops[i].size.x,
					drops[i].size.y,
				}
				if raylib.CheckCollisionRecs(player_rect, drop_rect) {
					switch drops[i].kind {
					case .HEALTH:
						health = min(max_health, health + drops[i].amount)
						play(sounds.health)
					case .AMMO:
						primary.ammo = min(primary.ammo_cap, primary.ammo + i32(drops[i].amount))
						secondary.ammo = min(
							secondary.ammo_cap,
							secondary.ammo + i32(drops[i].amount),
						)
						play(sounds.ammo)
					case .CURRENCY:
						currency += i32(drops[i].amount)
						run_coins_earned += i32(drops[i].amount)
						play(sounds.coin, rand.float32_range(0.97, 1.03))
					case .RELIC_CHEST:
						// Open the chest: draw a relic and pause for accept/discard.
						if !tutorial_mode {
							if kind, ok := draw_relic(); ok {
								pending_relic = kind
								relic_pick_open = true
							} else {
								currency += 100 // everything owned: pay out instead
							}
							play(sounds.shop_buy)
						}
					}
					if drops[i].kind == .RELIC_CHEST {
						// The chest is consumed even if the draw was declined.
						unordered_remove(&drops, i)
						continue
					}
					tutorial_note(.PICKUP)
					unordered_remove(&drops, i)
				}
			}

			if !tutorial_mode && !console_open && len(enemies) == 0 && len(cards) == 0 {
				// Between waves: checkpoint the run so it can be continued later.
				save_run()
				// Every 5th cleared wave opens the shop instead of a card pick.
				// (`wave` is the *next* wave, so wave-1 is the one just cleared.)
				if wave > 1 && (wave - 1) % 5 == 0 {
					shop_selected = 0
					build_shop()
					state = .SHOP
				} else if !debug_mode || wave == 1 {
					spawn_cards(&cards, card_choices)
				}
				// In debug (not shop wave), skip the card reward after wave 1.
			}
			// Mission Control: a selected "level" checks its objective every frame
			// and clears itself (paying the reward) the moment it's met. No-op on a
			// normal endless run.
			mission_check_complete()
			// Tutorials: respawn a fresh dummy when the field is clear, and
			// advance the step script.
			if tutorial_mode {
				if len(enemies) == 0 {
					spawn_tutorial_dummies()
				}
				tutorial_update(dT)
				// Leaving the tutorial drops straight back to the menu.
				if raylib.IsKeyPressed(raylib.KeyboardKey.ESCAPE) {
					tutorial_done()
				}
				if !tutorial_mode {
					continue
				}
			}
			// ESC opens the in-game settings panel (a normal run has nothing to
			// "leave", so pausing is the useful back action). The tutorial above
			// handles its own ESC-to-exit.

			raylib.BeginTextureMode(target)
			raylib.ClearBackground(raylib.BLACK)
			// Offset the camera by the (decaying) shake just for drawing.
			camera.offset = {
				400 + rand.float32_range(-shake, shake),
				300 + rand.float32_range(-shake, shake),
			}
			raylib.BeginMode2D(camera)
			// Floor (checkerboard over the arena, tinted by the chosen arena).
			pal := ARENAS[arena]
			trunk := raylib.Color{pal.cover.r / 3, pal.cover.g / 3, pal.cover.b / 3, 255}
			tile: f32 = 40
			for ty := f32(0); ty < ARENA_H; ty += tile {
				for tx := f32(0); tx < ARENA_W; tx += tile {
					dark := (int(tx / tile) + int(ty / tile)) % 2 == 0
					tint := dark ? pal.floor_dark : pal.floor_light
					raylib.DrawRectangleV({tx, ty}, {tile, tile}, tint)
				}
			}
			// Decorative floor scatter, drawn under walls and cover.
			for m in floor_marks {
				draw_floor_mark(m, pal.decor_col)
			}
			// Walls.
			for w in walls {
				raylib.DrawRectangleRec(w, pal.wall)
			}
			// Static cover (trees, pines, boulders, crates) -- drawn by kind so
			// each arena reads as a place instead of a pile of identical circles.
			for t in props {
				c := t.pos + t.size * 0.5
				switch t.kind {
				case .TREE:
					raylib.DrawRectangleV({c.x - 6, c.y - 2}, {12, 20}, trunk)
					raylib.DrawCircleV(c, 24, pal.cover)
					raylib.DrawCircleV({c.x - 8, c.y - 8}, 14, pal.cover_top)
				case .PINE:
					// Stacked triangles read as an evergreen from the top-down view.
					raylib.DrawRectangleV({c.x - 5, c.y + 4}, {10, 18}, trunk)
					raylib.DrawTriangle(
						{c.x, c.y - 26},
						{c.x - 20, c.y + 10},
						{c.x + 20, c.y + 10},
						pal.cover,
					)
					raylib.DrawTriangle(
						{c.x, c.y - 12},
						{c.x - 14, c.y + 16},
						{c.x + 14, c.y + 16},
						pal.cover_top,
					)
				case .ROCK:
					raylib.DrawCircleV(c, 23, pal.cover)
					raylib.DrawCircleV({c.x - 7, c.y - 6}, 12, pal.cover_top)
					raylib.DrawCircleV({c.x + 9, c.y + 8}, 9, pal.cover)
				case .CRATE:
					raylib.DrawRectangleV(t.pos, t.size, pal.cover)
					raylib.DrawRectangleLinesEx(
						{t.pos.x, t.pos.y, t.size.x, t.size.y},
						2,
						pal.cover_top,
					)
					// Cross-brace so a crate doesn't read as a plain box.
					raylib.DrawLineEx(t.pos, t.pos + t.size, 2, pal.cover_top)
					raylib.DrawLineEx(
						{t.pos.x + t.size.x, t.pos.y},
						{t.pos.x, t.pos.y + t.size.y},
						2,
						pal.cover_top,
					)
				}
			}
			// Barrels.
			for b in barrels {
				raylib.DrawRectangleV(b.pos, b.size, raylib.MAROON)
				raylib.DrawRectangleLinesEx(
					{b.pos.x, b.pos.y, b.size.x, b.size.y},
					2,
					raylib.ORANGE,
				)
			}
			// Dash trail + drops.
			for t in trail {
				a := u8(80 * (t.life / 0.3))
				raylib.DrawRectangleV(t.pos, size, raylib.Color{255, 0, 0, a})
			}
			for d in drops {
				alpha: u8 = 255
				if d.life < 3 {
					alpha = u8(255 * (d.life / 3))
				}
				switch d.kind {
				case .HEALTH:
					raylib.DrawRectangleV(d.position, d.size, raylib.Color{0, 255, 90, alpha})
				case .AMMO:
					raylib.DrawRectangleV(d.position, d.size, raylib.Color{110, 190, 255, alpha})
				case .CURRENCY:
					raylib.DrawRectangleV(d.position, d.size, raylib.Color{255, 205, 60, alpha})
				case .RELIC_CHEST:
					// A gilded chest with a pulsing glow so it reads as the
					// wave's reward.
					c := d.position + d.size * 0.5
					pulse: f32 = 0.5 + 0.5 * f32(math.sin(raylib.GetTime() * 4.0))
					raylib.DrawCircleV(
						c,
						d.size.x * (0.9 + 0.3 * pulse),
						raylib.Color{255, 200, 60, u8(50 * alpha / 255)},
					)
					raylib.DrawRectangleV(d.position, d.size, raylib.BROWN)
					raylib.DrawRectangleLinesEx(
						{d.position.x, d.position.y, d.size.x, d.size.y},
						2,
						raylib.GOLD,
					)
					// Lid line + lock.
					mid := d.position.y + d.size.y * 0.4
					raylib.DrawLineEx(
						{d.position.x, mid},
						{d.position.x + d.size.x, mid},
						2,
						raylib.GOLD,
					)
					raylib.DrawRectangleV(c - {4, 2}, {8, 8}, raylib.GOLD)
				}
			}
			// Attack telegraphs, drawn under the enemies so the danger zones read as
			// ground effects rather than UI. Every boss/sniper wind-up paints its
			// tell here, which is what makes those attacks fair to dodge.
			draw_telegraphs()
			// Enemies (chargers flash a white box while winding up).
			for e in enemies {
				// Crystalized elites flash white for a beat after acting.
				body := e.color
				if e.flash > 0 {
					body = raylib.WHITE
				}
				// Phantom chargers go translucent while passing through terrain.
				if e.elite && e.kind == .CHARGER && e.state == .CHARGE {
					body.a = 110
				}
				// A burrowed DUSTMAW draws only its ground mound (draw_boss_body).
				if !(e.kind == .BOSS && e.boss_hidden) {
					raylib.DrawRectangleV(e.position, e.size, body)
				}
				// Per-kind decoration so the new archetypes and the boss read as
				// distinct silhouettes at a glance.
				{
					ec := e.position + e.size * 0.5
					er := max(e.size.x, e.size.y) * 0.5
					#partial switch e.kind {
					case .SPLITTER:
						// A seam down the middle: it looks ready to come apart.
						raylib.DrawLineEx(
							{e.position.x + 3, ec.y},
							{e.position.x + e.size.x - 3, ec.y},
							2,
							raylib.WHITE,
						)
					case .ORBITER:
						// A ring marking its orbit around you.
						raylib.DrawCircleLines(
							i32(ec.x),
							i32(ec.y),
							er + 4,
							raylib.Color{body.r, body.g, body.b, 140},
						)
					case .SNIPER:
						// A long barrel + scope glint.
						raylib.DrawLineEx(ec, ec + e.muzzle_dir * (er + 8), 2, raylib.DARKGRAY)
						raylib.DrawCircleV(ec, 4, raylib.WHITE)
					case .BOSS:
						draw_boss_body(e)
					}
				}
				// Muzzle flash at the barrel this enemy last fired from, so
				// incoming fire is traceable to its source.
				if e.muzzle > 0 {
					ec := e.position + e.size * 0.5
					er := max(e.size.x, e.size.y) * 0.5
					mp := ec + e.muzzle_dir * (er + 3)
					mf := clamp(e.muzzle / ENEMY_MUZZLE_FLASH_TIME, 0, 1)
					raylib.DrawCircleV(mp, 8 * mf, raylib.Color{255, 170, 60, u8(120 * mf)})
					raylib.DrawCircleV(mp, 4.5 * mf, raylib.Color{255, 245, 200, u8(230 * mf)})
				}
				// Tracer's PHASE marks: a cross slashed across the body. The
				// first mark is one diagonal, the second completes the X, and
				// extra marks thicken it -- so a charged REND reads at a glance.
				if e.phase_marks > 0 {
					mark_c := e.position + e.size * 0.5
					mark_r := max(e.size.x, e.size.y) * 0.5 + 2
					mark_n := min(e.phase_marks, PHASE_MARK_MAX)
					mark_thick := 1.5 + f32(mark_n) * 0.7
					mark_col := raylib.Color{150, 255, 160, u8(180 + 15 * mark_n)}
					// First mark: top-right -> bottom-left.
					raylib.DrawLineEx(
						mark_c + {mark_r, -mark_r},
						mark_c + {-mark_r, mark_r},
						mark_thick,
						mark_col,
					)
					// Second mark completes the cross: top-left -> bottom-right.
					if mark_n >= 2 {
						raylib.DrawLineEx(
							mark_c + {-mark_r, -mark_r},
							mark_c + {mark_r, mark_r},
							mark_thick,
							mark_col,
						)
					}
				}
				if e.elite {
					// Bulwark crystal plates: one shard per intact side, drawn
					// where it sits so the weak directions are readable.
					if e.kind == .TANK {
						center := e.position + e.size * 0.5
						rad := max(e.size.x, e.size.y) * 0.5
						for k in 0 ..< ELITE_TANK_PLATES {
							if !e.plate_live[k] {
								continue
							}
							raylib.DrawPoly(center + e.plate_dir[k] * rad, 4, 5, 0, raylib.SKYBLUE)
						}
					}
					// Crystalized: a floating shard marks it, plus a health bar.
					draw_crystal_shard(
						{e.position.x + e.size.x * 0.5, e.position.y - 18},
						7,
						f32(e.id),
					)
					if e.max_hp > 0 {
						bx := i32(e.position.x)
						by := i32(e.position.y) - 8
						w := i32(e.size.x)
						filled := i32(e.size.x * (e.hp / e.max_hp))
						raylib.DrawRectangle(bx, by, w, 4, raylib.RED)
						raylib.DrawRectangle(bx, by, filled, 4, raylib.GREEN)
					}
				}
				if e.kind == .CHARGER && e.state == .WINDUP {
					raylib.DrawRectangleLinesEx(
						{e.position.x - 4, e.position.y - 4, e.size.x + 8, e.size.y + 8},
						3,
						raylib.WHITE,
					)
				}
				// Practice DPS dummy: an always-on health bar with a damage-per-
				// second bar under it that tracks how hard the player is hitting.
				if e.kind == .DUMMY_DPS && e.max_hp > 0 {
					bx := i32(e.position.x)
					bw := i32(e.size.x)
					by := i32(e.position.y) - 26
					raylib.DrawRectangle(bx, by, bw, 5, raylib.MAROON)
					hp_w := i32(e.size.x * clamp(e.hp / e.max_hp, 0, 1))
					raylib.DrawRectangle(bx, by, hp_w, 5, raylib.GREEN)
					raylib.DrawRectangle(bx, by + 6, bw, 4, raylib.Color{40, 40, 40, 255})
					dps_w := i32(e.size.x * clamp(e.dps_value / DUMMY_DPS_BAR_MAX, 0, 1))
					raylib.DrawRectangle(bx, by + 6, dps_w, 4, raylib.GOLD)
				}
				// Status markers: one pip per active effect, above the body.
				if e.effects != {} {
					pip_x := e.position.x
					for eff in Status_Effect {
						if eff not_in e.effects {
							continue
						}
						raylib.DrawRectangleV(
							{pip_x, e.position.y - 12},
							{6, 6},
							status_color(eff),
						)
						pip_x += 8
					}
				}
			}
			// Projectiles. A blade wind reads as a crescent rather than a box.
			for b in bullets {
				if b.wind {
					c := b.position + b.size * 0.5
					a := math.atan2_f32(b.velocity.y, b.velocity.x) * raylib.RAD2DEG
					r := b.size.x * 0.7
					raylib.DrawCircleSector(
						c,
						r,
						a - 70,
						a + 70,
						12,
						RR_EDGE_WIND[rr_adaptation].col,
					)
					raylib.DrawCircleSectorLines(c, r, a - 70, a + 70, 12, raylib.WHITE)
				} else {
					// Tracer streak plus a soft glow, so shots read as fast lines
					// rather than floating rectangles.
					bc := b.position + b.size * 0.5
					sp := raylib.Vector2Length(b.velocity)
					if sp > 1 {
						dir := b.velocity / sp
						// Tail length scales with speed, capped so a slow heavy
						// round doesn't smear across the arena.
						raylib.DrawLineEx(
							bc - dir * min(sp * 0.02, 20),
							bc - dir * 2,
							b.size.x * 0.9,
							raylib.Color{255, 240, 150, 120},
						)
					}
					raylib.DrawCircleV(bc, b.size.x * 0.45, raylib.Color{255, 255, 210, 110})
					raylib.DrawRectangleV(b.position, b.size, raylib.YELLOW)
				}
			}
			for b in enemy_bullets {
				raylib.DrawRectangleV(b.position, b.size, raylib.MAGENTA)
			}
			// Player (shape + darker outline come from the chosen character).
			draw_player()
			draw_melee_flash()
			draw_muzzle_volley_flash()
			// Expanding blast rings (orange for barrels, green for REND detonations).
			for x in explosions {
				f := x.life / x.max_life
				c := x.color
				c.a = u8(f32(c.a) * f)
				raylib.DrawCircleV(x.pos, x.radius * (1 - f), c)
			}
			// Impact sparks: additive-looking flecks that shrink as they die.
			for s in sparks {
				f := clamp(s.life / s.max_life, 0, 1)
				c := s.color
				c.a = u8(f32(c.a) * f)
				raylib.DrawCircleV(s.pos, s.size * (0.4 + 0.6 * f), c)
			}
			// Blood spray, fading as it dries.
			for b in blood {
				f := clamp(b.life / b.max_life, 0, 1)
				c := b.color
				c.a = u8(f32(c.a) * f)
				raylib.DrawCircleV(b.pos, b.size * (0.6 + 0.4 * f), c)
			}
			// Floating damage numbers, drawn last so they read over the action.
			for n in damage_numbers {
				f := clamp(n.life / DAMAGE_NUMBER_TIME, 0, 1)
				c := n.color
				c.a = u8(255 * f)
				label := raylib.TextFormat("%i", i32(n.value + 0.5))
				raylib.DrawText(label, i32(n.pos.x), i32(n.pos.y), 14, c)
			}
			raylib.EndMode2D()
			for &c in cards {
				card_rect := raylib.Rectangle{c.position.x, c.position.y, c.size.x, c.size.y}
				c.hover = raylib.CheckCollisionRecs(mouse, card_rect)
				color := c.hover ? raylib.VIOLET : raylib.DARKPURPLE
				raylib.DrawRectangleV(c.position, c.size, color)
				x := i32(c.position.x)
				y := i32(c.position.y)
				w := i32(c.size.x)
				// Title, auto-shrunk and centred to fit the card.
				title_fs: i32 = 22
				for title_fs > 6 && raylib.MeasureText(c.name, title_fs) > w - 16 {
					title_fs -= 1
				}
				title_w := raylib.MeasureText(c.name, title_fs)
				raylib.DrawText(c.name, x + (w - title_w) / 2, y + 16, title_fs, raylib.BLACK)
				// Effect line under it, also shrunk to fit.
				desc_fs: i32 = 13
				for desc_fs > 6 && raylib.MeasureText(c.description, desc_fs) > w - 12 {
					desc_fs -= 1
				}
				desc_w := raylib.MeasureText(c.description, desc_fs)
				raylib.DrawText(c.description, x + (w - desc_w) / 2, y + 78, desc_fs, raylib.BLACK)
				if c.hover {
					raylib.DrawRectangleLinesEx(card_rect, 2, raylib.WHITE)
				}
			}
			raylib.DrawRectangleV(mouse_pos, {5, 5}, raylib.GREEN)
			raylib.DrawRectangle(10, 10, 200, 20, raylib.RED)
			raylib.DrawRectangle(10, 10, i32(200 * health / max_health), 20, raylib.GREEN)
			raylib.DrawRectangleLines(10, 10, 200, 20, raylib.WHITE)
			if player_poison > 0 {
				raylib.DrawText("POISONED", 216, 12, 16, raylib.Color{120, 230, 120, 255})
			}
			if endless_mode {
				draw_centered(raylib.TextFormat("WAVE %i  -  ENDLESS", int(wave)), 6, 24, raylib.GOLD)
			} else {
				draw_centered(
					raylib.TextFormat(
						"WAVE %i / %i",
						int(min(wave, ARENAS[arena].waves)),
						int(ARENAS[arena].waves),
					),
					6,
					24,
					raylib.LIGHTGRAY,
				)
			}
			// Big centred callout: the arena's boss name as it arrives, then ARENA
			// CLEARED when it dies. Fades over its last second.
			if banner_timer > 0 {
				ba := u8(clamp(banner_timer, 0, 1) * 255)
				draw_centered(
					banner_text,
					120,
					34,
					raylib.Color{banner_col.r, banner_col.g, banner_col.b, ba},
				)
			}
			// Boss encounter bar: a wide bar across the top whenever the arena's
			// boss is alive, so the fight reads as a set-piece (and shows the flip).
			for e in enemies {
				if e.kind != .BOSS {
					continue
				}
				bw: i32 = 420
				bx: i32 = (800 - bw) / 2
				by: i32 = 44
				raylib.DrawRectangle(bx, by, bw, 16, raylib.Color{40, 12, 12, 220})
				frac := clamp(e.hp / max(e.max_hp, 1), 0, 1)
				bar_col := raylib.RED
				if e.boss_phase >= 2 {
					bar_col = raylib.ORANGE
				}
				raylib.DrawRectangle(bx, by, i32(f32(bw) * frac), 16, bar_col)
				raylib.DrawRectangleLines(bx, by, bw, 16, raylib.WHITE)
				draw_centered(ARENA_BOSSES[arena].name, by + 20, 16, raylib.LIGHTGRAY)
				if e.boss_hidden {
					draw_centered(cstring("UNDERGROUND"), by + 38, 14, raylib.Color{196, 164, 110, 255})
				} else if e.boss_phase >= 2 {
					draw_centered(cstring("ENRAGED"), by + 38, 14, raylib.ORANGE)
				}
			}
			// Active weapon + ammo, then the two slots you can Q to. The signature
			// slot has no ammo: it shows its name and MELEE.
			if active_slot == SLOT_SIGNATURE || active_stats().class == .MELEE {
				raylib.DrawText(
					raylib.TextFormat("[%s] MELEE", slot_name(active_slot)),
					560,
					10,
					20,
					raylib.WHITE,
				)
			} else {
				raylib.DrawText(
					raylib.TextFormat(
						"[%s] %i / %i",
						slot_name(active_slot),
						int(w.mag),
						int(w.ammo),
					),
					560,
					10,
					20,
					raylib.WHITE,
				)
			}
			raylib.DrawText(
				raylib.TextFormat(
					"Q: %s  |  %s",
					slot_name((active_slot + 1) % SLOT_COUNT),
					slot_name((active_slot + 2) % SLOT_COUNT),
				),
				560,
				34,
				16,
				raylib.GRAY,
			)
			if w.reload > 0 {
				raylib.DrawText(cstring("RELOADING"), 560, 54, 18, raylib.ORANGE)
			}
			raylib.DrawText(raylib.TextFormat("$ %i", int(currency)), 10, 34, 20, raylib.GOLD)
			// Character/passive/on-hit sidebar is drawn in the left letterbox bar by the
			// present step when there's room; only fall back to the canvas here on
			// 4:3 windows with no pillarbox.
			if view_x < CHAR_PASSIVE_MIN_BAR {
				draw_sidebar_hud(220, 34, 560)
			}
			// Mission Control HUD: the active "level" and live progress toward its
			// objective, plus a completion banner the moment it clears.
			if m := current_mission(); m != nil {
				cur, total := mission_progress()
				obj := cstring("WAVE")
				if m.objective == .KILLS {
					obj = "KILLS"
				} else if m.objective == .ELITES {
					obj = "ELITES"
				}
				obj_col := raylib.SKYBLUE
				if mission_cleared_this_run {
					obj_col = raylib.GREEN
				}
				raylib.DrawText(
					raylib.TextFormat("%s  %s %i/%i", string(m.name), string(obj), cur, total),
					10,
					58,
					15,
					obj_col,
				)
			}
			if mission_banner > 0 {
				m := current_mission()
				if m != nil {
					bk := clamp(mission_banner / 2.5, 0, 1)
					bc := raylib.GOLD
					if mission_cleared_this_run && mission_banner > 1.0 {
						bc = raylib.GREEN
					}
					draw_centered(
						raylib.TextFormat("MISSION COMPLETE  +%i", m.reward),
						170,
						34,
						raylib.Color{bc.r, bc.g, bc.b, u8(255 * bk)},
					)
				}
			}
			// E is the universal kick -- unless one of RR's blade forms replaces
			// it, in which case the HUD names the move you actually get.
			e_label := cstring("E: KICK")
			e_col := raylib.RAYWHITE
			if character == .RR && rr_adaptation == .RESILIENCE {
				e_label = "E: GUARD (HOLD)"
				e_col = raylib.SKYBLUE
			} else if character == .RR && rr_adaptation == .PRECISION {
				e_label = "E: BLINK"
				e_col = raylib.SKYBLUE
			}
			raylib.DrawText(e_label, 560, 74, 16, e_col)
			raylib.DrawText(
				cstring(
					"WASD move   MOUSE aim   SPACE fire   Q slot   E kick   SHIFT dash   R reload   ` console",
				),
				10,
				576,
				15,
				raylib.GRAY,
			)
			if debug_mode {
				raylib.DrawText("DEBUG", 220, 10, 20, raylib.ORANGE)
			}
			// Difficulty is always shown so a run's rules aren't a mystery; the
			// hidden GF toggle is appended when it's bending them further.
			if gf_mode {
				raylib.DrawText(
					raylib.TextFormat("%s + GF MODE", difficulty_name(difficulty)),
					10,
					56,
					15,
					raylib.SKYBLUE,
				)
			} else {
				raylib.DrawText(
					raylib.TextFormat("%s", difficulty_name(difficulty)),
					10,
					56,
					15,
					raylib.GRAY,
				)
			}
			console_draw()
			if tutorial_mode {
				tutorial_draw()
			}
			if settings.show_fps {
				raylib.DrawText(
					raylib.TextFormat("%i FPS", i32(raylib.GetFPS())),
					690,
					576,
					18,
					raylib.LIME,
				)
			}
			raylib.EndTextureMode()

		case .SHOP:
			n := len(shop_items)
			reroll_row := n // the row after the offers
			leave_row := n + 1
			entries := n + 2
			if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
				shop_selected = (shop_selected + 1) % entries
				play(sounds.ui_move)
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
				shop_selected = (shop_selected - 1 + entries) % entries
				play(sounds.ui_move)
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.R) {
				if try_shop_reroll() {
					play(sounds.shop_buy)
				} else {
					play(sounds.ui_move)
				}
			}
			// ESC leaves the shop (back to the run), same as choosing LEAVE.
			if raylib.IsKeyPressed(raylib.KeyboardKey.ESCAPE) {
				leave_shop()
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
				if shop_selected == leave_row {
					leave_shop()
				} else if shop_selected == reroll_row {
					if try_shop_reroll() {
						play(sounds.shop_buy)
					} else {
						play(sounds.ui_move)
					}
				} else if buy_shop_item(shop_selected) {
					play(sounds.shop_buy)
				} else {
					play(sounds.ui_move)
				}
			}
			raylib.BeginTextureMode(target)
			raylib.ClearBackground(raylib.BLACK)
			draw_centered(cstring("SHOP"), 30, 44, raylib.WHITE)
			draw_centered(raylib.TextFormat("COINS: %i", int(currency)), 84, 24, raylib.GOLD)
			if tutorial_mode {
				tutorial_draw_shop()
			}
			clicked := -1
			for it, i in shop_items {
				color := shop_tier_color(it.tier)
				if it.sold {
					color = raylib.DARKGRAY
				} else if i == shop_selected {
					color = raylib.YELLOW
				} else if currency < it.cost {
					color = raylib.GRAY
				}
				label: cstring
				if it.sold {
					label = raylib.TextFormat("%s   -   SOLD", it.name)
				} else {
					label = raylib.TextFormat("%s   -   %i", it.name, int(it.cost))
				}
				row := 150 + i32(i) * 58
				ck, hv := ui_row(label, row, 26, color)
				if mouse_moved && hv {shop_selected = i}
				if ck {clicked = i}
				draw_centered(it.desc, row + 28, 16, raylib.DARKGRAY)
			}
			// Reroll row.
			reroll_y := 150 + i32(n) * 58
			rerolls_left := SHOP_MAX_REROLLS - shop_rerolls_used
			reroll_label: cstring
			if rerolls_left > 0 {
				reroll_label = raylib.TextFormat(
					"REROLL OFFERS   -   $%i   (%i LEFT)",
					int(shop_reroll_cost()),
					int(rerolls_left),
				)
			} else {
				reroll_label = cstring("REROLL OFFERS   -   NONE LEFT")
			}
			reroll_color := raylib.GRAY
			if rerolls_left > 0 {
				reroll_color = shop_selected == reroll_row ? raylib.YELLOW : raylib.RAYWHITE
			}
			rck, rhv := ui_row(reroll_label, reroll_y, 24, reroll_color)
			if mouse_moved && rhv {shop_selected = reroll_row}
			if rck {clicked = reroll_row}
			// Leave row.
			leave_y := reroll_y + 58
			leave_color := shop_selected == leave_row ? raylib.YELLOW : raylib.GRAY
			lck, lhv := ui_row(cstring("LEAVE"), leave_y, 26, leave_color)
			if mouse_moved && lhv {shop_selected = leave_row}
			if lck {clicked = leave_row}
			draw_centered(
				cstring("UP/DOWN move   ENTER buy   R reroll   LEAVE to continue"),
				552,
				18,
				raylib.GRAY,
			)
			raylib.EndTextureMode()
			// A click acts on the row it landed on, exactly like ENTER.
			if clicked >= 0 {
				shop_selected = clicked
				if clicked == leave_row {
					leave_shop()
				} else if clicked == reroll_row {
					if try_shop_reroll() {
						play(sounds.shop_buy)
					} else {
						play(sounds.ui_move)
					}
				} else if buy_shop_item(clicked) {
					play(sounds.shop_buy)
				} else {
					play(sounds.ui_move)
				}
			}

		case .GAME_OVER:
			if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) ||
			   raylib.IsKeyPressed(raylib.KeyboardKey.ESCAPE) {
				play(sounds.ui_select)
				end_run()
			} else if raylib.IsKeyPressed(raylib.KeyboardKey.R) {
				// Replay the exact loadout that just ended.
				play(sounds.ui_select)
				start_run(
					start_loadout(
						result.character,
						result.gun,
						result.secondary,
						result.dash,
						result.utility,
					),
				)
			}
			raylib.BeginTextureMode(target)
			raylib.ClearBackground(raylib.BLACK)
			draw_centered(cstring("RUN OVER"), 40, 52, raylib.RED)
			draw_centered(
				raylib.TextFormat(
					"CHARACTER %s    ARENA %s",
					string(CHARACTERS[result.character].name),
					string(ARENAS[result.arena].name),
				),
				108,
				22,
				raylib.VIOLET,
			)
			draw_centered(
				raylib.TextFormat(
					"PRIMARY %s    SECONDARY %s",
					string(GUNS[result.gun].name),
					string(SECONDARIES[result.secondary].name),
				),
				138,
				18,
				raylib.DARKGRAY,
			)
			draw_centered(
				raylib.TextFormat(
					"DASH %s    UTILITY %s",
					string(DASHES[result.dash].name),
					string(UTILITIES[result.utility].name),
				),
				162,
				18,
				raylib.DARKGRAY,
			)
			draw_stat(cstring("WAVE REACHED"), raylib.TextFormat("%i", result.wave_reached), 214)
			draw_stat(cstring("ENEMIES SLAIN"), raylib.TextFormat("%i", result.kills), 248)
			draw_stat(cstring("ELITES SLAIN"), raylib.TextFormat("%i", result.elite_kills), 282)
			draw_stat(cstring("COINS EARNED"), raylib.TextFormat("%i", result.coins_earned), 316)
			draw_stat(cstring("COINS SPENT"), raylib.TextFormat("%i", result.coins_spent), 350)
			draw_stat(
				cstring("TIME SURVIVED"),
				raylib.TextFormat("%i:%02i", int(result.time) / 60, int(result.time) % 60),
				384,
			)
			g_main, _ := ui_row(cstring("ENTER   MAIN MENU"), 480, 24, raylib.GRAY)
			g_retry, _ := ui_row(cstring("R   RETRY SAME LOADOUT"), 512, 22, raylib.DARKGRAY)
			raylib.EndTextureMode()
			if g_main {
				play(sounds.ui_select)
				end_run()
			} else if g_retry {
				// Replay the exact loadout that just ended.
				play(sounds.ui_select)
				start_run(
					start_loadout(
						result.character,
						result.gun,
						result.secondary,
						result.dash,
						result.utility,
					),
				)
			}
		}

		// Present the canvas, scaled to fit the window (letterboxed).
		raylib.BeginDrawing()
		raylib.ClearBackground(raylib.BLACK)
		raylib.DrawTexturePro(
			target.texture,
			{0, 0, f32(windowX), -f32(windowY)},
			{view_x, view_y, view_w, view_h},
			{0, 0},
			0,
			raylib.WHITE,
		)
		// Ambient weather: a screen-space foreground overlay, scissored to the
		// presented canvas rect so it never bleeds into the letterbox bars. Each
		// kind draws differently (flakes / streaks / embers / grit).
		if state == .PLAYING && len(weather) > 0 {
			wk := arena_weather()
			raylib.BeginScissorMode(i32(view_x), i32(view_y), i32(view_w), i32(view_h))
			for w in weather {
				#partial switch wk {
				case .RAIN:
					// A short streak trailing the drop.
					tail := w.pos - w.vel * 0.02
					raylib.DrawLineEx(w.pos, tail, w.size, raylib.Color{150, 190, 235, 170})
				case .ASH:
					raylib.DrawCircleV(w.pos, w.size * 0.4, raylib.Color{255, 210, 130, 210})
					raylib.DrawCircleV(w.pos, w.size * 1.1, raylib.Color{255, 120, 40, 60})
				case .DUST:
					raylib.DrawCircleV(w.pos, w.size * 0.5, raylib.Color{190, 160, 120, 130})
				case:
					raylib.DrawCircleV(w.pos, w.size, raylib.Color{240, 248, 255, 200})
				}
			}
			raylib.EndScissorMode()
		}
		// Character/passive/on-hit sidebar, moved into the left pillarbox bar so the
		// gameplay canvas stays clear. Width-fitted to the bar. Skipped on 4:3
		// windows where the canvas HUD already drew it.
		if state == .PLAYING && view_x >= CHAR_PASSIVE_MIN_BAR {
			draw_sidebar_hud(14, 20, view_x - 28)
		}
		// Player-hurt wash: a red vignette over the whole screen, drawn in screen
		// space so it covers the letterbox too. Heaviest at the moment of the hit
		// and fading out over PLAYER_HURT_FLASH_TIME.
		if hurt_flash > 0 && settings.hurt_vignette {
			k := hurt_flash / PLAYER_HURT_FLASH_TIME
			// Square the falloff so most of the fade is a faint tint, with only
			// the first frames really flaring.
			a := 210 * k * k
			// Concentrated at the edges: a few nested outlines, each thicker and
			// fainter, so the middle of the screen stays readable. Hugged to the
			// presented canvas rect so it never bleeds into the letterbox bars.
			band: f32 = max(view_w, view_h) * 0.07
			for i in 0 ..< 4 {
				inset := f32(i) * band
				alpha := u8(a / f32(5 - i))
				rect := raylib.Rectangle {
					view_x + inset,
					view_y + inset,
					view_w - inset * 2,
					view_h - inset * 2,
				}
				raylib.DrawRectangleLinesEx(rect, band, raylib.Color{255, 40, 40, alpha})
			}
		}
		// Relic accept/discard overlay, drawn over the frozen frame (highest
		// priority: it was triggered from a chest you just touched).
		if relic_pick_open {
			relic_pick_draw()
		} else if ingame_panel_open {
			draw_ingame_panel()
		} else if auto_paused {
			// Auto-pause overlay: dim + a "click to resume" prompt while unfocused.
			sw := f32(raylib.GetScreenWidth())
			sh := f32(raylib.GetScreenHeight())
			raylib.DrawRectangleRec(raylib.Rectangle{0, 0, sw, sh}, raylib.Color{0, 0, 0, 120})
			draw_centered(cstring("PAUSED"), i32(sh * 0.42), 44, raylib.WHITE)
			draw_centered(
				cstring("window unfocused - audio muted"),
				i32(sh * 0.42) + 52,
				18,
				raylib.GRAY,
			)
		}
		raylib.EndDrawing()
	}
}
