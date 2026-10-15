package main
import "core:math"
import "core:math/rand"
import "vendor:raylib"

// ---------------------------------------------------------------------------
// Arena / tuning constants
// ---------------------------------------------------------------------------

ARENA_W :: 1600
ARENA_H :: 1200
WALL_THICK :: 40
RELOAD_TIME :: 1.0
MELEE_FLASH_TIME :: 0.15 // how long the swing arc is shown after a melee hit
BASE_DASH_DAMAGE :: 30 // damage per second dealt by a damaging dash

// Characters. Every main character has a signature passive; the numeric knobs
// for each live here, and the dash "synergies" are folded in by start_loadout.
TRACER_WEIGHT_PENALTY :: 0.14 // move speed lost per point of active-weapon weight
TRACER_MIN_SPEED_MULT :: 0.55 // Tracer never drops below this fraction of SPEED
// Traceur's Heart: every attack spins her up, and her speed decays when idle.
TRACEUR_PER_ATTACK :: 0.12 // charge added per shot/swing (0..1)
TRACEUR_DECAY :: 0.35 // charge lost per second while not attacking
TRACEUR_MAX_BONUS :: 0.50 // speed bonus at full charge (+50% of her speed stat)
// Synergy: Tracer <-> SLIDE ("Power Slide"). Sliding is her signature; it's
// faster, cheaper and refreshes Traceur's Heart so a slide into a fight keeps
// her momentum.
TRACER_SLIDE_SPEED_MULT :: 1.35
TRACER_SLIDE_CD_MULT :: 0.75
TRACER_SLIDE_TIME_MULT :: 1.30 // slides linger longer (more distance + damage)
TRACER_PHASE_DURATION_MULT :: 1.70
TRACER_PHASE_CD_MULT :: 0.80
// Synergy: Bud <-> IMPACT ("Meteor"). His impact dash hits far harder and knocks
// enemies flying, turning a dash into his main engage tool.
BUD_IMPACT_DAMAGE_MULT :: 2.40
BUD_IMPACT_KNOCK :: 1100 // px/s shove applied to enemies a Bud impact hits
// Bud's "Guard Up" passive: he takes less damage from whatever he faces. Face
// an incoming hit (aim that way) and it is blunted.
BUD_GUARD_ARC :: 0.95 // half-angle of the guard cone around his facing
BUD_GUARD_REDUCTION :: 0.25 // damage shaved off hits arriving inside it
// Bud's "Unhappy" passive: holding a gun (not a melee weapon) leaves him
// miserable, halving his accuracy, attack power and move speed.
BUD_UNHAPPY_SPREAD_MULT :: 2.0 // accuracy halved -> spread doubled
BUD_UNHAPPY_MIN_SPREAD :: 0.14 // floor so even pinpoint guns lose accuracy
BUD_UNHAPPY_DAMAGE_MULT :: 0.5
BUD_UNHAPPY_SPEED_MULT :: 0.5
// Bud's Fists combo: press E again within this window to chain the next strike.
BUD_COMBO_WINDOW :: 0.55
// Navy's "Take Aim": no move input at all gives complete accuracy (spread 0).
// Synergy: Navy <-> BLINK. His redeploy blink goes further, comes back sooner,
// and instantly finishes a reload so he lands topped up.
NAVY_BLINK_DISTANCE_MULT :: 1.50
NAVY_BLINK_CD_MULT :: 0.75
// RR's "Adaptation": his strongest stat gets a reinforcing bonus. Recomputed
// live, so his playstyle tracks whatever the run has invested in.
RR_ADAPT_OFFENSE :: 0.20 // +20% damage (guns + melee)
RR_ADAPT_MOBILITY :: 0.15 // +15% move speed
RR_ADAPT_RESILIENCE :: 0.20 // -20% damage taken
RR_ADAPT_PRECISION :: 0.40 // -40% spread
// Synergy: RR <-> BURST. The all-rounder's dash comes back sooner, and for a
// short "Second Wind" it amplifies whichever Adaptation he is currently on.
RR_BURST_CD_MULT :: 0.75
RR_SURGE_TIME :: 1.60
RR_SURGE_EXTRA :: 0.50 // surge makes the active adaptation 50% stronger
EXPLOSION_RADIUS :: 130
EXPLOSION_DAMAGE :: 6
EXPLOSION_TIME :: 0.35

// Player upgrade ceilings. Once a card would push a stat past its cap it stops
// being offered, so runs plateau instead of snowballing forever.
MAX_SPEED :: 450
MAX_BONUS_DAMAGE :: 6
MAX_BONUS_PROJECTILES :: 4
MAX_BONUS_PIERCE :: 3
// Melee / handling ups. Melee has its own damage, swing speed, reach and knock
// so a fists-and-blades build can scale without touching guns.
MAX_BONUS_MELEE_DAMAGE :: 8
MIN_MELEE_CD_MULT :: 0.40 // swing speed cap (lower = faster)
MAX_MELEE_RANGE_MULT :: 2.0
MAX_BONUS_MELEE_KNOCK :: 400
MIN_RELOAD_MULT :: 0.35 // reload time cap as a fraction of base
MIN_DASH_CD_MULT :: 0.40
MAX_MAG_MULT :: 3.0
MAX_AMMO_MULT :: 4.0
MAX_LIFESTEAL :: 12

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

