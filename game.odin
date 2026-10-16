package main
import "core:math"
import "core:math/rand"
import "vendor:raylib"

// ---------------------------------------------------------------------------
// Arena / tuning constants
// ---------------------------------------------------------------------------

ARENA_W :: 1600
ARENA_H :: 1200
WALL_THICK :: 60
RELOAD_TIME :: 1.0
MELEE_FLASH_TIME :: 0.15 // how long the swing arc is shown after a melee hit
MUZZLE_FLASH_TIME :: 0.045 // how long a gun's muzzle flash lingers after firing
// Navy's Muzzle Thrust: the bayonet's LUNGE stabs, then fires a point-blank
// burst -- a rectangle along the strike that carries the primary gun's damage.
// It spends one round, and with no loaded firearm in slot 0 it is a plain lunge.
MUZZLE_VOLLEY_REACH :: 70 // how far ahead of Navy the burst box is centred
MUZZLE_VOLLEY_LENGTH :: 190 // burst box length, along the strike
MUZZLE_VOLLEY_WIDTH :: 96 // burst box width, across the strike
MUZZLE_VOLLEY_FLASH_TIME :: 0.12 // the volley's flash lingers longer than a gun's
BASE_DASH_DAMAGE :: 30 // damage per second dealt by a damaging dash

// GF mode (Ctrl+G) / the EASY difficulty it mirrors.
GF_AIM_RANGE :: 900 // px within which aim assist looks for a target
GF_AIM_CONE :: f32(0.35) // radians (~20 deg) a target must sit inside your aim
GF_DAMAGE_MULT :: f32(0.5) // incoming damage scale while the assist is active

// Difficulty tuning, indexed by Difficulty (EASY, NORMAL, HARD). EASY's assists
// come from GF_DAMAGE_MULT; these only cover the enemy-side knobs. Kept as
// package variables so they can be indexed by a runtime difficulty.
DIFF_ENEMY_DAMAGE := [3]f32{1.0, 1.0, 1.6} // incoming hit scale
DIFF_ENEMY_SPEED := [3]f32{1.0, 1.0, 1.15} // enemy move-speed scale
DIFF_SPAWN_MULT := [3]f32{0.75, 1.0, 1.25} // wave size scale

// Hit feedback: floating damage numbers, blood spray, and screen shake. All are
// gated by the matching setting and capped so a busy wave can't overwhelm.
DAMAGE_NUMBER_TIME :: 0.7
DAMAGE_NUMBER_MAX :: 48
BLOOD_MAX :: 240
BLOOD_GRAVITY :: 340
SHAKE_DECAY :: 9.0 // how fast a shake magnitude bleeds off (units/second)
BLOOD_COLOR :: raylib.Color{158, 22, 22, 255}

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
// Tracer's PHASE CLAWS mechanic: her light strikes stack PHASE marks and the
// REND finisher consumes them for a burst, splashing a mark onto neighbours. The
// marks decay if the target is left alone, so the loop is "stay on it, then
// finish" -- landing both lights is what makes the finisher pay off.
PHASE_MARK_MAX :: 4
PHASE_MARK_DECAY :: 1.60 // seconds a mark survives without a fresh hit
PHASE_MARK_REND_DAMAGE :: 0.6 // bonus REND damage per mark consumed (flat)
PHASE_MARK_SPLASH_RADIUS :: 70
PHASE_MARK_SPLASH_DAMAGE :: 0.6
// REND's detonation visual: a small green burst where the cross was consumed.
PHASE_BURST_RADIUS :: 44
PHASE_BURST_TIME :: 0.25
// Finishing a marked target with REND heals Tracer, so the glass-cannon has a
// way to sustain the close-range commitment her claws demand.
PHASE_REND_HEAL :: 8.0
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
// Signature combos: press E again within this window to chain the next strike
// (jab -> hook -> elbow -> ...). Waiting resets the chain to the first strike.
SIGNATURE_COMBO_WINDOW :: 0.55
// Bud's flying knee is a charged strike: while it is the armed next strike it
// winds up over this long, and its damage grows with the charge (see `charged`).
KNEE_CHARGE_TIME :: 0.40
KNEE_CHARGE_BONUS :: 1.00 // +100% damage at full charge
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
// Neither defense nor precision reaches RR's blade, so two of his forms replace
// the E kick outright rather than leaving the adaptation bonus dead on melee.
// RESILIENCE's BULWARK turns E into a held GUARD; PRECISION's NEEDLE turns it
// into a short blink.
RR_BLOCK_SPEED_MULT :: 0.45 // the guard drags his move speed down to 45%
RR_BLOCK_ARC :: 0.75 // radians of "front" the guard covers
BLOCK_FLASH_TIME :: 0.15 // how long a cancelled hit flares the guard arc
RR_NEEDLE_BLINK_CD :: 0.60
RR_NEEDLE_BLINK_DIST :: 70
RR_NEEDLE_BLINK_INV :: 0.12
// Per-card stat gains, shared by apply_upgrade and RR's Adaptation scoring so
// both sides agree on what a single card is worth.
CARD_ATTACK_DAMAGE :: 1.0
CARD_SPEED_BONUS :: 50.0
CARD_HEALTH_BONUS :: 25.0
CARD_SPREAD_CUT :: 0.2
// How many of a mode's cards it takes to fully trigger RR's Adaptation. All four
// are the same, so no mode is cheaper to lock in than another.
RR_ADAPT_CARDS :: 4
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

// Status effects. Attacks apply whatever set is in `attack_effects` (built by
// cards); enemies tick each active effect down and suffer it while it lasts.
BURN_TIME :: 3.0
BURN_DPS :: 5.0
POISON_TIME :: 6.0
POISON_DPS :: 2.5
FREEZE_TIME :: 2.0
FREEZE_SLOW :: 0.45 // move-speed multiplier while frozen
SHOCK_TIME :: 1.2 // stunned (no move, no attack) while shocked
MAX_STATUS_POWER :: 4.0 // cap on per-element power (damage / slow / stun)
MAX_STATUS_TIME_MULT :: 2.5 // cap on the global duration multiplier

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
difficulty: Difficulty = .NORMAL

// Menu navigation state (mouse + keyboard share these selections).
main_menu_sel: int = 0
settings_sel: int = 0
quit_requested: bool = false

// Tutorial state. The select screen picks a tier (and a character for the
// advanced tier); the tutorial itself walks a list of steps.
tutorial_select_sel: int = 0
tutorial_mode: bool = false
tutorial_kind: Tutorial_Kind = .BASIC
tutorial_char: Character = .RR
tutorial_step: int = 0
tutorial_timer: f32 = 0
tutorial_flags: Tutorial_Flags

// "GF mode" (Ctrl+G): a hidden comfort toggle for players who aren't used to
// games. Movement uses newest-key-wins on each axis (so holding W and tapping S
// moves down instead of cancelling out), and attacks get a little aim assist
// while incoming damage is reduced. Nothing here is shown on the official
// menus; the difficulty screen exposes the same assists as presets.
gf_mode: bool = false
gf_clock: f32 = 0 // monotonic seconds, used to order direction-key presses
gf_t_w: f32 = 0
gf_t_a: f32 = 0
gf_t_s: f32 = 0
gf_t_d: f32 = 0

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
// Q cycles through the two gun slots plus SLOT_SIGNATURE (the character's own
// melee weapon), which has no weapon struct and is always ready.
SLOT_PRIMARY :: 0
SLOT_SECONDARY :: 1
SLOT_SIGNATURE :: 2
SLOT_COUNT :: 3
gun: Gun = .SNIPER
secondary_kind: Secondary = .PISTOL
primary: weapon
secondary: weapon
active_slot: int = 0 // see SLOT_* above: primary, secondary, or signature melee
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

