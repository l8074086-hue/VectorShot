package main
import "core:math"
import "core:math/rand"
import "vendor:raylib"

main :: proc() {
	windowX: i32 = 800
	windowY: i32 = 600
	raylib.InitWindow(windowX, windowY, "Roguelike")
	raylib.SetTargetFPS(60)
	defer raylib.CloseWindow()
	raylib.ToggleFullscreen()

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
	defer delete(trees)
	defer delete(explosions)
	defer delete(shop_items)

	camera: raylib.Camera2D

	for !raylib.WindowShouldClose() {
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
		mousePos := raylib.Vector2{(raw_mouse.x - view_x) / scale, (raw_mouse.y - view_y) / scale}
		mouse := raylib.Rectangle{mousePos.x, mousePos.y, 5, 5}

		#partial switch state {
		case .MAIN_MENU:
			if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
				play(sounds.ui_select)
				skill_state = .MAIN
				state = .SKILL_SELECT
			}
			raylib.BeginTextureMode(target)
			raylib.ClearBackground(raylib.BLACK)
			title := cstring("ROGUELIKE")
			tw := raylib.MeasureText(title, 60)
			color: raylib.Color = raylib.WHITE
			raylib.DrawText(title, 400 - tw / 2, 200, 60, color)
			prompt := cstring("Press ENTER to start")
			pw := raylib.MeasureText(prompt, 25)
			raylib.DrawText(prompt, 400 - pw / 2, 300, 25, raylib.GRAY)
			raylib.EndTextureMode()
		case .SKILL_SELECT:
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
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
					// Apply the chosen loadout and start a fresh run.
					start_run(
						start_loadout(character, gun, secondary_kind, dash_kind, utility),
					)
				}
				raylib.BeginTextureMode(target)
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SKILL SELECT"), 50, 50, raylib.WHITE)
				draw_centered(
					raylib.TextFormat("1)  CHARACTER  %s", string(CHARACTERS[character].name)),
					120,
					28,
					raylib.RAYWHITE,
				)
				draw_centered(
					raylib.TextFormat("2)  PRIMARY    %s", string(GUNS[gun].name)),
					162,
					28,
					raylib.YELLOW,
				)
				draw_centered(
					raylib.TextFormat("3)  DASH       %s", string(DASHES[dash_kind].name)),
					204,
					28,
					raylib.SKYBLUE,
				)
				draw_centered(
					raylib.TextFormat("4)  UTILITY    %s", string(UTILITIES[utility].name)),
					246,
					28,
					raylib.GREEN,
				)
				draw_centered(
					raylib.TextFormat("5)  SECONDARY  %s", string(SECONDARIES[secondary_kind].name)),
					288,
					28,
					raylib.ORANGE,
				)
				draw_centered(
					raylib.TextFormat("6)  ARENA      %s", string(ARENAS[arena].name)),
					330,
					28,
					raylib.VIOLET,
				)
				draw_centered(
					cstring("Press 1 - 6 to change a slot"),
					420,
					22,
					raylib.RAYWHITE,
				)
				draw_centered(cstring("Press ENTER to start"), 452, 22, raylib.GRAY)
				raylib.EndTextureMode()
			case .CHARACTER:
				if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
					character = Character((int(character) + 1) % len(CHARACTERS))
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
					character = Character(
						(int(character) - 1 + len(CHARACTERS)) % len(CHARACTERS),
					)
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
					draw_centered(
						raylib.TextFormat("%i)  %s", int(ch) + 1, string(CHARACTERS[ch].name)),
						y,
						28,
						color,
					)
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
				}
				draw_centered(
					cstring("UP/DOWN or 1-9 to pick, ENTER to go back"),
					564,
					22,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
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
					draw_centered(
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
					draw_centered(GUNS[g].desc, y + 22, 16, raylib.GRAY)
				}
				draw_centered(
					cstring("UP/DOWN or 1-9 to pick, ENTER to go back"),
					572,
					20,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
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
					draw_centered(
						raylib.TextFormat("%i)  %s", int(d) + 1, string(DASHES[d].name)),
						y,
						28,
						color,
					)
					draw_centered(DASHES[d].desc, y + 30, 18, raylib.GRAY)
				}
				draw_centered(
					cstring("UP/DOWN or 1-9 to pick, ENTER to go back"),
					510,
					22,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
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
					draw_centered(
						raylib.TextFormat("%i)  %s", int(u) + 1, string(UTILITIES[u].name)),
						y,
						26,
						color,
					)
					draw_centered(UTILITIES[u].desc, y + 24, 16, raylib.GRAY)
				}
				draw_centered(
					cstring("UP/DOWN or 1-9 to pick, ENTER to go back"),
					520,
					22,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
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
					draw_centered(
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
					draw_centered(SECONDARIES[s].desc, y + 26, 16, raylib.GRAY)
				}
				draw_centered(
					cstring("UP/DOWN or 1-9 to pick, ENTER to go back"),
					560,
					20,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
			case .ARENA:
				if raylib.IsKeyPressed(raylib.KeyboardKey.DOWN) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.S) {
					arena = Arena_Kind((int(arena) + 1) % len(ARENAS))
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.UP) ||
				   raylib.IsKeyPressed(raylib.KeyboardKey.W) {
					arena = Arena_Kind((int(arena) - 1 + len(ARENAS)) % len(ARENAS))
				}
				for key, idx in NUMBER_KEYS {
					if idx < len(ARENAS) && raylib.IsKeyPressed(key) {
						arena = Arena_Kind(idx)
					}
				}
				if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
					skill_state = .MAIN
				}
				raylib.BeginTextureMode(target)
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SELECT ARENA"), 60, 40, raylib.WHITE)
				for a in Arena_Kind {
					color := arena == a ? raylib.VIOLET : raylib.DARKGRAY
					y := 140 + i32(a) * 80
					// Little palette swatch so the theme is visible before picking.
					raylib.DrawRectangle(120, y + 4, 34, 34, ARENAS[a].floor_dark)
					raylib.DrawRectangleLines(120, y + 4, 34, 34, ARENAS[a].wall)
					draw_centered(
						raylib.TextFormat("%i)  %s", int(a) + 1, string(ARENAS[a].name)),
						y,
						28,
						color,
					)
					draw_centered(ARENAS[a].desc, y + 30, 18, raylib.GRAY)
				}
				draw_centered(
					cstring("UP/DOWN or 1-9 to pick, ENTER to go back"),
					540,
					22,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
			}
		case .PLAYING:
			camera.target = position + size * 0.5
			camera.offset = {400, 300}
			camera.zoom = 1
			// Count active play time for the results screen.
			run_time += dT
			// Aim at the cursor: convert the canvas-space mouse back through the
			// camera into world space, then face that way. Firing and kicking use
			// aim_dir, so you no longer shoot wherever you happen to be moving.
			world_mouse := (mousePos - camera.offset) / camera.zoom + camera.target
			to_mouse := world_mouse - (position + size * 0.5)
			if raylib.Vector2Length(to_mouse) > 0.01 {
				aim_dir = raylib.Vector2Normalize(to_mouse)
			}
			if world_key_pressed(raylib.KeyboardKey.Q) {
				active_slot = 1 - active_slot
				play(sounds.ui_move)
			}
			dir := raylib.Vector2(0)
			if world_key_down(raylib.KeyboardKey.A) {dir.x -= 1}
			if world_key_down(raylib.KeyboardKey.D) {dir.x += 1}
			if world_key_down(raylib.KeyboardKey.W) {dir.y -= 1}
			if world_key_down(raylib.KeyboardKey.S) {dir.y += 1}
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
				}
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
							apply_enemy_damage(&enemies[i], dash_damage * dT, position + size * 0.5 - ec)
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
			if dir != raylib.Vector2(0) && dash_timer <= 0 {
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
			if world_key_down(raylib.KeyboardKey.SPACE) && w.cooldown <= 0 {
				if ws.class == .MELEE {
					// Melee weapon in the active slot: swing it (no ammo).
					if active_slot == 0 {
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
					for k in 0 ..< shots {
						offset: f32 = 0
						if shots > 1 {
							offset = (f32(k) / f32(shots - 1) - 0.5) * arc
						}
						// Random inaccuracy on top of the fan so single-shot guns like
						// the SMG/MINIGUN spray a little. Precision cards shrink this.
						offset += rand.float32_range(-spread, spread) * 0.5
						shot_dir := raylib.Vector2Rotate(aim_dir, offset)
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
							},
						)
					}
					w.cooldown = ws.cooldown
					w.mag -= 1
					if active_slot == 0 {
						play(sounds.primary[gun], rand.float32_range(0.94, 1.06))
					} else {
						play(sounds.secondary[secondary_kind], rand.float32_range(0.94, 1.06))
					}
				}
			}
			// Manual reload: R (only if you have something to load).
			if world_key_pressed(raylib.KeyboardKey.R) &&
			   w.reload <= 0 &&
			   w.mag < w.mag_cap &&
			   w.ammo > 0 {
				w.reload = reload_time
				play(sounds.reload)
			}
			// Auto-reload when the mag runs dry.
			if w.mag <= 0 && w.ammo > 0 && w.reload <= 0 {
				w.reload = reload_time
				play(sounds.reload)
			}
			// Universal kick: every character can always do this, whatever they
			// have equipped. Character melee multipliers scale KICK's stats.
			if melee_cooldown > 0 {
				melee_cooldown -= dT
			}
			if melee_flash > 0 {
				melee_flash -= dT
			}
			if world_key_pressed(raylib.KeyboardKey.E) && melee_cooldown <= 0 {
				swing := unarmed_stats()
				melee_cooldown = swing_cooldown(swing)
				play(sounds.kick, swing.sound_pitch)
				melee_swing(swing, aim_dir)
			}
			if world_key_pressed(raylib.KeyboardKey.LEFT_SHIFT) && dash_cooldown <= 0 {
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
			if world_key_pressed(raylib.KeyboardKey.F) {
				clear(&cards)
				spawn_cards(&cards, card_choices)
			}
			if world_key_pressed(raylib.KeyboardKey.G) {
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
						apply_upgrade(cards[i].name)
						play(sounds.card)
						clear(&cards)
						if !debug_mode {
							new_wave(&enemies, wave)
						}
						wave += 1
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
					if bullet_hit_before(&bullets[i], e.id) {
						continue
					}
					if raylib.CheckCollisionRecs(
						{p.x, p.y, s.x, s.y},
						{e.position.x, e.position.y, e.size.x, e.size.y},
					) {
						play_enemy_hit(apply_enemy_damage(e, bullets[i].damage, -bullets[i].velocity))
						bullet_register_hit(&bullets[i], e.id)
						if e.hp <= 0 {
							spawn_kill_rewards(e.position, e.elite)
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
				update_enemy(&enemies[i], dT)
				// Phantom chargers pass straight through terrain mid-dash, but
				// are still kept inside the arena.
				if enemies[i].elite &&
				   enemies[i].kind == .CHARGER &&
				   enemies[i].state == .CHARGE {
					e := &enemies[i]
					e.position.x = clamp(
						e.position.x,
						f32(WALL_THICK),
						f32(ARENA_W) - f32(WALL_THICK) - e.size.x,
					)
					e.position.y = clamp(
						e.position.y,
						f32(WALL_THICK),
						f32(ARENA_H) - f32(WALL_THICK) - e.size.y,
					)
				} else {
					resolve_obstacles(&enemies[i].position, enemies[i].size)
				}
			}
			update_elite_abilities(&enemies, dT)
			separate_enemies()

			if inv_timer > 0 {
				inv_timer -= dT
			}
			player_rect := raylib.Rectangle{position.x, position.y, size.x, size.y}
			for i := len(enemies) - 1; i >= 0; i -= 1 {
				enemy_rect := raylib.Rectangle {
					enemies[i].position.x,
					enemies[i].position.y,
					enemies[i].size.x,
					enemies[i].size.y,
				}
				if raylib.CheckCollisionRecs(player_rect, enemy_rect) {
					if inv_timer <= 0 {
						apply_player_damage(enemies[i].damage, enemies[i].position + enemies[i].size * 0.5)
						inv_timer = 0.5
						play(sounds.player_hurt)
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
						inv_timer = 0.5
						play(sounds.player_hurt)
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
					}
					unordered_remove(&drops, i)
				}
			}

			if !console_open && len(enemies) == 0 && len(cards) == 0 {
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

			raylib.BeginTextureMode(target)
			raylib.ClearBackground(raylib.BLACK)
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
			// Walls.
			for w in walls {
				raylib.DrawRectangleRec(w, pal.wall)
			}
			// Trees / boulders (round static cover).
			for t in trees {
				c := t.pos + t.size * 0.5
				raylib.DrawRectangleV({c.x - 6, c.y - 2}, {12, 20}, trunk)
				raylib.DrawCircleV({c.x, c.y}, 22, pal.cover)
				raylib.DrawCircleV({c.x - 7, c.y - 7}, 13, pal.cover_top)
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
				}
			}
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
				raylib.DrawRectangleV(e.position, e.size, body)
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
							raylib.DrawPoly(
								center + e.plate_dir[k] * rad,
								4,
								5,
								0,
								raylib.SKYBLUE,
							)
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
			}
			// Projectiles.
			for b in bullets {
				raylib.DrawRectangleV(b.position, b.size, raylib.YELLOW)
			}
			for b in enemy_bullets {
				raylib.DrawRectangleV(b.position, b.size, raylib.MAGENTA)
			}
			// Player (shape + darker outline come from the chosen character).
			draw_player()
			draw_melee_flash()
			// Expanding blast rings.
			for x in explosions {
				f := x.life / EXPLOSION_TIME
				raylib.DrawCircleV(
					x.pos,
					EXPLOSION_RADIUS * (1 - f),
					raylib.Color{255, 150, 40, u8(170 * f)},
				)
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
				raylib.DrawText(
					c.description,
					x + (w - desc_w) / 2,
					y + 78,
					desc_fs,
					raylib.BLACK,
				)
				if c.hover {
					raylib.DrawRectangleLinesEx(card_rect, 2, raylib.WHITE)
				}
			}
			raylib.DrawRectangleV(mousePos, {5, 5}, raylib.GREEN)
			raylib.DrawRectangle(10, 10, 200, 20, raylib.RED)
			raylib.DrawRectangle(10, 10, i32(200 * health / max_health), 20, raylib.GREEN)
			raylib.DrawRectangleLines(10, 10, 200, 20, raylib.WHITE)
			draw_centered(raylib.TextFormat("WAVE %i", int(wave)), 6, 24, raylib.LIGHTGRAY)
			// Active weapon + ammo, with the other slot shown for reference.
			weapon_name := active_slot == 0 ? string(GUNS[gun].name) : string(SECONDARIES[secondary_kind].name)
			other_name := active_slot == 0 ? string(SECONDARIES[secondary_kind].name) : string(GUNS[gun].name)
			if active_stats().class == .MELEE {
				raylib.DrawText(
					raylib.TextFormat("[%s] MELEE", weapon_name),
					560,
					10,
					20,
					raylib.WHITE,
				)
			} else {
				raylib.DrawText(
					raylib.TextFormat("[%s] %i / %i", weapon_name, int(w.mag), int(w.ammo)),
					560,
					10,
					20,
					raylib.WHITE,
				)
			}
			raylib.DrawText(raylib.TextFormat("Q: %s", other_name), 560, 34, 16, raylib.GRAY)
			if w.reload > 0 {
				raylib.DrawText(cstring("RELOADING"), 560, 54, 18, raylib.ORANGE)
			}
			raylib.DrawText(raylib.TextFormat("$ %i", int(currency)), 10, 34, 20, raylib.GOLD)
			raylib.DrawText(
				raylib.TextFormat("%s", string(CHARACTERS[character].name)),
				220,
				34,
				20,
				CHARACTERS[character].color,
			)
			// Passive readout: its name, plus live state for the ones that build up.
			raylib.DrawText(
				raylib.TextFormat("%s", string(CHARACTERS[character].passive)),
				220,
				56,
				14,
				raylib.LIGHTGRAY,
			)
			if character == .TRACER {
				// Traceur's Heart charge bar.
				raylib.DrawRectangle(220, 74, 120, 8, raylib.DARKGRAY)
				raylib.DrawRectangle(220, 74, i32(120 * clamp(traceur_charge, 0, 1)), 8, raylib.GOLD)
				raylib.DrawRectangleLines(220, 74, 120, 8, raylib.GRAY)
			} else if character == .RR {
				name := string(rr_adaptation_name())
				if rr_surge > 0 {
					raylib.DrawText(
						raylib.TextFormat("ADAPT: %s [SURGE]", name),
						220,
						72,
						14,
						raylib.GOLD,
					)
				} else {
					raylib.DrawText(
						raylib.TextFormat("ADAPT: %s", name),
						220,
						72,
						14,
						raylib.SKYBLUE,
					)
				}
			}
			controls := character == .BUD ? cstring("WASD move   MOUSE aim   SPACE fire/swing   Q swap   E fists   SHIFT dash   R reload   ` console") : cstring("WASD move   MOUSE aim   SPACE fire/swing   Q swap   E kick   SHIFT dash   R reload   ` console")
			raylib.DrawText(controls, 10, 576, 15, raylib.GRAY)
			if debug_mode {
				raylib.DrawText("DEBUG", 220, 10, 20, raylib.ORANGE)
			}
			console_draw()
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
			if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
				if shop_selected == leave_row {
					// Leave the shop and spawn the next wave.
					state = .PLAYING
					play(sounds.ui_select)
					if !debug_mode {
						new_wave(&enemies, wave)
					}
					wave += 1
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
				draw_centered(label, row, 26, color)
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
			draw_centered(reroll_label, reroll_y, 24, reroll_color)
			// Leave row.
			leave_y := reroll_y + 58
			leave_color := shop_selected == leave_row ? raylib.YELLOW : raylib.GRAY
			draw_centered(cstring("LEAVE"), leave_y, 26, leave_color)
			draw_centered(
				cstring("UP/DOWN move   ENTER buy   R reroll   LEAVE to continue"),
				552,
				18,
				raylib.GRAY,
			)
			raylib.EndTextureMode()

		case .GAME_OVER:
			if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
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
			draw_centered(cstring("ENTER   MAIN MENU"), 480, 24, raylib.GRAY)
			draw_centered(cstring("R   RETRY SAME LOADOUT"), 512, 22, raylib.DARKGRAY)
			raylib.EndTextureMode()
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
		raylib.EndDrawing()
	}
}
