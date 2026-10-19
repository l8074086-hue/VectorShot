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
	NEEDLE, // RR's PRECISION blink (E)
	DESTROY, // destroyed the lesson's target (RR's OFFENSE turret)
	COMBO, // chained the signature combo to its third link (Bud's ELBOW)
	KNEE, // landed Bud's flying KNEE with real charge wound up
	GUARD, // took a hit inside Bud's GUARD UP cone
	MARK_KILL, // killed a PHASE-marked target with REND (Tracer's heal)
	HEART, // spun TRACEUR'S HEART all the way up with attacks
	VOLT,
	CARD, // picked one of the upgrade cards the tutorial dealt
	ELEMENT_CARD, // picked a STATUS (element) card the tutorial dealt
	SHOP_DONE, // left the shop the tutorial opened
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

// The element the player took in the Medium "Now you try" status lesson. The
// follow-up step uses it to stage a matching target (SHOCK/FREEZE -> a walking
// dummy, POISON/BURN -> a stationary one). Reset when the tutorial starts.
tutorial_picked_element: Status_Effect = .Burn

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
	{"Basics complete. Now head into a real run!", .NONE, 3.5},
}

MEDIUM_STEPS := [?]Tutorial_Step {
	{"You have 3 weapon slots: PRIMARY, SECONDARY, and SIGNATURE. Press Q to cycle", .CYCLE, 0},
	{"Test fire each slot on a dummy - every weapon has unique ammo, range and feel", .FIRE, 0},
	{"Your SIGNATURE is a character-specific melee combo. Swing it now", .SIGNATURE, 0},
	{"Clearing a wave offers UPGRADE CARDS. Pick one to shape your build", .CARD, 0},
	{"Some cards infuse attacks with STATUS EFFECTS - watch them on these dummies", .NONE, 6.0},
	{"BURN and POISON deal damage over time. FREEZE slows enemies. SHOCK stuns them", .NONE, 5.0},
	{"Now you try - pick a STATUS card to infuse your own attacks", .ELEMENT_CARD, 0},
	{"Your attacks carry that effect now. Finish the dummy and walk over its coins", .PICKUP, 0},
	{
		"The FORTUNE utility offers more card choices. Other utilities stack with your build",
		.NONE,
		5.0,
	},
	{"Every 5th wave opens a SHOP. Buy an upgrade, then pick LEAVE to continue", .SHOP_DONE, 0},
	{"E/RMB = kick, SHIFT = dash. Clear waves, upgrade, survive. Good luck!", .NONE, 4.0},
}

// RR's Adaptation is driven by your upgrades, so a fresh run sits on OFFENSE.
// The tutorial walks him through each stance instead (see rr_tutorial_adaptation).
RR_STEPS := [?]Tutorial_Step {
	{
		"RR's ADAPTATION follows your build - whichever stat you invest in most determines his stance",
		.NONE,
		7.0,
	},
	{
		"OFFENSE (most damage): Vector Edge cuts, sweeps, then a shock smash - destroy the turret",
		.DESTROY,
		20.0,
	},
	{
		"RESILIENCE (most max HP): face the turret and hold E/RMB to raise BULWARK and block its shots. You cannot attack while guarding",
		.BLOCK,
		20.0,
	},
	{
		"PRECISION (spread reduction): press E/RMB to NEEDLE-blink out of the firing line",
		.NEEDLE,
		20.0,
	},
	{
		"MOBILITY (most speed): press SHIFT to BURST-dash - his blade reaches and closes faster",
		.DASH,
		20.0,
	},
	{
		"BURST dash also grants SECOND WIND - it amplifies whichever Adaptation you are on",
		.NONE,
		7.0,
	},
	{"Adapt to the fight - stack the stat that counters enemies. Press Q to swap slots", .NONE, 5.0},
}