// Status effects. `attack_effects` is what every player attack (shot or swing)
// inflicts; `status_power` deepens one element; `status_time_mult` stretches all
// durations. Enemies keep their own active set + timers (see the enemy struct).
attack_effects: Status_Set = {}
status_power: [Status_Effect]f32 = {.Burn = 1, .Freeze = 1, .Poison = 1, .Shock = 1}
status_time_mult: f32 = 1

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
// Counts down after a shot so the held gun can show a muzzle flash.
muzzle_flash: f32 = 0
// Direction of Navy's last Muzzle Thrust, so its burst box can be drawn.
muzzle_volley_dir: raylib.Vector2 = {1, 0}
// Signature combo: which strike is next, how long the chain stays open, and the
// wind-up charge for a charged strike (Bud's flying knee).
combo_index: int = 0
combo_timer: f32 = 0
combo_charge: f32 = 0

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
rr_block: bool = false // BULWARK guard up: front damage cancelled, move slowed
block_flash: f32 = 0 // flares the guard arc when it actually cancels a hit
rr_blink_cd: f32 = 0 // NEEDLE blink timer (its E move replaces the kick)

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
damage_numbers: [dynamic]damage_number
blood: [dynamic]blood_drop
// Screen shake: a decaying magnitude the camera jitters by, scaled by the
// screen-shake setting and amplified by events (hits, explosions).
shake: f32 = 0
shake_mag: f32 = 0

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
	active_slot = SLOT_PRIMARY
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
	muzzle_flash = 0
	melee_flash_range = KICK.reach
	melee_flash_arc = KICK.arc
	melee_flash_dir = {0, -1}
	melee_flash_shape = KICK.shape
	melee_flash_color = KICK.flash_color
	combo_index = 0
	combo_timer = 0
	combo_charge = 0
	attack_effects = {}
	status_time_mult = 1
	for eff in Status_Effect {
		status_power[eff] = 1
	}
	traceur_charge = 0
	rr_surge = 0
	rr_block = false
	block_flash = 0
	rr_blink_cd = 0
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
	return active_slot == SLOT_SECONDARY ? &secondary : &primary
}

// Display name for any slot; used by the HUD and the Q-cycle hint.
slot_name :: proc(slot: int) -> string {
	switch slot {
	case SLOT_PRIMARY:
		return string(GUNS[gun].name)
	case SLOT_SECONDARY:
		return string(SECONDARIES[secondary_kind].name)
	case SLOT_SIGNATURE:
		return string(SIGNATURE_NAMES[character])
	}
	return ""
}

active_stats :: proc() -> Weapon_Stats {
	switch active_slot {
	case SLOT_SECONDARY:
		return SECONDARIES[secondary_kind]
	case SLOT_SIGNATURE:
		return signature_stats()
	}
	return GUNS[gun]
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
	// RR's BULWARK guard is a stance, not free: holding it drags him down.
	if rr_block {
		speed *= RR_BLOCK_SPEED_MULT
	}
	return speed
}