// Crystalized-elite behaviors. Every elite is a corrupted variant with its own
// trick: GRUNT devours grunts, RUNNER zig-zag dashes, TANK wears directional
// crystal plates, RANGED throws boomerang shards, CHARGER phases through terrain.
// Must exceed `separate_enemies`' minimum spacing or a meal is unreachable: a
// Devourer is ELITE_SIZE_MULT grunts wide, so it can only ever get
// (65 + 50) / 2 = 57.5px from a grunt's center. This leaves a little slack.
ELITE_DEVOUR_RANGE :: 84 // GRUNT: how close a grunt must be to be eaten
ELITE_DEVOUR_HEAL :: 0.20 // fraction of max hp restored per meal
ELITE_DEVOUR_COOLDOWN :: 3.0 // seconds between meals
ELITE_DEVOUR_LURE :: 160 // GRUNT drifts toward a grunt within this range
ELITE_DASH_COUNT :: 4 // RUNNER: zig-zag dashes per burst
ELITE_DASH_SPEED :: 640 // px/s while dashing
ELITE_DASH_TIME :: 0.12 // seconds per dash
ELITE_DASH_ZIGZAG :: 0.55 // sideways bias per dash (alternates)
ELITE_DASH_CYCLE :: 1.8 // seconds of stalking between bursts
ELITE_BOOMERANG_RANGE :: 320 // RANGED: shard outbound distance before it turns
ELITE_BOOMERANG_SPEED :: 300
ELITE_TANK_PLATES :: 3 // TANK: directional plates to shatter before hp is exposed
ELITE_PLATE_ARC :: 0.70 // half-angle (radians) a hit must fall within to crack a plate

// Shop: how many offers are stocked, and the reroll limit/cost curve.
SHOP_OFFER_COUNT :: 3
SHOP_MAX_REROLLS :: 2
SHOP_REROLL_BASE_COST :: 15

// Starting utilities picked on the loadout screen. These are the raw bonuses
// `start_loadout` folds into Run_Stats.
UTIL_MAX_HEALTH :: 25
UTIL_SPEED :: 50
UTIL_DAMAGE :: 1
UTIL_SPREAD_CUT :: 0.2
UTIL_DASH_CD_MULT :: 0.7 // SCOUT multiplies dash cooldown by this
UTIL_AMMO_MULT :: 1.5 // PACKRAT scales both weapons' reserve capacity

// ---------------------------------------------------------------------------
// Run state
//
// These used to be locals inside `main`. They're package-level now so that
// `start_run` / `end_run` (and the update helpers below) can reach them.
// ---------------------------------------------------------------------------

state: GameState = .MAIN_MENU
debug_mode: bool = false
skill_state: SkillSlotState = .MAIN

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
ammo_mult: f32 = 1 // reserve-capacity scale from the chosen utility

// Card upgrades. These apply to whichever weapon is active at fire time.
bonus_damage: f32 = 0
bonus_projectiles: i32 = 0
bonus_pierce: i32 = 0
spread_cut: f32 = 0

// Melee / handling upgrades, fed by their own cards and shop offers.
bonus_melee_damage: f32 = 0 // extra damage on every melee swing
melee_speed_mult: f32 = 1 // multiplies swing cooldowns (lower = faster)
melee_range_mult: f32 = 1 // multiplies melee reach
bonus_melee_knock: f32 = 0 // extra shove on melee hits
lifesteal: f32 = 0 // HP healed per enemy killed
mag_mult: f32 = 1 // magazine-size scale (applied live to both slots)
ammo_growth_mult: f32 = 1 // reserve-ammo scale (applied live to both slots)

// Melee. Swing stats come from the active weapon, the KICK, or Bud's FISTS;
// `melee_cooldown` is the universal swing timer. The flash fields remember the
// last swing (direction + shape + size + colour) so the drawn flash uses the
// exact same geometry the hit test did.
melee_cooldown: f32 = 0
melee_flash: f32 = 0
melee_flash_range: f32 = 92
melee_flash_arc: f32 = 0.7
melee_flash_dir: raylib.Vector2 = {0, -1}
melee_flash_shape: Melee_Shape = .SECTOR
melee_flash_color: raylib.Color = {255, 255, 255, 255}
// Bud's Fists combo: which strike is next, and how long the chain stays open.
combo_index: int = 0
combo_timer: f32 = 0

// Dash.
dash_kind: Dash_Kind = .BURST
dash_timer: f32 = 0
DASH_SPEED: f32 = 800
DASH_DURATION: f32 = 0.15
dash_cooldown: f32 = 0
dash_cooldown_max: f32 = 0.5
dash_cooldown_base: f32 = 0.5 // post-synergy cooldown, floor for DASHCD cards
dash_blink: bool = false
dash_distance: f32 = 0
dash_damages: bool = false
dash_damage: f32 = BASE_DASH_DAMAGE
reload_time: f32 = RELOAD_TIME // Navy reloads faster; set from Run_Stats
reload_time_base: f32 = RELOAD_TIME // RELOAD card floors against this

// Chosen main character. Drives the body silhouette, melee scaling, and traits.
character: Character = .RR
// Per-character passive state.
moving: bool = false // is the player giving move input this frame?
traceur_charge: f32 = 0 // Traceur's Heart 0..1 (built by attacking)
rr_adaptation: RR_Adaptation = .OFFENSE // RR's Adaptation, recomputed each frame
rr_surge: f32 = 0 // RR's Second Wind timer (dashing amplifies his adaptation)

// Progression.
wave: i32 = 1
card_choices: int = 3
utility: Utility = .VITALITY
currency: i32 = 0
arena: Arena_Kind = .GRASSLAND

