package main
import "vendor:raylib"

// ---------------------------------------------------------------------------
// Tutorials
//
// Three tiers of hands-on practice, run inside a real (but harmless) arena:
// the player can't be hurt and the "enemies" are stationary dummies. Each tier
// is a list of steps; a step with an action advances once the player performs
// it, and an informational step (action == .NONE) auto-advances after `hold`
// seconds. The advanced tier teaches one character's kit, chosen up front.
// ---------------------------------------------------------------------------

Tutorial_Kind :: enum {
	BASIC,
	MEDIUM,
	ADVANCED,
}

// "Things the player can do", used as both a step requirement and a record of
// what has been done this session (see tutorial_flags).
Tutorial_Action :: enum {
	NONE,
	AIM,
	MOVE,
	FIRE,
	RELOAD,
	DASH,
	KICK,
	PICKUP,
	CYCLE,
	SIGNATURE,
	MARK,
	REND,
	BLOCK,
	VOLT,
}

Tutorial_Flags :: bit_set[Tutorial_Action]

Tutorial_Step :: struct {
	text:   cstring,
	action: Tutorial_Action,
	hold:   f32, // auto-advance delay for informational steps
}

// Record that the player performed an action (used to clear step requirements).
tutorial_note :: proc(a: Tutorial_Action) {
	if tutorial_mode {
		tutorial_flags += {a}
	}
}

// --- step scripts -----------------------------------------------------------
//
// A step with action == .NONE is a read-only lesson that auto-advances after
// `hold` seconds. Any other action clears as soon as the player performs it
// (with a long fallback so nothing can trap them). Text wraps to three lines.

BASIC_STEPS := [?]Tutorial_Step {
	{"This is a safe sandbox: nothing here can hurt you. Move with WASD", .MOVE, 0},
	{"Aim with your mouse - your character always faces the cursor", .AIM, 0},
	{"Hold LMB or SPACE to fire your current weapon. Guns keep firing while held", .FIRE, 0},
	{"Press R to manually reload. It also auto-reloads when the magazine runs dry", .RELOAD, 0},
	{"Press SHIFT to dash. You are invulnerable during it, but it has a cooldown", .DASH, 0},
	{"Press E or RMB to kick - free, no ammo, and knocks enemies back", .KICK, 0},
	{"Kills drop coins - finish a dummy and walk over the loot to collect it", .PICKUP, 0},
	{"Basics complete. Clear the room and head into a real run!", .NONE, 3.5},
}

MEDIUM_STEPS := [?]Tutorial_Step {
	{"You have 3 weapon slots: PRIMARY, SECONDARY, and SIGNATURE. Press Q to cycle", .CYCLE, 0},
	{"Test fire each slot on a dummy - every weapon has unique ammo, range and feel", .FIRE, 0},
	{"Your SIGNATURE is a character-specific melee combo. Swing it now", .SIGNATURE, 0},
	{"After clearing a wave, you'll choose an UPGRADE CARD (ATTACK, HEALTH, SPEED, PIERCE, etc.)", .NONE, 5.0},
	{"Some cards infuse attacks with STATUS EFFECTS: BURN, FREEZE, POISON, or SHOCK", .NONE, 5.0},
	{"BURN and POISON deal damage over time. FREEZE slows enemies. SHOCK stuns them", .NONE, 5.0},
	{"The FORTUNE utility gives you more card choices. Other utilities stack with your build", .NONE, 5.0},
	{"Every 5th wave opens a SHOP. Spend coins on ammo, health, upgrades and rerolls", .NONE, 5.0},
	{"The SHOCKED dummy is stunned - kill it and walk over its coins to collect", .PICKUP, 0},
	{"E/RMB = kick, SHIFT = dash. Clear waves, upgrade, survive. Good luck!", .NONE, 4.0},
}

