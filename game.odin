package main
import "core:math/rand"
import "vendor:raylib"

// ---------------------------------------------------------------------------
// Arena / tuning constants
// ---------------------------------------------------------------------------

ARENA_W :: 1600
ARENA_H :: 1200
WALL_THICK :: 40
RELOAD_TIME :: 1.0
MELEE_COOLDOWN_MAX :: 0.4
MELEE_DAMAGE :: 2
MELEE_RANGE :: 92 // how far the kick reaches (px)
MELEE_ARC :: 0.7 // half-angle of the swing (radians)
MELEE_KNOCKBACK :: 100 // instant shove applied to anything kicked
EXPLOSION_RADIUS :: 130
EXPLOSION_DAMAGE :: 6
EXPLOSION_TIME :: 0.35

// Player upgrade ceilings. Once a card would push a stat past its cap it stops
// being offered, so runs plateau instead of snowballing forever.
MAX_SPEED :: 450
MAX_BONUS_DAMAGE :: 6
MAX_BONUS_PROJECTILES :: 4
MAX_BONUS_PIERCE :: 3

// Enemies get tougher, hit harder and move a little faster every wave, so the
// difficulty curve keeps up with the player's upgrades.
ENEMY_HP_PER_WAVE :: 0.16
ENEMY_DMG_PER_WAVE :: 0.06
ENEMY_SPEED_PER_WAVE :: 0.02
ENEMY_SPEED_CAP :: 1.4

// Elite variants: rare early, more common later. Beefier, angrier, richer.
ELITE_BASE_CHANCE :: 0.03
ELITE_CHANCE_PER_WAVE :: 0.01
ELITE_CHANCE_CAP :: 0.20
ELITE_HP_MULT :: 2.5
ELITE_DMG_MULT :: 1.6
ELITE_SPEED_MULT :: 1.1
ELITE_SIZE_MULT :: 1.3

// Shop: how many offers are stocked, and the reroll limit/cost curve.
SHOP_OFFER_COUNT :: 3
SHOP_MAX_REROLLS :: 2
SHOP_REROLL_BASE_COST :: 15

// ---------------------------------------------------------------------------
// Run state
//
// These used to be locals inside `main`. They're package-level now so that
// `start_run` / `end_run` (and the update helpers below) can reach them.
// ---------------------------------------------------------------------------

state: GameState = .MAIN_MENU
debug_mode: bool = false
skill_state: SkillSlotState = .MAIN_SCREEN

// Player.
position: raylib.Vector2 = {50, 50}
size: raylib.Vector2 = {30, 30}
health: f32 = 100
max_health: f32 = 100
inv_timer: f32 = 0
last_dir: raylib.Vector2 = {0, -1} // last movement direction (used by dashes)
aim_dir: raylib.Vector2 = {0, -1} // points at the mouse cursor
SPEED: f32 = 200

// Weapons. Each slot keeps its own mag/ammo; active_slot picks which one fires.
gun: Gun = .SNIPER
secondary_kind: Secondary = .PISTOL
primary: weapon
secondary: weapon
active_slot: int = 0 // 0 = primary, 1 = secondary

// Card upgrades. These apply to whichever weapon is active at fire time.
bonus_damage: f32 = 0
bonus_projectiles: i32 = 0
bonus_pierce: i32 = 0
spread_cut: f32 = 0

// Melee.
melee_cooldown: f32 = 0
melee_flash: f32 = 0

// Dash.
dash_kind: Dash_Kind = .BURST
dash_timer: f32 = 0
DASH_SPEED: f32 = 800
DASH_DURATION: f32 = 0.15
dash_cooldown: f32 = 0
dash_cooldown_max: f32 = 0.5
dash_blink: bool = false
dash_distance: f32 = 0
dash_damages: bool = false

// Progression.
wave: i32 = 1
card_choices: int = 3
utility: Utility = .VITALITY
currency: i32 = 0

// Shop.
shop_items: [dynamic]shop_item
shop_selected: int = 0
shop_rerolls_used: i32 = 0