// Per-run tallies, surfaced on the results screen and reset by start_run.
run_time: f32 = 0
run_kills: i32 = 0
run_elite_kills: i32 = 0
run_coins_earned: i32 = 0
run_coins_spent: i32 = 0
result: Run_Result

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
	ammo_mult = stats.ammo_mult
	weapon_init(&primary, GUNS[stats.primary])
	weapon_init(&secondary, SECONDARIES[stats.secondary])
	active_slot = 0
	bonus_damage = stats.bonus_damage
	bonus_projectiles = 0
	bonus_pierce = 0
	spread_cut = stats.spread_cut
	bonus_melee_damage = 0
	melee_speed_mult = 1
	melee_range_mult = 1
	bonus_melee_knock = 0
	lifesteal = 0
	mag_mult = 1
	ammo_growth_mult = 1
	character = stats.character
	melee_cooldown = 0
	melee_flash = 0
	melee_flash_range = KICK.reach
	melee_flash_arc = KICK.arc
	melee_flash_dir = {0, -1}
	melee_flash_shape = KICK.shape
	melee_flash_color = KICK.flash_color
	combo_index = 0
	combo_timer = 0
	traceur_charge = 0
	rr_surge = 0
	moving = false
	DASH_SPEED = stats.dash_speed
	DASH_DURATION = stats.dash_duration
	dash_cooldown = 0
	dash_cooldown_max = stats.dash_cooldown
	dash_cooldown_base = stats.dash_cooldown
	dash_blink = stats.dash_blink
	dash_distance = stats.dash_distance
	dash_damages = stats.dash_damages
	dash_damage = stats.dash_damage
	reload_time = stats.reload_time
	reload_time_base = stats.reload_time
	dash_timer = 0
	inv_timer = 0
	max_health = stats.max_health
	health = max_health
	card_choices = stats.card_choices
	wave = 1
	currency = 0
	shop_selected = 0
	shop_rerolls_used = 0
	reset_run_stats()
	last_dir = {0, -1}
	aim_dir = {0, -1}
	clear_run_entities()
	build_arena(arena)
	update_rr_adaptation()
	state = .PLAYING
}

// Zero the per-run tallies shown on the results screen.
reset_run_stats :: proc() {
	run_time = 0
	run_kills = 0
	run_elite_kills = 0
	run_coins_earned = 0
	run_coins_spent = 0
}

// Record that an enemy died. Elite kills are tracked separately for the results.
count_kill :: proc(elite: bool) {
	run_kills += 1
	if elite {
		run_elite_kills += 1
	}
}

// Snapshot the finished run for the results screen.
finalize_result :: proc() {
	result = Run_Result {
		arena        = arena,
		character    = character,
		gun          = gun,
		secondary    = secondary_kind,
		dash         = dash_kind,
		utility      = utility,
		wave_reached = max(wave - 1, 1),
		kills        = run_kills,
		elite_kills  = run_elite_kills,
		coins_earned = run_coins_earned,
		coins_spent  = run_coins_spent,
		time         = run_time,
	}
}

// Transition into the results screen once, capturing the run. Safe to call from
// several collision checks in the same frame.
game_over :: proc() {
	if state == .GAME_OVER {
		return
	}
	finalize_result()
	state = .GAME_OVER
	play(sounds.game_over)
}

// Give a weapon slot its starting mag/reserve from its stat block. Melee
// weapons have no capacity, so this leaves them empty and always "ready".
weapon_init :: proc(w: ^weapon, g: Weapon_Stats) {
	w.mag = g.magazine_capacity
	w.ammo = i32(f32(g.ammo_capacity) * ammo_mult)
	w.ammo_cap = w.ammo
	w.mag_cap = g.magazine_capacity
	w.reload = 0
	w.cooldown = 0
}

active_weapon :: proc() -> ^weapon {
	return active_slot == 1 ? &secondary : &primary
}

active_stats :: proc() -> Weapon_Stats {
	return active_slot == 1 ? SECONDARIES[secondary_kind] : GUNS[gun]
}

// Bud's "Unhappy": holding a gun (rather than a melee weapon) sours him.
bud_unhappy :: proc() -> bool {
	return character == .BUD && active_stats().class == .GUN
}

// Movement speed after every character trait and passive. TRACER is dragged
// down by heavy weapons but spun up by Traceur's Heart; BUD is slowed while
// stuck holding a gun; RR's Adaptation can add mobility.
character_move_speed :: proc() -> f32 {
	speed := SPEED
	if character == .BUD && bud_unhappy() {
		speed *= BUD_UNHAPPY_SPEED_MULT
	}
	if character == .TRACER {
		w := active_stats().weight
		speed *= clamp(1 - w * TRACER_WEIGHT_PENALTY, TRACER_MIN_SPEED_MULT, 1)
		speed *= 1 + TRACEUR_MAX_BONUS * clamp(traceur_charge, 0, 1)
	}
	if character == .RR && rr_adaptation == .MOBILITY {
		speed *= 1 + RR_ADAPT_MOBILITY * rr_adapt_scale()
	}
	return speed
}

// One melee hitbox test shared by the swing and (conceptually) the flash, so the
// drawn shape can never drift from what actually gets hit. `reach`/`arc` mean
// whatever `shape` says they mean (see Melee_Shape).
melee_shape_hits :: proc(
	origin, dir: raylib.Vector2,
	reach, arc: f32,
	shape: Melee_Shape,
	target: raylib.Vector2,
) -> bool {
	to := target - origin
	switch shape {
	case .SECTOR:
		dist := raylib.Vector2Length(to)
		return dist > 0.01 && dist <= reach && raylib.Vector2Angle(dir, to) <= arc
	case .THRUST:
		along := raylib.Vector2DotProduct(to, dir)
		if along < 0 || along > reach {
			return false
		}
		perp := abs(raylib.Vector2CrossProduct(dir, to)) // dir is unit length
		return perp <= arc
	case .BLAST:
		center := origin + dir * reach
		return raylib.Vector2Length(target - center) <= arc
	}
	return false
}

// Every attack (shot or swing) spins up Tracer's Heart. Other characters ignore
// it, so callers can note attacks unconditionally.
note_attack :: proc() {
	if character == .TRACER {
		traceur_charge = clamp(traceur_charge + TRACEUR_PER_ATTACK, 0, 1)
	}
}

// The unarmed attack: Bud throws the next Fists strike (advancing the combo),
// everyone else kicks. Returns the stats for this swing; the caller owns the
// cooldown timer and the swing itself.
unarmed_stats :: proc() -> Weapon_Stats {
	if character != .BUD {
		return KICK
	}
	stats := FISTS[combo_index]
	combo_index = (combo_index + 1) % len(FISTS)
	combo_timer = BUD_COMBO_WINDOW
	return stats
}

// Cooldown for a melee swing, after the SWING-speed card's multiplier.
swing_cooldown :: proc(stats: Weapon_Stats) -> f32 {
	return stats.cooldown * melee_speed_mult
}