// One melee hitbox test shared by the swing and (conceptually) the flash, so the
// drawn shape can never drift from what actually gets hit. `reach`/`arc` mean
// whatever `shape` says they mean (see Melee_Shape).
//
// The target is a body, not a point: it is passed as its centre plus a radius.
// Testing only the centre made the narrow THRUST blades (arc 6-9px) whiff on the
// 30-80px enemies whenever their middle sat a few pixels off the aim line, or
// slightly behind the player. Every shape is grown by `target_radius` so a blade
// that visibly overlaps a body connects.
melee_shape_hits :: proc(
	origin, dir: raylib.Vector2,
	reach, arc: f32,
	shape: Melee_Shape,
	target: raylib.Vector2,
	target_radius: f32,
) -> bool {
	to := target - origin
	switch shape {
	case .SECTOR:
		dist := raylib.Vector2Length(to)
		return dist > 0.01 && dist <= reach + target_radius &&
		       raylib.Vector2Angle(dir, to) <= arc
	case .THRUST:
		// Distance from the target centre to the swing segment, grown by both
		// the blade's half-width and the target's radius. Clamping `along` keeps
		// the near end of the blade live, so an enemy on top of the player is
		// still stabbed instead of skipped by an `along < 0` test.
		along := clamp(raylib.Vector2DotProduct(to, dir), 0, reach)
		closest := origin + dir * along
		return raylib.Vector2Length(target - closest) <= arc + target_radius
	case .BLAST:
		center := origin + dir * reach
		return raylib.Vector2Length(target - center) <= arc + target_radius
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

// Which strike the chain currently points at. Everyone reads it from the static
// SIGNATURES table, except RR: Vector Edge reshapes itself to his Adaptation, so
// his signature is resolved from RR_EDGE at runtime instead. Callers go through
// this so one lookup serves the held weapon, the swing and the HUD alike.
signature_at :: proc(index: int) -> Weapon_Stats {
	if character == .RR {
		return RR_EDGE[rr_adaptation][index % SIGNATURE_COUNT[.RR]]
	}
	n := SIGNATURE_COUNT[character]
	if n <= 0 {
		return KICK
	}
	return SIGNATURES[character][index % n]
}

// The strike that is currently armed in the signature chain, *without*
// advancing it. Used to draw the held/worn weapon and for the HUD; only an
// actual throw (unarmed_stats) moves the combo along.
signature_stats :: proc() -> Weapon_Stats {
	return signature_at(combo_index)
}

// The unarmed attack: each character throws the next strike of their own
// signature combo, advancing the chain. Returns the stats for this swing; the
// caller owns the cooldown timer and the swing itself.
unarmed_stats :: proc() -> Weapon_Stats {
	n := SIGNATURE_COUNT[character]
	if n <= 0 {
		return KICK
	}
	stats := signature_at(combo_index)
	combo_index = (combo_index + 1) % n
	combo_timer = SIGNATURE_COMBO_WINDOW
	return stats
}

// Is the next signature strike a charged one? While true, the combo charge
// winds up (Bud's flying knee), so the finisher lands harder the longer it is
// held. Characters without a charged strike never build charge.
signature_next_charged :: proc() -> bool {
	n := SIGNATURE_COUNT[character]
	if n <= 0 {
		return false
	}
	return signature_at(combo_index % n).charged
}

// Cooldown for a melee swing, after the SWING-speed card's multiplier.
swing_cooldown :: proc(stats: Weapon_Stats) -> f32 {
	return stats.cooldown * melee_speed_mult
}

// Swing a melee weapon (the universal KICK, one of Bud's FISTS, or a weapon in a
// slot) toward `dir`: damage and shove every enemy its hitbox covers. Records the
// exact geometry so the flash can draw what was hit, and feeds Traceur's Heart.
// `finisher` marks the last strike of a signature chain -- RR's Second Wind turns
// a surged finisher into a thrown blade wind.
melee_swing :: proc(stats: Weapon_Stats, dir: raylib.Vector2, finisher: bool = false) {
	// Charged strikes (Bud's flying knee) hit harder the longer they wound up.
	charge := stats.charged ? combo_charge : 0
	// Committed strikes (the knee, the bayonet lunge) shove the attacker
	// forward first, so the hitbox and flash start where the strike lands.
	if stats.lunge > 0 {
		position += dir * stats.lunge
		resolve_obstacles(&position, size)
		// The shove can bury the attacker in a perimeter wall, where
		// resolve_obstacles would push it out of the arena -- clamp it back in.
		clamp_to_arena(&position, size)
	}
	cs := CHARACTERS[character]
	// Base per-hit damage. REND adds to this per enemy, from the marks it
	// consumes, so it is figured here and reused inside the loop.
	base_dmg := (stats.damage + bonus_melee_damage) * cs.melee_damage_mult + bonus_damage
	if character == .RR && rr_adaptation == .OFFENSE {
		base_dmg *= 1 + RR_ADAPT_OFFENSE * rr_adapt_scale()
	}
	base_dmg *= 1 + KNEE_CHARGE_BONUS * charge
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
		e_r := max(enemies[i].size.x, enemies[i].size.y) * 0.5
		if !melee_shape_hits(player_c, dir, reach, stats.arc, stats.shape, e_c, e_r) {
			continue
		}
		to := e_c - player_c
		// REND pays out whatever PHASE marks the lights have stacked on it.
		dmg := base_dmg
		marked := false
		if stats.phase_detonate {
			marked = enemies[i].phase_marks > 0
			dmg += PHASE_MARK_REND_DAMAGE * f32(enemies[i].phase_marks)
		}
		// Marking lights are pure setup: they deal no damage at all, even with
		// damage upgrades, so the killing blow -- and REND's heal -- always
		// lands on REND instead of a light stealing it.
		if stats.phase_apply > 0 {
			dmg = 0
		}
		hit := apply_enemy_damage(&enemies[i], dmg, player_c - e_c)
		if hit != .DAMAGE {
			play_enemy_hit(hit)
		}
		// Melee carries the player's on-hit status set just like bullets do.
		apply_status(&enemies[i], attack_effects)
		// Phase Claws: lights stack marks, REND spends them and splashes.
		if stats.phase_apply > 0 {
			mark_enemy(&enemies[i], stats.phase_apply)
		}
		if stats.phase_detonate {
			// REND visibly explodes the cross it consumed.
			tutorial_note(.REND)
			if marked {
				append(
					&explosions,
					explosion {
						pos = e_c,
						life = PHASE_BURST_TIME,
						max_life = PHASE_BURST_TIME,
						radius = PHASE_BURST_RADIUS,
						color = raylib.Color{150, 255, 160, 255},
					},
				)
			}
			phase_mark_splash(i)
			enemies[i].phase_marks = 0
		}
		if raylib.Vector2Length(to) > 0.01 {
			enemies[i].position += raylib.Vector2Normalize(to) * knock
		}
		if enemies[i].hp <= 0 {
			// REND's payoff: finishing a marked target heals Tracer, so her
			// glass-cannon build can sustain the close-range commitment.
			if marked {
				health = min(health + PHASE_REND_HEAL, max_health)
			}
			spawn_kill_rewards(enemies[i].position, enemies[i].elite)
			unordered_remove(&enemies, i)
		}
	}
	// PHASE splash can drop enemies the swing itself never covered; sweep any
	// that died so they still drop their rewards.
	if stats.phase_detonate {
		for i := len(enemies) - 1; i >= 0; i -= 1 {
			if enemies[i].hp <= 0 {
				spawn_kill_rewards(enemies[i].position, enemies[i].elite)
				unordered_remove(&enemies, i)
			}
		}
	}
	// RR's Second Wind: a surged finisher hurls a blade wind out of the swing, so
	// his BURST dash feeds straight back into the combo.
	if finisher && character == .RR && rr_surge > 0 {
		spawn_blade_wind(dir, stats)
	}
	// Navy's Muzzle Thrust: the lunge's bayonet fires a point-blank burst.
	if stats.muzzle_volley {
		fire_muzzle_volley(dir)
	}
	// A charged finisher spends its wind-up.
	if stats.charged {
		combo_charge = 0
	}
}

// Throw a blade wind: the travelling crescent RR's Second Wind hurls out of a
// surged finisher. Each form tunes its own wind (RR_EDGE_WIND) -- FLURRY is the
// fast ladder, so its wind is much weaker to stop it outpacing the others.
spawn_blade_wind :: proc(dir: raylib.Vector2, stats: Weapon_Stats) {
	if character != .RR {
		return
	}
	cfg := RR_EDGE_WIND[rr_adaptation]
	d := dir
	if raylib.Vector2Length(d) < 0.01 {
		d = {1, 0}
	}
	d = raylib.Vector2Normalize(d)
	pc := position + size * 0.5
	append(
		&bullets,
		bullet {
			position = pc - raylib.Vector2{9, 9},
			size = raylib.Vector2{18, 18},
			velocity = d * cfg.speed,
			damage = stats.damage * cfg.mult,
			pierce = cfg.pierce,
			effects = attack_effects,
			wind = true,
		},
	)
}

// Navy's Muzzle Thrust. The bayonet's LUNGE stabs, then fires a point-blank
// burst: a rectangle punched out along the strike that carries the primary
// gun's damage. Spends one round; with no loaded firearm in slot 0 the lunge
// stays a plain stab.
fire_muzzle_volley :: proc(dir: raylib.Vector2) {
	if GUNS[gun].class != .GUN || primary.mag <= 0 {
		return
	}
	d := dir
	if raylib.Vector2Length(d) < 0.01 {
		d = {1, 0}
	}
	d = raylib.Vector2Normalize(d)
	primary.mag -= 1
	tutorial_note(.VOLT)
	muzzle_flash = MUZZLE_VOLLEY_FLASH_TIME
	muzzle_volley_dir = d
	play(sounds.primary[gun], rand.float32_range(0.94, 1.06))
	damage := GUNS[gun].damage + bonus_damage
	perp := raylib.Vector2{-d.y, d.x}
	center := position + size * 0.5 + d * MUZZLE_VOLLEY_REACH
	half_len := f32(MUZZLE_VOLLEY_LENGTH) * 0.5
	half_wid := f32(MUZZLE_VOLLEY_WIDTH) * 0.5
	for i := len(enemies) - 1; i >= 0; i -= 1 {
		ec := enemies[i].position + enemies[i].size * 0.5
		to := ec - center
		if abs(raylib.Vector2DotProduct(to, d)) > half_len ||
		   abs(raylib.Vector2DotProduct(to, perp)) > half_wid {
			continue
		}
		play_enemy_hit(apply_enemy_damage(&enemies[i], damage, -d))
		apply_status(&enemies[i], attack_effects)
		if enemies[i].hp <= 0 {
			spawn_kill_rewards(enemies[i].position, enemies[i].elite)
			unordered_remove(&enemies, i)
		}
	}
}

// The Muzzle Thrust bloom: a muzzle flash at the tip plus the burst box along
// the strike, drawn while the volley's (longer) flash lives. Navy-only and only
// while the signature is in hand, so a gun's flash never lights this up.
draw_muzzle_volley_flash :: proc() {
	if muzzle_flash <= 0 || character != .NAVY || active_slot != SLOT_SIGNATURE {
		return
	}
	f := clamp(muzzle_flash / MUZZLE_VOLLEY_FLASH_TIME, 0, 1)
	d := muzzle_volley_dir
	pc := position + size * 0.5
	// Muzzle flash at the bayonet tip.
	muz := pc + d * 30
	raylib.DrawCircleV(muz, 6 + 6 * f, raylib.GOLD)
	raylib.DrawCircleV(muz, 3, raylib.Color{255, 250, 220, 255})
	// Burst box, rotated to the strike.
	center := pc + d * MUZZLE_VOLLEY_REACH
	rec := raylib.Rectangle {
		center.x,
		center.y,
		MUZZLE_VOLLEY_LENGTH,
		MUZZLE_VOLLEY_WIDTH,
	}
	origin := raylib.Vector2{MUZZLE_VOLLEY_LENGTH * 0.5, MUZZLE_VOLLEY_WIDTH * 0.5}
	rot := math.atan2_f32(d.y, d.x) * raylib.RAD2DEG
	raylib.DrawRectanglePro(rec, origin, rot, raylib.Color{255, 210, 110, u8(130 * f)})
	raylib.DrawRectanglePro(rec, origin, rot, raylib.Color{255, 245, 200, u8(70 * f * f)})
}

// Add PHASE marks to an enemy, capped. Tracer's light claw strikes call this.
mark_enemy :: proc(e: ^enemy, amount: i32) {
	if amount <= 0 {
		return
	}
	tutorial_note(.MARK)
	e.phase_marks = min(e.phase_marks + amount, PHASE_MARK_MAX)
	e.phase_time = PHASE_MARK_DECAY
}

// REND's detonation splash: enemies near a spent mark take a little damage and
// pick up a mark themselves, so repeated finishers spread through a crowd.
phase_mark_splash :: proc(source: int) {
	if source < 0 || source >= len(enemies) {
		return
	}
	center := enemies[source].position + enemies[source].size * 0.5
	for j := len(enemies) - 1; j >= 0; j -= 1 {
		if j == source {
			continue
		}
		e := &enemies[j]
		ec := e.position + e.size * 0.5
		if raylib.Vector2Length(ec - center) > PHASE_MARK_SPLASH_RADIUS {
			continue
		}
		apply_enemy_damage(e, PHASE_MARK_SPLASH_DAMAGE, center - ec)
		mark_enemy(e, 1)
	}
}

// PHASE marks fade if the enemy is left alone, so Tracer has to keep pressure on
// a target to line up a big REND.
tick_phase_marks :: proc(dT: f32) {
	for i in 0 ..< len(enemies) {
		if enemies[i].phase_marks <= 0 {
			continue
		}
		enemies[i].phase_time -= dT
		if enemies[i].phase_time <= 0 {
			enemies[i].phase_marks = 0
		}
	}
}

// Pick RR's Adaptation from whichever stat the run has invested in most. Called
// every frame so it tracks the build live; ties resolve to the earlier mode.
update_rr_adaptation :: proc() {
	if character != .RR {
		return
	}
	// Each mode measures investment on the same scale -- RR_ADAPT_CARDS picks of
	// its card -- so no adaptation is cheaper to lock in than another. Before
	// this, PRECISION maxed on 2 cards while OFFENSE needed 6, which pinned a
	// player to NEEDLE for most of a run.
	base := CHARACTERS[.RR]
	offense := clamp(bonus_damage / (RR_ADAPT_CARDS * CARD_ATTACK_DAMAGE), 0, 1)
	mobility := clamp(
		(SPEED - base.speed) / max(RR_ADAPT_CARDS * CARD_SPEED_BONUS, 1),
		0,
		1,
	)
	resilience := clamp(
		(max_health - base.max_health) / max(RR_ADAPT_CARDS * CARD_HEALTH_BONUS, 1),
		0,
		1,
	)
	precision := clamp(spread_cut / max(RR_ADAPT_CARDS * CARD_SPREAD_CUT, 1), 0, 1)
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
	// RR's advanced tutorial forces each stance in turn so the lesson is
	// reachable without hunting for the matching upgrade cards.
	if a, ok := rr_tutorial_adaptation(); ok {
		rr_adaptation = a
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

// Whether the GF-mode comfort assists are active: either the hidden Ctrl+G
// toggle is on, or the player picked the official EASY difficulty.
assists_on :: proc() -> bool {
	return gf_mode || difficulty == .EASY
}

difficulty_name :: proc(d: Difficulty) -> string {
	switch d {
	case .EASY:
		return "EASY"
	case .NORMAL:
		return "NORMAL"
	case .HARD:
		return "HARD"
	}
	return "NORMAL"
}

difficulty_desc :: proc(d: Difficulty) -> cstring {
	switch d {
	case .EASY:
		return "aim assist, half damage taken"
	case .NORMAL:
		return "the intended experience"
	case .HARD:
		return "enemies hit harder and move faster"
	}
	return ""
}

// GF mode movement: newest direction key wins on each axis. Holding an opposite
// pair (W+S / A+D) no longer cancels -- the more recently pressed key moves you,
// and releasing it hands control back to the other. Different axes still add
// together, so diagonals work exactly as before.
gf_move_dir :: proc() -> raylib.Vector2 {
	d := raylib.Vector2(0)
	a := world_key_down(raylib.KeyboardKey.A)
	dd := world_key_down(raylib.KeyboardKey.D)
	if a && dd {
		d.x = gf_t_d > gf_t_a ? 1 : -1
	} else if a {
		d.x = -1
	} else if dd {
		d.x = 1
	}
	w := world_key_down(raylib.KeyboardKey.W)
	s := world_key_down(raylib.KeyboardKey.S)
	if w && s {
		d.y = gf_t_s > gf_t_w ? 1 : -1
	} else if w {
		d.y = -1
	} else if s {
		d.y = 1
	}
	return d
}

// GF mode aim assist: if an enemy sits inside a narrow cone of where the player
// is aiming, snap the shot onto it. Only the shot direction is bent -- the
// character still faces the cursor -- so it stays forgiving, not magnetic.
gf_assist_aim :: proc(aim: raylib.Vector2) -> raylib.Vector2 {
	pc := position + size * 0.5
	best := aim
	best_d := f32(GF_AIM_RANGE)
	for e in enemies {
		ec := e.position + e.size * 0.5
		to := ec - pc
		dist := raylib.Vector2Length(to)
		if dist < 1 || dist > best_d {
			continue
		}
		if raylib.Vector2Angle(aim, to) > GF_AIM_CONE {
			continue
		}
		best_d = dist
		best = raylib.Vector2Normalize(to)
	}
	return best
}

// The single funnel for player damage. BUD's "Guard Up" blunts hits arriving
// from the direction he's facing (aim); RR's Resilience adaptation blunts all.
apply_player_damage :: proc(amount: f32, from: raylib.Vector2) {
	// Tutorial arenas are a safe sandbox: the player cannot be hurt.
	if tutorial_mode {
		return
	}
	// RR's BULWARK guard (E held): everything arriving from the front is
	// cancelled outright. Checked first so a blocked hit costs nothing at all --
	// the slow on his move speed is the whole price of the stance.
	if rr_block {
		to := from - (position + size * 0.5)
		if raylib.Vector2Length(to) < 0.01 ||
		   raylib.Vector2Angle(aim_dir, raylib.Vector2Normalize(to)) < RR_BLOCK_ARC {
			block_flash = BLOCK_FLASH_TIME
			return
		}
	}
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
	// Difficulty scales the hit, then the GF-mode "tougher player" assist halves
	// whatever is left (so EASY + the Ctrl+G toggle stack as a safety net).
	dmg *= DIFF_ENEMY_DAMAGE[int(difficulty)]
	if assists_on() {
		dmg *= GF_DAMAGE_MULT
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
	clear(&damage_numbers)
	clear(&blood)
	shake = 0
	shake_mag = 0
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
	// Difficulty scales how many show up; never fewer than one.
	num := max(i32(f32(wave)*DIFF_SPAWN_MULT[int(difficulty)] + 0.5), 1)
	spawn_enemies(enemies, num, wave)
}

// Per-enemy steering. Movement is applied here; wall collision is resolved
// afterwards in the update loop.
update_enemy :: proc(e: ^enemy, dT: f32) {
	if e.flash > 0 {
		e.flash -= dT
	}
	// Practice dummies hold position and never act.
	if e.training {
		return
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
	// Status: a shocked enemy is stunned (holds still); a frozen one still acts
	// but crawls. Both read the effect set ticked over in update_status.
	if enemy_stunned(e) {
		return
	}
	spd := e.speed * enemy_speed_mult(e) * DIFF_ENEMY_SPEED[int(difficulty)]

	switch e.kind {
	case .GRUNT, .TANK:
		// Crystalized grunts (Devourers) drift toward a nearby ally to feed.
		if e.elite && e.kind == .GRUNT {
			if lure, ok := nearest_other_enemy(e, ELITE_DEVOUR_LURE); ok {
				if d := raylib.Vector2Length(lure - ec); d > 0.01 {
					e.position += (lure - ec) / d * spd * dT
					break
				}
			}
		}
		e.position += dir * spd * dT

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
				e.position += dir * spd * 0.30 * dT
				if e.ability_timer <= 0 {
					e.elite_step = ELITE_DASH_COUNT
					e.ability_timer = ELITE_DASH_CYCLE
				}
			}
		} else {
			// Fast, with a little zig-zag so they're harder to line up.
			perp := raylib.Vector2{-dir.y, dir.x}
			osc := rand.float32_range(-0.5, 0.5)
			e.position += (dir + perp * osc) * spd * dT
		}

	case .RANGED:
		e.fire_cooldown -= dT
		if dist > s.preferred_range + 50 {
			e.position += dir * spd * dT
		} else if dist < s.preferred_range - 50 {
			e.position -= dir * spd * dT
		} else {
			// Hover and strafe.
			perp := raylib.Vector2{-dir.y, dir.x}
			side: f32 = e.id % 2 == 0 ? 1.0 : -1.0
			e.position += perp * spd * 0.7 * dT * side
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
			e.position += dir * spd * dT
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
	// Feedback for real number hits only (marking lights deal 0 and stay silent):
	// a floating number, a blood spray, and a little kick to the camera.
	if amount > 0.01 {
		spawn_damage_number(e.position + e.size * 0.5, amount)
		spawn_blood(e.position + e.size * 0.5, from)
		add_shake(min(amount * 0.35, 5))
	}
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

// --- Hit feedback -----------------------------------------------------------

// Queue a screen shake. The stored magnitude is the strongest pending one;
// main.odin converts it to a camera jitter and decays it each frame.
add_shake :: proc(mag: f32) {
	shake_mag = max(shake_mag, mag)
}

spawn_damage_number :: proc(pos: raylib.Vector2, amount: f32) {
	if !settings.damage_numbers || amount < 1 {
		return
	}
	if len(damage_numbers) >= DAMAGE_NUMBER_MAX {
		ordered_remove(&damage_numbers, 0)
	}
	append(
		&damage_numbers,
		damage_number {
			pos = pos + raylib.Vector2{rand.float32_range(-8, 8), -8},
			vel = raylib.Vector2{rand.float32_range(-16, 16), -50},
			life = DAMAGE_NUMBER_TIME,
			value = amount,
			color = raylib.WHITE,
		},
	)
}

// A short spray of droplets thrown along the hit direction.
spawn_blood :: proc(pos: raylib.Vector2, dir: raylib.Vector2) {
	if !settings.blood {
		return
	}
	d := dir
	if raylib.Vector2Length(d) < 0.01 {
		d = {1, 0}
	} else {
		d = raylib.Vector2Normalize(d)
	}
	for _ in 0 ..< 4 {
		if len(blood) >= BLOOD_MAX {
			ordered_remove(&blood, 0)
		}
		sp := raylib.Vector2Rotate(d, rand.float32_range(-0.7, 0.7)) * rand.float32_range(50, 170)
		life := rand.float32_range(0.45, 0.9)
		append(
			&blood,
			blood_drop {
				pos = pos,
				vel = sp,
				life = life,
				max_life = life,
				size = rand.float32_range(2, 4.5),
				color = BLOOD_COLOR,
			},
		)
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
// Status effects
// ---------------------------------------------------------------------------

// How much damage-per-second an effect deals after its power scaling. Only the
// damage-over-time effects return anything; freeze/shock are handled elsewhere.
status_dps :: proc(eff: Status_Effect) -> f32 {
	base: f32
	switch eff {
	case .Burn:
		base = BURN_DPS
	case .Poison:
		base = POISON_DPS
	case .Freeze, .Shock:
		base = 0
	}
	return base * status_power[eff]
}

// Duration of a fresh application, after power (Shock lasts longer with power)
// and the global time multiplier.
status_duration :: proc(eff: Status_Effect) -> f32 {
	base: f32
	switch eff {
	case .Burn:
		base = BURN_TIME
	case .Poison:
		base = POISON_TIME
	case .Freeze:
		base = FREEZE_TIME
	case .Shock:
		base = SHOCK_TIME * status_power[eff]
	}
	return base * status_time_mult
}

// Move-speed multiplier an enemy suffers from its active effects (freeze slows,
// and stronger freeze power slows harder).
enemy_speed_mult :: proc(e: ^enemy) -> f32 {
	if .Freeze in e.effects {
		return clamp(1 - (1 - FREEZE_SLOW) * status_power[.Freeze], 0.08, 1)
	}
	return 1
}

// A shocked enemy is briefly stunned: it neither moves nor attacks.
enemy_stunned :: proc(e: ^enemy) -> bool {
	return .Shock in e.effects
}

// Stamp `set` onto an enemy, refreshing each effect's timer (a re-application
// tops it back up but never stacks beyond one timer per effect).
apply_status :: proc(e: ^enemy, set: Status_Set) {
	if set == {} {
		return
	}
	for eff in set {
		e.effects += {eff}
		e.effect_timer[eff] = max(e.effect_timer[eff], status_duration(eff))
	}
}

// Tick every enemy's active effects: drain timers, apply damage-over-time, and
// drop expired effects. Kills from a damage-over-time effect pay out normally.
update_status :: proc(enemies: ^[dynamic]enemy, dT: f32) {
	for i := len(enemies) - 1; i >= 0; i -= 1 {
		e := &enemies[i]
		if e.effects == {} {
			continue
		}
		dmg: f32 = 0
		// Iterate the enum (not the set) so removing bits is safe.
		for eff in Status_Effect {
			if eff not_in e.effects {
				continue
			}
			e.effect_timer[eff] -= dT
			if e.effect_timer[eff] <= 0 {
				e.effect_timer[eff] = 0
				e.effects -= {eff}
				continue
			}
			dmg += status_dps(eff) * dT
		}
		if dmg > 0 {
			// Crystal plates absorb damage-over-time too. Elemental ticks used
			// to write hp directly and phase straight through an elite Bulwark's
			// armor; this mirrors the plate guard in apply_enemy_damage.
			if !(e.elite && e.kind == .TANK && e.plates > 0) {
				e.hp -= dmg
				if e.hp <= 0 {
					spawn_kill_rewards(e.position, e.elite)
					unordered_remove(enemies, i)
				}
			}
		}
	}
}

// Human-readable name for one status effect (HUD + enemy markers).
status_name :: proc(eff: Status_Effect) -> cstring {
	switch eff {
	case .Burn:
		return "BURN"
	case .Freeze:
		return "FREEZE"
	case .Poison:
		return "POISON"
	case .Shock:
		return "SHOCK"
	}
	return "?"
}

// Representative colour for one status effect (HUD dots + enemy tint markers).
status_color :: proc(eff: Status_Effect) -> raylib.Color {
	switch eff {
	case .Burn:
		return raylib.ORANGE
	case .Freeze:
		return raylib.SKYBLUE
	case .Poison:
		return raylib.LIME
	case .Shock:
		return raylib.YELLOW
	}
	return raylib.WHITE
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

// Keep an entity inside the arena's playable area. A committed lunge (Bud's
// knee, Navy's stab, RR's FLURRY) can land deep inside a perimeter wall, and
// resolve_against_rect then ejects it through the wall's *outside* edge because
// that is the shorter overlap. Clamping back in after the shove closes that
// hole for good.
clamp_to_arena :: proc(pos: ^raylib.Vector2, sz: raylib.Vector2) {
	pos.x = clamp(pos.x, f32(WALL_THICK), f32(ARENA_W) - f32(WALL_THICK) - sz.x)
	pos.y = clamp(pos.y, f32(WALL_THICK), f32(ARENA_H) - f32(WALL_THICK) - sz.y)
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
	add_shake(9)
	append(
		&explosions,
		explosion {
			pos = center,
			life = EXPLOSION_TIME,
			max_life = EXPLOSION_TIME,
			radius = EXPLOSION_RADIUS,
			color = raylib.Color{255, 150, 40, 255},
		},
	)

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
	if raylib.Vector2Distance(pc, center) <= EXPLOSION_RADIUS && inv_timer <= 0 && !tutorial_mode {
		scale := DIFF_ENEMY_DAMAGE[int(difficulty)] * (assists_on() ? GF_DAMAGE_MULT : 1)
		health -= EXPLOSION_DAMAGE * scale
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
	// Practice dummies must not skew run stats, but they still drop a small
	// coin pile so the loot lesson is something you actually kill and collect.
	if tutorial_mode {
		play(sounds.enemy_die, rand.float32_range(0.92, 1.08))
		append(
			&drops,
			drop{position = pos, size = {10, 10}, kind = .CURRENCY, amount = f32(rand.int_range(2, 5)), life = 8.0},
		)
		return
	}
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
		SPEED = min(SPEED + CARD_SPEED_BONUS, f32(MAX_SPEED))
	} else if name == "ATTACK" {
		bonus_damage = min(bonus_damage + CARD_ATTACK_DAMAGE, f32(MAX_BONUS_DAMAGE))
	} else if name == "HEALTH" {
		max_health += CARD_HEALTH_BONUS
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
		spread_cut += CARD_SPREAD_CUT
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
	} else if name == "IGNITE" {
		attack_effects += {.Burn}
	} else if name == "CRYO" {
		attack_effects += {.Freeze}
	} else if name == "VENOM" {
		attack_effects += {.Poison}
	} else if name == "STATIC" {
		attack_effects += {.Shock}
	} else if name == "KINDLING" {
		status_power[.Burn] = min(status_power[.Burn] + 0.5, MAX_STATUS_POWER)
	} else if name == "DEEP FREEZE" {
		status_power[.Freeze] = min(status_power[.Freeze] + 0.5, MAX_STATUS_POWER)
	} else if name == "VIRULENCE" {
		status_power[.Poison] = min(status_power[.Poison] + 0.5, MAX_STATUS_POWER)
	} else if name == "CONDUIT" {
		status_power[.Shock] = min(status_power[.Shock] + 0.5, MAX_STATUS_POWER)
	} else if name == "ELEMENTALIST" {
		status_time_mult = min(status_time_mult * 1.25, MAX_STATUS_TIME_MULT)
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
	// Infusions are one-time (the set either has the element or not); the
	// power/time boosters only make sense once you carry the matching element.
	case "IGNITE":
		return .Burn not_in attack_effects
	case "CRYO":
		return .Freeze not_in attack_effects
	case "VENOM":
		return .Poison not_in attack_effects
	case "STATIC":
		return .Shock not_in attack_effects
	case "KINDLING":
		return .Burn in attack_effects && status_power[.Burn] < MAX_STATUS_POWER
	case "DEEP FREEZE":
		return .Freeze in attack_effects && status_power[.Freeze] < MAX_STATUS_POWER
	case "VIRULENCE":
		return .Poison in attack_effects && status_power[.Poison] < MAX_STATUS_POWER
	case "CONDUIT":
		return .Shock in attack_effects && status_power[.Shock] < MAX_STATUS_POWER
	case "ELEMENTALIST":
		return attack_effects != {} && status_time_mult < MAX_STATUS_TIME_MULT
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

// Map a point in the held weapon's local space (x = forward along the aim,
// y = to the right) into world space, given the hand position and basis.
wep_pt :: proc(hand, fwd, right: raylib.Vector2, lx, ly: f32) -> raylib.Vector2 {
	return hand + fwd * lx + right * ly
}

// Draw the held gun. Each look is built from a few lines and circles so no two
// weapons read alike; a live `muzzle_flash` adds the flash at the barrel.
draw_held_gun :: proc(look: Weapon_Look) {
	fwd := aim_dir
	if raylib.Vector2Length(fwd) < 0.01 {
		fwd = {1, 0}
	}
	fwd = raylib.Vector2Normalize(fwd)
	right := raylib.Vector2{-fwd.y, fwd.x}
	hand := position + size * 0.5 + fwd * (size.x * 0.28)

	metal := raylib.Color{104, 112, 128, 255}
	steel := raylib.Color{68, 74, 86, 255}
	dark := raylib.Color{34, 38, 48, 255}
	wood := raylib.Color{126, 84, 48, 255}
	firing := muzzle_flash > 0

	// Guns only; melee looks never reach here (melee draws via draw_melee_model).
	#partial switch look {
	case .PISTOL, .AUTO:
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 2, 0), wep_pt(hand, fwd, right, 17, 0), 6, metal)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 4, 2), wep_pt(hand, fwd, right, 2, 11), 7, dark)
		if firing {
			raylib.DrawCircleV(wep_pt(hand, fwd, right, 18, 0), 6, raylib.GOLD)
		}
	case .REVOLVER:
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 4, 0), wep_pt(hand, fwd, right, 19, 0), 6, metal)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 8, 0), 6, dark)
		raylib.DrawCircleLinesV(wep_pt(hand, fwd, right, 8, 0), 6, steel)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 4, 2), wep_pt(hand, fwd, right, 2, 12), 7, wood)
		if firing {
			raylib.DrawCircleV(wep_pt(hand, fwd, right, 20, 0), 6, raylib.GOLD)
		}
	case .DUAL:
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 2, -5), wep_pt(hand, fwd, right, 15, -5), 5, metal)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 2, 5), wep_pt(hand, fwd, right, 15, 5), 5, metal)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 4, -3), wep_pt(hand, fwd, right, 2, -11), 6, dark)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 4, 3), wep_pt(hand, fwd, right, 2, 11), 6, dark)
		if firing {
			raylib.DrawCircleV(wep_pt(hand, fwd, right, 16, -5), 4, raylib.GOLD)
			raylib.DrawCircleV(wep_pt(hand, fwd, right, 16, 5), 4, raylib.GOLD)
		}
	case .SMG:
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -2, 0), wep_pt(hand, fwd, right, 15, 0), 9, dark)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 15, 0), wep_pt(hand, fwd, right, 23, 0), 4, metal)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 12, 4), wep_pt(hand, fwd, right, 10, 14), 5, steel)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 4, 4), wep_pt(hand, fwd, right, 2, 12), 6, dark)
		if firing {
			raylib.DrawCircleV(wep_pt(hand, fwd, right, 24, 0), 4, raylib.GOLD)
		}
	case .RIFLE:
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -10, 2), wep_pt(hand, fwd, right, 2, 2), 7, wood)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -2, 0), wep_pt(hand, fwd, right, 22, 0), 6, dark)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 22, 0), wep_pt(hand, fwd, right, 33, 0), 3, metal)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 14, 4), wep_pt(hand, fwd, right, 12, 14), 5, steel)
		if firing {
			raylib.DrawCircleV(wep_pt(hand, fwd, right, 34, 0), 4, raylib.GOLD)
		}
	case .SHOTGUN:
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -10, 2), wep_pt(hand, fwd, right, 2, 2), 8, wood)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 2, 0), wep_pt(hand, fwd, right, 29, 0), 8, metal)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 13, 5), wep_pt(hand, fwd, right, 22, 5), 9, wood)
		if firing {
			raylib.DrawCircleV(wep_pt(hand, fwd, right, 30, 0), 7, raylib.GOLD)
		}
	case .MINIGUN:
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -2, 0), wep_pt(hand, fwd, right, 13, 0), 14, dark)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 13, -5), wep_pt(hand, fwd, right, 31, -5), 3, metal)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 13, 0), wep_pt(hand, fwd, right, 32, 0), 3, metal)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 13, 5), wep_pt(hand, fwd, right, 31, 5), 3, metal)
		if firing {
			raylib.DrawCircleV(wep_pt(hand, fwd, right, 32, 0), 5, raylib.GOLD)
		}
	case .CANNON:
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -2, 0), wep_pt(hand, fwd, right, 17, 0), 18, dark)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 17, 0), wep_pt(hand, fwd, right, 27, 0), 14, steel)
		raylib.DrawCircleLinesV(wep_pt(hand, fwd, right, 27, 0), 8, metal)
		if firing {
			raylib.DrawCircleV(wep_pt(hand, fwd, right, 29, 0), 10, raylib.GOLD)
		}
	case .SNIPER:
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -12, 2), wep_pt(hand, fwd, right, 2, 2), 7, wood)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 0, 0), wep_pt(hand, fwd, right, 20, 0), 6, dark)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 20, 0), wep_pt(hand, fwd, right, 42, 0), 3, metal)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 13, -7), 5, dark)
		raylib.DrawCircleLinesV(wep_pt(hand, fwd, right, 13, -7), 5, steel)
		if firing {
			raylib.DrawCircleV(wep_pt(hand, fwd, right, 43, 0), 4, raylib.GOLD)
		}
	}
}