// Entities.
enemies: [dynamic]enemy
bullets: [dynamic]bullet
enemy_bullets: [dynamic]bullet
cards: [dynamic]card
trail: [dynamic]trail_point
drops: [dynamic]drop
walls: [dynamic]raylib.Rectangle
barrels: [dynamic]barrel
trees: [dynamic]tree
explosions: [dynamic]explosion

// Start a fresh run from a chosen loadout: resets every run variable, rebuilds
// the arena, and drops you into PLAYING.
start_run :: proc(stats: Run_Stats) {
	position = {f32(ARENA_W) / 2 - size.x / 2, f32(ARENA_H) / 2 - size.y / 2}
	SPEED = stats.speed
	gun = stats.primary
	secondary_kind = stats.secondary
	weapon_init(&primary, GUNS[stats.primary])
	weapon_init(&secondary, SECONDARIES[stats.secondary])
	active_slot = 0
	bonus_damage = 0
	bonus_projectiles = 0
	bonus_pierce = 0
	spread_cut = 0
	melee_cooldown = 0
	melee_flash = 0
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
	currency = 0
	shop_selected = 0
	shop_rerolls_used = 0
	last_dir = {0, -1}
	aim_dir = {0, -1}
	clear_run_entities()
	build_arena()
	state = .PLAYING
}

// Give a weapon slot its starting mag/reserve from its stat block.
weapon_init :: proc(w: ^weapon, g: Gun_Stats) {
	w.mag = g.magazine_capacity
	w.ammo = g.ammo_capacity
	w.ammo_cap = g.ammo_capacity
	w.mag_cap = g.magazine_capacity
	w.reload = 0
	w.cooldown = 0
}

active_weapon :: proc() -> ^weapon {
	return active_slot == 1 ? &secondary : &primary
}

active_stats :: proc() -> Gun_Stats {
	return active_slot == 1 ? SECONDARIES[secondary_kind] : GUNS[gun]
}

// PRECISION is only a useful offer while the active weapon still has spread to
// cut (i.e. it hasn't been clamped down to its min_spread yet).
precision_is_useful :: proc() -> bool {
	s := active_stats()
	return spread_cut < s.spread - s.min_spread
}

// Top both slots back up (used by the shop's ammo refill).
refill_weapon_ammo :: proc(w: ^weapon) {
	w.ammo = w.ammo_cap
	w.mag = w.mag_cap
	w.reload = 0
}

// Advance one weapon's fire cooldown + reload. Ticked for *both* slots so
// swapping weapons can't be used to dodge a cooldown or stall a reload.
weapon_tick :: proc(w: ^weapon, dT: f32) {
	if w.cooldown > 0 {
		w.cooldown -= dT
	}
	if w.reload > 0 {
		w.reload -= dT
		if w.reload <= 0 {
			refill := min(w.mag_cap - w.mag, w.ammo)
			w.mag += refill
			w.ammo -= refill
		}
	}
}

// Clear every spawned entity (enemies, projectiles, pickups, props effects).
clear_run_entities :: proc() {
	clear(&enemies)
	clear(&bullets)
	clear(&enemy_bullets)
	clear(&cards)
	clear(&trail)
	clear(&drops)
	clear(&explosions)
	clear(&shop_items)
}

// Tear the run down and return to the main menu (used on death).
end_run :: proc() {
	clear_run_entities()
	state = .MAIN_MENU
}

// ---------------------------------------------------------------------------
// Enemies
// ---------------------------------------------------------------------------

next_enemy_id: i32 = 1

// Later waves unlock tougher enemy kinds. Thresholds are cumulative so each
// kind keeps a stable share once it's unlocked.
pick_enemy_kind :: proc(wave: i32) -> Enemy_Kind {
	roll := rand.float32()
	if wave >= 2 && roll < 0.30 {
		return .RANGED
	}
	if wave >= 3 && roll < 0.65 {
		return .RUNNER
	}
	if wave >= 4 && roll < 0.80 {
		return .CHARGER
	}
	if wave >= 5 && roll < 0.90 {
		return .TANK
	}
	return .GRUNT
}

