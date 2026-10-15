package main
import "vendor:raylib"

GameState :: enum {
	MAIN_MENU,
	SKILL_SELECT,
	PLAYING,
	SHOP,
	GAME_OVER,
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
	// Bulwark (elite TANK): each crystal plate guards one world-space direction.
	// A hit arriving from roughly that direction shatters it; while any plate
	// remains the armored body shrugs off hp damage.
	plate_dir:     [ELITE_TANK_PLATES]raylib.Vector2,
	plate_live:    [ELITE_TANK_PLATES]bool,
}

Enemy_Kind :: enum {
	GRUNT,
	RUNNER,
	TANK,
	RANGED,
	CHARGER,
}

// What a hit on an enemy actually did, so callers can pick the right feedback.
Enemy_Hit :: enum {
	DAMAGE,  // hp was reduced
	BLOCKED, // a Bulwark's armored body absorbed it (plates still intact)
	SHATTER, // a Bulwark crystal plate broke off
}

// Ranged/charger enemies use a tiny state machine.
Enemy_State :: enum {
	CHASE,
	WINDUP, // charger telegraphing its dash
	CHARGE, // charger mid-dash
	RECOVER, // brief pause after a charge
	STRAFE, // ranged keeping its distance
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
}

Drop_Kind :: enum {
	HEALTH,
	AMMO,
	CURRENCY,
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

tree :: struct {
	pos:  raylib.Vector2,
	size: raylib.Vector2,
}

// Purely visual blast marker shown after a barrel pops.
explosion :: struct {
	pos:  raylib.Vector2,
	life: f32,
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
}

Arena_Stats :: struct {
	name:        cstring,
	desc:        cstring,
	floor_dark:  raylib.Color,
	floor_light: raylib.Color,
	wall:        raylib.Color,
	cover:       raylib.Color, // tree/boulder body
	cover_top:   raylib.Color, // tree/boulder highlight
}

// What a weapon slot actually is. Guns spend ammo and fire bullets; melee
// weapons swing an arc and are always ready.
Weapon_Class :: enum {
	GUN,
	MELEE,
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
