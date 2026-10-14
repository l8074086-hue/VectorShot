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
	MAIN_SCREEN,
	SKILL_ONE,
	SKILL_TWO,
	SKILL_THREE,
	SKILL_FOUR,
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
}

Enemy_Kind :: enum {
	GRUNT,
	RUNNER,
	TANK,
	RANGED,
	CHARGER,
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

Gun :: enum {
	SNIPER,
	SHOTGUN,
	SMG,
	RIFLE,
	MINIGUN,
	CANNON,
}

// Secondary weapons are their own set of sidearms (not the primary guns).
Secondary :: enum {
	PISTOL,
	REVOLVER,
	DUAL,
	SAWED,
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
	name:              cstring,
	desc:              cstring,
	bullet_speed:      f32,
	damage:            f32,
	projectiles:       i32,
	spread:            f32, // total fan arc / base inaccuracy in radians
	cooldown:          f32, // seconds between shots
	pierce:            i32, // enemies each shot passes through
	ammo_capacity:     i32, // max reserve ammo (outside the mag)
	magazine_capacity: i32, // shots per magazine
	bullet_size:       raylib.Vector2,
	min_spread:        f32, // PRECISION cannot tighten below this
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
	speed:         f32,
	primary:       Gun,
	secondary:     Secondary,
	dash_speed:    f32,
	dash_duration: f32,
	dash_cooldown: f32,
	dash_blink:    bool,
	dash_distance: f32,
	dash_damages:  bool,
	max_health:    f32,
	card_choices:  int,
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