// Swing a melee weapon (the universal KICK, one of Bud's FISTS, or a weapon in a
// slot) toward `dir`: damage and shove every enemy its hitbox covers. Records the
// exact geometry so the flash can draw what was hit, and feeds Traceur's Heart.
melee_swing :: proc(stats: Weapon_Stats, dir: raylib.Vector2) {
	cs := CHARACTERS[character]
	dmg := (stats.damage + bonus_melee_damage) * cs.melee_damage_mult + bonus_damage
	if character == .RR && rr_adaptation == .OFFENSE {
		dmg *= 1 + RR_ADAPT_OFFENSE * rr_adapt_scale()
	}
	reach := stats.reach * cs.melee_range_mult * melee_range_mult
	knock := (stats.knockback + bonus_melee_knock) * cs.melee_knock_mult
	melee_flash_range = reach
	melee_flash_arc = stats.arc
	melee_flash_dir = dir
	melee_flash_shape = stats.shape
	melee_flash_color = stats.flash_color
	melee_flash = MELEE_FLASH_TIME
	note_attack()
	player_c := position + size * 0.5
	for i := len(enemies) - 1; i >= 0; i -= 1 {
		e_c := enemies[i].position + enemies[i].size * 0.5
		if !melee_shape_hits(player_c, dir, reach, stats.arc, stats.shape, e_c) {
			continue
		}
		to := e_c - player_c
		hit := apply_enemy_damage(&enemies[i], dmg, player_c - e_c)
		if hit != .DAMAGE {
			play_enemy_hit(hit)
		}
		if raylib.Vector2Length(to) > 0.01 {
			enemies[i].position += raylib.Vector2Normalize(to) * knock
		}
		if enemies[i].hp <= 0 {
			spawn_kill_rewards(enemies[i].position, enemies[i].elite)
			unordered_remove(&enemies, i)
		}
	}
}

// Pick RR's Adaptation from whichever stat the run has invested in most. Called
// every frame so it tracks the build live; ties resolve to the earlier mode.
update_rr_adaptation :: proc() {
	if character != .RR {
		return
	}
	base := CHARACTERS[.RR]
	offense := clamp(bonus_damage / f32(MAX_BONUS_DAMAGE), 0, 1)
	mobility := clamp(
		(SPEED - base.speed) / max(MAX_SPEED - base.speed, 1),
		0,
		1,
	)
	resilience := clamp((max_health - base.max_health) / base.max_health, 0, 1)
	precision := clamp(spread_cut / 0.40, 0, 1)
	best := offense
	rr_adaptation = .OFFENSE
	if mobility > best {
		best = mobility
		rr_adaptation = .MOBILITY
	}
	if resilience > best {
		best = resilience
		rr_adaptation = .RESILIENCE
	}
	if precision > best {
		best = precision
		rr_adaptation = .PRECISION
	}
}

// Scale applied to whichever Adaptation bonus is active: 1 normally, larger for
// a moment after RR's BURST dash (his "Second Wind" synergy).
rr_adapt_scale :: proc() -> f32 {
	if character == .RR && rr_surge > 0 {
		return 1 + RR_SURGE_EXTRA
	}
	return 1
}

