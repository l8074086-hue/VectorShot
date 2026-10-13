package main
import "core:math/rand"
import "vendor:raylib"

// Direct-pick keys used on the skill-select option screens (1-9).
NUMBER_KEYS := [9]raylib.KeyboardKey{.ONE, .TWO, .THREE, .FOUR, .FIVE, .SIX, .SEVEN, .EIGHT, .NINE}

GameState :: enum {
	MAIN_MENU,
	SKILL_SELECT,
	PLAYING,
	GAME_OVER,
}

SkillSlotState :: enum {
	MAIN_SCREEN,
	SKILL_ONE,
	SKILL_TWO,
	SKILL_THREE,
}

BULLET_MAX_HITS :: 8

bullet :: struct {
	position:  raylib.Vector2,
	size:      raylib.Vector2,
	velocity:  raylib.Vector2,
	damage:    f32,
	pierce:    i32, // how many more enemies this shot can pass through
	hits:      [BULLET_MAX_HITS]i32, // enemy ids already damaged
	hit_count: int,
}

card :: struct {
	position:    raylib.Vector2,
	size:        raylib.Vector2,
	name:        cstring,
	description: cstring,
	hover:       bool,
}

card_definition :: struct {
	name:        cstring,
	description: cstring,
}

// Every upgrade that can be offered between waves. Effects are applied in
// `main` by matching `name`, so keep the names in sync with that switch.
CARD_POOL :: [?]card_definition {
	{"DASH", "UPGRADE"},
	{"ATTACK", "UPGRADE"},
	{"SPEED", "UPGRADE"},
	{"HEALTH", "UPGRADE"},
	{"PROJECTILE", "UPGRADE"},
	{"PRECISION", "UPGRADE"},
	{"PIERCE", "UPGRADE"},
}

trail_point :: struct {
	pos:  raylib.Vector2,
	life: f32,
}

enemy :: struct {
	position:  raylib.Vector2,
	size:      raylib.Vector2,
	velocity:  raylib.Vector2,
	attacking: bool,
	color:     raylib.Color,
	damage:    f32,
	hp:        f32,
	id:        i32,
	speed:     f32,
}

Enemy_Kind :: enum {
	GRUNT,
	RUNNER,
	TANK,
}

Enemy_Stats :: struct {
	name:   cstring,
	size:   raylib.Vector2,
	speed:  f32,
	damage: f32,
	hp:     f32,
	color:  raylib.Color,
}

ENEMIES := [Enemy_Kind]Enemy_Stats {
	.GRUNT  = {"GRUNT", {50, 50}, 80, 10, 2, raylib.BLUE},
	.RUNNER = {"RUNNER", {30, 30}, 150, 6, 1, raylib.ORANGE},
	.TANK   = {"TANK", {80, 80}, 45, 20, 8, raylib.DARKGREEN},
}

// Later waves unlock tougher enemy kinds.
pick_enemy_kind :: proc(wave: i32) -> Enemy_Kind {
	roll := rand.float32()
	if wave >= 5 && roll < 0.20 {
		return .TANK
	}
	if wave >= 3 && roll < 0.55 {
		return .RUNNER
	}
	return .GRUNT
}

next_enemy_id: i32 = 1

bullet_hit_before :: proc(b: ^bullet, id: i32) -> bool {
	for h in 0 ..< b.hit_count {
		if b.hits[h] == id {
			return true
		}
	}
	return false
}

bullet_register_hit :: proc(b: ^bullet, id: i32) {
	if b.hit_count < BULLET_MAX_HITS {
		b.hits[b.hit_count] = id
		b.hit_count += 1
	}
}

Gun :: enum {
	SNIPER,
	SHOTGUN,
	SMG,
	RIFLE,
	MINIGUN,
	CANNON,
}

Dash_Kind :: enum {
	BURST,
	BLINK,
	PHASE,
	IMPACT,
	SLIDE,
}

Utility :: enum {
	VITALITY,
	SWIFT,
	FORTUNE,
}

Gun_Stats :: struct {
	name:         cstring,
	desc:         cstring,
	bullet_speed: f32,
	damage:       f32,
	projectiles:  i32,
	spread:       f32, // total fan arc / base inaccuracy in radians
	cooldown:     f32, // seconds between shots
	pierce:       i32, // enemies each shot passes through
	bullet_size:  raylib.Vector2,
	min_spread:   f32, // PRECISION cannot tighten below this
}

