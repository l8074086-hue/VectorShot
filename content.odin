package main
import "vendor:raylib"

// Every upgrade that can be offered between waves. Effects are applied in
// `apply_upgrade` by matching `name`, so keep the names in sync with that switch.
// The description is what the card shows under its title.
CARD_POOL :: [?]card_definition {
	{"DASH", "STRONGER DASH"},
	{"ATTACK", "+1 DAMAGE"},
	{"SPEED", "+50 MOVE SPEED"},
	{"HEALTH", "+25 MAX HP"},
	{"PROJECTILE", "+1 PROJECTILE"},
	{"PRECISION", "-20% SPREAD"},
	{"PIERCE", "+1 PIERCE"},
	{"MELEE", "+1.5 MELEE DMG"},
	{"SWING", "+15% SWING SPD"},
	{"REACH", "+12% MELEE REACH"},
	{"KNOCK", "+60 KNOCKBACK"},
	{"LIFESTEAL", "+2 HP PER KILL"},
	{"RELOAD", "-15% RELOAD"},
	{"DASHCD", "-15% DASH CD"},
	{"MAG", "+25% MAG SIZE"},
	{"AMMO", "+25% RESERVE"},
	// Status line: infuse attacks with an element, then deepen it. The boost
	// cards only appear once you actually carry the matching element.
	{"IGNITE", "ON HIT: BURN"},
	{"CRYO", "ON HIT: FREEZE"},
	{"VENOM", "ON HIT: POISON"},
	{"STATIC", "ON HIT: SHOCK"},
	{"KINDLING", "+BURN POWER"},
	{"DEEP FREEZE", "+FREEZE POWER"},
	{"VIRULENCE", "+POISON POWER"},
	{"CONDUIT", "+SHOCK POWER"},
	{"ELEMENTALIST", "+25% STATUS TIME"},
}

// Possible shop offers. Each visit draws a few distinct entries from here, so
// the stock rotates instead of being the same fixed list every time. `tier`
// sets the price band and the draw weight (COMMON shows up most often).
SHOP_POOL :: [?]shop_definition {
	// COMMON
	{"AMMO REFILL", "TOP UP BOTH GUNS", 15, .AMMO, "", .COMMON},
	{"PATCH UP", "RESTORE FULL HP", 20, .HEAL, "", .COMMON},
	{"TOUGHEN UP", "+25 MAX HP", 25, .MAX_HP, "", .COMMON},
	{"SHARPSHOOTER", "+1 DAMAGE", 25, .UPGRADE, "ATTACK", .COMMON},
	{"LIGHT FEET", "+50 SPEED", 25, .UPGRADE, "SPEED", .COMMON},
	// Melee line: lets a blades/fists build keep pace with gun builds.
	{"HEAVY HANDS", "+1.5 MELEE DMG", 30, .UPGRADE, "MELEE", .COMMON},
	{"LONG REACH", "+12% MELEE REACH", 30, .UPGRADE, "REACH", .COMMON},
	{"BIG SHOVE", "+60 KNOCKBACK", 30, .UPGRADE, "KNOCK", .COMMON},
	{"BANDOLIER", "+25% RESERVE AMMO", 30, .UPGRADE, "AMMO", .COMMON},
	// RARE
	{"TIGHT GROUPS", "-20% SPREAD", 35, .UPGRADE, "PRECISION", .RARE},
	{"EXTENDED DASH", "STRONGER DASH", 35, .UPGRADE, "DASH", .RARE},
	{"QUICK SWING", "+15% SWING SPEED", 35, .UPGRADE, "SWING", .RARE},
	{"FAST HANDS", "-15% RELOAD TIME", 35, .UPGRADE, "RELOAD", .RARE},
	{"SLIPPERY", "-15% DASH COOLDOWN", 35, .UPGRADE, "DASHCD", .RARE},
	{"EXTENDED MAG", "+25% MAGAZINE", 35, .UPGRADE, "MAG", .RARE},
	{"HOT LOAD", "+1 PIERCE", 40, .UPGRADE, "PIERCE", .RARE},
	// EPIC
	{"MYSTERY CRATE", "RANDOM UPGRADE", 50, .UPGRADE, "RANDOM", .EPIC},
	{"VAMPIRISM", "+2 HP PER KILL", 45, .UPGRADE, "LIFESTEAL", .EPIC},
	{"DOUBLE TAP", "+1 PROJECTILE", 60, .UPGRADE, "PROJECTILE", .EPIC},
	// Status line: infusions first, then the boosters (which only stock once
	// you carry the matching element, via upgrade_is_useful).
	{"FLAMING ROUNDS", "ATTACKS BURN", 40, .UPGRADE, "IGNITE", .RARE},
	{"CRYO ROUNDS", "ATTACKS FREEZE", 40, .UPGRADE, "CRYO", .RARE},
	{"VENOM ROUNDS", "ATTACKS POISON", 40, .UPGRADE, "VENOM", .RARE},
	{"STATIC ROUNDS", "ATTACKS SHOCK", 40, .UPGRADE, "STATIC", .RARE},
	{"KINDLING", "+BURN POWER", 35, .UPGRADE, "KINDLING", .COMMON},
	{"DEEP FREEZE", "+FREEZE POWER", 35, .UPGRADE, "DEEP FREEZE", .COMMON},
	{"VIRULENCE", "+POISON POWER", 35, .UPGRADE, "VIRULENCE", .COMMON},
	{"CONDUIT", "+SHOCK POWER", 35, .UPGRADE, "CONDUIT", .COMMON},
	{"ELEMENTALIST", "+25% STATUS TIME", 45, .UPGRADE, "ELEMENTALIST", .EPIC},
}