// Shared material palette for the melee models. Guns keep their own colour
// locals, but every hand-built melee weapon pulls from here so they all read as
// the same set. `WEAPON_OUTLINE` is the dark stamp laid behind held/worn weapons
// so they still show on the brighter arenas, the way a character's outline does.
WEAPON_OUTLINE :: raylib.Color{18, 18, 24, 255}
WEAPON_GRIP :: raylib.Color{70, 74, 84, 255}
WEAPON_METAL :: raylib.Color{104, 112, 128, 255}
WEAPON_STEEL :: raylib.Color{68, 74, 86, 255}
WEAPON_DARK :: raylib.Color{34, 38, 48, 255}
WEAPON_WOOD :: raylib.Color{126, 84, 48, 255}

// Draw one melee weapon model at `hand`, pointing along `fwd` with `right`
// perpendicular. `stats.flash_color` is the weapon's accent (blade steel, claw
// glow, ...). Shared by the held weapon and the signature worn on the back, so
// a given weapon always looks the same wherever it appears. A weapon with no
// explicit `look` falls back to the shape-driven stick below.
draw_melee_model :: proc(
	look: Weapon_Look,
	stats: Weapon_Stats,
	hand, fwd, right: raylib.Vector2,
) {
	col := stats.flash_color
	ang := math.atan2_f32(fwd.y, fwd.x) * raylib.RAD2DEG
	#partial switch look {
	case .DAGGER:
		// Short blade: pommel, wrapped grip, crossguard, tapered point.
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -9, 0), wep_pt(hand, fwd, right, 0, 0), 6, WEAPON_OUTLINE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -8, 0), wep_pt(hand, fwd, right, 1, 0), 4, WEAPON_GRIP)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 0, -6), wep_pt(hand, fwd, right, 0, 6), 4, WEAPON_OUTLINE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 0, -5), wep_pt(hand, fwd, right, 0, 5), 2, WEAPON_METAL)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 1, 0), wep_pt(hand, fwd, right, 19, 0), 9, WEAPON_OUTLINE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 1, 0), wep_pt(hand, fwd, right, 19, 0), 5, col)
		raylib.DrawLineEx(
			wep_pt(hand, fwd, right, 3, 1.5),
			wep_pt(hand, fwd, right, 18, 1.5),
			1,
			raylib.WHITE,
		)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 20, 0), 3.5, WEAPON_OUTLINE)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 20, 0), 2.5, col)
	case .SPEAR:
		// Long shaft with a leaf head; the shaft scales with reach.
		l := clamp(stats.reach * 0.30, f32(26), f32(54))
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -l * 0.5, 0), wep_pt(hand, fwd, right, l * 0.5, 0), 5, WEAPON_OUTLINE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -l * 0.45, 0), wep_pt(hand, fwd, right, l * 0.5, 0), 3, WEAPON_WOOD)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, -l * 0.5, 0), 3, WEAPON_OUTLINE)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, -l * 0.5, 0), 2, WEAPON_METAL)
		head := wep_pt(hand, fwd, right, l * 0.5, 0)
		mid := wep_pt(hand, fwd, right, l * 0.5 + 5, 0)
		tip := wep_pt(hand, fwd, right, l * 0.5 + 14, 0)
		raylib.DrawLineEx(head, tip, 9, WEAPON_OUTLINE)
		raylib.DrawCircleV(mid, 6, WEAPON_OUTLINE)
		raylib.DrawLineEx(head, tip, 5, col)
		raylib.DrawCircleV(mid, 5, col)
		raylib.DrawCircleV(tip, 2.5, col)
	case .BATON:
		// Rounded baton: a wrapped grip and a weighted head.
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -11, 0), wep_pt(hand, fwd, right, 14, 0), 9, WEAPON_OUTLINE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -10, 0), wep_pt(hand, fwd, right, 14, 0), 6, WEAPON_DARK)
		for k in 0 ..< 3 {
			x := -9 + f32(k) * 3
			raylib.DrawLineEx(wep_pt(hand, fwd, right, x, -3), wep_pt(hand, fwd, right, x, 3), 2, WEAPON_STEEL)
		}
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 17, 0), 8, WEAPON_OUTLINE)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 17, 0), 6, WEAPON_METAL)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 17, 0), 2.5, col)
	case .HAMMER:
		// Wooden haft with a blocky steel head across the tip.
		l := clamp(stats.reach * 0.20, f32(12), f32(18))
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -12, 0), wep_pt(hand, fwd, right, l, 0), 8, WEAPON_OUTLINE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -11, 0), wep_pt(hand, fwd, right, l, 0), 5, WEAPON_WOOD)
		head := wep_pt(hand, fwd, right, l + 3, 0)
		hw, hh := f32(11), f32(26)
		raylib.DrawRectanglePro(
			raylib.Rectangle{head.x, head.y, hw, hh},
			{hw * 0.5, hh * 0.5},
			ang,
			WEAPON_OUTLINE,
		)
		iw, ih := f32(8), f32(22)
		raylib.DrawRectanglePro(
			raylib.Rectangle{head.x, head.y, iw, ih},
			{iw * 0.5, ih * 0.5},
			ang,
			WEAPON_STEEL,
		)
		// Bright striking face on the leading edge.
		raylib.DrawLineEx(
			wep_pt(hand, fwd, right, l + 8, -10),
			wep_pt(hand, fwd, right, l + 8, 10),
			3,
			col,
		)
	case .BLADE:
		// RR's Vector Edge: a long tech blade with an energy node.
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -11, 0), wep_pt(hand, fwd, right, 0, 0), 6, WEAPON_OUTLINE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -10, 0), wep_pt(hand, fwd, right, 1, 0), 4, WEAPON_GRIP)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 0, -8), wep_pt(hand, fwd, right, 0, 8), 5, WEAPON_OUTLINE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 0, -7), wep_pt(hand, fwd, right, 0, 7), 3, WEAPON_METAL)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 4, 0), 3.5, col)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 4, 0), 1.5, raylib.WHITE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 1, 0), wep_pt(hand, fwd, right, 29, 0), 10, WEAPON_OUTLINE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 1, 0), wep_pt(hand, fwd, right, 29, 0), 6, col)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 3, 2), wep_pt(hand, fwd, right, 28, 2), 1.5, raylib.WHITE)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 31, 0), 3.5, col)
	case .CLAWS:
		// Three phase prongs off a palm plate.
		raylib.DrawCircleV(wep_pt(hand, fwd, right, -1, 0), 7, WEAPON_OUTLINE)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, -1, 0), 5, WEAPON_DARK)
		for k in -1 ..= 1 {
			base := wep_pt(hand, fwd, right, 2, f32(k) * 3)
			tip := wep_pt(hand, fwd, right, 17, f32(k) * 6)
			raylib.DrawLineEx(base, tip, 5, WEAPON_OUTLINE)
			raylib.DrawLineEx(base, tip, 3, col)
			raylib.DrawCircleV(tip, 2, col)
		}
	case .BAYONET:
		// A rifle body with a long blade fixed under the muzzle.
		l := clamp(stats.reach * 0.24, f32(20), f32(32))
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -14, 2), wep_pt(hand, fwd, right, -5, 2), 7, WEAPON_WOOD)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -14, 0), wep_pt(hand, fwd, right, 10, 0), 8, WEAPON_OUTLINE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -13, 0), wep_pt(hand, fwd, right, 10, 0), 5, WEAPON_DARK)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 2, 4), wep_pt(hand, fwd, right, 0, 12), 5, WEAPON_OUTLINE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 2, 4), wep_pt(hand, fwd, right, 1, 11), 3, WEAPON_STEEL)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 9, 0), wep_pt(hand, fwd, right, l, 0), 6, WEAPON_OUTLINE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 9, 0), wep_pt(hand, fwd, right, l, 0), 3, col)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, l + 1, 0), 2.5, col)
	case .FISTS:
		// A closed fist with three metal knuckles and a wrist wrap.
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 3, 0), 7, WEAPON_OUTLINE)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 3, 0), 6, WEAPON_GRIP)
		for k in -1 ..= 1 {
			raylib.DrawCircleV(wep_pt(hand, fwd, right, 8, f32(k) * 3.2), 2, WEAPON_METAL)
		}
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -4, -5), wep_pt(hand, fwd, right, -4, 5), 4, col)
	case .BOOT:
		// A boot: shin, rounded foot, and a sole edge.
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -9, 0), wep_pt(hand, fwd, right, 4, 0), 9, WEAPON_OUTLINE)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, -8, 0), wep_pt(hand, fwd, right, 4, 0), 6, WEAPON_DARK)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 7, 0), 6, WEAPON_OUTLINE)
		raylib.DrawCircleV(wep_pt(hand, fwd, right, 7, 0), 5, WEAPON_DARK)
		raylib.DrawLineEx(wep_pt(hand, fwd, right, 3, 4), wep_pt(hand, fwd, right, 11, 4), 2, WEAPON_STEEL)
	case:
		draw_melee_generic(stats, hand, fwd, right)
	}
}