// The single funnel for player damage. BUD's "Guard Up" blunts hits arriving
// from the direction he's facing (aim); RR's Resilience adaptation blunts all.
apply_player_damage :: proc(amount: f32, from: raylib.Vector2) {
	dmg := amount
	if character == .BUD {
		to := from - (position + size * 0.5)
		if raylib.Vector2Length(to) > 0.01 &&
		   raylib.Vector2Angle(aim_dir, raylib.Vector2Normalize(to)) < BUD_GUARD_ARC {
			dmg *= 1 - BUD_GUARD_REDUCTION
		}
	}
	if character == .RR && rr_adaptation == .RESILIENCE {
		dmg *= 1 - min(RR_ADAPT_RESILIENCE * rr_adapt_scale(), 1)
	}
	health -= dmg
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

// Finish a reload immediately (Navy's blink synergy). Consumes reserve ammo the
// same way a normal completed reload would.
instant_reload :: proc(w: ^weapon) {
	refill := min(w.mag_cap - w.mag, w.ammo)
	w.mag += refill
	w.ammo -= refill
	w.reload = 0
}

// EXTENDED MAG: grow a slot's magazine (melee slots have no mag, so no-op) and
// hand the player the extra rounds immediately.
grow_magazine :: proc(w: ^weapon, factor: f32) {
	if w.mag_cap <= 0 {
		return
	}
	grown := i32(f32(w.mag_cap) * factor)
	w.mag += grown - w.mag_cap
	w.mag_cap = grown
}

// BANDOLIER: grow a slot's reserve ammo the same way.
grow_ammo :: proc(w: ^weapon, factor: f32) {
	if w.ammo_cap <= 0 {
		return
	}
	grown := i32(f32(w.ammo_cap) * factor)
	w.ammo += grown - w.ammo_cap
	w.ammo_cap = grown
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

// Per-wave stat multipliers, shared by normal wave spawns and console spawns so
// a hand-spawned enemy is tuned to the current difficulty.
enemy_scales :: proc(wave: i32) -> (hp: f32, dmg: f32, spd: f32) {
	hp = 1 + ENEMY_HP_PER_WAVE * f32(wave - 1)
	dmg = 1 + ENEMY_DMG_PER_WAVE * f32(wave - 1)
	spd = min(1 + ENEMY_SPEED_PER_WAVE * f32(wave - 1), f32(ENEMY_SPEED_CAP))
	return
}

// Build and append one enemy at `pos`. Used by both the wave spawner and the
// debug console's `spawn` command.
spawn_enemy_at :: proc(kind: Enemy_Kind, elite: bool, wave: i32, pos: raylib.Vector2) {
	hp_scale, dmg_scale, spd_scale := enemy_scales(wave)
	s := ENEMIES[kind]
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
	if elite && kind == .GRUNT {
		// Devourers are as bulky as a tank so they survive long enough to feed.
		hp = ENEMIES[.TANK].hp * hp_scale
	}

	en := enemy {
		position = pos,
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
		plates = elite && kind == .TANK ? ELITE_TANK_PLATES : 0,
	}
	if elite && kind == .TANK {
		// Spread the plates evenly, with a random base so every Bulwark
		// presents its weak sides differently.
		base := rand.float32() * 2 * math.PI
		for k in 0 ..< ELITE_TANK_PLATES {
			ang := base + f32(k) * (2 * math.PI / f32(ELITE_TANK_PLATES))
			en.plate_dir[k] = {math.cos_f32(ang), math.sin_f32(ang)}
			en.plate_live[k] = true
		}
	}
	append(&enemies, en)
	next_enemy_id += 1
}

// Spawn just outside the player so a console-spawned enemy is immediately
// visible. Falls back to the normal random ring if that spot is inside cover.
spawn_enemy_near_player :: proc(kind: Enemy_Kind, elite: bool, wave: i32) {
	s := ENEMIES[kind]
	sz := s.size
	if elite {
		sz *= ELITE_SIZE_MULT
	}
	ang := rand.float32() * 2 * math.PI
	pc := position + size * 0.5
	p := pc + raylib.Vector2{math.cos_f32(ang), math.sin_f32(ang)} * 150 - sz * 0.5
	p.x = clamp(p.x, f32(WALL_THICK), f32(ARENA_W) - f32(WALL_THICK) - sz.x)
	p.y = clamp(p.y, f32(WALL_THICK), f32(ARENA_H) - f32(WALL_THICK) - sz.y)
	if box_blocked(p, sz) {
		p = random_spawn_pos(sz)
	}
	spawn_enemy_at(kind, elite, wave, p)
}

spawn_enemies :: proc(enemies: ^[dynamic]enemy, num: i32, wave: i32) {
	elite_chance := min(
		ELITE_BASE_CHANCE + ELITE_CHANCE_PER_WAVE * f32(wave - 1),
		f32(ELITE_CHANCE_CAP),
	)
	for _ in 0 ..< num {
		kind := pick_enemy_kind(wave)
		elite := wave >= 2 && rand.float32() < elite_chance
		sz := ENEMIES[kind].size
		if elite {
			sz *= ELITE_SIZE_MULT
		}
		spawn_enemy_at(kind, elite, wave, random_spawn_pos(sz))
	}
}

// Drop a pickup just outside the player (debug console `item` command).
spawn_drop_near_player :: proc(kind: Drop_Kind, amount: f32) {
	sz: raylib.Vector2 = kind == .CURRENCY ? {10, 10} : {12, 12}
	ang := rand.float32() * 2 * math.PI
	pc := position + size * 0.5
	p := pc + raylib.Vector2{math.cos_f32(ang), math.sin_f32(ang)} * 110 - sz * 0.5
	p.x = clamp(p.x, f32(WALL_THICK), f32(ARENA_W) - f32(WALL_THICK) - sz.x)
	p.y = clamp(p.y, f32(WALL_THICK), f32(ARENA_H) - f32(WALL_THICK) - sz.y)
	append(&drops, drop{position = p, size = sz, kind = kind, amount = amount, life = 8.0})
}

new_wave :: proc(enemies: ^[dynamic]enemy, wave: i32) {
	play(sounds.wave_start)
	spawn_enemies(enemies, wave, wave)
}

// Per-enemy steering. Movement is applied here; wall collision is resolved
// afterwards in the update loop.
update_enemy :: proc(e: ^enemy, dT: f32) {
	if e.flash > 0 {
		e.flash -= dT
	}
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
		// Crystalized grunts (Devourers) drift toward a nearby ally to feed.
		if e.elite && e.kind == .GRUNT {
			if lure, ok := nearest_other_enemy(e, ELITE_DEVOUR_LURE); ok {
				if d := raylib.Vector2Length(lure - ec); d > 0.01 {
					e.position += (lure - ec) / d * e.speed * dT
					break
				}
			}
		}
		e.position += dir * e.speed * dT

	case .RUNNER:
		if e.elite {
			// Blinker: bursts of erratic zig-zag dashes, charger-style.
			e.state_timer -= dT
			if e.state_timer > 0 {
				e.position += e.charge_dir * ELITE_DASH_SPEED * dT
			} else if e.elite_step > 0 {
				e.elite_step -= 1
				side: f32 = e.elite_step % 2 == 0 ? 1.0 : -1.0
				perp := raylib.Vector2{-dir.y, dir.x}
				e.charge_dir = raylib.Vector2Normalize(dir + perp * ELITE_DASH_ZIGZAG * side)
				e.state_timer = ELITE_DASH_TIME
				e.flash = 0.12
				play(sounds.dash, 1.3)
			} else {
				// Stalk slowly between bursts, then let the next burst rip.
				e.ability_timer -= dT
				e.position += dir * e.speed * 0.30 * dT
				if e.ability_timer <= 0 {
					e.elite_step = ELITE_DASH_COUNT
					e.ability_timer = ELITE_DASH_CYCLE
				}
			}
		} else {
			// Fast, with a little zig-zag so they're harder to line up.
			perp := raylib.Vector2{-dir.y, dir.x}
			osc := rand.float32_range(-0.5, 0.5)
			e.position += (dir + perp * osc) * e.speed * dT
		}

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
			if e.elite {
				// Boomerang: a fan of three shards that fly out, then back.
				spread := [3]f32{-0.30, 0.0, 0.30}
				for off in spread {
					append(
						&enemy_bullets,
						bullet {
							position = ec - {5, 5},
							size = {10, 10},
							velocity = raylib.Vector2Rotate(dir, off) * ELITE_BOOMERANG_SPEED,
							damage = s.damage,
							pierce = 0,
							boomerang = true,
							max_range = ELITE_BOOMERANG_RANGE,
						},
					)
				}
			} else {
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
			}
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

// Center of the nearest *fellow grunt* within `radius`, used by the Devourer to
// home in on a meal.
nearest_other_enemy :: proc(e: ^enemy, radius: f32) -> (raylib.Vector2, bool) {
	ec := e.position + e.size * 0.5
	best := raylib.Vector2{}
	best_d := radius
	found := false
	for other in enemies {
		if other.id == e.id || other.elite || other.kind != .GRUNT {
			continue
		}
		oc := other.position + other.size * 0.5
		if d := raylib.Vector2Length(oc - ec); d < best_d {
			best_d = d
			best = oc
			found = true
		}
	}
	return best, found
}

// Elite abilities that have to mutate the enemy list run in their own pass so
// removals can't invalidate the AI loop. Right now that's the Devourer eating
// an ally; the rest of the elites act inside `update_enemy`.
update_elite_abilities :: proc(enemies: ^[dynamic]enemy, dT: f32) {
	for i in 0 ..< len(enemies) {
		e := &enemies[i]
		if !e.elite || e.kind != .GRUNT {
			continue
		}
		e.ability_timer -= dT
		if e.ability_timer > 0 {
			continue
		}
		ec := e.position + e.size * 0.5
		best := -1
		best_d: f32 = ELITE_DEVOUR_RANGE
		for j in 0 ..< len(enemies) {
			if j == i || enemies[j].elite || enemies[j].kind != .GRUNT {
				continue
			}
			oc := enemies[j].position + enemies[j].size * 0.5
			if d := raylib.Vector2Length(oc - ec); d < best_d {
				best_d = d
				best = j
			}
		}
		if best < 0 {
			continue
		}
		// The victim dies (and still drops); the Devourer heals off it.
		spawn_kill_rewards(enemies[best].position, false)
		e.hp = min(e.hp + e.max_hp * ELITE_DEVOUR_HEAL, e.max_hp)
		e.flash = 0.25
		e.ability_timer = ELITE_DEVOUR_COOLDOWN
		unordered_remove(enemies, best)
		break // removal shifted indices; resume next frame
	}
}

// Damage an enemy. The Bulwark's crystal plates are directional: a hit arriving
// from roughly a plate's side shatters that plate, and while any plate remains
// the armored body takes no hp damage. `from` points from the enemy toward the
// source of the damage. The result tells the caller what happened.
apply_enemy_damage :: proc(e: ^enemy, amount: f32, from: raylib.Vector2) -> Enemy_Hit {
	if e.elite && e.kind == .TANK && e.plates > 0 {
		dir: raylib.Vector2 = {0, 0}
		if raylib.Vector2Length(from) > 0.01 {
			dir = raylib.Vector2Normalize(from)
		}
		threshold := math.cos_f32(ELITE_PLATE_ARC)
		for k in 0 ..< ELITE_TANK_PLATES {
			if !e.plate_live[k] {
				continue
			}
			if raylib.Vector2DotProduct(dir, e.plate_dir[k]) >= threshold {
				e.plate_live[k] = false
				e.plates -= 1
				e.flash = 0.15
				return .SHATTER
			}
		}
		// Struck the armored body, not a plate: hp stays protected.
		e.flash = 0.06
		return .BLOCKED
	}
	e.hp -= amount
	return .DAMAGE
}

// Impact feedback for a resolved enemy hit: a metallic clink on armored bodies,
// a glassy break when a Bulwark plate shatters, the usual tick otherwise.
play_enemy_hit :: proc(result: Enemy_Hit) {
	switch result {
	case .BLOCKED:
		play(sounds.clink, rand.float32_range(0.95, 1.08))
	case .SHATTER:
		play(sounds.shatter, rand.float32_range(0.97, 1.03))
	case .DAMAGE:
		play(sounds.hit, rand.float32_range(0.9, 1.1))
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

build_arena :: proc(kind: Arena_Kind) {
	clear(&walls)
	clear(&barrels)
	clear(&trees)

	t := f32(WALL_THICK)
	// Border is shared by every layout.
	append(&walls, raylib.Rectangle{0, 0, ARENA_W, t})
	append(&walls, raylib.Rectangle{0, ARENA_H - t, ARENA_W, t})
	append(&walls, raylib.Rectangle{0, 0, t, ARENA_H})
	append(&walls, raylib.Rectangle{ARENA_W - t, 0, t, ARENA_H})

	// Interior cover differs per arena. The center of every layout is left open
	// so the player always spawns with room to move.
	switch kind {
	case .GRASSLAND:
		rects := [?]raylib.Rectangle {
			{300, 220, 220, 40},
			{1080, 220, 220, 40},
			{300, 940, 220, 40},
			{1080, 940, 220, 40},
			{760, 260, 80, 220},
			{760, 720, 80, 220},
			{480, 560, 220, 80},
			{900, 560, 220, 80},
		}
		spots := [?]raylib.Vector2 {
			{250, 600},
			{1350, 600},
			{800, 190},
			{800, 1010},
			{560, 380},
			{1040, 380},
			{560, 820},
			{1040, 820},
		}
		barrel_spots := [?]raylib.Vector2 {
			{600, 300},
			{1000, 300},
			{600, 900},
			{1000, 900},
			{400, 600},
			{1200, 600},
		}
		add_walls(rects[:])
		add_trees(spots[:])
		add_barrels(barrel_spots[:])

	case .CANYON:
		rects := [?]raylib.Rectangle {
			{220, 300, 560, 44},
			{820, 300, 560, 44},
			{220, 880, 560, 44},
			{820, 880, 560, 44},
			{520, 450, 44, 300},
			{1036, 450, 44, 300},
		}
		spots := [?]raylib.Vector2{{250, 200}, {1350, 200}, {250, 1000}, {1350, 1000}}
		barrel_spots := [?]raylib.Vector2 {
			{400, 420},
			{1200, 420},
			{400, 780},
			{1200, 780},
			{800, 340},
			{800, 860},
			{600, 620},
			{1000, 620},
		}
		add_walls(rects[:])
		add_trees(spots[:])
		add_barrels(barrel_spots[:])

	case .RUINS:
		rects := [?]raylib.Rectangle {
			{285, 285, 70, 70},
			{765, 285, 70, 70},
			{1245, 285, 70, 70},
			{285, 565, 70, 70},
			{1245, 565, 70, 70},
			{285, 845, 70, 70},
			{765, 845, 70, 70},
			{1245, 845, 70, 70},
		}
		spots := [?]raylib.Vector2{{540, 300}, {1060, 300}, {540, 900}, {1060, 900}}
		barrel_spots := [?]raylib.Vector2{{800, 320}, {800, 880}, {520, 600}, {1080, 600}}
		add_walls(rects[:])
		add_trees(spots[:])
		add_barrels(barrel_spots[:])

	case .GLACIER:
		rects := [?]raylib.Rectangle {
			{300, 500, 300, 44},
			{1000, 500, 300, 44},
			{300, 656, 300, 44},
			{1000, 656, 300, 44},
			{760, 190, 80, 180},
			{760, 830, 80, 180},
		}
		spots := [?]raylib.Vector2 {
			{240, 260},
			{1360, 260},
			{240, 940},
			{1360, 940},
			{560, 300},
			{1040, 300},
			{560, 900},
			{1040, 900},
			{420, 420},
			{1180, 420},
			{420, 780},
			{1180, 780},
		}
		barrel_spots := [?]raylib.Vector2{{800, 260}, {800, 940}}
		add_walls(rects[:])
		add_trees(spots[:])
		add_barrels(barrel_spots[:])
	}
}

// Small helpers for build_arena so each layout is just a list of placements.
add_walls :: proc(rects: []raylib.Rectangle) {
	for r in rects {
		append(&walls, r)
	}
}

add_trees :: proc(spots: []raylib.Vector2) {
	for p in spots {
		append(&trees, tree{pos = {p.x - 22, p.y - 22}, size = {44, 44}})
	}
}

add_barrels :: proc(spots: []raylib.Vector2) {
	for p in spots {
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
			apply_enemy_damage(&enemies[i], EXPLOSION_DAMAGE, center - ec)
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
	count_kill(elite)
	// Vampirism: every kill heals a little, capped by max health.
	if lifesteal > 0 {
		health = min(health + lifesteal, max_health)
	}
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
	} else if name == "MELEE" {
		bonus_melee_damage = min(bonus_melee_damage + 1.5, f32(MAX_BONUS_MELEE_DAMAGE))
	} else if name == "SWING" {
		melee_speed_mult = max(melee_speed_mult * 0.85, MIN_MELEE_CD_MULT)
	} else if name == "REACH" {
		melee_range_mult = min(melee_range_mult + 0.12, MAX_MELEE_RANGE_MULT)
	} else if name == "KNOCK" {
		bonus_melee_knock = min(bonus_melee_knock + 60, f32(MAX_BONUS_MELEE_KNOCK))
	} else if name == "LIFESTEAL" {
		lifesteal = min(lifesteal + 2, f32(MAX_LIFESTEAL))
	} else if name == "RELOAD" {
		reload_time = max(reload_time * 0.85, reload_time_base * MIN_RELOAD_MULT)
	} else if name == "DASHCD" {
		dash_cooldown_max = max(
			dash_cooldown_max * 0.85,
			dash_cooldown_base * MIN_DASH_CD_MULT,
		)
	} else if name == "MAG" {
		mag_mult = min(mag_mult * 1.25, MAX_MAG_MULT)
		grow_magazine(&primary, 1.25)
		grow_magazine(&secondary, 1.25)
	} else if name == "AMMO" {
		ammo_growth_mult = min(ammo_growth_mult * 1.25, MAX_AMMO_MULT)
		grow_ammo(&primary, 1.25)
		grow_ammo(&secondary, 1.25)
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
	case "MELEE":
		return bonus_melee_damage < f32(MAX_BONUS_MELEE_DAMAGE)
	case "SWING":
		return melee_speed_mult > MIN_MELEE_CD_MULT
	case "REACH":
		return melee_range_mult < MAX_MELEE_RANGE_MULT
	case "KNOCK":
		return bonus_melee_knock < f32(MAX_BONUS_MELEE_KNOCK)
	case "LIFESTEAL":
		return lifesteal < f32(MAX_LIFESTEAL)
	case "RELOAD":
		return reload_time > reload_time_base * MIN_RELOAD_MULT
	case "DASHCD":
		return dash_cooldown_max > dash_cooldown_base * MIN_DASH_CD_MULT
	case "MAG":
		return mag_mult < MAX_MAG_MULT
	case "AMMO":
		return ammo_growth_mult < MAX_AMMO_MULT
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
	run_coins_spent += cost
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
	run_coins_spent += it.cost
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
	character: Character,
	primary: Gun,
	secondary: Secondary,
	dash: Dash_Kind,
	utility: Utility,
) -> Run_Stats {
	cs := CHARACTERS[character]
	d := DASHES[dash]
	stats := Run_Stats {
		character     = character,
		speed         = cs.speed,
		primary       = primary,
		secondary     = secondary,
		dash_speed    = d.speed,
		dash_duration = d.duration,
		dash_cooldown = d.cooldown,
		dash_blink    = d.blink,
		dash_distance = d.distance,
		dash_damages  = d.damages,
		dash_damage   = BASE_DASH_DAMAGE,
		reload_time   = RELOAD_TIME * cs.reload_mult,
		max_health    = cs.max_health,
		card_choices  = 3,
		ammo_mult     = cs.ammo_mult,
	}

	// Dash affinity: a character's signature dash gets a little extra.
	switch character {
	case .TRACER:
		switch dash {
		case .SLIDE:
			stats.dash_speed *= TRACER_SLIDE_SPEED_MULT
			stats.dash_cooldown *= TRACER_SLIDE_CD_MULT
			stats.dash_duration *= TRACER_SLIDE_TIME_MULT
		case .PHASE:
			stats.dash_duration *= TRACER_PHASE_DURATION_MULT
			stats.dash_cooldown *= TRACER_PHASE_CD_MULT
		case .BURST, .BLINK, .IMPACT:
		}
	case .BUD:
		if dash == .IMPACT {
			stats.dash_damage *= BUD_IMPACT_DAMAGE_MULT
		}
	case .RR:
		if dash == .BURST {
			stats.dash_cooldown *= RR_BURST_CD_MULT
		}
	case .NAVY:
		if dash == .BLINK {
			stats.dash_distance *= NAVY_BLINK_DISTANCE_MULT
			stats.dash_cooldown *= NAVY_BLINK_CD_MULT
		}
	}

	switch utility {
	case .VITALITY:
		stats.max_health += UTIL_MAX_HEALTH
	case .SWIFT:
		stats.speed += UTIL_SPEED
	case .FORTUNE:
		stats.card_choices += 1
	case .TRIGGER:
		stats.bonus_damage += UTIL_DAMAGE
	case .DEADEYE:
		stats.spread_cut += UTIL_SPREAD_CUT
	case .SCOUT:
		stats.dash_cooldown *= UTIL_DASH_CD_MULT
	case .PACKRAT:
		stats.ammo_mult *= UTIL_AMMO_MULT
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

// Human-readable name for RR's current Adaptation, shown on the HUD.
rr_adaptation_name :: proc() -> cstring {
	switch rr_adaptation {
	case .OFFENSE:
		return "OFFENSE"
	case .MOBILITY:
		return "MOBILITY"
	case .RESILIENCE:
		return "RESILIENCE"
	case .PRECISION:
		return "PRECISION"
	}
	return "OFFENSE"
}

// Draw the last melee swing using the *same* geometry the hit test used, so the
// flash can never disagree with the hitbox. Must be called inside the world
// camera's 2D mode. Each shape gets its own look, so no two melee weapons read
// the same on screen.
draw_melee_flash :: proc() {
	if melee_flash <= 0 {
		return
	}
	t := clamp(melee_flash / MELEE_FLASH_TIME, 0, 1)
	pc := position + size * 0.5
	col := melee_flash_color
	col.a = u8(f32(col.a) * t)
	angle := math.atan2_f32(melee_flash_dir.y, melee_flash_dir.x) * raylib.RAD2DEG
	switch melee_flash_shape {
	case .SECTOR:
		arc_deg := melee_flash_arc * raylib.RAD2DEG
		raylib.DrawCircleSector(
			pc,
			melee_flash_range,
			angle - arc_deg,
			angle + arc_deg,
			24,
			col,
		)
	case .THRUST:
		// A thin blade: a rectangle running from the body along the swing.
		rec := raylib.Rectangle{pc.x, pc.y, melee_flash_range, melee_flash_arc * 2}
		raylib.DrawRectanglePro(rec, {0, melee_flash_arc}, angle, col)
		tip := pc + melee_flash_dir * melee_flash_range
		raylib.DrawCircleV(tip, melee_flash_arc, raylib.Color{col.r, col.g, col.b, col.a})
	case .BLAST:
		// A smash: a ring that contracts onto the impact point ahead of you.
		center := pc + melee_flash_dir * melee_flash_range
		radius := melee_flash_arc * (1.4 - 0.4 * t)
		raylib.DrawCircleV(center, radius, col)
		raylib.DrawCircleLinesV(center, radius, raylib.WHITE)
	}
}

// Draw a main character's body: a darker outline shape behind the body color.
// `center` is the body center and `half` its half-extents.
draw_character_body :: proc(cs: Character_Stats, center: raylib.Vector2, half: raylib.Vector2) {
	inflate: f32 = 3
	switch cs.shape {
	case .SQUARE:
		raylib.DrawRectangleV(
			center - half - raylib.Vector2{inflate, inflate},
			half * 2 + raylib.Vector2{inflate, inflate} * 2,
			cs.outline,
		)
		raylib.DrawRectangleV(center - half, half * 2, cs.color)
	case .CIRCLE:
		raylib.DrawCircleV(center, half.x + inflate, cs.outline)
		raylib.DrawCircleV(center, half.x, cs.color)
	case .TRIANGLE:
		// Outline triangle first, then the body triangle inset by `inflate`.
		raylib.DrawTriangle(
			{center.x, center.y - half.y - inflate},
			{center.x - half.x - inflate, center.y + half.y + inflate},
			{center.x + half.x + inflate, center.y + half.y + inflate},
			cs.outline,
		)
		raylib.DrawTriangle(
			{center.x, center.y - half.y},
			{center.x - half.x, center.y + half.y},
			{center.x + half.x, center.y + half.y},
			cs.color,
		)
	}
}

// The player's in-world body, using the currently chosen character.
draw_player :: proc() {
	draw_character_body(CHARACTERS[character], position + size * 0.5, size * 0.5)
}

// A small character portrait for the select screen.
draw_character_icon :: proc(ch: Character, center: raylib.Vector2, r: f32) {
	draw_character_body(CHARACTERS[ch], center, {r, r})
}

// One results-screen row: label on the left, value right-aligned, both centered
// around the 800px canvas so the table reads cleanly.
draw_stat :: proc(label: cstring, value: cstring, y: i32) {
	raylib.DrawText(label, 280, y, 22, raylib.GRAY)
	vw := raylib.MeasureText(value, 22)
	raylib.DrawText(value, 520 - vw, y, 22, raylib.WHITE)
}

// A floating crystal shard marks a crystalized (elite) enemy. `phase` staggers
// the bob so a group of elites doesn't pulse in lockstep.
draw_crystal_shard :: proc(center: raylib.Vector2, radius: f32, phase: f32) {
	c := raylib.Vector2{center.x, center.y + math.sin_f32(f32(raylib.GetTime()) * 3 + phase) * 3}
	raylib.DrawPoly(c, 4, radius, 0, raylib.Color{24, 68, 104, 255}) // dark crystal edge
	raylib.DrawPoly(c, 4, radius * 0.74, 0, raylib.SKYBLUE) // body
	raylib.DrawPoly(c, 4, radius * 0.34, 0, raylib.WHITE) // facet highlight
}

skill_screen_draw :: proc(selected_skill: cstring) {

}