ENEMIES := [Enemy_Kind]Enemy_Stats {
	.GRUNT = {
		name = "GRUNT",
		size = {50, 50},
		speed = 80,
		damage = 10,
		hp = 2,
		color = raylib.BLUE,
		spawn_weight = 14,
		unlock_wave = 1,
	},
	.RUNNER = {
		name = "RUNNER",
		size = {30, 30},
		speed = 150,
		damage = 6,
		hp = 1,
		color = raylib.ORANGE,
		spawn_weight = 18,
		unlock_wave = 2,
	},
	.RANGED = {
		name = "SHOOTER",
		size = {36, 36},
		speed = 75,
		damage = 8,
		hp = 3,
		color = raylib.VIOLET,
		ranged = true,
		preferred_range = 280,
		fire_rate = 1.4,
		spawn_weight = 16,
		unlock_wave = 2,
	},
	.TANK = {
		name = "TANK",
		size = {80, 80},
		speed = 45,
		damage = 20,
		hp = 8,
		color = raylib.DARKGREEN,
		spawn_weight = 7,
		unlock_wave = 5,
	},
	.CHARGER = {
		name = "CHARGER",
		size = {46, 46},
		speed = 95,
		damage = 14,
		hp = 4,
		color = raylib.MAROON,
		charge_speed = 560,
		spawn_weight = 12,
		unlock_wave = 4,
	},
	// Splitters burst into two halves when killed, so chipping one down spreads the
	// threat instead of clearing it.
	.SPLITTER = {
		name = "SPLITTER",
		size = {46, 46},
		speed = 70,
		damage = 8,
		hp = 5,
		color = raylib.PURPLE,
		spawn_weight = 9,
		unlock_wave = 6,
	},
	// Orbiters ring the arena around the player, weaving in for a hit and peeling
	// back out -- pressure you have to turn to face.
	.ORBITER = {
		name = "ORBITER",
		size = {38, 38},
		speed = 120,
		damage = 10,
		hp = 4,
		color = raylib.LIME,
		spawn_weight = 10,
		unlock_wave = 8,
	},
	// Snipers hold the far ring, telegraph with a flash, then fire one fast aimed
	// shot -- punishes standing still.
	.SNIPER = {
		name = "SNIPER",
		size = {34, 34},
		speed = 60,
		damage = 12,
		hp = 2,
		color = raylib.GOLD,
		ranged = true,
		preferred_range = 400,
		fire_rate = 2.4,
		spawn_weight = 8,
		unlock_wave = 10,
	},
	// The boss is never rolled from the spawn table (weight 0); each arena's boss
	// is built by spawn_arena_boss from ARENA_BOSSES. This entry is only a
	// fallback for the generic enemy plumbing (it holds no boss-specific stats).
	.BOSS = {
		name = "WARDEN",
		size = {120, 120},
		speed = 55,
		damage = 26,
		hp = 90,
		color = raylib.RED,
		ranged = true,
		preferred_range = 260,
		fire_rate = 1.6,
		spawn_weight = 0,
		unlock_wave = 5,
	},
	// Tutorial practice targets. These never spawn in a real wave (spawn_weight 0).
	// Speed is zero for everything except the patroller, which walks its route
	// slowly; all of them copy a real kind's look so they read as familiar enemies.
	.DUMMY_DPS = {
		name = "DUMMY",
		size = {50, 50},
		speed = 0,
		damage = 0,
		hp = 60,
		color = raylib.BLUE,
		spawn_weight = 0,
		unlock_wave = 99,
	},
	.DUMMY_RANGED = {
		name = "TURRET",
		size = {36, 36},
		speed = 0,
		damage = 4,
		hp = 5,
		color = raylib.VIOLET,
		ranged = true,
		preferred_range = 280,
		fire_rate = 1.4,
		spawn_weight = 0,
		unlock_wave = 99,
	},
	.DUMMY_WEAK = {
		name = "DUMMY",
		size = {30, 30},
		speed = 0,
		damage = 0,
		hp = 3,
		color = raylib.ORANGE,
		spawn_weight = 0,
		unlock_wave = 99,
	},
	.DUMMY_PATROL = {
		name = "DRIFTER",
		size = {46, 46},
		speed = 70,
		damage = 0,
		hp = 10,
		color = raylib.MAROON,
		spawn_weight = 0,
		unlock_wave = 99,
	},
}