BUD_STEPS := [?]Tutorial_Step {
	{
		"Bud fights bare-handed. Press Q to equip his FISTS - SPACE throws JAB, HOOK, ELBOW, KNEE",
		.NONE,
		7.0,
	},
	{
		"Chain them: keep pressing inside the combo window to carry the chain all the way to the ELBOW",
		.COMBO,
		20.0,
	},
	{
		"The 4th strike (KNEE) is CHARGED - let it wind up while it's armed, then throw it",
		.KNEE,
		20.0,
	},
	{
		"A fully charged KNEE doubles its damage and hurls enemies flying with massive knockback",
		.NONE,
		6.0,
	},
	{
		"GUARD UP: face the turret and let a shot land head-on - damage inside the cone is cut 25%",
		.GUARD,
		20.0,
	},
	{
		"E or RMB gives a fast KICK you can weave between his combo strikes",
		.KICK,
		20.0,
	},
	{
		"Holding a gun makes Bud UNHAPPY - worse accuracy, damage and speed. Stick to his fists",
		.NONE,
		7.0,
	},
	{"Keep the chain rolling - pressure is key", .NONE, 4.0},
}

TRACER_STEPS := [?]Tutorial_Step {
	{
		"Press Q for TRACER'S PHASE CLAWS. CLAW and CROSS land PHASE MARKS on what they touch",
		.NONE,
		7.0,
	},
	{
		"Get close and claw it - the lights deal no damage at all, they only stack marks",
		.MARK,
		20.0,
	},
	{
		"REND is the 3rd strike: it detonates every mark for burst damage and splashes marks nearby",
		.REND,
		20.0,
	},
	{
		"Finish a MARKED target with REND and Tracer heals 8 HP - stack the marks, then finish it",
		.MARK_KILL,
		20.0,
	},
	{
		"TRACEUR'S HEART: every attack spins her up to +50% speed. Keep attacking until it tops out",
		.HEART,
		20.0,
	},
	{
		"Her SLIDE dash instantly refills Traceur's Heart - slide into fights at top speed",
		.DASH,
		20.0,
	},
	{"Glass cannon: strike hard, reposition with SHIFT", .NONE, 4.0},
}