// Is there room for a box of `sz` at top-left `p`? Checks walls and props so we
// never drop an enemy inside geometry.
box_blocked :: proc(p: raylib.Vector2, sz: raylib.Vector2) -> bool {
	r := raylib.Rectangle{p.x, p.y, sz.x, sz.y}
	for w in walls {
		if raylib.CheckCollisionRecs(r, w) {
			return true
		}
	}
	for b in barrels {
		if raylib.CheckCollisionRecs(r, {b.pos.x, b.pos.y, b.size.x, b.size.y}) {
			return true
		}
	}
	for t in trees {
		if raylib.CheckCollisionRecs(r, {t.pos.x, t.pos.y, t.size.x, t.size.y}) {
			return true
		}
	}
	return false
}

random_spawn_pos :: proc(sz: raylib.Vector2) -> raylib.Vector2 {
	lo_x := ARENA_W / 8
	hi_x := ARENA_W - ARENA_W / 8
	lo_y := ARENA_H / 8
	hi_y := ARENA_H - ARENA_H / 8
	for _ in 0 ..< 40 {
		p := raylib.Vector2{f32(rand.int_range(lo_x, hi_x)), f32(rand.int_range(lo_y, hi_y))}
		ec := p + sz * 0.5
		pc := position + size * 0.5
		// Don't spawn right on top of the player.
		if raylib.Vector2Distance(ec, pc) < 320 {
			continue
		}
		if box_blocked(p, sz) {
			continue
		}
		return p
	}
	return raylib.Vector2{f32(ARENA_W) * 0.5, f32(WALL_THICK) + 40}
}

spawn_enemies :: proc(enemies: ^[dynamic]enemy, num: i32, wave: i32) {
	hp_scale := 1 + ENEMY_HP_PER_WAVE * f32(wave - 1)
	dmg_scale := 1 + ENEMY_DMG_PER_WAVE * f32(wave - 1)
	spd_scale := min(1 + ENEMY_SPEED_PER_WAVE * f32(wave - 1), f32(ENEMY_SPEED_CAP))
	elite_chance := min(
		ELITE_BASE_CHANCE + ELITE_CHANCE_PER_WAVE * f32(wave - 1),
		f32(ELITE_CHANCE_CAP),
	)

	for _ in 0 ..< num {
		kind := pick_enemy_kind(wave)
		s := ENEMIES[kind]
		elite := wave >= 2 && rand.float32() < elite_chance

		sz := s.size
		hp := s.hp * hp_scale
		damage := s.damage * dmg_scale
		speed := s.speed * spd_scale
		if elite {
			sz *= ELITE_SIZE_MULT
			hp *= ELITE_HP_MULT
			damage *= ELITE_DMG_MULT
			speed *= ELITE_SPEED_MULT
		}

		append(
			enemies,
			enemy {
				position = random_spawn_pos(sz),
				size = sz,
				velocity = {0, 0},
				attacking = false,
				color = s.color,
				damage = damage,
				hp = hp,
				max_hp = hp,
				id = next_enemy_id,
				speed = speed,
				kind = kind,
				state = .CHASE,
				elite = elite,
			},
		)
		next_enemy_id += 1
	}
}

new_wave :: proc(enemies: ^[dynamic]enemy, wave: i32) {
	play(sounds.wave_start)
	spawn_enemies(enemies, wave, wave)
}