// Primary-slot weapons: guns and melee blades in one pool. Guns fill the
// ballistic fields; melee entries leave those zero and fill reach/arc/knockback.
// `damage`, `cooldown` and `weight` apply to both.
GUNS := [Gun]Weapon_Stats {
	.SNIPER = {
		class = .GUN,
		name = "SNIPER",
		look = .SNIPER,
		desc = "SLOW, HEAVY, PIERCES",
		damage = 2.0,
		cooldown = 1.00,
		weight = 2.4,
		bullet_speed = 900,
		projectiles = 1,
		spread = 0.00,
		pierce = 2,
		ammo_capacity = 20,
		magazine_capacity = 5,
		bullet_size = {10, 10},
		min_spread = 0.00,
	},
	.SHOTGUN = {
		class = .GUN,
		name = "SHOTGUN",
		look = .SHOTGUN,
		desc = "5-PELLET SPREAD",
		damage = 1.0,
		cooldown = 0.60,
		weight = 1.6,
		bullet_speed = 340,
		projectiles = 5,
		spread = 0.40,
		pierce = 0,
		ammo_capacity = 30,
		magazine_capacity = 2,
		bullet_size = {8, 8},
		min_spread = 0.10,
	},
	.SMG = {
		class = .GUN,
		name = "SMG",
		look = .SMG,
		desc = "FAST FIRE, LOW DMG",
		damage = 0.6,
		cooldown = 0.07,
		weight = 0.7,
		bullet_speed = 520,
		projectiles = 1,
		spread = 0.10,
		pierce = 0,
		ammo_capacity = 60,
		magazine_capacity = 30,
		bullet_size = {7, 7},
		min_spread = 0.02,
	},
	.RIFLE = {
		class = .GUN,
		name = "RIFLE",
		look = .RIFLE,
		desc = "BALANCED ALL-ROUNDER",
		damage = 1.0,
		cooldown = 0.15,
		weight = 1.2,
		bullet_speed = 700,
		projectiles = 1,
		spread = 0.03,
		pierce = 0,
		ammo_capacity = 30,
		magazine_capacity = 10,
		bullet_size = {9, 9},
		min_spread = 0.00,
	},
	.MINIGUN = {
		class = .GUN,
		name = "MINIGUN",
		look = .MINIGUN,
		desc = "VERY FAST, WIDE SPREAD",
		damage = 0.4,
		cooldown = 0.05,
		weight = 0.6,
		bullet_speed = 600,
		projectiles = 1,
		spread = 0.28,
		pierce = 0,
		ammo_capacity = 300,
		magazine_capacity = 150,
		bullet_size = {6, 6},
		min_spread = 0.10,
	},
	.CANNON = {
		class = .GUN,
		name = "CANNON",
		look = .CANNON,
		desc = "SLOW, HUGE DMG, PIERCES",
		damage = 4.0,
		cooldown = 0.90,
		weight = 3.0,
		bullet_speed = 320,
		projectiles = 1,
		spread = 0.00,
		pierce = 1,
		ammo_capacity = 10,
		magazine_capacity = 3,
		bullet_size = {16, 16},
		min_spread = 0.00,
	},
	// Melee primaries.
	.KNIFE = {
		class = .MELEE,
		name = "KNIFE",
		look = .DAGGER,
		desc = "FAST, SHORT, NARROW THRUST",
		damage = 1.4,
		cooldown = 0.22,
		weight = 0.4,
		shape = .THRUST,
		reach = 78,
		arc = 9,
		knockback = 45,
		sound_pitch = 1.30,
		flash_color = {190, 240, 255, 255},
	},
	.BATON = {
		class = .MELEE,
		name = "BATON",
		look = .BATON,
		desc = "BIG SHOVE, STURDY WING",
		damage = 2.5,
		cooldown = 0.45,
		weight = 0.8,
		shape = .SECTOR,
		reach = 104,
		arc = 0.72,
		knockback = 170,
		sound_pitch = 1.10,
		flash_color = {150, 200, 255, 255},
	},
	.HAMMER = {
		class = .MELEE,
		name = "HAMMER",
		look = .HAMMER,
		desc = "SLOW, HUGE SMASH",
		damage = 6.0,
		cooldown = 0.90,
		weight = 2.6,
		shape = .BLAST,
		reach = 74,
		arc = 50,
		knockback = 280,
		sound_pitch = 0.70,
		flash_color = {255, 170, 60, 255},
	},
	.SPEAR = {
		class = .MELEE,
		name = "SPEAR",
		look = .SPEAR,
		desc = "LONG, TIGHT THRUST",
		damage = 3.0,
		cooldown = 0.55,
		weight = 1.6,
		shape = .THRUST,
		reach = 168,
		arc = 8,
		knockback = 90,
		sound_pitch = 1.55,
		flash_color = {255, 240, 140, 255},
	},
}

// Secondary-slot weapons: lighter sidearms plus a couple of melee options.
SECONDARIES := [Secondary]Weapon_Stats {
	.PISTOL = {
		class = .GUN,
		name = "PISTOL",
		look = .PISTOL,
		desc = "STEADY SIDEARM",
		damage = 0.9,
		cooldown = 0.22,
		weight = 0.8,
		bullet_speed = 620,
		projectiles = 1,
		spread = 0.03,
		pierce = 0,
		ammo_capacity = 48,
		magazine_capacity = 12,
		bullet_size = {8, 8},
		min_spread = 0.00,
	},
	.REVOLVER = {
		class = .GUN,
		name = "REVOLVER",
		look = .REVOLVER,
		desc = "HARD-HITTING, SLOW",
		damage = 2.2,
		cooldown = 0.55,
		weight = 1.4,
		bullet_speed = 780,
		projectiles = 1,
		spread = 0.02,
		pierce = 1,
		ammo_capacity = 24,
		magazine_capacity = 6,
		bullet_size = {11, 11},
		min_spread = 0.00,
	},
	.DUAL = {
		class = .GUN,
		name = "DUAL",
		look = .DUAL,
		desc = "TWIN SHOTS",
		damage = 0.7,
		cooldown = 0.28,
		weight = 1.0,
		bullet_speed = 600,
		projectiles = 2,
		spread = 0.16,
		pierce = 0,
		ammo_capacity = 60,
		magazine_capacity = 18,
		bullet_size = {7, 7},
		min_spread = 0.03,
	},
	.SAWED = {
		class = .GUN,
		name = "SAWED",
		look = .SHOTGUN,
		desc = "4-PELLET BLAST",
		damage = 0.8,
		cooldown = 0.70,
		weight = 1.5,
		bullet_speed = 420,
		projectiles = 4,
		spread = 0.50,
		pierce = 0,
		ammo_capacity = 20,
		magazine_capacity = 4,
		bullet_size = {8, 8},
		min_spread = 0.15,
	},
	.KNIFE = {
		class = .MELEE,
		name = "KNIFE",
		look = .DAGGER,
		desc = "FAST, SHORT, NARROW THRUST",
		damage = 1.4,
		cooldown = 0.22,
		weight = 0.4,
		shape = .THRUST,
		reach = 78,
		arc = 9,
		knockback = 45,
		sound_pitch = 1.30,
		flash_color = {190, 240, 255, 255},
	},
	.BATON = {
		class = .MELEE,
		name = "BATON",
		look = .BATON,
		desc = "BIG SHOVE, STURDY WING",
		damage = 2.5,
		cooldown = 0.45,
		weight = 0.8,
		shape = .SECTOR,
		reach = 104,
		arc = 0.72,
		knockback = 170,
		sound_pitch = 1.10,
		flash_color = {150, 200, 255, 255},
	},
}