NAVY_STEPS := [?]Tutorial_Step {
	{"Press Q twice to reach Navy's SIGNATURE: the BAYONET. Fire to swing it", .SIGNATURE, 0},
	{
		"The bayonet chains a fast THRUST into a committed LUNGE that carries you forward",
		.NONE,
		4.0,
	},
	{"The LUNGE also fires a MUZZLE VOLLEY: a point-blank burst along the stab line", .VOLT, 0},
	{"The volley spends one round and hits with your PRIMARY gun's damage", .NONE, 4.0},
	{"With an empty primary mag the lunge stays a plain stab - no volley, no cost", .NONE, 4.0},
	{
		"E or RMB is only Navy's plain kick: free, but it never volleys - just knocks back",
		.KICK,
		0,
	},
	{
		"TAKE AIM: standing completely still gives PERFECT accuracy. Stop to snipe, move to spray",
		.NONE,
		5.0,
	},
	{
		"Navy carries extra ammo and reloads fast. His BLINK dash finishes reloads instantly",
		.NONE,
		5.0,
	},
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

// The action the current step is waiting on (.NONE for info steps). Used to
// route a card pick to the right lesson when two steps deal cards.
tutorial_current_action :: proc() -> Tutorial_Action {
	steps := tutorial_steps()
	if tutorial_step < 0 || tutorial_step >= len(steps) {
		return .NONE
	}
	return steps[tutorial_step].action
}

// Record a card pick. Notes the action the current step is waiting on, and
// remembers which element was taken so the status follow-up can stage the
// matching dummy. The element is recorded regardless of step; only the note is
// gated so an early element card can't auto-satisfy the "Now you try" lesson.
tutorial_note_card :: proc(name: cstring) {
	switch name {
	case "IGNITE":
		tutorial_picked_element = .Burn
	case "CRYO":
		tutorial_picked_element = .Freeze
	case "VENOM":
		tutorial_picked_element = .Poison
	case "STATIC":
		tutorial_picked_element = .Shock
	}
	if !tutorial_mode {
		return
	}
	action := tutorial_current_action()
	if action == .ELEMENT_CARD {
		tutorial_note(.ELEMENT_CARD)
	} else if action == .CARD {
		tutorial_note(.CARD)
	}
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
	// Tutorials are always plain sandbox runs: drop any mission selected on the
	// Mission Control screen so its objective/HUD never leaks into a lesson, and
	// don't leave a real run's save behind.
	active_mission = -1
	mission_cleared_this_run = false
	mission_banner = 0
	clear_run_save()
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
	tutorial_picked_element = .Burn
	clear(&enemies)
	spawn_tutorial_dummies()
	tutorial_step_entered()
}

// Two stationary dummies placed either side of the player. They hold a deep
// health pool so there is always something to shoot, and they come back if the
// player clears the room (see the respawn in the main loop).
spawn_tutorial_dummies :: proc() {
	pc := position + size * 0.5
	for i in 0 ..< 2 {
		off := f32(i) * 2 - 1
		pos := pc + raylib.Vector2{off * 180, -80}
		spawn_tutorial_target(.DUMMY_DPS, pos)
	}
}

// Spawn one practice dummy at `pos` and hand it back so the caller can tweak it
// (effects, patrol route, aim). Returns nil if nothing was spawned. Only valid
// until the next enemy is appended.
spawn_tutorial_target :: proc(kind: Enemy_Kind, pos: raylib.Vector2) -> ^enemy {
	spawn_enemy_at(kind, false, 1, pos)
	if len(enemies) == 0 {
		return nil
	}
	return &enemies[len(enemies) - 1]
}

// A stationary punching bag for melee lessons, with enough health that a whole
// combo chain (and a charged finisher) can land on it without it dying halfway
// through the lesson.
spawn_tutorial_bag :: proc(pc: raylib.Vector2, offset: raylib.Vector2) {
	e := spawn_tutorial_target(.DUMMY_DPS, pc + offset)
	if e == nil {
		return
	}
	e.hp = 9999
	e.max_hp = 9999
}

// Give a DUMMY_PATROL a short horizontal route centered on where it stands.
set_patrol_route :: proc(e: ^enemy) {
	c := e.position + e.size * 0.5
	e.patrol_points[0] = c + {-140, 0}
	e.patrol_points[1] = c + {140, 0}
	e.patrol_count = 2
	e.patrol_index = 1
}

// A practice turret that fires straight at where the player is standing, so a
// lesson can be done while under fire. `durable` raises its health so it keeps
// shooting for the whole step; an OFFENSE lesson leaves it killable instead.
spawn_tutorial_turret :: proc(
	pc: raylib.Vector2,
	offset: raylib.Vector2,
	durable := true,
) -> ^enemy {
	t := spawn_tutorial_target(.DUMMY_RANGED, pc + offset)
	if t == nil {
		return nil
	}
	t.shoot_dir = raylib.Vector2Normalize(pc - (t.position + t.size * 0.5))
	if durable {
		t.hp = 9999
		t.max_hp = 9999
	}
	return t
}

// Tag a dummy with a status that never expires, for the status-effects demo.
// The health pool is raised too, so BURN/POISON damage-over-time can't kill the
// exhibit before the player has seen it.
demonstrate_status :: proc(e: ^enemy, eff: Status_Effect) {
	e.effects += {eff}
	e.effect_timer[eff] = 9999
	e.hp = 9999
	e.max_hp = 9999
}

// The four "on hit" infusion cards, in status order, for the try-it lesson.
ELEMENT_CARD_NAMES := [?]cstring{"IGNITE", "CRYO", "VENOM", "STATIC"}

// Deal a fixed hand of named cards, for lessons that must show specific choices.
// Mirrors spawn_cards' layout so the hand lands in the same spot.
spawn_tutorial_cards :: proc(cards: ^[dynamic]card, names: []cstring) {
	CARD_W: f32 = 120
	CARD_H: f32 = 160
	spacing := CARD_W + 40
	center_x := f32(800) / 2
	y := f32(600) / 2 - CARD_H / 2
	n := len(names)
	total_w := spacing * f32(n) - (spacing - CARD_W)
	start_x := center_x - total_w / 2
	for name, i in names {
		desc: cstring = ""
		for c in CARD_POOL {
			if c.name == name {
				desc = c.description
				break
			}
		}
		append(
			cards,
			card{{start_x + spacing * f32(i), y}, {CARD_W, CARD_H}, name, desc, false},
		)
	}
}

// Stage the step we just entered. Some lessons need the real thing on screen --
// a live target, a dealt hand of cards, or the actual shop -- not just a
// description. Called from tutorial_start and tutorial_next (i.e. on every step
// change).
tutorial_step_entered :: proc() {
	if !tutorial_mode {
		return
	}
	// Clear any interactive staging from the previous step (e.g. cards still on
	// screen because the fallback timer moved on), and forget actions from
	// earlier steps so each action step needs its own fresh input.
	clear(&cards)
	tutorial_flags = {}
	tutorial_settle = -1
	pc := position + size * 0.5
	switch tutorial_kind {
	case .BASIC:
		switch tutorial_step {
		case 6:
			// "Kills drop coins...": a fragile target that always pays out.
			spawn_tutorial_target(.DUMMY_WEAK, pc + {0, -170})
		}
	case .MEDIUM:
		switch tutorial_step {
		case 3:
			// card lesson: deal a real hand to pick from
			spawn_cards(&cards, card_choices)
		case 4:
			// status lesson: show each effect live. Two walkers take the movement
			// effects (SHOCK, FREEZE); two stationary targets take the damage-over-
			// time effects (POISON, BURN). `demonstrate_status` keeps them alive.
			clear(&enemies)
			if e := spawn_tutorial_target(.DUMMY_PATROL, pc + {-150, -190}); e != nil {
				set_patrol_route(e)
				demonstrate_status(e, .Shock)
			}
			if e := spawn_tutorial_target(.DUMMY_PATROL, pc + {150, -190}); e != nil {
				set_patrol_route(e)
				demonstrate_status(e, .Freeze)
			}
			if e := spawn_tutorial_target(.DUMMY_DPS, pc + {-95, -105}); e != nil {
				demonstrate_status(e, .Poison)
			}
			if e := spawn_tutorial_target(.DUMMY_DPS, pc + {95, -105}); e != nil {
				demonstrate_status(e, .Burn)
			}
		case 6:
			// "Now you try": deal exactly the four element cards and wait for a pick.
			spawn_tutorial_cards(&cards, ELEMENT_CARD_NAMES[:])
		case 7:
			// The pick is in: clear the demo and stage one target matching the
			// chosen element -- movement effects get a walker, damage-over-time a
			// stationary dummy. The player finishes it off and collects the coins.
			clear(&enemies)
			if tutorial_picked_element == .Shock || tutorial_picked_element == .Freeze {
				if e := spawn_tutorial_target(.DUMMY_PATROL, pc + {0, -170}); e != nil {
					set_patrol_route(e)
				}
			} else {
				spawn_tutorial_target(.DUMMY_DPS, pc + {0, -170})
			}
		case 9:
			// shop lesson: open the actual shop, with coins to spend
			currency = max(currency, 90)
			build_shop()
			state = .SHOP
		}
	case .ADVANCED:
		// Each character's script gets the target that best fits its lesson.
		switch tutorial_char {
		case .RR:
			// Every Adaptation gets a live turret firing at the player, and the
			// step only clears when RR answers it the way that form is meant to:
			// OFFENSE destroys it, RESILIENCE blocks a shot, PRECISION blinks,
			// MOBILITY dashes. Staging is cleared first so each lesson starts
			// from a clean arena.
			switch tutorial_step {
			case 1:
				// OFFENSE: a killable turret to take apart with the Vector Edge.
				clear(&enemies)
				spawn_tutorial_turret(pc, {0, -220}, false)
			case 2:
				// RESILIENCE: a sturdy turret to face and BULWARK its shots.
				clear(&enemies)
				spawn_tutorial_turret(pc, {0, -240})
			case 3:
				// PRECISION: a turret to blink out of the firing line.
				clear(&enemies)
				spawn_tutorial_turret(pc, {0, -240})
			case 4:
				// MOBILITY: a turret set further out to dash toward.
				clear(&enemies)
				spawn_tutorial_turret(pc, {0, -210})
			}
		case .BUD:
			// Each step is a real test against a live target: carry the combo to
			// the ELBOW, land a charged KNEE, then take a shot inside his guard
			// cone. The arena is cleared first so each lesson starts clean.
			switch tutorial_step {
			case 1:
				// Combo: something to chain all four links into.
				clear(&enemies)
				spawn_tutorial_bag(pc, {0, -95})
			case 2:
				// Charged KNEE: the lunge covers the gap, so set it downrange.
				clear(&enemies)
				spawn_tutorial_bag(pc, {0, -170})
			case 4:
				// GUARD UP: a live turret to eat a shot from, facing it head-on.
				clear(&enemies)
				spawn_tutorial_turret(pc, {0, -240})
			case 5:
				// KICK: something to shove around between the combo links.
				clear(&enemies)
				spawn_tutorial_bag(pc, {0, -85})
			}
		case .TRACER:
			// Every step is a live test too: land a mark, detonate it, kill the
			// marked target to heal, then spin the Heart and slide back in.
			switch tutorial_step {
			case 1:
				// Marks: the lights deal no damage, so this bag shows the mark
				// count stacking up without dying under the lesson.
				clear(&enemies)
				spawn_tutorial_bag(pc, {0, -85})
			case 2:
				// REND: the detonator itself.
				clear(&enemies)
				spawn_tutorial_bag(pc, {0, -85})
			case 3:
				// Marked kill: a target light enough that REND is what finishes
				// it -- an unmarked REND leaves it alive to try again. Set close
				// in, since each light shoves it back a little.
				clear(&enemies)
				spawn_tutorial_target(.DUMMY_WEAK, pc + {0, -55})
			case 4:
				// Traceur's Heart: keep swinging until it tops out. Zero the meter
				// on entry so the step is always a real spin-up, never a leftover
				// charge carried over from the marked-kill lesson.
				clear(&enemies)
				spawn_tutorial_bag(pc, {0, -95})
				traceur_charge = 0
			case 5:
				// SLIDE: a turret to slide into at full speed.
				clear(&enemies)
				spawn_tutorial_turret(pc, {0, -240})
			}
		case .NAVY:
			// TAKE AIM: a distant turret to snipe from a standstill.
			if tutorial_step == 6 {
				if t := spawn_tutorial_target(.DUMMY_RANGED, pc + {240, -150}); t != nil {
					t.shoot_dir = {1, 0}
				}
			}
		}
	}
}

// --- runtime ----------------------------------------------------------------

// An action step the player can't perform (e.g. R on a full magazine, or a
// character form they can't reach) shouldn't trap them; after this long the
// step moves on by itself. A step may set its own longer grace period in `hold`.
TUTORIAL_ACTION_TIMEOUT :: 14.0

// Once a step's action is met, linger this long before advancing, so the prompt
// doesn't blink past the instant the player does the thing.
TUTORIAL_ACTION_DWELL :: 1.5

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
		// Requirement met: hold a beat so the advance reads clearly.
		if tutorial_settle < 0 {
			tutorial_settle = 0
		}
		tutorial_settle += dT
		if tutorial_settle >= TUTORIAL_ACTION_DWELL {
			tutorial_next()
		}
	} else {
		// Fallback: give plenty of time, then move on regardless. Action steps
		// that want a longer grace period (a form test) set it in `hold`.
		fallback := s.hold > 0 ? s.hold : TUTORIAL_ACTION_TIMEOUT
		tutorial_timer += dT
		if tutorial_timer >= fallback {
			tutorial_next()
		}
	}
}

tutorial_next :: proc() {
	tutorial_step += 1
	tutorial_timer = 0
	tutorial_step_entered()
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
	// Confirmation while the step lingers after being completed.
	if s.action != .NONE && tutorial_settle >= 0 {
		raylib.DrawText("NICE!", 716, 482, 18, raylib.LIME)
	}
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

// Compact step hint for the shop, where the full bottom banner would cover the
// shop's own controls line. Sits in the gap under the coin count.
tutorial_draw_shop :: proc() {
	steps := tutorial_steps()
	if tutorial_step >= len(steps) {
		return
	}
	txt := string(steps[tutorial_step].text)
	fs: i32 = 18
	for fs > 9 && raylib.MeasureText(raylib.TextFormat("%s", txt), fs) > 760 {
		fs -= 1
	}
	draw_centered(raylib.TextFormat("%s", txt), 112, fs, raylib.SKYBLUE)
}