Dash_Stats :: struct {
	name:     cstring,
	desc:     cstring,
	speed:    f32,
	duration: f32,
	cooldown: f32,
	blink:    bool,
	distance: f32,
	damages:  bool, // dash deals contact damage while active
}

Utility_Stats :: struct {
	name: cstring,
	desc: cstring,
}

GUNS := [Gun]Gun_Stats {
	.SNIPER  = {"SNIPER", "SLOW, HEAVY, PIERCES", 900, 2.0, 1, 0.00, 1.00, 2, {10, 10}, 0.00},
	.SHOTGUN = {"SHOTGUN", "5-PELLET SPREAD", 340, 1.0, 5, 0.40, 0.60, 0, {8, 8}, 0.10},
	.SMG     = {"SMG", "FAST FIRE, LOW DMG", 520, 0.6, 1, 0.10, 0.07, 0, {7, 7}, 0.02},
	.RIFLE   = {"RIFLE", "BALANCED ALL-ROUNDER", 700, 1.0, 1, 0.03, 0.15, 0, {9, 9}, 0.00},
	.MINIGUN = {"MINIGUN", "VERY FAST, WIDE SPREAD", 600, 0.4, 1, 0.28, 0.05, 0, {6, 6}, 0.10},
	.CANNON  = {"CANNON", "SLOW, HUGE DMG, PIERCES", 320, 4.0, 1, 0.00, 0.90, 1, {16, 16}, 0.00},
}

DASHES := [Dash_Kind]Dash_Stats {
	.BURST  = {"BURST", "SHORT QUICK DASH", 800, 0.15, 0.50, false, 0, false},
	.BLINK  = {"BLINK", "INSTANT TELEPORT", 0, 0, 1.00, true, 240, false},
	.PHASE  = {"PHASE", "LONG I-FRAMES", 520, 0.40, 0.90, false, 0, false},
	.IMPACT = {"IMPACT", "DAMAGES ENEMIES", 700, 0.20, 0.70, false, 0, true},
	.SLIDE  = {"SLIDE", "FAST, LONG DISTANCE", 1100, 0.22, 0.80, false, 0, false},
}

UTILITIES := [Utility]Utility_Stats {
	.VITALITY = {"VITALITY", "+25 MAX HP"},
	.SWIFT    = {"SWIFT", "+50 MOVE SPEED"},
	.FORTUNE  = {"FORTUNE", "+1 CARD CHOICE"},
}

// Per-run stats derived from the chosen loadout. Cards upgrade these afterward.
Run_Stats :: struct {
	speed:         f32,
	bullet_speed:  f32,
	damage:        f32,
	projectiles:   i32,
	spread:        f32,
	pierce:        i32,
	bullet_size:   raylib.Vector2,
	fire_rate:     f32,
	dash_speed:    f32,
	dash_duration: f32,
	dash_cooldown: f32,
	dash_blink:    bool,
	dash_distance: f32,
	dash_damages:  bool,
	max_health:    f32,
	card_choices:  int,
}

start_loadout :: proc(gun: Gun, dash: Dash_Kind, utility: Utility) -> Run_Stats {
	g := GUNS[gun]
	d := DASHES[dash]
	stats := Run_Stats {
		speed         = 200,
		bullet_speed  = g.bullet_speed,
		damage        = g.damage,
		projectiles   = g.projectiles,
		spread        = g.spread,
		pierce        = g.pierce,
		bullet_size   = g.bullet_size,
		fire_rate     = g.cooldown,
		dash_speed    = d.speed,
		dash_duration = d.duration,
		dash_cooldown = d.cooldown,
		dash_blink    = d.blink,
		dash_distance = d.distance,
		dash_damages  = d.damages,
		max_health    = 100,
		card_choices  = 3,
	}

	switch utility {
	case .VITALITY:
		stats.max_health += 25
	case .SWIFT:
		stats.speed += 50
	case .FORTUNE:
		stats.card_choices += 1
	}
	return stats
}