// The universal kick, bound to E for every character: a plain unarmed strike
// that is always available alongside whatever the active slot does. It shares
// the melee cooldown with the signature chain, so swings never overlap.
KICK: Weapon_Stats = {
	class       = .MELEE,
	name        = "KICK",
	look        = .BOOT,
	damage      = 2.0,
	cooldown    = 0.40,
	shape       = .SECTOR,
	reach       = 92,
	arc         = 0.70,
	knockback   = 100,
	sound_pitch = 1.00,
	flash_color = {255, 255, 255, 255},
}

// Signature weapons. Every character has their own melee weapon on the third
// Q slot (SPACE throws it), authored as a short combo the same way Bud's Fists
// were. Each press lands the
// next strike and advances the chain (wrapping at the end); waiting too long
// resets to the first. A strike with `charged` scales with the charge built up
// while it is armed (see KNEE_CHARGE_* in game.odin).
SIGNATURE_LEN :: 4

// `#partial`: RR is deliberately absent here -- his Vector Edge reshapes to his
// Adaptation and lives in RR_EDGE below, resolved at runtime by signature_at in
// game.odin. signature_at never reads SIGNATURES[.RR], so that key stays zero.
SIGNATURES := #partial [Character][SIGNATURE_LEN]Weapon_Stats {
	// Tracer: phase claws. The two lights deal no damage at all -- they exist
	// purely to stack PHASE marks, and REND carries the whole combo's damage
	// plus the heal on a marked kill. That keeps the killing blow (and the
	// lifesteal) on REND instead of a light stealing it, and concentrates the
	// burst where the player can see it. REND also splashes marks through a
	// crowd. It spins up Traceur's Heart almost immediately.
	.TRACER = {
		{
			class = .MELEE,
			name = "CLAW",
			desc = "APPLIES MARK",
			damage = 0.0,
			cooldown = 0.12,
			shape = .THRUST,
			reach = 80,
			arc = 6,
			knockback = 25,
			sound_pitch = 1.45,
			flash_color = {200, 255, 200, 255},
			phase_apply = 2,
		},
		{
			class = .MELEE,
			name = "CROSS",
			desc = "APPLIES MARK",
			damage = 0.0,
			cooldown = 0.12,
			shape = .THRUST,
			reach = 80,
			arc = 6,
			knockback = 25,
			sound_pitch = 1.50,
			flash_color = {200, 255, 200, 255},
			phase_apply = 2,
		},
		{
			class = .MELEE,
			name = "REND",
			desc = "MARK DETONATOR",
			damage = 1.0,
			cooldown = 0.20,
			shape = .SECTOR,
			reach = 96,
			arc = 0.80,
			knockback = 70,
			sound_pitch = 1.20,
			flash_color = {170, 255, 170, 255},
			phase_detonate = true,
		},
		{}, // unused slot (SIGNATURE_COUNT caps the chain at 3)
	},
	// Bud, the fist fighter: jab, hook, elbow, then the lunging FLYING KNEE.
	.BUD = {
		{
			class = .MELEE,
			name = "JAB",
			desc = "QUICK STRAIGHT",
			damage = 1.2,
			cooldown = 0.16,
			shape = .THRUST,
			reach = 66,
			arc = 7,
			knockback = 30,
			sound_pitch = 1.35,
			flash_color = {255, 235, 210, 255},
		},
		{
			class = .MELEE,
			name = "HOOK",
			desc = "WIDE SWING",
			damage = 2.2,
			cooldown = 0.22,
			shape = .SECTOR,
			reach = 84,
			arc = 0.95,
			knockback = 90,
			sound_pitch = 1.05,
			flash_color = {255, 205, 150, 255},
		},
		{
			class = .MELEE,
			name = "ELBOW",
			desc = "FINISHING SMASH",
			damage = 4.2,
			cooldown = 0.34,
			shape = .BLAST,
			reach = 60,
			arc = 42,
			knockback = 240,
			sound_pitch = 0.75,
			flash_color = {255, 120, 90, 255},
		},
		{
			class = .MELEE,
			name = "KNEE",
			desc = "CHARGED FINISHER",
			damage = 5.5,
			cooldown = 0.55,
			shape = .THRUST,
			reach = 92,
			arc = 16,
			knockback = 340,
			sound_pitch = 0.62,
			flash_color = {255, 80, 60, 255},
			lunge = 110,
			charged = true,
		},
	},
	// Navy: a disciplined bayonet. Long, thin, precise thrusts; the second is a
	// committed lunge that closes the distance.
	.NAVY = {
		{
			class = .MELEE,
			name = "THRUST",
			desc = "PRECISE STAB",
			damage = 1.8,
			cooldown = 0.24,
			shape = .THRUST,
			reach = 92,
			arc = 6,
			knockback = 60,
			sound_pitch = 1.55,
			flash_color = {180, 200, 255, 255},
		},
		{
			class = .MELEE,
			name = "LUNGE",
			desc = "STAB + POINT-BLANK",
			damage = 3.0,
			cooldown = 0.40,
			shape = .THRUST,
			reach = 128,
			arc = 6,
			knockback = 120,
			sound_pitch = 1.30,
			flash_color = {150, 180, 255, 255},
			lunge = 46,
			muzzle_volley = true,
		},
		{}, // unused slot (SIGNATURE_COUNT caps the chain at 2)
		{}, // unused slot
	},
}

