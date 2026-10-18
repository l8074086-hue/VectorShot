package main
import "vendor:raylib"

GameState :: enum {
	MAIN_MENU,
	DIFFICULTY,
	MISSION_CONTROL,
	EQUIPMENT,
	TUTORIAL_SELECT,
	TUTORIAL,
	SETTINGS,
	SKILL_SELECT,
	PLAYING,
	SHOP,
	GAME_OVER,
}

// Official difficulty. EASY turns on the same assists GF mode (Ctrl+G) toggles
// mid-run; HARD keeps the baseline rules but hits harder and moves faster.
Difficulty :: enum {
	EASY,
	NORMAL,
	HARD,
}

SkillSlotState :: enum {
	MAIN,
	CHARACTER,
	GUN,
	DASH,
	UTILITY,
	SECONDARY,
	ARENA,
}

BULLET_MAX_HITS :: 8

// Status effects carried by enemies and projectiles. A set (rather than a
// list of names) so membership tests are cheap, copies are value-semantics,
// and there's no allocation to manage.
Status_Effect :: enum {
	Burn,
	Freeze,
	Poison,
	Shock,
}

Status_Set :: bit_set[Status_Effect]

bullet :: struct {
	position:  raylib.Vector2,
	size:      raylib.Vector2,
	velocity:  raylib.Vector2,
	damage:    f32,
	pierce:    i32, // how many more enemies this shot can pass through
	hits:      [BULLET_MAX_HITS]i32, // enemy ids already damaged
	hit_count: int,
	// Boomerang shards (elite RANGED only): fly out to `max_range`, then head
	// back the way they came.
	boomerang: bool,
	returning: bool,
	traveled:  f32,
	max_range: f32,
	// Effects this shot applies to whatever it hits.
	effects:   Status_Set,
	// RR's Second Wind blade wind: a thrown crescent, drawn as an arc instead
	// of a box.
	wind:      bool,
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

trail_point :: struct {
	pos:  raylib.Vector2,
	life: f32,
}

enemy :: struct {
	position:      raylib.Vector2,
	size:          raylib.Vector2,
	velocity:      raylib.Vector2,
	attacking:     bool,
	color:         raylib.Color,
	damage:        f32,
	hp:            f32,
	max_hp:        f32,
	id:            i32,
	speed:         f32,
	kind:          Enemy_Kind,
	state:         Enemy_State,
	state_timer:   f32,
	fire_cooldown: f32,
	charge_dir:    raylib.Vector2, // locked-in direction while charging
	elite:         bool,
	// Crystalized-elite state. `plates` = Bulwark crystal plates left; other
	// elites use `ability_timer` for their ability cooldown and `flash` for a
	// brief white tell after acting.
	plates:        i32,
	elite_step:    i32, // RUNNER: dashes left in the current burst
	ability_timer: f32,
	flash:         f32,
	// Muzzle flash: counts down after this enemy fires, and remembers the way it
	// fired so the flash draws at the barrel it shot from. Purely visual.
	muzzle:        f32,
	muzzle_dir:    raylib.Vector2,
	// BOSS (WARDEN): whether it has flipped into its faster second phase, the
	// angle its radial shot is currently spinning from, and which attack the
	// current WINDUP telegraph is building toward (0 volley, 1 slam).
	boss_phase:    i32,
	boss_spin:     f32,
	boss_next:     i32,
	// Per-boss moveset scratch (see boss.odin).
	boss_kind:     Boss_Kind,     // which arena boss this is, for dispatch
	boss_seq:      i32,           // sub-step within the current attack
	boss_timer2:   f32,           // secondary timer (between-attack pacing)
	boss_hidden:   bool,          // DUSTMAW: burrowed (invulnerable, no contact)
	boss_aux:      raylib.Vector2,// scratch aim/dash/target direction
	// MECHANIKTRON: seconds left in its exposed window (its weakpoint is only
	// vulnerable while this runs), and how many full crystal-clears it has
	// survived (each one makes the next exposed window longer).
	boss_stun:     f32,
	boss_clears:   i32,
	// Bulwark (elite TANK): each crystal plate guards one world-space direction.
	// A hit arriving from roughly that direction shatters it; while any plate
	// remains the armored body shrugs off hp damage.
	plate_dir:     [ELITE_TANK_PLATES]raylib.Vector2,
	plate_live:    [ELITE_TANK_PLATES]bool,
	// Active status effects on this enemy, plus how many seconds each has left.
	// The set is the source of truth for "is it active"; the timer array is
	// indexed by effect and only meaningful while the matching bit is set.
	effects:       Status_Set,
	effect_timer:  [Status_Effect]f32,
	// Tracer's Phase Claws: PHASE marks stack from her light hits and her REND
	// finisher consumes them for a burst. `phase_time` counts down to a decay if
	// the enemy is left alone, so the marks have to be spent, not banked.
	phase_marks:   i32,
	phase_time:    f32,
	// DUMMY_PATROL: a fixed patrol route. `patrol_count` of the first slots in
	// `patrol_points` are live (world positions of the dummy's center) and
	// `patrol_index` is the waypoint being walked toward. A fixed array (not
	// [dynamic]) keeps the enemy plain-old-data, so removing/clearing enemies
	// never leaks.
	patrol_points: [DUMMY_PATROL_POINTS]raylib.Vector2,
	patrol_count:  i32,
	patrol_index:  i32,
	// DUMMY_RANGED: the locked-in direction it fires. It never aims at the
	// player, so a lesson can stand safely to one side of the firing line.
	shoot_dir:     raylib.Vector2,
	// DUMMY_DPS training readout. `dps_window` accumulates damage taken since the
	// last sample, `dps_value` is the damage-per-second shown on the bar, and
	// `dps_timer` counts toward the next sample. Harmless on every other kind.
	dps_window:    f32,
	dps_value:     f32,
	dps_timer:     f32,
}

// Enemy kinds that exist only to be shot in tutorial arenas. `pick_enemy_kind`
// never returns these, so they can't leak into a real wave.
Enemy_Kind :: enum {
	GRUNT,
	RUNNER,
	TANK,
	RANGED,
	CHARGER,
	SPLITTER, // dies into two smaller copies of itself
	ORBITER,  // circles the player at a fixed radius, occasionally darting in
	SNIPER,   // long-range; telegraphs then fires a fast aimed shot
	BOSS,     // multi-phase set-piece, spawned on boss waves (never in pick_enemy_kind)
	DUMMY_DPS,    // big, stationary target with a deep health pool
	DUMMY_RANGED, // stationary; fires along a fixed direction on a timer
	DUMMY_WEAK,   // fragile stationary target; dies to a single hit
	DUMMY_PATROL, // walks a fixed patrol route forever
}

// What a hit on an enemy actually did, so callers can pick the right feedback.
Enemy_Hit :: enum {
	DAMAGE, // hp was reduced
	BLOCKED, // a Bulwark's armored body absorbed it (plates still intact)
	SHATTER, // a Bulwark crystal plate broke off
}

// Ranged/charger enemies use a tiny state machine.
Enemy_State :: enum {
	CHASE,
	WINDUP,  // charger/sniper/boss telegraphing its next attack
	CHARGE,  // charger mid-dash
	RECOVER, // brief pause after a charge
	STRAFE,  // ranged keeping its distance
	// Boss (WARDEN) states: it cycles telegraph -> attack -> recover, and flips
	// to its faster second phase below half health.
	// Boss moveset states. Each boss's own update picks an attack into
	// e.boss_next and telegraphs it in WINDUP, then runs it here.
	BOSS_SHOOT,  // firing a ranged attack
	BOSS_SLAM,   // a telegraphed ground attack / stomp
	BOSS_RAGE,   // phase-2 enrage flourish before the fight resumes
	BOSS_ATTACK, // executing the chosen attack (dispatched per Boss_Kind)
	BOSS_BURROW, // DUSTMAW: underground, untargetable, drifting to strike
	BOSS_EMERGE, // DUSTMAW: rising out of the ground, now vulnerable
}

Enemy_Stats :: struct {
	name:            cstring,
	size:            raylib.Vector2,
	speed:           f32,
	damage:          f32,
	hp:              f32,
	color:           raylib.Color,
	ranged:          bool,
	preferred_range: f32, // RANGED tries to hover at this distance
	fire_rate:       f32, // seconds between RANGED shots
	charge_speed:    f32, // CHARGER dash speed
	// Status effects this enemy's hits inflict (and, for now, none are set).
	effects:         Status_Set,
	// Wave-spawn weighting. `spawn_weight` is this type's relative share of a
	// wave (only compared against types already unlocked); `unlock_wave` is the
	// first wave it can appear on. A weight of 0 never spawns (bosses, dummies).
	spawn_weight:    f32,
	unlock_wave:     i32,
}

Drop_Kind :: enum {
	HEALTH,
	AMMO,
	CURRENCY,
	RELIC_CHEST, // boss-only: walk over it to draw a relic (accept or discard)
}

// Relic: a rare permanent passive for the run, drawn from a chest a boss drops.
// You accept or discard it, so a draw is never forced.
Relic_Kind :: enum {
	VAMPIRE_FANG,   // heal a little on every kill
	IRON_STEADY,    // + max health
	SWIFT_SOLE,     // + move speed
	SHARP_EDGE,     // cut spread
	QUICK_WRIST,    // faster melee swings
	THICK_MAG,      // bigger magazines
	BULLET_RESERVE, // more reserve ammo
	HEAVY_BARREL,   // + damage
}

Relic :: struct {
	name: cstring,
	desc: cstring,
}

// Pickups left behind by slain enemies. Ammo drops can reuse this.
drop :: struct {
	position: raylib.Vector2,
	size:     raylib.Vector2,
	kind:     Drop_Kind,
	amount:   f32,
	life:     f32, // seconds before it despawns
}

// Static environment props.
barrel :: struct {
	pos:  raylib.Vector2,
	size: raylib.Vector2,
	hp:   f32,
}

// A MECHANIKTRON power crystal: a destructible backfield target. Shattering the
// whole set stuns the boss and opens its weakpoint for a short window.
crystal :: struct {
	pos:    raylib.Vector2,
	size:   raylib.Vector2,
	hp:     f32,
	max_hp: f32,
	flash:  f32,
}

// A thrown rock: MECHANIKTRON's straight-flying rockets and COLOSSUS's heavy
// arcing boulders share one entity. Both detonate on the first thing they
// touch (player, cover or wall) or when the fuse runs out; only `gravity` and
// the size/blast fields make a boulder arc and land like a rock.
rocket :: struct {
	pos:     raylib.Vector2,
	vel:     raylib.Vector2,
	life:    f32,
	damage:  f32,
	size:    f32,          // hit/draw box edge
	blast:   f32,          // explosion radius where it lands
	gravity: f32,          // downward accel; 0 flies flat like a rocket
	boulder: bool,         // draws as a tumbling rock, not a slim shell
	color:   raylib.Color,
}

// Static cover. All kinds are solid to movement and bullets (they live in the
// same "props" list the obstacle resolver walks) but draw differently so an
// arena reads as a place rather than a pile of identical circles.
Prop_Kind :: enum {
	TREE,  // round canopy on a trunk
	PINE,  // conical evergreen
	ROCK,  // boulder
	CRATE, // square supply crate
}

prop :: struct {
	pos:  raylib.Vector2,
	size: raylib.Vector2,
	kind: Prop_Kind,
}

// Scattered floor detail (grass tufts, pebbles, cracks, embers...). Purely
// decorative: it never collides, it just stops large flat floors reading as a
// flat checkerboard.
Floor_Decor :: enum {
	GRASS,  // grass tufts
	PEBBLE, // scattered stones
	CRACK,  // hairline fractures
	SNOW,   // snow patches
	EMBER,  // glowing hot flecks
}

floor_mark :: struct {
	pos:  raylib.Vector2,
	size: f32,
	kind: Floor_Decor,
}

// Purely visual blast marker shown after a barrel pops.
explosion :: struct {
	pos:      raylib.Vector2,
	life:     f32,
	max_life: f32,
	radius:   f32,
	color:    raylib.Color,
}

// A short-lived bright fleck thrown off by an impact or a kill. Sparks are the
// game's universal "something connected" cue: unlike the blood spray they are
// always on, because they carry hit confirmation rather than gore.
spark :: struct {
	pos:      raylib.Vector2,
	vel:      raylib.Vector2,
	life:     f32,
	max_life: f32,
	size:     f32,
	color:    raylib.Color,
}

// Floating damage number (enemy hp lost), drifting up and fading out. Purely
// informational, gated by the damage-numbers setting.
damage_number :: struct {
	pos:   raylib.Vector2,
	vel:   raylib.Vector2,
	life:  f32,
	value: f32,
	color: raylib.Color,
}

// A blood droplet/burst: flies out from an enemy hit, settles and fades. Used
// as both spray and floor splatter, gated by the blood setting.
blood_drop :: struct {
	pos:      raylib.Vector2,
	vel:      raylib.Vector2,
	life:     f32,
	max_life: f32,
	size:     f32,
	color:    raylib.Color,
}

// Primary-slot weapons. The list mixes guns and melee blades; Weapon_Stats.class
// says which, and everything (select screen, firing, HUD) treats them uniformly.
Gun :: enum {
	SNIPER,
	SHOTGUN,
	SMG,
	RIFLE,
	MINIGUN,
	CANNON,
	KNIFE,
	BATON,
	HAMMER,
	SPEAR,
}

// Secondary-slot weapons: the sidearm pool, which also mixes guns and melee.
Secondary :: enum {
	PISTOL,
	REVOLVER,
	DUAL,
	SAWED,
	KNIFE,
	BATON,
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
	TRIGGER,
	DEADEYE,
	SCOUT,
	PACKRAT,
}

// Each arena is a distinct wall/prop layout plus a color theme. Chosen on the
// loadout screen and rebuilt at the start of every run.
Arena_Kind :: enum {
	GRASSLAND,
	CANYON,
	RUINS,
	GLACIER,
	FOUNDRY,
	FOREST,
	SWAMP,
}

// Ambient sky weather for an arena. Drawn as a screen-space foreground overlay on
// top of the game, so it reads as "falling from the sky" over the top-down view.
// Each kind uses the same particle pool but different drift, size and colour.
Weather_Kind :: enum {
	NONE,
	SNOW, // slow drifting white flakes
	RAIN, // fast vertical streaks
	ASH,  // slow drifting hot embers
	DUST, // fast horizontal grit
}

// One ambient weather particle. Positions are in screen space and wrap around, so
// the field is cheap and endless.
weather_particle :: struct {
	pos:  raylib.Vector2,
	vel:  raylib.Vector2,
	size: f32,
}

Arena_Stats :: struct {
	name:        cstring,
	desc:        cstring,
	floor_dark:  raylib.Color,
	floor_light: raylib.Color,
	wall:        raylib.Color,
	cover:       raylib.Color, // prop body
	cover_top:   raylib.Color, // prop highlight
	decor:       Floor_Decor,  // kind of floor scatter
	decor_col:   raylib.Color, // floor scatter tint
	weather:     Weather_Kind, // ambient sky effect, if any
	// How many normal waves this arena runs before its boss arrives. The boss
	// wave is the arena's finale: beat it to clear the map (and continue as
	// endless survival). Later maps are longer.
	waves:       i32,
}

// The set-piece boss that guards an arena, keyed by Arena_Kind so every map has
// its own look, stats and attack flavour. One boss per run: it spawns once on
// its arena's final wave and never appears in the normal spawn table.
// Every arena's boss is a distinct fight, so its AI, telegraphs and
// silhouette dispatch on this kind instead of sharing one generic state
// machine. One boss per arena, keyed from ARENA_BOSSES.
Boss_Kind :: enum {
	PACKLEADER,  // GRASSLAND: wolf alpha -- poison arrows, a runner pack, side dashes
	DUSTMAW,     // CANYON: burrowing worm -- pops up to strike, then hides again
	COLOSSUS,    // RUINS: stone titan -- stomps, hurled rubble, charges
	FROSTBITE,   // GLACIER: ice wraith -- icicle fans, frost novas, blinks
	MECHANIKTRON, // FOUNDRY: war machine -- rockets + hand slams, invulnerable
	              // except for a back weakpoint opened by shattering its crystals
	THORNWALD,   // FOREST: tree horror -- thorn spirals, root lashes, saplings
	BOGWRAITH,   // SWAMP: bog spirit -- poison novas, phasing, wisps
}

Arena_Boss :: struct {
	name:            cstring,
	kind:            Boss_Kind, // picks the moveset, telegraphs and silhouette
	color:           raylib.Color,
	size:            raylib.Vector2,
	hp:              f32,
	speed:           f32,
	damage:          f32,
	preferred_range: f32, // distance the boss tries to hold (where it applies)
}

// What a mission (level) asks you to do. `target` is a wave number for SURVIVE
// and an enemy count for KILLS/ELITES.
Objective_Kind :: enum {
	SURVIVE, // reach wave N
	KILLS,    // kill N enemies
	ELITES,   // kill N elites
}

// A selectable mission ("level") on the Mission Control screen. Each pairs an
// objective with a forced arena and a wave-density modifier, and pays a coin
// bonus the moment the objective is met mid-run (the run then continues as
// normal endless survival). Progress (which missions are cleared) lives in
// settings.missions_done as a bitmask.
Mission :: struct {
	name:      cstring,
	objective: Objective_Kind,
	target:    i32,
	arena:     Arena_Kind,
	density:   f32, // enemy-count multiplier applied to this mission's waves
	reward:    i32, // bonus coins granted on completion
}

// What a weapon slot actually is. Guns spend ammo and fire bullets; melee
// weapons swing an arc and are always ready.
Weapon_Class :: enum {
	GUN,
	MELEE,
}

// How a *held* gun is drawn in the player's hands. `AUTO` falls back to a plain
// pistol. Melee weapons ignore this and draw from their swing shape instead, so
// a knife, baton, hammer and spear each already read differently.
Weapon_Look :: enum {
	AUTO,
	// Guns.
	PISTOL,
	REVOLVER,
	DUAL,
	SMG,
	RIFLE,
	SHOTGUN,
	MINIGUN,
	CANNON,
	SNIPER,
	// Melee. Each names a hand-built silhouette (see draw_melee_model), so a
	// knife, spear, baton and hammer all read differently instead of sharing a
	// generic per-shape stick.
	DAGGER,
	SPEAR,
	BATON,
	HAMMER,
	BLADE, // RR's Vector Edge
	CLAWS, // Tracer's Phase Claws
	BAYONET, // Navy's Bayonet
	FISTS, // Bud's Fists
	BOOT, // the universal kick
}

// The hitbox *and* the drawn flash of a melee swing. The two always share the
// same geometry, so what you see is exactly what you hit.
//   SECTOR - a wedge: `reach` long, `arc` is the half-angle in radians.
//   THRUST - a rectangle: `reach` long, `arc` is the half-width in px.
//   BLAST  - a circle centred `reach` ahead of you, radius `arc` (px).
Melee_Shape :: enum {
	SECTOR,
	THRUST,
	BLAST,
}

// RR's Adaptation picks whichever of these he has invested in most.
RR_Adaptation :: enum {
	OFFENSE,
	MOBILITY,
	RESILIENCE,
	PRECISION,
}

// One entry in a weapon pool (primary or secondary). Guns fill the ballistic
// fields; melee weapons leave those at zero and fill `reach`/`arc`/`knockback`.
// `damage`, `cooldown` and `weight` apply to both.
Weapon_Stats :: struct {
	class:             Weapon_Class,
	name:              cstring,
	desc:              cstring,
	damage:            f32,
	cooldown:          f32, // seconds between shots/swings
	// How heavy the weapon feels. Only TRACER is affected (heavy weapons drag her
	// move speed down), so it is a design knob rather than a universal stat.
	weight:            f32,
	// Gun fields (class == .GUN).
	bullet_speed:      f32,
	projectiles:       i32,
	spread:            f32, // total fan arc / base inaccuracy in radians
	pierce:            i32, // enemies each shot passes through
	ammo_capacity:     i32, // max reserve ammo (outside the mag)
	magazine_capacity: i32, // shots per magazine
	bullet_size:       raylib.Vector2,
	min_spread:        f32, // PRECISION cannot tighten below this
	// Melee fields (class == .MELEE).
	shape:             Melee_Shape, // hitbox + flash geometry (see Melee_Shape)
	reach:             f32, // how far the swing reaches (px)
	arc:               f32, // half-angle (rad) or half-width/radius (px), by shape
	knockback:         f32, // instant shove applied to anything hit
	sound_pitch:       f32, // pitch applied when playing the swing sound
	flash_color:       raylib.Color, // colour of the drawn swing flash
	// Held silhouette. Guns pick a firearm frame; melee picks a hand-built model
	// (knife, spear, hammer, ...). AUTO falls back to the generic shape drawing.
	look:              Weapon_Look,
	// Signature-strike extras. Both are zero/false for ordinary weapons.
	lunge:             f32, // forward self-shove applied on the swing (px)
	charged:           bool, // damage scales with the combo charge (Bud's knee)
	// Tracer's Phase Claws. A light strike applies this many PHASE marks to each
	// enemy it hits; a strike with `phase_detonate` instead consumes the marks
	// on what it hits for bonus damage and splashes a mark onto neighbours.
	phase_apply:       i32,
	phase_detonate:    bool,
	// Navy's Muzzle Thrust. A strike with this fires a point-blank slug out of
	// the primary gun (slot 0), spending one round; with no loaded firearm in
	// slot 0 it degrades to a plain strike.
	muzzle_volley:     bool,
}

// Body silhouette used to draw each main character (and their select-screen
// icon). A darker `outline` is stamped behind every shape.
Body_Shape :: enum {
	SQUARE,
	TRIANGLE,
	CIRCLE,
}

Character :: enum {
	RR,
	TRACER,
	BUD,
	NAVY,
}

// A playable main character. `speed`/`max_health` are the pre-utility base, and
// the melee multipliers scale any melee weapon (and the universal kick).
Character_Stats :: struct {
	name:              cstring,
	desc:              cstring,
	color:             raylib.Color,
	outline:           raylib.Color, // darker shade, drawn as a border
	shape:             Body_Shape,
	speed:             f32,
	max_health:        f32,
	melee_damage_mult: f32,
	melee_range_mult:  f32,
	melee_knock_mult:  f32,
	ammo_mult:         f32, // scales both weapons' reserve capacity
	reload_mult:       f32, // scales RELOAD_TIME (<1 reloads faster)
	passive:           cstring, // short passive name, shown on the HUD/select
	passive_desc:      cstring, // one-line explanation
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

// Per-run stats derived from the chosen loadout. Cards upgrade these afterward.
Run_Stats :: struct {
	character:     Character,
	speed:         f32,
	primary:       Gun,
	secondary:     Secondary,
	dash_speed:    f32,
	dash_duration: f32,
	dash_cooldown: f32,
	dash_blink:    bool,
	dash_distance: f32,
	dash_damages:  bool,
	dash_damage:   f32, // damage per second dealt by a damaging dash
	reload_time:   f32,
	max_health:    f32,
	card_choices:  int,
	// Bonuses folded in from the chosen utility so they look like early upgrades.
	bonus_damage:  f32, // starts the ATTACK bonus above zero
	spread_cut:    f32, // starts the PRECISION bonus above zero
	ammo_mult:     f32, // scales both weapons' reserve capacity (1.0 = normal)
}

// Serialized run state for save & resume. Written to run_save.cfg each time a
// wave is cleared, and restored into a freshly-built run to continue. Live
// entities (enemies/drops/bullets) aren't serialized: resume lands on the
// between-waves boundary, right where the card reward or shop appears.
Run_Save :: struct {
	character:         Character,
	primary:           Gun,
	secondary:         Secondary,
	dash:              Dash_Kind,
	utility:           Utility,
	arena:             Arena_Kind,
	active_mission:    int,
	mission_cleared:   bool,
	wave:              i32,
	health:            f32,
	max_health:        f32,
	currency:          i32,
	speed:             f32,
	bonus_damage:      f32,
	bonus_projectiles: i32,
	bonus_pierce:      i32,
	spread_cut:        f32,
	bonus_melee_damage: f32,
	bonus_melee_knock:  f32,
	lifesteal:         f32,
	mag_mult:          f32,
	ammo_mult:         f32,
	ammo_growth_mult:  f32,
	melee_speed_mult:  f32,
	melee_range_mult:  f32,
	card_choices:      int,
	status_time_mult:  f32,
	attack_effects:    u32,    // Status_Set bitmask
	status_power:      [4]f32, // per-Status_Effect power
	relics_equipped:   u32,    // Up to 3 equipped relics for this run
	endless:           bool,   // arena boss already down: this run is in endless mode
}

// Snapshot of a finished run, shown on the results screen. Captured at death so
// it survives the teardown that returns to the main menu.
Run_Result :: struct {
	arena:        Arena_Kind,
	character:    Character,
	gun:          Gun,
	secondary:    Secondary,
	dash:         Dash_Kind,
	utility:      Utility,
	wave_reached: i32,
	kills:        i32,
	elite_kills:  i32,
	coins_earned: i32,
	coins_spent:  i32,
	time:         f32,
}

// Runtime ammo/reload state for one weapon slot.
weapon :: struct {
	mag:      i32,
	ammo:     i32,
	ammo_cap: i32,
	mag_cap:  i32,
	reload:   f32,
	cooldown: f32,
}

// Shop stock. One of each is offered per shop visit.
Shop_Item_Kind :: enum {
	AMMO,
	HEAL,
	MAX_HP,
	UPGRADE,
}

// Rarity band for shop offers: sets the price range and how often the offer is
// drawn from SHOP_POOL (see `shop_tier_weight`).
Shop_Tier :: enum {
	COMMON,
	RARE,
	EPIC,
}

// A possible shop offer (the static template, kept in SHOP_POOL).
shop_definition :: struct {
	name:    cstring,
	desc:    cstring,
	cost:    i32,
	kind:    Shop_Item_Kind,
	upgrade: cstring, // for .UPGRADE: a card name, or "RANDOM"
	tier:    Shop_Tier,
}

// One stocked offer for the current shop visit.
shop_item :: struct {
	name:    cstring,
	desc:    cstring,
	cost:    i32,
	kind:    Shop_Item_Kind,
	upgrade: cstring,
	tier:    Shop_Tier,
	sold:    bool,
}