draw_centered :: proc(text: cstring, y, size: i32, color: raylib.Color) {
	width := raylib.MeasureText(text, size)
	raylib.DrawText(text, 400 - width / 2, y, size, color)
}

spawn_cards :: proc(cards: ^[dynamic]card, count := 3, precision_useful: bool) {
	CARD_W: f32 = 120
	CARD_H: f32 = 160
	spacing: f32 = CARD_W + 40
	center_x := f32(800) / 2
	y := f32(600) / 2 - CARD_H / 2

	// Build the deal pool, dropping PRECISION once the current gun can't get
	// any tighter (its spread is already at min_spread).
	pool: [dynamic]card_definition
	defer delete(pool)
	for c in CARD_POOL {
		if c.name == "PRECISION" && !precision_useful {
			continue
		}
		append(&pool, c)
	}
	rand.shuffle(pool[:])
	n := min(count, len(pool))

	// Center the row for however many cards we actually deal.
	total_width := spacing * f32(n) - (spacing - CARD_W)
	start_x := center_x - total_width / 2

	for i in 0 ..< n {
		pos := raylib.Vector2{start_x + spacing * f32(i), y}
		append(cards, card{pos, {CARD_W, CARD_H}, pool[i].name, pool[i].description, false})
	}
}

spawn_enemies :: proc(enemies: ^[dynamic]enemy, num: i32, wave: i32) {
	for _ in 0 ..< num {
		s := ENEMIES[pick_enemy_kind(wave)]
		pos := raylib.Vector2 {
			f32(raylib.GetRandomValue(0, 800 - i32(s.size.x))),
			f32(raylib.GetRandomValue(0, 600 - i32(s.size.y))),
		}
		append(
			enemies,
			enemy {
				position = pos,
				size = s.size,
				velocity = {0, 0},
				attacking = false,
				color = s.color,
				damage = s.damage,
				hp = s.hp,
				id = next_enemy_id,
				speed = s.speed,
			},
		)
		next_enemy_id += 1
	}
}

new_wave :: proc(enemies: ^[dynamic]enemy, wave: i32) {
	spawn_enemies(enemies, wave, wave)
}

skill_screen_draw :: proc(selected_skill: cstring) {

}