// RR's Vector Edge is not a fixed combo -- it reshapes itself to his current
// Adaptation (see update_rr_adaptation in game.odin). Whichever stat his build
// has invested in most decides how the blade fights, so the same press does a
// different thing as he adapts. No ladder uses `charged` (that stays Bud's
// exclusive); MOBILITY and RESILIENCE reach for `lunge` instead, and PRECISION
// is all long thin thrusts -- the opposite of Bud's short fists.
RR_EDGE := [RR_Adaptation][SIGNATURE_LEN]Weapon_Stats {
	// OFFENSE: the default blade -- cut, sweep, then a heavy shock smash.
	.OFFENSE = {
		{
			class = .MELEE,
			name = "SLICE",
			desc = "QUICK CUT",
			damage = 2.0,
			cooldown = 0.16,
			shape = .THRUST,
			reach = 84,
			arc = 9,
			knockback = 40,
			sound_pitch = 1.30,
			flash_color = {255, 180, 180, 255},
		},
		{
			class = .MELEE,
			name = "ARC",
			desc = "WIDE SWEEP",
			damage = 3.0,
			cooldown = 0.22,
			shape = .SECTOR,
			reach = 96,
			arc = 0.85,
			knockback = 110,
			sound_pitch = 1.00,
			flash_color = {255, 130, 130, 255},
		},
		{
			class = .MELEE,
			name = "PULSE",
			desc = "SHOCK FINISHER",
			damage = 5.0,
			cooldown = 0.32,
			shape = .BLAST,
			reach = 66,
			arc = 48,
			knockback = 230,
			sound_pitch = 0.80,
			flash_color = {255, 90, 90, 255},
		},
		{}, // unused slot (SIGNATURE_COUNT caps the chain at 3)
	},
	// MOBILITY: two very fast flicks, then a lunging stab that closes distance.
	.MOBILITY = {
		{
			class = .MELEE,
			name = "FLICK",
			desc = "RAPID CUT",
			damage = 1.2,
			cooldown = 0.10,
			shape = .THRUST,
			reach = 70,
			arc = 7,
			knockback = 30,
			sound_pitch = 1.45,
			flash_color = {190, 255, 255, 255},
		},
		{
			class = .MELEE,
			name = "FLICK",
			desc = "RAPID CUT",
			damage = 1.2,
			cooldown = 0.10,
			shape = .THRUST,
			reach = 70,
			arc = 7,
			knockback = 30,
			sound_pitch = 1.50,
			flash_color = {190, 255, 255, 255},
		},
		{
			class = .MELEE,
			name = "GAPCUT",
			desc = "CLOSING STAB",
			damage = 2.4,
			cooldown = 0.24,
			shape = .THRUST,
			reach = 112,
			arc = 13,
			knockback = 150,
			sound_pitch = 1.18,
			flash_color = {140, 230, 255, 255},
			lunge = 72,
		},
		{}, // unused slot (SIGNATURE_COUNT caps the chain at 3)
	},
	// RESILIENCE: slow, wide sweeps with huge shove, so the blade controls the
	// space around him and keeps him safe.
	.RESILIENCE = {
		{
			class = .MELEE,
			name = "SWEEP",
			desc = "WIDE GUARD",
			damage = 2.0,
			cooldown = 0.30,
			shape = .SECTOR,
			reach = 92,
			arc = 0.85,
			knockback = 150,
			sound_pitch = 0.95,
			flash_color = {230, 200, 255, 255},
		},
		{
			class = .MELEE,
			name = "SWEEP",
			desc = "WIDE GUARD",
			damage = 2.6,
			cooldown = 0.34,
			shape = .SECTOR,
			reach = 98,
			arc = 0.95,
			knockback = 180,
			sound_pitch = 0.90,
			flash_color = {220, 180, 255, 255},
		},
		{
			class = .MELEE,
			name = "BULWARK",
			desc = "KNOCKBACK SLAM",
			damage = 4.2,
			cooldown = 0.50,
			shape = .BLAST,
			reach = 70,
			arc = 52,
			knockback = 360,
			sound_pitch = 0.70,
			flash_color = {200, 150, 255, 255},
		},
		{}, // unused slot (SIGNATURE_COUNT caps the chain at 3)
	},
	// PRECISION: long, needle-thin thrusts -- the opposite of Bud's short fists.
	.PRECISION = {
		{
			class = .MELEE,
			name = "PIERCE",
			desc = "THIN THRUST",
			damage = 1.8,
			cooldown = 0.20,
			shape = .THRUST,
			reach = 112,
			arc = 5,
			knockback = 30,
			sound_pitch = 1.60,
			flash_color = {255, 255, 200, 255},
		},
		{
			class = .MELEE,
			name = "PIERCE",
			desc = "THIN THRUST",
			damage = 1.8,
			cooldown = 0.20,
			shape = .THRUST,
			reach = 112,
			arc = 5,
			knockback = 30,
			sound_pitch = 1.60,
			flash_color = {255, 255, 200, 255},
		},
		{
			class = .MELEE,
			name = "LANCE",
			desc = "LONG FINISHER",
			damage = 3.4,
			cooldown = 0.34,
			shape = .THRUST,
			reach = 158,
			arc = 6,
			knockback = 100,
			sound_pitch = 1.38,
			flash_color = {255, 245, 160, 255},
		},
		{}, // unused slot (SIGNATURE_COUNT caps the chain at 3)
	},
}

// Short flavor name for each Vector Edge form, shown on the HUD so the reshaping
// reads at a glance.
RR_EDGE_NAMES := [RR_Adaptation]cstring {
	.OFFENSE    = "ONSLAUGHT",
	.MOBILITY   = "FLURRY",
	.RESILIENCE = "BULWARK",
	.PRECISION  = "NEEDLE",
}

// How each Vector Edge form throws a blade wind when RR surges: the damage
// multiplier over the finisher's own damage, its travel speed, how many enemies
// it cuts through, and its colour. FLURRY is the fast ladder, so its wind is much
// weaker -- otherwise the quickest combo would also throw the strongest shot.
RR_EDGE_WIND := [RR_Adaptation]struct {
	mult:   f32,
	speed:  f32,
	pierce: i32,
	col:    raylib.Color,
} {
	.OFFENSE    = {1.00, 520, 2, {255, 170, 120, 225}},
	.MOBILITY   = {0.40, 660, 1, {190, 255, 255, 225}},
	.RESILIENCE = {1.20, 430, 3, {220, 180, 255, 225}},
	.PRECISION  = {0.90, 720, 2, {255, 250, 190, 225}},
}

// How many strikes each signature combo actually uses; the rest of the
// [SIGNATURE_LEN] rows above are left zero.
SIGNATURE_COUNT := [Character]int {
	.RR     = 3,
	.TRACER = 3,
	.BUD    = 4,
	.NAVY   = 2,
}