// RR's Adaptation is driven by your upgrades, so a fresh run sits on OFFENSE.
// The tutorial walks him through each stance instead (see rr_tutorial_adaptation).
RR_STEPS := [?]Tutorial_Step {
	{"RR's ADAPTATION follows your build - whichever stat you invest in most determines his stance", .NONE, 5.0},
	{"OFFENSE (most damage): Vector Edge is cuts/sweeps leading to a shock smash", .NONE, 5.0},
	{"RESILIENCE (most max HP): hold E/RMB to raise BULWARK and block frontal damage", .BLOCK, 0},
	{"PRECISION (spread reduction): E becomes NEEDLE - a short blink to reposition", .NONE, 5.0},
	{"MOBILITY (most speed): his blade strikes and reach adapt to hit and close faster", .NONE, 5.0},
	{"BURST dash grants SECOND WIND - amplifies your current stance by 50% briefly", .NONE, 5.0},
	{"Adapt to the fight - stack the stat that counters enemies. Press Q to swap slots", .NONE, 4.0},
}

BUD_STEPS := [?]Tutorial_Step {
	{"Press Q to equip Bud's FISTS. Attack to start the JAB-HOOK-ELBOW-KNEE combo", .SIGNATURE, 0},
	{"Keep attacking within the combo window. Missing it resets back to JAB", .NONE, 4.0},
	{"The 4th strike (KNEE) is CHARGED - hold briefly while armed to wind it up", .NONE, 5.0},
	{"A fully charged KNEE lunges forward and sends enemies flying with massive knockback", .NONE, 4.0},
	{"GUARD UP: Bud blocks frontal hits, taking reduced damage. Face enemies head-on", .NONE, 5.0},
	{"E or RMB gives a fast KICK you can weave between combo strikes", .KICK, 0},
	{"Holding a gun makes Bud UNHAPPY - worse accuracy and damage. Stick to his fists", .NONE, 5.0},
	{"Keep the chain rolling - pressure is key", .NONE, 3.5},
}

TRACER_STEPS := [?]Tutorial_Step {
	{"Press Q for TRACER'S PHASE CLAWS. CLAW and CROSS apply PHASE MARKS", .MARK, 0},
	{"Marks deal no direct damage - they stack and fade if you don't detonate them", .NONE, 4.0},
	{"REND (3rd strike) detonates all marks for burst damage plus splash to nearby enemies", .REND, 0},
	{"Killing a marked enemy with REND heals Tracer for 8 HP", .NONE, 4.0},
	{"TRACEUR'S HEART: attacks build speed up to +50%. Keep the pressure on", .NONE, 5.0},
	{"SLIDE dash instantly refills Traceur's Heart - slide into fights at full speed", .NONE, 5.0},
	{"Glass cannon: strike hard, reposition with SHIFT", .NONE, 3.5},
}

NAVY_STEPS := [?]Tutorial_Step {
	{"Press Q twice to reach Navy's SIGNATURE: the BAYONET. Fire to swing it", .SIGNATURE, 0},
	{"The bayonet chains a fast THRUST into a committed LUNGE that carries you forward", .NONE, 4.0},
	{"The LUNGE also fires a MUZZLE VOLLEY: a point-blank burst along the stab line", .VOLT, 0},
	{"The volley spends one round and hits with your PRIMARY gun's damage", .NONE, 4.0},
	{"With an empty primary mag the lunge stays a plain stab - no volley, no cost", .NONE, 4.0},
	{"E or RMB is only Navy's plain kick: free, but it never volleys - just knocks back", .KICK, 0},
	{"TAKE AIM: standing completely still gives PERFECT accuracy. Stop to snipe, move to spray", .NONE, 5.0},
	{"Navy carries extra ammo and reloads fast. His BLINK dash finishes reloads instantly", .NONE, 5.0},
	{"Thrust, lunge, volley - that's the Navy rhythm. Q cycles back to your guns", .NONE, 3.5},
}