// Per-enemy steering. Movement is applied here; wall collision is resolved
// afterwards in the update loop.
update_enemy :: proc(e: ^enemy, dT: f32) {
	s := ENEMIES[e.kind]
	pc := position + size * 0.5
	ec := e.position + e.size * 0.5
	to := pc - ec
	dist := raylib.Vector2Length(to)
	dir: raylib.Vector2 = {0, 0}
	if dist > 0.01 {
		dir = to / dist
	}

	switch e.kind {
	case .GRUNT, .TANK:
		e.position += dir * e.speed * dT

	case .RUNNER:
		// Fast, with a little zig-zag so they're harder to line up.
		perp := raylib.Vector2{-dir.y, dir.x}
		osc := rand.float32_range(-0.5, 0.5)
		e.position += (dir + perp * osc) * e.speed * dT

	case .RANGED:
		e.fire_cooldown -= dT
		if dist > s.preferred_range + 50 {
			e.position += dir * e.speed * dT
		} else if dist < s.preferred_range - 50 {
			e.position -= dir * e.speed * dT
		} else {
			// Hover and strafe.
			perp := raylib.Vector2{-dir.y, dir.x}
			side: f32 = e.id % 2 == 0 ? 1.0 : -1.0
			e.position += perp * e.speed * 0.7 * dT * side
		}
		if e.fire_cooldown <= 0 && dist < s.preferred_range + 140 {
			append(
				&enemy_bullets,
				bullet {
					position = ec - {5, 5},
					size = {10, 10},
					velocity = dir * 260,
					damage = s.damage,
					pierce = 0,
				},
			)
			e.fire_cooldown = s.fire_rate
		}

	case .CHARGER:
		e.state_timer -= dT
		#partial switch e.state {
		case .CHASE:
			e.position += dir * e.speed * dT
			if dist < 340 {
				e.state = .WINDUP
				e.state_timer = 0.45
			}
		case .WINDUP:
			if e.state_timer <= 0 {
				e.state = .CHARGE
				e.state_timer = 0.30
				e.charge_dir = dir
			}
		case .CHARGE:
			e.position += e.charge_dir * s.charge_speed * dT
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = 0.6
			}
		case .RECOVER:
			if e.state_timer <= 0 {
				e.state = .CHASE
			}
		}
	}
}