// Display name for each character's signature weapon (select screen + HUD).
SIGNATURE_NAMES := [Character]cstring {
	.RR     = "VECTOR EDGE",
	.TRACER = "PHASE CLAWS",
	.BUD    = "FISTS",
	.NAVY   = "BAYONET",
}

// The melee model each character's signature weapon draws with. Every strike in
// a combo shares one silhouette (a Vector Edge is always the same blade), so
// this is keyed by character rather than by individual strike.
SIGNATURE_LOOK := [Character]Weapon_Look {
	.RR     = .BLADE,
	.TRACER = .CLAWS,
	.BUD    = .FISTS,
	.NAVY   = .BAYONET,
}

// Playable main characters. `speed`/`max_health` are the base before any
// utility bonus; the melee multipliers scale every melee swing (weapon or kick).
CHARACTERS := [Character]Character_Stats {
	// NAME, DESC, COLOR, OUTLINE, SHAPE, SPEED, MAX_HP, MELEE_DMG, MELEE_RANGE, MELEE_KNOCK, AMMO, RELOAD, PASSIVE, PASSIVE_DESC
	.RR     = {
		"RR",
		"ALL-ROUNDER",
		{220, 55, 65, 255},
		{130, 20, 30, 255},
		.SQUARE,
		200,
		100,
		1.00,
		1.00,
		1.00,
		1.00,
		1.00,
		"ADAPTATION",
		"BONUS FOLLOWS HIS TOP STAT",
	},
	.TRACER = {
		"TRACER",
		"FAST & FRAGILE, LOVES SLIDE",
		{250, 220, 40, 255},
		{150, 120, 0, 255},
		.TRIANGLE,
		265,
		70,
		0.85,
		0.95,
		0.90,
		1.00,
		1.00,
		"TRACEUR'S HEART",
		"ATTACKS BUILD SPEED (MAX +50%)",
	},
	.BUD    = {
		"BUD",
		"FIST FIGHTER; GUNS MAKE HIM UNHAPPY",
		{215, 140, 70, 255},
		{120, 65, 20, 255},
		.CIRCLE,
		185,
		140,
		1.60,
		1.35,
		1.30,
		0.85,
		1.10,
		"GUARD UP",
		"BLOCKS HIS FACING; FISTS COMBO",
	},
	.NAVY   = {
		"NAVY",
		"OFFICER: AMMO & FAST RELOADS",
		{40, 60, 130, 255},
		{15, 25, 65, 255},
		.SQUARE,
		195,
		110,
		1.10,
		1.05,
		1.50,
		1.30,
		0.70,
		"TAKE AIM",
		"PERFECT ACCURACY WHEN STILL",
	},
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
	.TRIGGER  = {"TRIGGER", "+1 DAMAGE"},
	.DEADEYE  = {"DEADEYE", "-20% SPREAD"},
	.SCOUT    = {"SCOUT", "-30% DASH COOLDOWN"},
	.PACKRAT  = {"PACKRAT", "+50% MAX AMMO"},
}

// Playable arenas. Same 1600x1200 bounds and border, but each has its own
// interior layout and palette. `build_arena` matches on the kind to place cover.
// --- relics ------------------------------------------------------------------
//
// Rare run passives, drawn one at a time from the chest a boss drops. You accept
// or discard each draw, so opening a chest is always a choice, never a tax.
RELICS := [Relic_Kind]Relic {
	.VAMPIRE_FANG = {"VAMPIRE'S FANG", "Heal a little on every kill."},
	.IRON_STEADY = {"IRON STEADY", "+25 max health (and heal it now)."},
	.SWIFT_SOLE = {"SWIFT SOLE", "+25 move speed."},
	.SHARP_EDGE = {"SHARP EDGE", "Cut your spread."},
	.QUICK_WRIST = {"QUICK WRIST", "Melee swings come out faster."},
	.THICK_MAG = {"THICK MAG", "Bigger magazines on both guns."},
	.BULLET_RESERVE = {"DEEP POCKETS", "More reserve ammo on both guns."},
	.HEAVY_BARREL = {"HEAVY BARREL", "+1.5 damage on every hit."},
}

ARENAS := [Arena_Kind]Arena_Stats {
	.GRASSLAND = {
		"GRASSLAND",
		"OPEN FIELD, SCATTERED GROVE",
		{28, 44, 28, 255},
		{34, 52, 32, 255},
		{48, 82, 44, 255},
		{70, 120, 58, 255},
		{40, 70, 40, 255},
		.GRASS,
		{92, 150, 78, 255},
		.NONE,
		11,
	},
	.CANYON    = {
		"CANYON",
		"LONG SHELVES, TIGHT LANES",
		{52, 32, 22, 255},
		{62, 40, 27, 255},
		{140, 84, 48, 255},
		{150, 96, 60, 255},
		{196, 134, 78, 255},
		.PEBBLE,
		{178, 128, 84, 255},
		.DUST,
		12,
	},
	.RUINS     = {
		"RUINS",
		"PILLAR GRID, OPEN SIGHTLINES",
		{34, 34, 40, 255},
		{42, 42, 50, 255},
		{96, 92, 86, 255},
		{120, 116, 108, 255},
		{160, 156, 148, 255},
		.CRACK,
		{140, 136, 128, 255},
		.NONE,
		13,
	},
	.GLACIER   = {
		"GLACIER",
		"SPARSE WALLS, DENSE BOULDERS",
		{38, 52, 66, 255},
		{52, 68, 84, 255},
		{110, 132, 154, 255},
		{148, 172, 196, 255},
		{205, 224, 240, 255},
		.SNOW,
		{225, 238, 250, 255},
		.SNOW,
		14,
	},
	.FOUNDRY   = {
		"FOUNDRY",
		"MACHINERY, CRATES, VOLATILE STOCK",
		{40, 24, 20, 255},
		{50, 30, 24, 255},
		{92, 58, 44, 255},
		{120, 72, 48, 255},
		{168, 96, 56, 255},
		.EMBER,
		{255, 150, 60, 255},
		.ASH,
		15,
	},
	.FOREST    = {
		"FOREST",
		"DENSE WOODLAND, NARROW CLEARINGS",
		{22, 40, 24, 255},
		{28, 48, 28, 255},
		{40, 76, 40, 255},
		{64, 116, 52, 255},
		{30, 60, 30, 255},
		.GRASS,
		{80, 140, 66, 255},
		.NONE,
		16,
	},
	.SWAMP     = {
		"SWAMP",
		"MURKY POOLS, REEDS AND MUDS",
		{26, 34, 28, 255},
		{32, 42, 33, 255},
		{56, 72, 52, 255},
		{78, 100, 62, 255},
		{44, 58, 40, 255},
		.PEBBLE,
		{96, 118, 82, 255},
		.RAIN,
		17,
	},
}


