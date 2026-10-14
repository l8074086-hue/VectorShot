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
				skill_state = .MAIN_SCREEN
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
			case .MAIN_SCREEN:
				if raylib.IsKeyPressed(raylib.KeyboardKey.ONE) {
					skill_state = .SKILL_ONE
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.TWO) {
					skill_state = .SKILL_TWO
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.THREE) {
					skill_state = .SKILL_THREE
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.FOUR) {
					skill_state = .SKILL_FOUR
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
					// Apply the chosen loadout and start a fresh run.
					start_run(start_loadout(gun, secondary_kind, dash_kind, utility))
				}
				raylib.BeginTextureMode(target)
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SKILL SELECT"), 60, 50, raylib.WHITE)
				draw_centered(
					raylib.TextFormat("1)  GUN        %s", string(GUNS[gun].name)),
					160,
					30,
					raylib.YELLOW,
				)
				draw_centered(
					raylib.TextFormat("2)  DASH       %s", string(DASHES[dash_kind].name)),
					220,
					30,
					raylib.SKYBLUE,
				)
				draw_centered(
					raylib.TextFormat("3)  UTILITY    %s", string(UTILITIES[utility].name)),
					280,
					30,
					raylib.GREEN,
				)
				draw_centered(
					raylib.TextFormat("4)  SECONDARY  %s", string(SECONDARIES[secondary_kind].name)),
					340,
					30,
					raylib.ORANGE,
				)
				draw_centered(
					cstring("Press 1 / 2 / 3 / 4 to change a slot"),
					420,
					22,
					raylib.RAYWHITE,
				)
				draw_centered(cstring("Press ENTER to start"), 456, 22, raylib.GRAY)
				raylib.EndTextureMode()
			case .SKILL_ONE:
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
					skill_state = .MAIN_SCREEN
				}
				raylib.BeginTextureMode(target)
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SELECT GUN"), 60, 40, raylib.WHITE)
				for g in Gun {
					color := gun == g ? raylib.YELLOW : raylib.DARKGRAY
					y := 110 + i32(g) * 60
					draw_centered(
						raylib.TextFormat("%i)  %s", int(g) + 1, string(GUNS[g].name)),
						y,
						28,
						color,
					)
					draw_centered(GUNS[g].desc, y + 30, 18, raylib.GRAY)
				}
				draw_centered(
					cstring("UP/DOWN or 1-9 to pick, ENTER to go back"),
					510,
					22,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
			case .SKILL_TWO:
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
					skill_state = .MAIN_SCREEN
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
			case .SKILL_THREE:
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
					skill_state = .MAIN_SCREEN
				}
				raylib.BeginTextureMode(target)
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SELECT UTILITY"), 60, 40, raylib.WHITE)
				for u in Utility {
					color := utility == u ? raylib.GREEN : raylib.DARKGRAY
					y := 160 + i32(u) * 90
					draw_centered(
						raylib.TextFormat("%i)  %s", int(u) + 1, string(UTILITIES[u].name)),
						y,
						32,
						color,
					)
					draw_centered(UTILITIES[u].desc, y + 36, 20, raylib.GRAY)
				}
				draw_centered(
					cstring("UP/DOWN or 1-9 to pick, ENTER to go back"),
					520,
					22,
					raylib.GRAY,
				)
				raylib.EndTextureMode()
			case .SKILL_FOUR:
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
					skill_state = .MAIN_SCREEN
				}
				raylib.BeginTextureMode(target)
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SELECT SECONDARY"), 60, 40, raylib.WHITE)
				for s in Secondary {
					color := secondary_kind == s ? raylib.ORANGE : raylib.DARKGRAY
					y := 140 + i32(s) * 80
					draw_centered(
						raylib.TextFormat("%i)  %s", int(s) + 1, string(SECONDARIES[s].name)),
						y,
						28,
						color,
					)
					draw_centered(SECONDARIES[s].desc, y + 30, 18, raylib.GRAY)
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
			// Aim at the cursor: convert the canvas-space mouse back through the
			// camera into world space, then face that way. Firing and kicking use
			// aim_dir, so you no longer shoot wherever you happen to be moving.
			world_mouse := (mousePos - camera.offset) / camera.zoom + camera.target
			to_mouse := world_mouse - (position + size * 0.5)
			if raylib.Vector2Length(to_mouse) > 0.01 {
				aim_dir = raylib.Vector2Normalize(to_mouse)
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.Q) {
				active_slot = 1 - active_slot
				play(sounds.ui_move)
			}
			dir := raylib.Vector2(0)
			if raylib.IsKeyDown(raylib.KeyboardKey.A) {dir.x -= 1}
			if raylib.IsKeyDown(raylib.KeyboardKey.D) {dir.x += 1}
			if raylib.IsKeyDown(raylib.KeyboardKey.W) {dir.y -= 1}
			if raylib.IsKeyDown(raylib.KeyboardKey.S) {dir.y += 1}

			if raylib.IsKeyPressed(raylib.KeyboardKey.F1) {
				debug_mode = !debug_mode
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.F2) {
				skill_state = .MAIN_SCREEN
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
							enemies[i].hp -= 30 * dT
							if enemies[i].hp <= 0 {
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
							barrels[i].hp -= 30 * dT
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
				position += raylib.Vector2Normalize(dir) * SPEED * dT
			}
			if dash_cooldown > 0 {
				dash_cooldown -= dT
			}

			// Active weapon: fetch its runtime state + stat block for this frame.
			weapon_tick(&primary, dT)
			weapon_tick(&secondary, dT)
			w := active_weapon()
			ws := active_stats()
			if raylib.IsKeyDown(raylib.KeyboardKey.SPACE) &&
			   w.cooldown <= 0 &&
			   w.mag > 0 &&
			   w.reload <= 0 {
				center := position + size * 0.5 - ws.bullet_size * 0.5
				shots := ws.projectiles + bonus_projectiles
				// The shot pattern comes from the weapon, but ATTACK/PROJECTILE/
				// PIERCE/PRECISION cards feed in on top, so both slots benefit.
				spread := max(ws.min_spread, ws.spread - spread_cut)
				// Fan shots across the gun's arc. Guns with no base spread (e.g. the
				// sniper) get an even default fan if cards add extra projectiles.
				arc := spread
				if shots > 1 && ws.spread <= 0 {
					arc = 0.12 * f32(shots - 1)
				}
				for k in 0 ..< shots {
					offset: f32 = 0
					if shots > 1 {
						offset = (f32(k) / f32(shots - 1) - 0.5) * arc
					}
					// Random inaccuracy on top of the fan so single-shot guns like
					// the SMG/MINIGUN spray a little. Precision cards shrink this.
					offset += rand.float32_range(-spread, spread) * 0.5
					shot_dir := raylib.Vector2Rotate(aim_dir, offset)
					append(
						&bullets,
						bullet {
							position = center,
							size = ws.bullet_size,
							velocity = shot_dir * ws.bullet_speed,
							damage = ws.damage + bonus_damage,
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
			// Manual reload: R (only if you have something to load).
			if raylib.IsKeyPressed(raylib.KeyboardKey.R) &&
			   w.reload <= 0 &&
			   w.mag < w.mag_cap &&
			   w.ammo > 0 {
				w.reload = RELOAD_TIME
				play(sounds.reload)
			}
			// Auto-reload when the mag runs dry.
			if w.mag <= 0 && w.ammo > 0 && w.reload <= 0 {
				w.reload = RELOAD_TIME
				play(sounds.reload)
			}
			// Melee kick: free (no ammo), an arc in the facing direction that shoves
			// enemies back hard.
			if melee_cooldown > 0 {
				melee_cooldown -= dT
			}
			if melee_flash > 0 {
				melee_flash -= dT
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.E) && melee_cooldown <= 0 {
				melee_cooldown = MELEE_COOLDOWN_MAX
				play(sounds.kick)
				melee_flash = 0.15
				player_c := position + size * 0.5
				for i := len(enemies) - 1; i >= 0; i -= 1 {
					e_c := enemies[i].position + enemies[i].size * 0.5
					to := e_c - player_c
					dist := raylib.Vector2Length(to)
					if dist > MELEE_RANGE || dist < 1 {
						continue
					}
					if raylib.Vector2Angle(last_dir, raylib.Vector2Normalize(to)) > MELEE_ARC {
						continue
					}
					enemies[i].hp -= MELEE_DAMAGE
					enemies[i].position += raylib.Vector2Normalize(to) * MELEE_KNOCKBACK
					if enemies[i].hp <= 0 {
						spawn_kill_rewards(enemies[i].position)
						unordered_remove(&enemies, i)
					}
				}
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.LEFT_SHIFT) && dash_cooldown <= 0 {
				play(sounds.dash)
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
			if raylib.IsKeyPressed(raylib.KeyboardKey.F) {
				clear(&cards)
				spawn_cards(&cards, card_choices, precision_is_useful())
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.G) {
				pop(&cards)
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.I) && !debug_mode {
				new_wave(&enemies, wave)
				wave += 1
			}
			if raylib.IsMouseButtonPressed(raylib.MouseButton.LEFT) {
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
						e.hp -= bullets[i].damage
						play(sounds.hit, rand.float32_range(0.9, 1.1))
						bullet_register_hit(&bullets[i], e.id)
						if e.hp <= 0 {
							spawn_kill_rewards(e.position)
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
				resolve_obstacles(&enemies[i].position, enemies[i].size)
			}
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
						health -= enemies[i].damage
						inv_timer = 0.5
						play(sounds.player_hurt)
					}
					if health <= 0 {
						state = .GAME_OVER
					}
				}
			}

			// Hostile projectiles (ranged enemies).
			for i := len(enemy_bullets) - 1; i >= 0; i -= 1 {
				enemy_bullets[i].position += enemy_bullets[i].velocity * dT
				bp := enemy_bullets[i].position
				bs := enemy_bullets[i].size
				if raylib.Vector2Distance(bp, position) > 1600 ||
				   bullet_blocked_by_terrain({bp.x, bp.y, bs.x, bs.y}) {
					unordered_remove(&enemy_bullets, i)
					continue
				}
				if raylib.CheckCollisionRecs({bp.x, bp.y, bs.x, bs.y}, player_rect) {
					if inv_timer <= 0 {
						health -= enemy_bullets[i].damage
						inv_timer = 0.5
						play(sounds.player_hurt)
					}
					unordered_remove(&enemy_bullets, i)
				}
			}

			if health <= 0 {
				state = .GAME_OVER
				play(sounds.game_over)
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
						play(sounds.coin, rand.float32_range(0.97, 1.03))
					}
					unordered_remove(&drops, i)
				}
			}

			if len(enemies) == 0 && len(cards) == 0 {
				// Every 5th cleared wave opens the shop instead of a card pick.
				// (`wave` is the *next* wave, so wave-1 is the one just cleared.)
				if wave > 1 && (wave - 1) % 5 == 0 {
					shop_selected = 0
					build_shop()
					state = .SHOP
				} else if !debug_mode || wave == 1 {
					spawn_cards(&cards, card_choices, precision_is_useful())
				}
				// In debug (not shop wave), skip the card reward after wave 1.
			}

			raylib.BeginTextureMode(target)
			raylib.ClearBackground(raylib.BLACK)
			raylib.BeginMode2D(camera)
			// Floor (checkerboard over the arena).
			tile: f32 = 40
			for ty := f32(0); ty < ARENA_H; ty += tile {
				for tx := f32(0); tx < ARENA_W; tx += tile {
					dark := (int(tx / tile) + int(ty / tile)) % 2 == 0
					tint := dark ? raylib.Color{26, 26, 32, 255} : raylib.Color{33, 33, 40, 255}
					raylib.DrawRectangleV({tx, ty}, {tile, tile}, tint)
				}
			}
			// Walls.
			for w in walls {
				raylib.DrawRectangleRec(w, raylib.Color{66, 66, 76, 255})
			}
			// Trees.
			for t in trees {
				c := t.pos + t.size * 0.5
				raylib.DrawRectangleV({c.x - 6, c.y - 2}, {12, 20}, raylib.DARKBROWN)
				raylib.DrawCircleV({c.x, c.y}, 22, raylib.DARKGREEN)
				raylib.DrawCircleV({c.x - 7, c.y - 7}, 13, raylib.GREEN)
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
				raylib.DrawRectangleV(e.position, e.size, e.color)
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
			// Player.
			raylib.DrawRectangleV(position, size, raylib.RED)
			if melee_flash > 0 {
				pc := position + size * 0.5
				// The kick is a wedge (radius + half-angle), so draw that exact
				// wedge instead of an approximating box — this lines the flash up
				// with what the kick really hits.
				angle := math.atan2_f32(last_dir.y, last_dir.x) * raylib.RAD2DEG
				arc_deg := f32(MELEE_ARC) * raylib.RAD2DEG
				fade := u8(200 * (melee_flash / 0.15))
				raylib.DrawCircleSector(
					pc,
					f32(MELEE_RANGE),
					angle - arc_deg,
					angle + arc_deg,
					20,
					raylib.Color{255, 255, 255, fade},
				)
			}
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
				padding: i32 = 10
				fs: i32 = 25
				for fs > 6 && raylib.MeasureText(c.name, fs) > i32(c.size.x) - padding * 2 {
					fs -= 1
				}
				raylib.DrawText(
					c.name,
					i32(c.position.x) + padding,
					i32(c.position.y) + padding,
					fs,
					raylib.BLACK,
				)
				raylib.DrawText(
					c.description,
					i32(c.position.x),
					i32(c.position.y) + 30,
					25,
					raylib.BLACK,
				)
			}
			raylib.DrawRectangleV(mousePos, {5, 5}, raylib.GREEN)
			raylib.DrawRectangle(10, 10, 200, 20, raylib.RED)
			raylib.DrawRectangle(10, 10, i32(200 * health / max_health), 20, raylib.GREEN)
			raylib.DrawRectangleLines(10, 10, 200, 20, raylib.WHITE)
			draw_centered(raylib.TextFormat("WAVE %i", int(wave)), 6, 24, raylib.LIGHTGRAY)
			// Active weapon + ammo, with the other slot shown for reference.
			weapon_name := active_slot == 0 ? string(GUNS[gun].name) : string(SECONDARIES[secondary_kind].name)
			other_name := active_slot == 0 ? string(SECONDARIES[secondary_kind].name) : string(GUNS[gun].name)
			raylib.DrawText(
				raylib.TextFormat("[%s] %i / %i", weapon_name, int(w.mag), int(w.ammo)),
				560,
				10,
				20,
				raylib.WHITE,
			)
			raylib.DrawText(raylib.TextFormat("Q: %s", other_name), 560, 34, 16, raylib.GRAY)
			if w.reload > 0 {
				raylib.DrawText(cstring("RELOADING"), 560, 54, 18, raylib.ORANGE)
			}
			raylib.DrawText(raylib.TextFormat("$ %i", int(currency)), 10, 34, 20, raylib.GOLD)
			raylib.DrawText(
				cstring(
					"WASD move   MOUSE aim   SPACE shoot   Q swap   E kick   SHIFT dash   R reload",
				),
				10,
				576,
				15,
				raylib.GRAY,
			)
			if debug_mode {
				raylib.DrawText("DEBUG", 220, 10, 20, raylib.ORANGE)
			}
			raylib.EndTextureMode()

		case .SHOP:
			n := len(shop_items)
			entries := n + 1 // the extra row is LEAVE
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
			if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
				if shop_selected >= n {
					// Leave the shop and spawn the next wave.
					state = .PLAYING
					play(sounds.ui_select)
					if !debug_mode {
						new_wave(&enemies, wave)
					}
					wave += 1
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
				color := raylib.RAYWHITE
				if it.sold {
					color = raylib.DARKGRAY
				} else if i == shop_selected {
					color = raylib.YELLOW
				}
				label: cstring
				if it.sold {
					label = raylib.TextFormat("%s   -   SOLD", it.name)
				} else {
					label = raylib.TextFormat("%s   -   %i", it.name, it.cost)
				}
				row := 150 + i32(i) * 58
				draw_centered(label, row, 26, color)
				draw_centered(it.desc, row + 28, 16, raylib.DARKGRAY)
			}
			leave_color := shop_selected >= n ? raylib.YELLOW : raylib.GRAY
			draw_centered(cstring("LEAVE"), 150 + i32(n) * 58, 26, leave_color)
			draw_centered(cstring("UP/DOWN move   ENTER buy/leave"), 552, 18, raylib.GRAY)
			raylib.EndTextureMode()

		case .GAME_OVER:
			if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
				play(sounds.ui_select)
				end_run()
			}
			raylib.BeginTextureMode(target)
			raylib.ClearBackground(raylib.BLACK)
			game_over := cstring("GAME OVER")
			gw := raylib.MeasureText(game_over, 60)
			raylib.DrawText(game_over, 400 - gw / 2, 200, 60, raylib.RED)
			prompt := cstring("Press ENTER to restart")
			pw := raylib.MeasureText(prompt, 25)
			raylib.DrawText(prompt, 400 - pw / 2, 300, 25, raylib.GRAY)
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