// Fallback silhouette built from the swing geometry (shape/reach/arc), used for
// a melee weapon that has no explicit `look`.
draw_melee_generic :: proc(stats: Weapon_Stats, hand, fwd, right: raylib.Vector2) {
	switch stats.shape {
	case .THRUST:
		// A slim blade. `arc` is the swing's half-width, not the blade's, so the
		// visual stays knife-thin instead of ballooning into a plank.
		halfw := clamp(1 + stats.arc * 0.25, f32(2), f32(4.5))
		blade := hand + fwd * (stats.reach * 0.62)
		raylib.DrawLineEx(hand, hand - fwd * 8, 5, WEAPON_GRIP)
		raylib.DrawLineEx(hand - right * (halfw + 3), hand + right * (halfw + 3), 3, WEAPON_GRIP)
		raylib.DrawLineEx(hand, blade + fwd * 2, halfw * 2 + 2, WEAPON_OUTLINE)
		raylib.DrawLineEx(hand, blade + fwd * 2, halfw * 2, stats.flash_color)
		raylib.DrawLineEx(
			hand + right * halfw * 0.45,
			blade,
			max(f32(1), halfw * 0.5),
			raylib.WHITE,
		)
		raylib.DrawCircleV(blade, halfw, stats.flash_color)
	case .SECTOR:
		// A weighted baton: short haft with a round head.
		head := hand + fwd * (stats.reach * 0.48)
		r := clamp(6 + stats.arc * 10, f32(9), f32(18))
		raylib.DrawLineEx(hand, head, 12, WEAPON_OUTLINE)
		raylib.DrawLineEx(hand, head, 7, WEAPON_GRIP)
		raylib.DrawCircleV(head, r + 3, WEAPON_OUTLINE)
		raylib.DrawCircleV(head, r, stats.flash_color)
	case .BLAST:
		// A hammer: haft with a heavy head.
		head := hand + fwd * (stats.reach * 0.52)
		r := clamp(stats.arc * 0.5, f32(10), f32(26))
		raylib.DrawLineEx(hand, head, 12, WEAPON_OUTLINE)
		raylib.DrawLineEx(hand, head, 6, WEAPON_GRIP)
		raylib.DrawCircleV(head, r + 4, WEAPON_OUTLINE)
		raylib.DrawCircleV(head, r, stats.flash_color)
		raylib.DrawCircleLinesV(head, r, raylib.WHITE)
	}
}