main :: proc() {
	state: GameState = .MAIN_MENU
	windowX: i32 = 800
	windowY: i32 = 600
	debug_mode: bool = false
	raylib.InitWindow(windowX, windowY, "Roguelike")
	raylib.SetTargetFPS(60)
	defer raylib.CloseWindow()

	position: raylib.Vector2 = {50, 50}
	size: raylib.Vector2 = {30, 30}
	SPEED: f32 = 200
	BULLET_SPEED: f32 = 400
	bullet_size: raylib.Vector2 = {10, 10}
	cards: [dynamic]card
	defer delete(cards)
	center: raylib.Vector2 = {}
	enemies: [dynamic]enemy

	last_dir: raylib.Vector2 = {0, -1}
	bullets: [dynamic]bullet
	defer delete(bullets)
	wave: i32 = 1
	health: f32 = 100
	max_health: f32 = 100
	projectile_num: i32 = 1
	player_damage: f32 = 1
	player_pierce: i32 = 0
	gun_spread: f32 = 0
	fire_rate: f32 = 0.30
	fire_cooldown: f32 = 0
	inv_timer: f32 = 0
	dash_timer: f32 = 0
	DASH_SPEED: f32 = 800
	DASH_DURATION: f32 = 0.15
	dash_cooldown: f32 = 0
	dash_cooldown_max: f32 = 0.5
	dash_blink: bool = false
	dash_distance: f32 = 0
	dash_damages: bool = false
	card_choices: int = 3
	gun: Gun = .SNIPER
	dash_kind: Dash_Kind = .BURST
	utility: Utility = .VITALITY
	skill_state: SkillSlotState = .MAIN_SCREEN
	trail: [dynamic]trail_point
	defer delete(trail)
	camera: raylib.Camera2D

	for !raylib.WindowShouldClose() {
		dT := raylib.GetFrameTime()
		mousePos := raylib.GetMousePosition()
		mouse := raylib.Rectangle{mousePos.x, mousePos.y, 5, 5}

		#partial switch state {
		case .MAIN_MENU:
			if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
				skill_state = .MAIN_SCREEN
				state = .SKILL_SELECT
			}
			raylib.BeginDrawing()
			raylib.ClearBackground(raylib.BLACK)
			title := cstring("ROGUELIKE")
			tw := raylib.MeasureText(title, 60)
			color: raylib.Color = raylib.WHITE
			raylib.DrawText(title, 400 - tw / 2, 200, 60, color)
			prompt := cstring("Press ENTER to start")
			pw := raylib.MeasureText(prompt, 25)
			raylib.DrawText(prompt, 400 - pw / 2, 300, 25, raylib.GRAY)
			raylib.EndDrawing()
		case .SKILL_SELECT:
			#partial switch skill_state {
			case .MAIN_SCREEN:
				if raylib.IsKeyPressed(raylib.KeyboardKey.ONE) {
					skill_state = .SKILL_ONE
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.TWO) {
					skill_state = .SKILL_TWO
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.THREE) {
					skill_state = .SKILL_THREE
				} else if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
					// Apply the chosen loadout and start a fresh run.
					stats := start_loadout(gun, dash_kind, utility)
					position = {50, 50}
					SPEED = stats.speed
					BULLET_SPEED = stats.bullet_speed
					player_damage = stats.damage
					projectile_num = stats.projectiles
					player_pierce = stats.pierce
					gun_spread = stats.spread
					bullet_size = stats.bullet_size
					fire_rate = stats.fire_rate
					fire_cooldown = 0
					DASH_SPEED = stats.dash_speed
					DASH_DURATION = stats.dash_duration
					dash_cooldown = 0
					dash_cooldown_max = stats.dash_cooldown
					dash_blink = stats.dash_blink
					dash_distance = stats.dash_distance
					dash_damages = stats.dash_damages
					dash_timer = 0
					inv_timer = 0
					max_health = stats.max_health
					health = max_health
					card_choices = stats.card_choices
					wave = 1
					clear(&enemies)
					clear(&bullets)
					clear(&cards)
					clear(&trail)
					state = .PLAYING
				}
				raylib.BeginDrawing()
				raylib.ClearBackground(raylib.BLACK)
				draw_centered(cstring("SKILL SELECT"), 70, 50, raylib.WHITE)
				draw_centered(
					raylib.TextFormat("1)  GUN      %s", string(GUNS[gun].name)),
					180,
					30,
					raylib.YELLOW,
				)
				draw_centered(
					raylib.TextFormat("2)  DASH     %s", string(DASHES[dash_kind].name)),
					240,
					30,
					raylib.SKYBLUE,
				)
				draw_centered(
					raylib.TextFormat("3)  UTILITY  %s", string(UTILITIES[utility].name)),
					300,
					30,
					raylib.GREEN,
				)
				draw_centered(
					cstring("Press 1 / 2 / 3 to change a slot"),
					400,
					22,
					raylib.RAYWHITE,
				)
				draw_centered(cstring("Press ENTER to start"), 440, 22, raylib.GRAY)
				raylib.EndDrawing()
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
				raylib.BeginDrawing()
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
				raylib.EndDrawing()
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
				raylib.BeginDrawing()
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
				raylib.EndDrawing()
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
				raylib.BeginDrawing()
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
				raylib.EndDrawing()
			}
		case .PLAYING:
			camera.target = position + size * 0.5
			camera.offset = {400, 300}
			camera.zoom = 1
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
								unordered_remove(&enemies, i)
							}
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
			if dir != raylib.Vector2(0) && dash_timer <= 0 {
				last_dir = dir
				position += raylib.Vector2Normalize(dir) * SPEED * dT
			}
			if dash_cooldown > 0 {
				dash_cooldown -= dT
			}

			if fire_cooldown > 0 {
				fire_cooldown -= dT
			}
			if raylib.IsKeyDown(raylib.KeyboardKey.SPACE) && fire_cooldown <= 0 {
				center = position + size * 0.5 - bullet_size * 0.5
				shots := projectile_num
				// Fan shots across the gun's arc. Guns with no base spread (e.g. the
				// sniper) get an even default fan if cards add extra projectiles.
				arc := gun_spread
				if shots > 1 && GUNS[gun].spread <= 0 {
					arc = 0.12 * f32(shots - 1)
				}
				for k in 0 ..< shots {
					offset: f32 = 0
					if shots > 1 {
						offset = (f32(k) / f32(shots - 1) - 0.5) * arc
					}
					// Random inaccuracy on top of the fan so single-shot guns like
					// the SMG/MINIGUN spray a little. Precision cards shrink this.
					offset += rand.float32_range(-gun_spread, gun_spread) * 0.5
					dir := raylib.Vector2Rotate(last_dir, offset)
					append(
						&bullets,
						bullet {
							position = center,
							size = bullet_size,
							velocity = dir * BULLET_SPEED,
							damage = player_damage,
							pierce = player_pierce,
						},
					)
				}
				fire_cooldown = fire_rate
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.LEFT_SHIFT) && dash_cooldown <= 0 {
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
			if raylib.IsKeyPressed(raylib.KeyboardKey.F) {
				clear(&cards)
				spawn_cards(&cards, card_choices, gun_spread > GUNS[gun].min_spread)
			}
			if raylib.IsKeyPressed(raylib.KeyboardKey.Q) {
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
						if cards[i].name == "SPEED" {
							SPEED += 50
						} else if cards[i].name == "ATTACK" {
							player_damage += 1
						} else if cards[i].name == "HEALTH" {
							max_health += 25
							health = max_health
						} else if cards[i].name == "DASH" {
							if dash_blink {
								dash_distance += 40
							} else {
								DASH_DURATION += 0.05
							}
						} else if cards[i].name == "PROJECTILE" {
							projectile_num += 1
						} else if cards[i].name == "PRECISION" {
							gun_spread = max(GUNS[gun].min_spread, gun_spread - 0.2)
						} else if cards[i].name == "PIERCE" {
							player_pierce += 1
						}
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
				if raylib.Vector2Distance(p, position) > 800 {
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
						bullet_register_hit(&bullets[i], e.id)
						if e.hp <= 0 {
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

			for i := len(enemies) - 1; i >= 0; i -= 1 {
				e := &enemies[i]
				e_dir := raylib.Vector2Normalize(position - e.position)
				e.position += e_dir * e.speed * dT
			}

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
					}
					if health <= 0 {
						state = .GAME_OVER
					}
				}
			}

			if len(enemies) == 0 && len(cards) == 0 && (!debug_mode || wave == 1) {

				spawn_cards(&cards, card_choices, gun_spread > GUNS[gun].min_spread)
			}

			raylib.BeginDrawing()
			raylib.ClearBackground(raylib.BLACK)
			raylib.BeginMode2D(camera)
			for t in trail {
				a := u8(80 * (t.life / 0.3))
				raylib.DrawRectangleV(t.pos, size, raylib.Color{255, 0, 0, a})
			}
			raylib.DrawRectangleV(position, size, raylib.RED)
			for b in bullets {
				raylib.DrawRectangleV(b.position, b.size, raylib.YELLOW)
			}
			for e in enemies {
				raylib.DrawRectangleV(e.position, e.size, e.color)
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
			if debug_mode {
				raylib.DrawText("DEBUG", 220, 10, 20, raylib.ORANGE)
			}
			raylib.EndDrawing()

		case .GAME_OVER:
			if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) {
				position = {50, 50}
				SPEED = 200
				health = 100
				max_health = 100
				projectile_num = 1
				player_damage = 1
				wave = 1
				inv_timer = 0
				dash_timer = 0
				dash_cooldown = 0
				DASH_DURATION = 0.15
				clear(&enemies)
				clear(&bullets)
				clear(&cards)
				clear(&trail)
				state = .MAIN_MENU
			}
			raylib.BeginDrawing()
			raylib.ClearBackground(raylib.BLACK)
			game_over := cstring("GAME OVER")
			gw := raylib.MeasureText(game_over, 60)
			raylib.DrawText(game_over, 400 - gw / 2, 200, 60, raylib.RED)
			prompt := cstring("Press ENTER to restart")
			pw := raylib.MeasureText(prompt, 25)
			raylib.DrawText(prompt, 400 - pw / 2, 300, 25, raylib.GRAY)
			raylib.EndDrawing()
		}
	}
}
