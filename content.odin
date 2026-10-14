package main
import "vendor:raylib"

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
	// RARE
	{"TIGHT GROUPS", "-20% SPREAD", 35, .UPGRADE, "PRECISION", .RARE},
	{"EXTENDED DASH", "STRONGER DASH", 35, .UPGRADE, "DASH", .RARE},
	{"HOT LOAD", "+1 PIERCE", 40, .UPGRADE, "PIERCE", .RARE},
	// EPIC
	{"MYSTERY CRATE", "RANDOM UPGRADE", 50, .UPGRADE, "RANDOM", .EPIC},
	{"DOUBLE TAP", "+1 PROJECTILE", 60, .UPGRADE, "PROJECTILE", .EPIC},
}

ENEMIES := [Enemy_Kind]Enemy_Stats {
	// NAME, SIZE, SPEED, DAMAGE, HP, COLOR, RANGED, PREFERRED_RANGE, FIRE_RATE, CHARGE_SPEED
	.GRUNT   = {"GRUNT", {50, 50}, 80, 10, 2, raylib.BLUE, false, 0, 0, 0},
	.RUNNER  = {"RUNNER", {30, 30}, 150, 6, 1, raylib.ORANGE, false, 0, 0, 0},
	.TANK    = {"TANK", {80, 80}, 45, 20, 8, raylib.DARKGREEN, false, 0, 0, 0},
	.RANGED  = {"SHOOTER", {36, 36}, 75, 8, 3, raylib.VIOLET, true, 280, 1.4, 0},
	.CHARGER = {"CHARGER", {46, 46}, 95, 14, 4, raylib.MAROON, false, 0, 0, 560},
}

GUNS := [Gun]Gun_Stats {
	// GUN = {NAME, DESC, BULLET_SPEED, DAMAGE, PROJECTILES, SPREAD, COOLDOWN, PIERCE, AMMO_CAPACITY, MAG_CAPACITY, BULLET_SIZE, MIN_SPREAD}
	.SNIPER  = {
		"SNIPER",
		"SLOW, HEAVY, PIERCES",
		900,
		2.0,
		1,
		0.00,
		1.00,
		2,
		20,
		5,
		{10, 10},
		0.00,
	},
	.SHOTGUN = {"SHOTGUN", "5-PELLET SPREAD", 340, 1.0, 5, 0.40, 0.60, 0, 30, 2, {8, 8}, 0.10},
	.SMG     = {"SMG", "FAST FIRE, LOW DMG", 520, 0.6, 1, 0.10, 0.07, 0, 60, 30, {7, 7}, 0.02},
	.RIFLE   = {"RIFLE", "BALANCED ALL-ROUNDER", 700, 1.0, 1, 0.03, 0.15, 0, 30, 10, {9, 9}, 0.00},
	.MINIGUN = {
		"MINIGUN",
		"VERY FAST, WIDE SPREAD",
		600,
		0.4,
		1,
		0.28,
		0.05,
		0,
		300,
		150,
		{6, 6},
		0.10,
	},
	.CANNON  = {
		"CANNON",
		"SLOW, HUGE DMG, PIERCES",
		320,
		4.0,
		1,
		0.00,
		0.90,
		1,
		10,
		3,
		{16, 16},
		0.00,
	},
}

// Sidearms for the secondary slot (a separate pool from GUNS).
SECONDARIES := [Secondary]Gun_Stats {
	// NAME, DESC, BULLET_SPEED, DAMAGE, PROJECTILES, SPREAD, COOLDOWN, PIERCE, AMMO_CAPACITY, MAG_CAPACITY, BULLET_SIZE, MIN_SPREAD
	.PISTOL   = {"PISTOL", "STEADY SIDEARM", 620, 0.9, 1, 0.03, 0.22, 0, 48, 12, {8, 8}, 0.00},
	.REVOLVER = {"REVOLVER", "HARD-HITTING, SLOW", 780, 2.2, 1, 0.02, 0.55, 1, 24, 6, {11, 11}, 0.00},
	.DUAL     = {"DUAL", "TWIN SHOTS", 600, 0.7, 2, 0.16, 0.28, 0, 60, 18, {7, 7}, 0.03},
	.SAWED    = {"SAWED", "4-PELLET BLAST", 420, 0.8, 4, 0.50, 0.70, 0, 20, 4, {8, 8}, 0.15},
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