// Draw the melee weapon held in the active slot. Pool weapons carry their own
// `look`; on the signature slot every combo step shares the character's model,
// while the stats still come from the armed combo step so a charged strike
// reads.
draw_held_melee :: proc(ws: Weapon_Stats) {
	fwd := aim_dir
	if raylib.Vector2Length(fwd) < 0.01 {
		fwd = {1, 0}
	}
	fwd = raylib.Vector2Normalize(fwd)
	right := raylib.Vector2{-fwd.y, fwd.x}
	hand := position + size * 0.5 + fwd * (size.x * 0.34)
	look := ws.look
	if active_slot == SLOT_SIGNATURE {
		look = SIGNATURE_LOOK[character]
	}
	draw_melee_model(look, ws, hand, fwd, right)
}

// The character's signature weapon, worn across the back whenever it is not the
// slot in hand, so your melee weapon is always visible on the body. It reuses
// the same model the held weapon draws with. Bud's "weapon" is his own hands, so
// his gloves ride at the hips instead of on his back.
draw_worn_signature :: proc() {
	sig := signature_at(0)
	pc := position + size * 0.5
	look := SIGNATURE_LOOK[character]
	if look == .FISTS {
		for k in 0 ..< 2 {
			side := f32(k) * 2 - 1
			hand := pc + raylib.Vector2{side * size.x * 0.62, size.y * 0.18}
			dir := raylib.Vector2{side, 0}
			draw_melee_model(.FISTS, sig, hand, dir, raylib.Vector2{-dir.y, dir.x})
		}
		return
	}
	// Laid diagonally over the shoulder; the body stamps over the middle, so
	// only the ends stick out.
	tilt := raylib.Vector2Normalize({0.72, -0.7})
	right := raylib.Vector2{-tilt.y, tilt.x}
	hand := pc - tilt * (size.x * 0.35)
	draw_melee_model(look, sig, hand, tilt, right)
}