// Soft body separation: overlapping enemies push each other apart instead of
// stacking into a single blob.
separate_enemies :: proc() {
	for i in 0 ..< len(enemies) {
		for j in i + 1 ..< len(enemies) {
			a := &enemies[i]
			b := &enemies[j]
			ac := a.position + a.size * 0.5
			bc := b.position + b.size * 0.5
			d := ac - bc
			dist := raylib.Vector2Length(d)
			min_dist := (a.size.x + b.size.x) * 0.5
			if dist > 0.01 && dist < min_dist {
				push := (min_dist - dist) * 0.5
				n := d / dist
				a.position += n * push
				b.position -= n * push
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Bullets
// ---------------------------------------------------------------------------

// Pierce support: bullets remember which enemies they've already damaged so a
// single shot doesn't hit the same enemy twice as it passes through.
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

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

build_arena :: proc() {
	clear(&walls)
	clear(&barrels)
	clear(&trees)

	t := f32(WALL_THICK)
	// Border.
	append(&walls, raylib.Rectangle{0, 0, ARENA_W, t})
	append(&walls, raylib.Rectangle{0, ARENA_H - t, ARENA_W, t})
	append(&walls, raylib.Rectangle{0, 0, t, ARENA_H})
	append(&walls, raylib.Rectangle{ARENA_W - t, 0, t, ARENA_H})

	// Interior cover.
	append(&walls, raylib.Rectangle{300, 220, 220, 40})
	append(&walls, raylib.Rectangle{1080, 220, 220, 40})
	append(&walls, raylib.Rectangle{300, 940, 220, 40})
	append(&walls, raylib.Rectangle{1080, 940, 220, 40})
	append(&walls, raylib.Rectangle{760, 260, 80, 220})
	append(&walls, raylib.Rectangle{760, 720, 80, 220})
	append(&walls, raylib.Rectangle{480, 560, 220, 80})
	append(&walls, raylib.Rectangle{900, 560, 220, 80})

	// Trees: round static cover.
	tree_spots := [?]raylib.Vector2 {
		{250, 600},
		{1350, 600},
		{800, 190},
		{800, 1010},
		{560, 380},
		{1040, 380},
		{560, 820},
		{1040, 820},
	}
	for p in tree_spots {
		append(&trees, tree{pos = {p.x - 22, p.y - 22}, size = {44, 44}})
	}

	// Explosive barrels.
	barrel_spots := [?]raylib.Vector2 {
		{600, 300},
		{1000, 300},
		{600, 900},
		{1000, 900},
		{400, 600},
		{1200, 600},
	}
	for p in barrel_spots {
		append(&barrels, barrel{pos = {p.x - 16, p.y - 16}, size = {32, 32}, hp = 6})
	}
}

// Push an AABB out of every wall/prop it overlaps, along the shallowest axis.
resolve_obstacles :: proc(pos: ^raylib.Vector2, sz: raylib.Vector2) {
	for w in walls {
		resolve_against_rect(pos, sz, w)
	}
	for b in barrels {
		resolve_against_rect(pos, sz, {b.pos.x, b.pos.y, b.size.x, b.size.y})
	}
	for t in trees {
		resolve_against_rect(pos, sz, {t.pos.x, t.pos.y, t.size.x, t.size.y})
	}
}

resolve_against_rect :: proc(pos: ^raylib.Vector2, sz: raylib.Vector2, r: raylib.Rectangle) {
	if !raylib.CheckCollisionRecs({pos.x, pos.y, sz.x, sz.y}, r) {
		return
	}
	dx_left := (pos.x + sz.x) - r.x
	dx_right := (r.x + r.width) - pos.x
	dy_top := (pos.y + sz.y) - r.y
	dy_bottom := (r.y + r.height) - pos.y
	ox := min(dx_left, dx_right)
	oy := min(dy_top, dy_bottom)
	if ox < oy {
		if dx_left < dx_right {
			pos.x -= ox
		} else {
			pos.x += ox
		}
	} else {
		if dy_top < dy_bottom {
			pos.y -= oy
		} else {
			pos.y += oy
		}
	}
}

// Walls and trees are solid to projectiles (barrels are handled separately so
// they can soak a hit and take damage).
bullet_blocked_by_terrain :: proc(rect: raylib.Rectangle) -> bool {
	for w in walls {
		if raylib.CheckCollisionRecs(rect, w) {
			return true
		}
	}
	for t in trees {
		if raylib.CheckCollisionRecs(rect, {t.pos.x, t.pos.y, t.size.x, t.size.y}) {
			return true
		}
	}
	return false
}

// Blow up at `center`: hurt nearby enemies (with a shove), the player, and
// chain into any other barrels caught in the blast.
explode_at :: proc(center: raylib.Vector2) {
	play(sounds.explosion)
	append(&explosions, explosion{pos = center, life = EXPLOSION_TIME})

	for i := len(enemies) - 1; i >= 0; i -= 1 {
		ec := enemies[i].position + enemies[i].size * 0.5
		if raylib.Vector2Distance(ec, center) <= EXPLOSION_RADIUS {
			enemies[i].hp -= EXPLOSION_DAMAGE
			d := ec - center
			if raylib.Vector2Length(d) > 0.01 {
				enemies[i].position += raylib.Vector2Normalize(d) * 24
			}
			if enemies[i].hp <= 0 {
				spawn_kill_rewards(enemies[i].position, enemies[i].elite)
				unordered_remove(&enemies, i)
			}
		}
	}

	pc := position + size * 0.5
	if raylib.Vector2Distance(pc, center) <= EXPLOSION_RADIUS && inv_timer <= 0 {
		health -= EXPLOSION_DAMAGE
		inv_timer = 0.5
	}

	for i := len(barrels) - 1; i >= 0; i -= 1 {
		bc := barrels[i].pos + barrels[i].size * 0.5
		if raylib.Vector2Distance(bc, center) <= EXPLOSION_RADIUS {
			barrels[i].hp -= EXPLOSION_DAMAGE
		}
	}
}

// ---------------------------------------------------------------------------
// Drops
// ---------------------------------------------------------------------------

// Enemies occasionally drop a small heal. Call right before removing an enemy.
try_spawn_health_drop :: proc(pos: raylib.Vector2, drops: ^[dynamic]drop) {
	if rand.float32() < 0.08 {
		append(
			drops,
			drop{position = pos, size = {12, 12}, kind = .HEALTH, amount = 20, life = 8.0},
		)
	}
}

// Ammo was starving runs, so it drops more often and in bigger bundles now.
try_spawn_ammo_drop :: proc(pos: raylib.Vector2, drops: ^[dynamic]drop) {
	if rand.float32() < 0.16 {
		append(drops, drop{position = pos, size = {12, 12}, kind = .AMMO, amount = 8, life = 8.0})
	}
}

// Coins are the common drop; spend them in the shop every 5 waves. Kept
// deliberately stingy so a big wave of enemies can't flood the run with cash.
try_spawn_currency_drop :: proc(pos: raylib.Vector2, drops: ^[dynamic]drop) {
	if rand.float32() < 0.5 {
		amount := f32(rand.int_range(2, 5)) // 2..4 coins
		append(
			drops,
			drop{position = pos, size = {10, 10}, kind = .CURRENCY, amount = amount, life = 8.0},
		)
	}
}

// Standard rewards for killing something. Call right before removing an enemy.
// Elites leave a guaranteed pile of coins on top of the usual rolls.
spawn_kill_rewards :: proc(pos: raylib.Vector2, elite := false) {
	play(sounds.enemy_die, rand.float32_range(0.92, 1.08))
	if elite {
		append(
			&drops,
			drop {
				position = pos,
				size = {13, 13},
				kind = .CURRENCY,
				amount = f32(rand.int_range(10, 18)),
				life = 8.0,
			},
		)
	}
	try_spawn_health_drop(pos, &drops)
	try_spawn_ammo_drop(pos, &drops)
	try_spawn_currency_drop(pos, &drops)
}

// ---------------------------------------------------------------------------
// Upgrades / shop
// ---------------------------------------------------------------------------

// Apply one upgrade card by name. Shared by the between-wave card pick and the
// shop's "mystery upgrade" so the two never drift apart.
apply_upgrade :: proc(name: cstring) {
	if name == "SPEED" {
		SPEED = min(SPEED + 50, f32(MAX_SPEED))
	} else if name == "ATTACK" {
		bonus_damage = min(bonus_damage + 1, f32(MAX_BONUS_DAMAGE))
	} else if name == "HEALTH" {
		max_health += 25
		health = max_health
	} else if name == "DASH" {
		if dash_blink {
			dash_distance += 40
		} else {
			DASH_DURATION += 0.05
		}
	} else if name == "PROJECTILE" {
		bonus_projectiles = min(bonus_projectiles + 1, MAX_BONUS_PROJECTILES)
	} else if name == "PRECISION" {
		spread_cut += 0.2
	} else if name == "PIERCE" {
		bonus_pierce = min(bonus_pierce + 1, MAX_BONUS_PIERCE)
	}
}

// Would this upgrade actually do anything right now? Capped stats report false so
// they can be filtered out of card deals and shop stock.
upgrade_is_useful :: proc(name: cstring) -> bool {
	switch name {
	case "SPEED":
		return SPEED < f32(MAX_SPEED)
	case "ATTACK":
		return bonus_damage < f32(MAX_BONUS_DAMAGE)
	case "PROJECTILE":
		return bonus_projectiles < MAX_BONUS_PROJECTILES
	case "PIERCE":
		return bonus_pierce < MAX_BONUS_PIERCE
	case "PRECISION":
		return precision_is_useful()
	}
	return true // HEALTH, DASH, etc. always have room
}

apply_random_upgrade :: proc() {
	// Roll from the upgrades that still have room, so a mystery crate can't
	// hand out a capped stat.
	pool: [dynamic]card_definition
	defer delete(pool)
	for c in CARD_POOL {
		if upgrade_is_useful(c.name) {
			append(&pool, c)
		}
	}
	if len(pool) == 0 {
		apply_upgrade("HEALTH")
		return
	}
	apply_upgrade(pool[rand.int_range(0, len(pool))].name)
}

// How often each rarity shows up in a stocked shop.
shop_tier_weight :: proc(tier: Shop_Tier) -> int {
	switch tier {
	case .COMMON:
		return 6
	case .RARE:
		return 3
	case .EPIC:
		return 1
	}
	return 1
}

shop_tier_color :: proc(tier: Shop_Tier) -> raylib.Color {
	switch tier {
	case .COMMON:
		return raylib.RAYWHITE
	case .RARE:
		return raylib.SKYBLUE
	case .EPIC:
		return raylib.VIOLET
	}
	return raylib.RAYWHITE
}

// Weighted roll of one offer from SHOP_POOL.
pick_shop_definition :: proc() -> shop_definition {
	total := 0
	for d in SHOP_POOL {
		total += shop_tier_weight(d.tier)
	}
	roll := rand.int_range(0, total)
	acc := 0
	for d in SHOP_POOL {
		acc += shop_tier_weight(d.tier)
		if roll < acc {
			return d
		}
	}
	return SHOP_POOL[0]
}

// Deal a fresh set of distinct offers into `shop_items`.
stock_shop :: proc() {
	clear(&shop_items)
	for tries := 0; len(shop_items) < SHOP_OFFER_COUNT && tries < 200; tries += 1 {
		d := pick_shop_definition()
		// Don't offer an upgrade the player can no longer benefit from.
		if d.kind == .UPGRADE && !upgrade_is_useful(d.upgrade) {
			continue
		}
		duplicate := false
		for it in shop_items {
			if it.name == d.name {
				duplicate = true
				break
			}
		}
		if duplicate {
			continue
		}
		append(&shop_items, shop_item{d.name, d.desc, d.cost, d.kind, d.upgrade, d.tier, false})
	}
}

// Cost of the next reroll; rises with each reroll already spent this visit.
shop_reroll_cost :: proc() -> i32 {
	return SHOP_REROLL_BASE_COST * (shop_rerolls_used + 1)
}

// Called once when the shop opens.
build_shop :: proc() {
	shop_selected = 0
	shop_rerolls_used = 0
	stock_shop()
}

// Reroll the offers. Returns false (and costs nothing) if out of rerolls or cash.
try_shop_reroll :: proc() -> bool {
	if shop_rerolls_used >= SHOP_MAX_REROLLS {
		return false
	}
	cost := shop_reroll_cost()
	if currency < cost {
		return false
	}
	currency -= cost
	shop_rerolls_used += 1
	shop_selected = 0
	stock_shop()
	return true
}

// Returns true if the purchase went through.
buy_shop_item :: proc(idx: int) -> bool {
	if idx < 0 || idx >= len(shop_items) {
		return false
	}
	it := &shop_items[idx]
	if it.sold || currency < it.cost {
		return false
	}
	currency -= it.cost
	switch it.kind {
	case .AMMO:
		refill_weapon_ammo(&primary)
		refill_weapon_ammo(&secondary)
	case .HEAL:
		health = max_health
	case .MAX_HP:
		max_health += 25
		health += 25
	case .UPGRADE:
		if it.upgrade == "RANDOM" {
			apply_random_upgrade()
		} else {
			apply_upgrade(it.upgrade)
		}
	}
	it.sold = true
	return true
}

// ---------------------------------------------------------------------------
// Cards
// ---------------------------------------------------------------------------

spawn_cards :: proc(cards: ^[dynamic]card, count := 3) {
	CARD_W: f32 = 120
	CARD_H: f32 = 160
	spacing: f32 = CARD_W + 40
	center_x := f32(800) / 2
	y := f32(600) / 2 - CARD_H / 2

	// Build the deal pool, dropping cards whose stat is already capped.
	pool: [dynamic]card_definition
	defer delete(pool)
	for c in CARD_POOL {
		if !upgrade_is_useful(c.name) {
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

// ---------------------------------------------------------------------------
// Loadout
// ---------------------------------------------------------------------------

start_loadout :: proc(
	primary: Gun,
	secondary: Secondary,
	dash: Dash_Kind,
	utility: Utility,
) -> Run_Stats {
	d := DASHES[dash]
	stats := Run_Stats {
		speed         = 200,
		primary       = primary,
		secondary     = secondary,
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

// ---------------------------------------------------------------------------
// UI helpers
// ---------------------------------------------------------------------------

// Direct-pick keys used on the skill-select option screens (1-9).
NUMBER_KEYS := [9]raylib.KeyboardKey{.ONE, .TWO, .THREE, .FOUR, .FIVE, .SIX, .SEVEN, .EIGHT, .NINE}

draw_centered :: proc(text: cstring, y, size: i32, color: raylib.Color) {
	width := raylib.MeasureText(text, size)
	raylib.DrawText(text, 400 - width / 2, y, size, color)
}

skill_screen_draw :: proc(selected_skill: cstring) {

}