// Per-arena bosses: each map's finale. These are the base stats; the wave
// scaler still applies on top. The volley/slam/summon knobs are what give each
// fight its own flavour (a bullet-hell, a heavy slammer, a summoner, ...), and
// the name/colour make the HUD bar read as a distinct set-piece.
ARENA_BOSSES := [Arena_Kind]Arena_Boss {
	.GRASSLAND = {
		name            = "PACKLEADER",
		kind            = .PACKLEADER,
		color           = {86, 132, 74, 255},
		size            = {80, 80},
		hp              = 140,
		speed           = 92,
		damage          = 13,
		preferred_range = 250,
	},
	.CANYON    = {
		name            = "DUSTMAW",
		kind            = .DUSTMAW,
		color           = {206, 162, 82, 255},
		size            = {92, 92},
		hp              = 175,
		speed           = 68,
		damage          = 17,
		preferred_range = 0, // DUSTMAW ambushes; it doesn't hold a range
	},
	.RUINS     = {
		name            = "THE COLOSSUS",
		kind            = .COLOSSUS,
		color           = {150, 150, 160, 255},
		size            = {116, 116},
		hp              = 230,
		speed           = 46,
		damage          = 18,
		// It fights with its arms, so it has to stand inside swinging range
		// instead of hanging back at a caster's distance.
		preferred_range = 120,
	},
	.GLACIER   = {
		name            = "FROSTBITE",
		kind            = .FROSTBITE,
		color           = {140, 220, 255, 255},
		size            = {84, 84},
		hp              = 210,
		speed           = 104,
		damage          = 15,
		preferred_range = 270,
	},
	.FOUNDRY   = {
		name            = "MECHANIKTRON",
		kind            = .MECHANIKTRON,
		color           = {150, 168, 186, 255},
		size            = {100, 100},
		hp              = 260,
		speed           = 66,
		damage          = 20,
		preferred_range = 265,
	},
	.FOREST    = {
		name            = "THORNWALD",
		kind            = .THORNWALD,
		color           = {72, 140, 78, 255},
		size            = {104, 104},
		hp              = 300,
		speed           = 60,
		damage          = 21,
		preferred_range = 215,
	},
	.SWAMP     = {
		name            = "BOGWRAITH",
		kind            = .BOGWRAITH,
		color           = {176, 110, 214, 255},
		size            = {92, 92},
		hp              = 350,
		speed           = 70,
		damage          = 23,
		preferred_range = 235,
	},
}



// --- missions (Mission Control "levels") ------------------------------------
//
// A mission is a goal layered on top of a normal endless run: pick one, it
// forces the arena, tweaks how dense the waves are, and pays `reward` the moment
// you meet its objective. Clearing a mission never ends the run -- it just
// records the clear and keeps going, so you can always push further.
//
// `density` is the wave modifier: 1.0 is the normal difficulty-scaled count,
// higher values crowd the arena. Objective/target per the Objective_Kind enum.
// Kept under 32 entries so completion fits an i32 bitmask.
MISSIONS := [?]Mission {
	{
		name = "FIRST CONTACT",
		objective = .SURVIVE,
		target = 3,
		arena = .GRASSLAND,
		density = 1.0,
		reward = 20,
	},
	{
		name = "CLEANUP",
		objective = .KILLS,
		target = 25,
		arena = .GRASSLAND,
		density = 1.0,
		reward = 25,
	},
	{
		name = "LONG HAUL",
		objective = .SURVIVE,
		target = 8,
		arena = .GRASSLAND,
		density = 1.0,
		reward = 45,
	},
	{
		name = "ELITE SQUAD",
		objective = .ELITES,
		target = 5,
		arena = .CANYON,
		density = 1.0,
		reward = 40,
	},
	{
		name = "TIGHT LANES",
		objective = .SURVIVE,
		target = 6,
		arena = .CANYON,
		density = 1.3,
		reward = 45,
	},
	{
		name = "BLOODBATH",
		objective = .KILLS,
		target = 60,
		arena = .CANYON,
		density = 1.5,
		reward = 60,
	},
	{
		name = "PILLAR GRID",
		objective = .SURVIVE,
		target = 5,
		arena = .RUINS,
		density = 1.2,
		reward = 35,
	},
	{
		name = "HUNTER",
		objective = .ELITES,
		target = 12,
		arena = .RUINS,
		density = 1.2,
		reward = 70,
	},
	{
		name = "BOULDERS",
		objective = .SURVIVE,
		target = 7,
		arena = .GLACIER,
		density = 1.3,
		reward = 50,
	},
	{
		name = "FROZEN WATCH",
		objective = .KILLS,
		target = 45,
		arena = .GLACIER,
		density = 1.3,
		reward = 55,
	},
}

// One-line objective text for a mission, e.g. "Survive to wave 8".
mission_objective_text :: proc(m: Mission) -> cstring {
	switch m.objective {
	case .SURVIVE:
		return raylib.TextFormat("Survive to wave %i", m.target)
	case .KILLS:
		return raylib.TextFormat("Kill %i enemies", m.target)
	case .ELITES:
		return raylib.TextFormat("Kill %i elites", m.target)
	}
	return ""
}