// Draw the weapon currently in the active slot (gun or melee).
draw_held_weapon :: proc() {
	ws := active_stats()
	if ws.class == .MELEE {
		draw_held_melee(ws)
	} else {
		draw_held_gun(ws.look)
	}
}

// The player's in-world body, using the currently chosen character. The
// signature weapon rides on the back while the slot in hand is a gun or a
// picked-up melee, and comes forward when the signature slot is active.
draw_player :: proc() {
	// RR's BULWARK guard is drawn first so the body stamps over its centre and
	// only the front rim reads as a shield. It flares white on a cancelled hit.
	if rr_block || block_flash > 0 {
		pc := position + size * 0.5
		a := math.atan2_f32(aim_dir.y, aim_dir.x) * raylib.RAD2DEG
		deg := f32(RR_BLOCK_ARC * raylib.RAD2DEG)
		t := clamp(block_flash / BLOCK_FLASH_TIME, 0, 1)
		r := size.x * 1.25
		raylib.DrawCircleSector(
			pc,
			r,
			a - deg,
			a + deg,
			16,
			raylib.Color{120, 200, 255, u8(120 + 100 * t)},
		)
		raylib.DrawCircleSectorLines(
			pc,
			r,
			a - deg,
			a + deg,
			16,
			raylib.Color{190, 235, 255, u8(160 + 95 * t)},
		)
	}
	if active_slot != SLOT_SIGNATURE {
		draw_worn_signature()
	}
	draw_character_body(CHARACTERS[character], position + size * 0.5, size * 0.5)
	draw_held_weapon()
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