// Pick the script for the current tutorial tier (and character, if advanced).
tutorial_steps :: proc() -> []Tutorial_Step {
	if tutorial_kind == .BASIC {
		return BASIC_STEPS[:]
	}
	if tutorial_kind == .MEDIUM {
		return MEDIUM_STEPS[:]
	}
	switch tutorial_char {
	case .RR:
		return RR_STEPS[:]
	case .BUD:
		return BUD_STEPS[:]
	case .TRACER:
		return TRACER_STEPS[:]
	case .NAVY:
		return NAVY_STEPS[:]
	}
	return BASIC_STEPS[:]
}

// --- setup ------------------------------------------------------------------

// Skill-select values stashed while a tutorial runs: the general tiers force a
// Navy loadout, and start_run() writes those same globals, so we put the
// player's own choices back when the tutorial ends.
tutorial_saved_char: Character
tutorial_saved_gun: Gun
tutorial_saved_secondary: Secondary
tutorial_saved_dash: Dash_Kind
tutorial_saved_utility: Utility

// Begin a tutorial: start a normal run for the chosen loadout, then mark it as
// a tutorial, drop in practice dummies, and reset the step cursor.
//
// Basic and Medium teach the universal controls, so they always play as Navy
// with a plain gun -- the simplest kit. (Otherwise the lesson depends on the
// player's last loadout: RR + the default VITALITY utility, for instance,
// locks his Adaptation to RESILIENCE, which turns E into BULWARK and makes the
// basic "kick" step impossible.) Advanced uses the character picked up front.
tutorial_start :: proc(kind: Tutorial_Kind, char: Character) {
	tutorial_saved_char = character
	tutorial_saved_gun = gun
	tutorial_saved_secondary = secondary_kind
	tutorial_saved_dash = dash_kind
	tutorial_saved_utility = utility

	primary := gun
	secondary := secondary_kind
	dash := dash_kind
	util := utility
	c := char
	if kind != .ADVANCED {
		c = .NAVY
		primary = .RIFLE
		secondary = .PISTOL
		dash = .BURST
		util = .VITALITY
	} else {
		// The advanced scripts teach each character's signature dash synergy,
		// so pin it -- the text would be a lie on any other dash. Navy's muzzle
		// volley also needs a real firearm in the primary slot.
		switch c {
		case .RR:
			dash = .BURST
		case .TRACER:
			dash = .SLIDE
		case .BUD:
			dash = .IMPACT
		case .NAVY:
			dash = .BLINK
			primary = .RIFLE
		}
	}
	stats := start_loadout(c, primary, secondary, dash, util)
	start_run(stats)
	tutorial_mode = true
	tutorial_kind = kind
	tutorial_char = c
	tutorial_step = 0
	tutorial_timer = 0
	tutorial_flags = {}
	clear(&enemies)
	spawn_tutorial_dummies()
}

// Two stationary dummies placed either side of the player.
spawn_tutorial_dummies :: proc() {
	pc := position + size * 0.5
	for i in 0 ..< 2 {
		off := f32(i) * 2 - 1
		pos := pc + raylib.Vector2{off * 180, -80}
		spawn_enemy_at(.GRUNT, false, 1, pos)
		if len(enemies) > 0 {
			e := &enemies[len(enemies) - 1]
			e.training = true
			// A beefy practice target that still dies so finishers can land.
			e.hp = 60
			e.max_hp = 60
			e.speed = 0
			// One dummy wears a permanent SHOCK so the lessons can show a live
			// status effect (and it stays put, stunned, while you farm it).
			if i == 1 {
				e.effects = {.Shock}
				e.effect_timer[.Shock] = 9999
			}
		}
	}
}

// --- runtime ----------------------------------------------------------------

// An action step the player can't perform (e.g. R on a full magazine, or a
// character form they can't reach) shouldn't trap them; after this long the
// step moves on by itself.
TUTORIAL_ACTION_TIMEOUT :: 14.0