// ---------------------------------------------------------------------------
// Bestiary
// ---------------------------------------------------------------------------
//
// One note per thing worth knowing about. Entries unlock as the player meets
// them: an enemy when it first appears, a boss when it is fought, an arena
// when it is entered, a character when they are picked.
//
// The ids are the unlock keys and never change; the display names and the
// text can be rewritten freely.

BESTIARY := [?]Bestiary_Entry {
	// --- enemies ---
	{
		"ENEMY.GRUNT",
		"GRUNT",
		.ENEMY,
		"VectorPlane keeps its shapes simple, and so does its wildlife. The corruption made this one aggressive and left the rest of it alone.",
	},
	{
		"ENEMY.RUNNER",
		"RUNNER",
		.ENEMY,
		"A long thin shape that was never built to hold still. The corruption gave it a reason to move and it has not needed a new one since.",
	},
	{
		"ENEMY.SHOOTER",
		"SHOOTER",
		.ENEMY,
		"It stands off at a distance and keeps the distance whether or not you come to it. The corruption did not have to do much to this one.",
	},
	{
		"ENEMY.TANK",
		"TANK",
		.ENEMY,
		"Wide on purpose. Whatever it was before, it was already a shape nothing could get past, so the corruption only had to make it mean it.",
	},
	{
		"ENEMY.CHARGER",
		"CHARGER",
		.ENEMY,
		"It sets a line and then it is on the line. The corruption gave it one idea, and the idea does not change.",
	},
	{
		"ENEMY.SPLITTER",
		"SPLITTER",
		.ENEMY,
		"It is one shape pretending to be one shape. Put a hole in it and the pretending stops.",
	},
	{
		"ENEMY.ORBITER",
		"ORBITER",
		.ENEMY,
		"It has a radius and it will not leave it. The corruption did not give it that. It already had it, and the corruption only gave it a reason to keep it.",
	},
	{
		"ENEMY.SNIPER",
		"SNIPER",
		.ENEMY,
		"A line drawn at you and held there. The corruption is what taught it that a line could stay drawn.",
	},
	// --- bosses ---
	{
		"BOSS.PACKLEADER",
		"PACKLEADER",
		.BOSS,
		"The first shape the corruption taught to hunt. It taught the others by being watched, which is how a cult teaches.",
	},
	{
		"BOSS.DUSTMAW",
		"DUSTMAW",
		.BOSS,
		"It worships by hiding. What it wants is underneath, and it goes down to be near it.",
	},
	{
		"BOSS.COLOSSUS",
		"THE COLOSSUS",
		.BOSS,
		"It was a monument once. It still stands where it stood, and it still faces what it was put up to face, and it has started walking.",
	},
	{
		"BOSS.FROSTBITE",
		"FROSTBITE",
		.BOSS,
		"The cold is the corruption at its oldest -- what was left of the Crimson Star when it went out. This one kept the shape.",
	},
	{
		"BOSS.MECHANIKTRON",
		"MECHANIKTRON",
		.BOSS,
		"It was built to be maintained. Nobody built it to worship anything, so the corruption found the maintenance loop and made that its devotion.",
	},
	{
		"BOSS.THORNWALD",
		"THORNWALD",
		.BOSS,
		"It was a tree. It is still a tree. The corruption grew it a shape and it grew the shape back.",
	},
	{
		"BOSS.BOGWRAITH",
		"BOGWRAITH",
		.BOSS,
		"It keeps the water still around it, which is not a thing water does. The shape is the only part of it that is not paying attention.",
	},
	// --- arenas ---
	{
		"ARENA.GRASSLAND",
		"GRASSLAND",
		.ARENA,
		"The corruption reached here first and found nothing worth reshaping. It took the ground instead, and the shapes here are still the shapes they were.",
	},
	{
		"ARENA.CANYON",
		"CANYON",
		.ARENA,
		"The walls are cut, not fallen. Something shaped this place on purpose, before the corruption, by hands that already knew what a corner was for.",
	},
	{
		"ARENA.RUINS",
		"RUINS",
		.ARENA,
		"A grid of pillars, a sightline down every axis. Whatever stood here was careful, and being careful did not help.",
	},
	{
		"ARENA.GLACIER",
		"GLACIER",
		.ARENA,
		"The cold is the corruption at its oldest. It came in early and it has had the longest to settle, and everything here has stopped holding its shape.",
	},
	{
		"ARENA.FOUNDRY",
		"FOUNDRY",
		.ARENA,
		"Machines left running, stock left unstable. The corruption did not break anything in here. It just kept the lights on.",
	},
	{
		"ARENA.FOREST",
		"FOREST",
		.ARENA,
		"It grows back thicker than you cut it and does not care which way you came in. Here the corruption stopped changing things and started making them.",
	},
	{
		"ARENA.SWAMP",
		"SWAMP",
		.ARENA,
		"Still water where the angles are wrong. Every shape in the swamp is a little off, and none of them have been wrong for long.",
	},
	// --- characters ---
	{
		"CHAR.RR",
		"RR",
		.CHARACTER,
		"A native of VectorPlane. He did not fall through, so no shape was waiting for him and the corruption never had a person to twist. Adaptation is what is left when nothing is imposed.",
	},
	{
		"CHAR.TRACER",
		"TRACER",
		.CHARACTER,
		"Fell from Earth. Fast, sharp, restless, so VectorPlane made her a triangle -- the shape of a thing that has not stopped going anywhere.",
	},
	{
		"CHAR.BUD",
		"BUD",
		.CHARACTER,
		"Fell from Earth. Solid, stubborn, immovable, so VectorPlane made him a circle -- the shape of a thing that has decided where it is.",
	},
	{
		"CHAR.NAVY",
		"NAVY",
		.CHARACTER,
		"Fell from Earth. Disciplined, ordered, military, so VectorPlane made him a square. He draws the same as RR, but a native's square is the ground and a human's is a posture.",
	},
}