// Advance the step cursor when the current step's requirement is met. Returns
// true when the whole script is finished (caller can then end the tutorial).
tutorial_update :: proc(dT: f32) {
	steps := tutorial_steps()
	if tutorial_step >= len(steps) {
		tutorial_done()
		return
	}
	s := steps[tutorial_step]
	if s.action == .NONE {
		tutorial_timer += dT
		if tutorial_timer >= s.hold {
			tutorial_next()
		}
	} else if s.action in tutorial_flags {
		tutorial_next()
	} else {
		// Fallback: give plenty of time, then move on regardless.
		tutorial_timer += dT
		if tutorial_timer >= TUTORIAL_ACTION_TIMEOUT {
			tutorial_next()
		}
	}
}

tutorial_next :: proc() {
	tutorial_step += 1
	tutorial_timer = 0
}

// RR's advanced tutorial steps through each Adaptation so the player can feel
// them out. Offense first, then Resilience (BULWARK), Precision (NEEDLE) and
// finally Mobility. Returns ok=false outside that specific tutorial.
rr_tutorial_adaptation :: proc() -> (a: RR_Adaptation, ok: bool) {
	if !(tutorial_mode && tutorial_kind == .ADVANCED && tutorial_char == .RR) {
		return .OFFENSE, false
	}
	switch tutorial_step {
	case 0, 1:
		return .OFFENSE, true
	case 2:
		return .RESILIENCE, true
	case 3:
		return .PRECISION, true
	case:
		return .MOBILITY, true
	}
}

// Finish the tutorial and return to the menu.
tutorial_done :: proc() {
	tutorial_mode = false
	clear_run_entities()
	// Put the player's own skill-select choices back (see tutorial_start).
	character = tutorial_saved_char
	gun = tutorial_saved_gun
	secondary_kind = tutorial_saved_secondary
	dash_kind = tutorial_saved_dash
	utility = tutorial_saved_utility
	state = .MAIN_MENU
	main_menu_sel = 1
}

// --- drawing ----------------------------------------------------------------

// Prompt banner for the current step, drawn in canvas space over the arena.
tutorial_draw :: proc() {
	steps := tutorial_steps()
	if tutorial_step >= len(steps) {
		return
	}
	s := steps[tutorial_step]
	// Panel across the bottom of the canvas.
	raylib.DrawRectangle(0, 470, 800, 130, raylib.Color{0, 0, 0, 190})
	raylib.DrawRectangle(0, 470, 800, 3, raylib.SKYBLUE)
	raylib.DrawText(
		raylib.TextFormat("TUTORIAL  %i / %i", tutorial_step + 1, len(steps)),
		16,
		482,
		18,
		raylib.SKYBLUE,
	)
	// The hint wraps into at most three lines for longer tutorials.
	txt := string(s.text)
	// Find the last space at or before `up_to` (falling back to a hard cut).
	wrap_at :: proc(txt: string, up_to: int) -> int {
		cut := up_to
		for cut > 0 && cut < len(txt) && txt[cut] != ' ' {
			cut -= 1
		}
		return cut > 0 ? cut : min(up_to, len(txt))
	}
	if len(txt) <= 60 {
		raylib.DrawText(raylib.TextFormat("%s", txt), 16, 512, 20, raylib.RAYWHITE)
	} else if len(txt) <= 120 {
		cut := wrap_at(txt, 60)
		raylib.DrawText(raylib.TextFormat("%s", txt[:cut]), 16, 508, 20, raylib.RAYWHITE)
		raylib.DrawText(raylib.TextFormat("%s", txt[cut:]), 16, 534, 20, raylib.RAYWHITE)
	} else {
		cut1 := wrap_at(txt, 60)
		cut2 := wrap_at(txt[cut1:], 60) + cut1
		raylib.DrawText(raylib.TextFormat("%s", txt[:cut1]), 16, 500, 18, raylib.RAYWHITE)
		raylib.DrawText(raylib.TextFormat("%s", txt[cut1:cut2]), 16, 522, 18, raylib.RAYWHITE)
		raylib.DrawText(raylib.TextFormat("%s", txt[cut2:]), 16, 544, 18, raylib.RAYWHITE)
	}
	raylib.DrawText("ESC to leave the tutorial", 16, 578, 16, raylib.GRAY)
}
