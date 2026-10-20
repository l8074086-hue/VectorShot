package main
import "core:math"
import "core:math/rand"
import "vendor:raylib"

// ---------------------------------------------------------------------------
// Arena bosses
// ---------------------------------------------------------------------------
// Every arena's finale is a hand-built fight. The shared skeleton (phase flip,
// telegraph -> execute -> recover) lives in update_boss, which then hands off to
// a per-boss moveset. Each boss also owns its own telegraph tell and silhouette
// (draw_boss_telegraph / draw_boss_body), so no two read the same.
//
// Conventions used throughout:
//   e.state       CHASE/RECOVER decide, WINDUP telegraphs, BOSS_ATTACK executes
//   e.boss_next   which attack this cycle picked (per-boss meaning)
//   e.boss_seq    sub-step *within* an attack (pillar marched out, ring fired)
//   e.boss_timer2 secondary timer (between-attack pacing, fire cadence)
//   e.boss_aux    scratch direction (aim line, dash/blink target)
// ---------------------------------------------------------------------------

// Fire one hostile projectile from `from` toward `dir`.
boss_shot :: proc(from, dir: raylib.Vector2, speed, damage, size: f32, effects: Status_Set = {}) {
	if raylib.Vector2Length(dir) < 0.01 {
		return
	}
	u := raylib.Vector2Normalize(dir)
	append(
		&enemy_bullets,
		bullet {
			position = from - {size * 0.5, size * 0.5},
			size = {size, size},
			velocity = u * speed,
			damage = damage,
			effects = effects,
		},
	)
}

// Fire `count` projectiles evenly around `from`.
boss_radial :: proc(
	from: raylib.Vector2,
	count: i32,
	speed, damage, size: f32,
	offset: f32 = 0,
	effects: Status_Set = {},
) {
	if count <= 0 {
		return
	}
	for i in 0 ..< count {
		ang := offset + f32(i) * (2 * math.PI / f32(count))
		append(
			&enemy_bullets,
			bullet {
				position = from - {size * 0.5, size * 0.5},
				size = {size, size},
				velocity = {math.cos_f32(ang), math.sin_f32(ang)} * speed,
				damage = damage,
				effects = effects,
			},
		)
	}
}

// Fire a spread of `count` shots aimed at the player.
boss_fan :: proc(
	from, to_player: raylib.Vector2,
	count: i32,
	spread, speed, damage, size: f32,
	effects: Status_Set = {},
) {
	if count <= 0 {
		return
	}
	base: f32 = 0
	if raylib.Vector2Length(to_player) > 0.01 {
		base = math.atan2_f32(to_player.y, to_player.x)
	}
	for i in 0 ..< count {
		off: f32 = 0
		if count > 1 {
			off = (f32(i) - f32(count - 1) * 0.5) * spread
		}
		ang := base + off
		append(
			&enemy_bullets,
			bullet {
				position = from - {size * 0.5, size * 0.5},
				size = {size, size},
				velocity = {math.cos_f32(ang), math.sin_f32(ang)} * speed,
				damage = damage,
				effects = effects,
			},
		)
	}
}

// Call in some help at the arena's own wave so adds are scaled like the fight.
// Queue a summon instead of spawning it inline.
//
// Boss AI runs inside the enemy update loop, which is holding `e := &enemies[i]`
// across the call. Spawning here would append to `enemies` under that pointer --
// and an append that grows capacity REALLOCATES the backing array, leaving `e`
// dangling. Every later `e.position` / `e.size` in that loop body is then a
// use-after-free, which is exactly the random SIGSEGV this used to throw.
//
// Deferred for the same reason splitter halves are (see pending_splits): the
// array must not be mutated while the combat loops are walking it.
boss_summon :: proc(kind: Enemy_Kind, count: i32) {
	append(&pending_summons, summon_request{kind = kind, count = count})
}

// Spawn everything the bosses queued this frame. Called once, after the enemy
// update loop has finished.
process_summons :: proc() {
	if len(pending_summons) == 0 {
		return
	}
	for req in pending_summons {
		for _ in 0 ..< req.count {
			spawn_enemy_at(
				req.kind,
				false,
				ARENAS[arena].waves,
				random_spawn_pos(ENEMIES[req.kind].size),
			)
		}
	}
	clear(&pending_summons)
}

// A player-hazard detonation: draws a blast and hurts the player if they're
// inside it (respecting i-frames, like a barrel going off).
boss_blast :: proc(pos: raylib.Vector2, radius, damage: f32, col: raylib.Color) {
	append(
		&explosions,
		explosion{pos = pos, life = 0.35, max_life = 0.35, radius = radius, color = col},
	)
	add_shake(5)
	pc := position + size * 0.5
	if raylib.Vector2Distance(pc, pos) <= radius && inv_timer <= 0 && !tutorial_mode {
		apply_player_damage(damage, pos)
		inv_timer = 0.4
	}
}

// A dust plume / burst, purely visual.
boss_dust :: proc(pos: raylib.Vector2, col: raylib.Color = {196, 164, 110, 255}) {
	append(
		&explosions,
		explosion{pos = pos, life = 0.4, max_life = 0.4, radius = 26, color = col},
	)
}

// One hazard bursting out of the ground (DUSTMAW's pillars, THORNWALD's roots):
// a plume plus a hit if the player is standing on the spot.
boss_pillar :: proc(pos: raylib.Vector2, damage: f32, col: raylib.Color) {
	append(
		&explosions,
		explosion{pos = pos, life = 0.4, max_life = 0.4, radius = 30, color = col},
	)
	add_shake(3)
	pc := position + size * 0.5
	if raylib.Vector2Distance(pc, pos) <= 44 && inv_timer <= 0 && !tutorial_mode {
		apply_player_damage(damage, pos)
		inv_timer = 0.4
	}
}

// Steer to hold a preferred distance: close in when far, back off when crowded,
// otherwise strafe sideways (at `strafe` speed) so the boss is a moving target.
boss_hold_range :: proc(e: ^enemy, dir: raylib.Vector2, dist, spd, target, dT: f32, strafe: f32) {
	perp := raylib.Vector2{-dir.y, dir.x}
	side: f32 = e.id % 2 == 0 ? 1.0 : -1.0
	if dist > target {
		e.position += dir * spd * dT
	} else if dist < target * 0.7 {
		e.position -= dir * spd * dT
	} else if strafe > 0 {
		e.position += perp * spd * strafe * dT * side
	}
}

// ---------------------------------------------------------------------------
// Dispatcher
// ---------------------------------------------------------------------------

// Boss AI entry point (called from update_enemy). Shared phase flip first, then
// the boss's own moveset.
update_boss :: proc(e: ^enemy, dir: raylib.Vector2, dist: f32, spd: f32, dT: f32) {
	// Enrage below half health: a short flourish, then a faster, denser fight.
	if e.boss_phase < 2 && e.hp <= e.max_hp * BOSS_PHASE2_FRAC {
		e.boss_phase = 2
		e.state = .BOSS_RAGE
		e.state_timer = 1.0
		e.flash = 0.5
		e.boss_seq = 0
		play(sounds.enemy_die, 0.7)
	}
	if e.state == .BOSS_RAGE {
		e.state_timer -= dT
		if e.state_timer <= 0 {
			boss_on_enrage(e)
			e.state = .CHASE
			e.state_timer = 0.4
		}
		return
	}
	switch e.boss_kind {
	case .PACKLEADER:
		update_boss_packleader(e, dir, dist, spd, dT)
	case .DUSTMAW:
		update_boss_dustmaw(e, dir, dist, spd, dT)
	case .COLOSSUS:
		update_boss_colossus(e, dir, dist, spd, dT)
	case .FROSTBITE:
		update_boss_frostbite(e, dir, dist, spd, dT)
	case .MECHANIKTRON:
		update_boss_mechaniktron(e, dir, dist, spd, dT)
	case .THORNWALD:
		update_boss_thornwald(e, dir, dist, spd, dT)
	case .BOGWRAITH:
		update_boss_bogwraith(e, dir, dist, spd, dT)
	}
}

// The flourish when a boss flips to phase 2. Summoners call in help here; the
// rest simply fight faster (their movesets read e.boss_phase).
boss_on_enrage :: proc(e: ^enemy) {
	switch e.boss_kind {
	case .PACKLEADER:
		boss_summon(.RUNNER, 3)
	case .THORNWALD:
		boss_summon(.SPLITTER, 2)
	case .MECHANIKTRON:
		boss_summon(.CHARGER, 2)
	case .BOGWRAITH:
		boss_summon(.ORBITER, 2)
	case .DUSTMAW, .COLOSSUS, .FROSTBITE:
	}
}

// ---------------------------------------------------------------------------
// PACKLEADER (GRASSLAND)
// A wolf alpha about the size of a tank. Holds a fixed range, looses poison
// arrows, calls runners, and darts sideways to keep you turning.
// ---------------------------------------------------------------------------
update_boss_packleader :: proc(e: ^enemy, dir: raylib.Vector2, dist: f32, spd: f32, dT: f32) {
	b := ARENA_BOSSES[arena]
	pc := position + size * 0.5
	phase2 := e.boss_phase >= 2

	// A dash overrides the range-holding steering.
	if e.state == .BOSS_ATTACK && e.boss_next == 2 && raylib.Vector2Length(e.boss_aux) > 0.01 {
		e.position += e.boss_aux * spd * (phase2 ? 2.6 : 2.0) * dT
	} else {
		boss_hold_range(e, dir, dist, spd, b.preferred_range, dT, 0.55)
	}

	e.state_timer -= dT
	#partial switch e.state {
	case .CHASE, .RECOVER:
		if e.state_timer <= 0 {
			r := rand.float32()
			e.boss_seq = 0
			if r < 0.55 {
				e.boss_next = 0 // poison arrow fan
				e.state_timer = phase2 ? 0.35 : 0.5
			} else if r < 0.8 {
				e.boss_next = 1 // call the pack
				e.state_timer = phase2 ? 0.4 : 0.6
			} else {
				e.boss_next = 2 // side dash
				e.state_timer = phase2 ? 0.2 : 0.35
			}
			e.state = .WINDUP
			e.flash = 0.12
		}
	case .WINDUP:
		e.boss_aux = dir
		if e.boss_next == 2 {
			side: f32 = rand.float32() < 0.5 ? 1.0 : -1.0
			perp := raylib.Vector2{-dir.y, dir.x}
			e.boss_aux = raylib.Vector2Normalize(perp) * side
		}
		if e.state_timer <= 0 {
			e.state = .BOSS_ATTACK
			switch e.boss_next {
			case 0:
				e.state_timer = 0.3
			case 1:
				e.state_timer = 0.45
			case 2:
				e.state_timer = phase2 ? 0.35 : 0.45
			}
		}
	case .BOSS_ATTACK:
		switch e.boss_next {
		case 0:
			if e.boss_seq == 0 {
				boss_fan(
					e.position + e.size * 0.5,
					pc - (e.position + e.size * 0.5),
					phase2 ? 5 : 3,
					0.17,
					360,
					e.damage,
					10,
					{.Poison},
				)
				e.muzzle = ENEMY_MUZZLE_FLASH_TIME
				e.muzzle_dir = dir
				add_shake(3)
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.3 : 0.5
			}
		case 1:
			if e.boss_seq == 0 {
				boss_summon(.RUNNER, phase2 ? 4 : 2)
				if phase2 {
					boss_summon(.RANGED, 1)
				}
				e.flash = 0.28
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = 0.5
			}
		case 2:
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = 0.45
			}
		}
	}
}

// ---------------------------------------------------------------------------
// DUSTMAW (CANYON)
// A burrowing worm: it spends most of the fight underground and untargetable,
// drifting under your feet, then bursts up for one telegraphed attack before
// diving again. The opening is the surfaced window -- dodge, then punish.
// ---------------------------------------------------------------------------
update_boss_dustmaw :: proc(e: ^enemy, dir: raylib.Vector2, dist: f32, spd: f32, dT: f32) {
	phase2 := e.boss_phase >= 2
	ec := e.position + e.size * 0.5
	e.state_timer -= dT
	e.boss_timer2 -= dT

	#partial switch e.state {
	case .CHASE:
		// First frame: go under immediately.
		e.boss_hidden = true
		e.boss_timer2 = 0.6
		e.state = .BOSS_BURROW
	case .BOSS_BURROW:
		e.boss_hidden = true
		// Travel underground toward the player, rippling the ground as it goes.
		if dist > 30 {
			e.position += dir * spd * 1.35 * dT
		}
		if e.boss_timer2 <= 0 {
			e.boss_hidden = false
			e.state = .BOSS_EMERGE
			e.state_timer = phase2 ? 0.35 : 0.5
			e.flash = 0.5
			boss_dust(ec)
			add_shake(5)
		}
	case .BOSS_EMERGE:
		if e.state_timer <= 0 {
			r := rand.float32()
			if dist < 140 {
				e.boss_next = 0 // chop
			} else if r < 0.5 {
				e.boss_next = 1 // dust nova
			} else {
				e.boss_next = 2 // stone-pillar wave
			}
			e.boss_seq = 0
			e.boss_aux = dir
			e.state = .WINDUP
			e.state_timer = e.boss_next == 2 ? 0.9 : 0.55
			e.flash = 0.2
		}
	case .WINDUP:
		e.boss_aux = dir
		if e.state_timer <= 0 {
			e.state = .BOSS_ATTACK
			switch e.boss_next {
			case 0:
				e.state_timer = 0.3
			case 1:
				e.state_timer = 0.9
			case 2:
				e.state_timer = 1.4
			}
		}
	case .BOSS_ATTACK:
		switch e.boss_next {
		case 0: // chop: a short cone of dust plus a bite up close
			if e.boss_seq == 0 {
				boss_fan(ec, dir, 3, 0.22, 330, e.damage, 12)
				if dist < 135 {
					apply_player_damage(e.damage, ec)
				}
				add_shake(6)
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				boss_dustmaw_dive(e, phase2)
			}
		case 1: // head out: dust balls in a full circle
			if e.boss_seq == 0 {
				boss_radial(ec, phase2 ? 14 : 10, 235, e.damage * 0.6, 12, rand.float32() * 6.28)
				add_shake(4)
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				boss_dustmaw_dive(e, phase2)
			}
		case 2: // stone pillars erupt one by one, marching out in a line
			total: i32 = phase2 ? 9 : 6
			step: f32 = 0.12
			elapsed := 1.4 - e.state_timer
			target := i32(elapsed / step)
			line := e.boss_aux
			if raylib.Vector2Length(line) > 0.01 {
				line = raylib.Vector2Normalize(line)
			}
			for e.boss_seq < total && e.boss_seq <= target {
				pa := ec + line * (60 + f32(e.boss_seq) * 92)
				boss_pillar(pa, e.damage * 0.8, raylib.Color{176, 140, 92, 255})
				e.boss_seq += 1
			}
			if e.state_timer <= 0 {
				boss_dustmaw_dive(e, phase2)
			}
		}
	}
}

boss_dustmaw_dive :: proc(e: ^enemy, phase2: bool) {
	e.state = .BOSS_BURROW
	e.boss_hidden = true
	e.boss_timer2 = phase2 ? 0.5 : 0.9
	boss_dust(e.position + e.size * 0.5)
}

// ---------------------------------------------------------------------------
// THE COLOSSUS (RUINS)
// A slow stone titan: telegraphed stomps with shockwave shards, hurled rubble
// that pounds the ground around you, and a lumbering charge that ends in a slam.
// ---------------------------------------------------------------------------
// --- COLOSSUS tuning ---------------------------------------------------------
// A wall of stone that closes distance and hits things: it swings, it slams,
// it lobs boulders, and it charges until the arena stops it. It never fires a
// fan of shards -- every threat it poses is a place on the ground, so the
// telegraph can always draw exactly where you must not be.
//
// Kept as named constants so the telegraph can state the true danger zone and
// an attack can never quietly drift out of sync with what it promises.
COLOSSUS_WINDUP :: 0.9 // matches the telegraph's 0.9s fade, so tells read fully
// Ground slam: a flat ring centred on its own feet.
COLOSSUS_SLAM_RADIUS :: 165
COLOSSUS_SLAM_DMG_MULT :: 1.0
// Heavy swing: a sweeping arc of three impacts in front of it.
COLOSSUS_SWING_REACH :: 92
COLOSSUS_SWING_RADIUS :: 88
COLOSSUS_SWING_ARC :: 0.55 // radians from centre to the outer blow
COLOSSUS_SWING_DMG_MULT :: 0.7
// Boulder throw: a high arc that lands short of the aim point.
COLOSSUS_BOULDER_SIZE :: 44
COLOSSUS_BOULDER_BLAST :: 130
COLOSSUS_BOULDER_SPEED :: 330
COLOSSUS_BOULDER_LIFT :: 190 // extra upward kick, so it arcs rather than skates
COLOSSUS_BOULDER_GRAVITY :: 620
COLOSSUS_BOULDER_LIFE :: 3.0
COLOSSUS_BOULDER_DMG_MULT :: 0.8
COLOSSUS_BOULDER_STEP :: 0.45
COLOSSUS_BOULDER_TIME :: 1.1
// Wall charge: drives in one locked direction until the arena stops it.
COLOSSUS_CHARGE_SPEED :: 560
COLOSSUS_CHARGE_TIME :: 1.5 // hard cap so it can never drive forever
// ...and the rubble burst left where it stops.
COLOSSUS_RUBBLE_RADIUS :: 84
COLOSSUS_RUBBLE_SCATTER :: 70
COLOSSUS_RUBBLE_TELE_RADIUS :: COLOSSUS_RUBBLE_SCATTER + COLOSSUS_RUBBLE_RADIUS
COLOSSUS_RUBBLE_DMG_MULT :: 0.7

// Scatter the rubble burst around `center`. Used by the wall charge, which is
// the only attack that does not warn on the player's own position.
colossus_rubble_burst :: proc(center: raylib.Vector2, damage: f32) {
	boss_blast(center, COLOSSUS_RUBBLE_TELE_RADIUS, damage, raylib.Color{200, 180, 150, 255})
	for _ in 0 ..< 4 {
		ang := rand.float32() * 2 * math.PI
		off := raylib.Vector2 {
			math.cos_f32(ang) * COLOSSUS_RUBBLE_SCATTER * 0.7,
			math.sin_f32(ang) * COLOSSUS_RUBBLE_SCATTER * 0.7,
		}
		boss_blast(center + off, COLOSSUS_RUBBLE_RADIUS, damage, raylib.Color{180, 155, 120, 255})
	}
}

update_boss_colossus :: proc(e: ^enemy, dir: raylib.Vector2, dist: f32, spd: f32, dT: f32) {
	b := ARENA_BOSSES[arena]
	ec := e.position + e.size * 0.5
	phase2 := e.boss_phase >= 2

	// The charge drives itself (see case 3); everything else holds its ground
	// and closes in so the swings can actually reach you.
	if !(e.state == .BOSS_ATTACK && e.boss_next == 3) {
		boss_hold_range(e, dir, dist, spd, b.preferred_range, dT, 0.2)
	}

	e.state_timer -= dT
	#partial switch e.state {
	case .CHASE, .RECOVER:
		if e.state_timer <= 0 {
			r := rand.float32()
			e.boss_seq = 0
			if r < 0.3 {
				e.boss_next = 0 // ground slam
				e.state_timer = COLOSSUS_WINDUP
			} else if r < 0.55 {
				e.boss_next = 1 // heavy swing
				e.state_timer = COLOSSUS_WINDUP
			} else if r < 0.8 {
				e.boss_next = 2 // boulder throw
				e.state_timer = COLOSSUS_WINDUP
			} else {
				e.boss_next = 3 // wall charge
				e.state_timer = COLOSSUS_WINDUP
			}
			e.state = .WINDUP
			e.flash = 0.15
		}
	case .WINDUP:
		// Every attack locks its heading the moment the tell appears, so the
		// drawn danger stays put while the titan wanders off it.
		e.boss_aux = dir
		if e.state_timer <= 0 {
			e.state = .BOSS_ATTACK
			switch e.boss_next {
			case 0:
				e.state_timer = 0.15
			case 1:
				e.state_timer = 0.3
			case 2:
				e.state_timer = COLOSSUS_BOULDER_TIME
			case 3:
				e.state_timer = COLOSSUS_CHARGE_TIME
			}
		}
	case .BOSS_ATTACK:
		switch e.boss_next {
		case 0: // ground slam: one flat ring at its own feet, nothing thrown
			if e.boss_seq == 0 {
				boss_blast(
					ec,
					COLOSSUS_SLAM_RADIUS,
					e.damage * COLOSSUS_SLAM_DMG_MULT,
					raylib.Color{200, 180, 140, 255},
				)
				add_shake(7)
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.5 : 0.85
			}
		case 1: // heavy swing: three blows sweeping the arc in front of it
			if e.boss_seq == 0 {
				// Sweep outward-in so the arm reads as moving through the arc.
				for i in 0 ..< 3 {
					// Swing arc is expressed relative to the locked heading, so
					// rotate `face` rather than aiming in world space.
					ang := -COLOSSUS_SWING_ARC +
						(f32(2 - i) / 2.0) * (2.0 * COLOSSUS_SWING_ARC)
					face := e.boss_aux
					if raylib.Vector2Length(face) < 0.01 {
						face = dir
					}
					world := raylib.Vector2 {
						face.x * math.cos_f32(ang) - face.y * math.sin_f32(ang),
						face.x * math.sin_f32(ang) + face.y * math.cos_f32(ang),
					}
					boss_blast(
						ec + world * COLOSSUS_SWING_REACH,
						COLOSSUS_SWING_RADIUS,
						e.damage * COLOSSUS_SWING_DMG_MULT,
						raylib.Color{215, 195, 160, 255},
					)
				}
				add_shake(6)
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.45 : 0.8
			}
		case 2: // boulder throw: one rock per beat, lobbed on an arc
			total: i32 = phase2 ? 3 : 2
			elapsed := 1.0 - e.state_timer
			target := i32(elapsed / COLOSSUS_BOULDER_STEP)
			for e.boss_seq < total && e.boss_seq <= target {
				// Spread the throw along the locked heading so a dodge has a gap.
				spread := (f32(e.boss_seq) - f32(total - 1) * 0.5) * 0.22
				face := e.boss_aux
				world := raylib.Vector2 {
					face.x * math.cos_f32(spread) - face.y * math.sin_f32(spread),
					face.x * math.sin_f32(spread) + face.y * math.cos_f32(spread),
				}
				colossus_fire_boulder(
					ec,
					ec + world * 520,
					e.damage * COLOSSUS_BOULDER_DMG_MULT,
				)
				e.boss_seq += 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.5 : 0.8
			}
		case 3: // wall charge: drive one locked heading until the arena stops it
			face := e.boss_aux
			if raylib.Vector2Length(face) < 0.01 {
				face = dir
			}
			// Test the step BEFORE committing to it. Moving first would bury the
			// titan up to a frame of travel inside the wall, and then detonate
			// the rubble burst from inside the geometry.
			step := face * COLOSSUS_CHARGE_SPEED * (phase2 ? 1.25 : 1.0) * dT
			next := e.position + step
			next_rect := raylib.Rectangle{next.x, next.y, e.size.x, e.size.y}
			// The arena (walls and cover) is the only thing that stops it.
			if bullet_blocked_by_terrain(next_rect) || e.state_timer <= 0 {
				colossus_rubble_burst(e.position + e.size * 0.5, e.damage * COLOSSUS_RUBBLE_DMG_MULT)
				add_shake(9)
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.6 : 0.9
			} else {
				e.position = next
			}
		}
	}
}

// ---------------------------------------------------------------------------
// FROSTBITE (GLACIER)
// A geisha with two folding fans. She duels in short, deliberate phrases:
// a step, a flick of the wrist, a turn, and only occasionally a dash. Movement
// is part of the choreography rather than the attack -- she glides mostly to
// reposition, and when she does commit to a lunge it ends in a slash. The fans
// themselves are the weapons: they sweep at close range and can be thrown out
// to curve back to her hand.
// ---------------------------------------------------------------------------

FROST_WINDUP :: 0.5 // readable, but quick enough to keep the flow going
// Where her fans actually reach.
FROST_SLASH_RADIUS :: 104 // one sweep of a fan
FROST_SLASH_ARC :: 1.5 // radians the sweep covers
FROST_SLASH_DMG_MULT :: 0.55 // per tick; a flurry is 3 of them
FROST_FLURRY_TICKS :: 3
// Waltz: she spins in place and the fans scythe around her. The anti-cuddle.
FROST_WALTZ_RADIUS :: 122
FROST_WALTZ_TICKS :: 4
FROST_WALTZ_DMG_MULT :: 0.4
FROST_WALTZ_TURN :: 5.2 // radians per second of spin
// Thrown fans: they fly out and curve back, so they can hit on the way in and
// again on the way home. Only two in the air at a time.
FROST_THROW_SPEED :: 520
FROST_THROW_RANGE :: 240
// How far apart the two fans leave her hands. Keep this tight: at range a wide
// split sends both fans sailing past you instead of through you, and then she
// never connects with this move at all.
FROST_THROW_SPREAD :: 0.15
FROST_THROW_DMG_MULT :: 0.6
// Cross step: the one committed lunge. Short, and it always ends in a slash.
FROST_CROSS_SPEED :: 760
FROST_CROSS_TIME :: 0.17
FROST_CROSS_DMG_MULT :: 0.9
// Pivot: no damage at all. She turns and drifts to a new angle. This is the
// move that makes her read as dancing instead of lunging.
FROST_PIVOT_SPEED :: 330
FROST_PIVOT_TIME :: 0.5
// Fan volley: a tight three-flick poke for when you won't let her close.
FROST_VOLLEY_COUNT :: 3
FROST_VOLLEY_SPREAD :: 0.22
FROST_VOLLEY_SPEED :: 400
FROST_VOLLEY_DMG_MULT :: 0.5
// Contact while she's moving is glancing, not lethal.
FROST_CONTACT_MULT :: 0.5
// Distance bands that decide which phrase she opens with.
FROST_CLOSE_RANGE :: 175
FROST_FAR_RANGE :: 330

// Rotate a vector by `ang` radians, counter-clockwise.
rotate_vec2 :: proc(v: raylib.Vector2, ang: f32) -> raylib.Vector2 {
	return raylib.Vector2 {
		v.x * math.cos_f32(ang) - v.y * math.sin_f32(ang),
		v.x * math.sin_f32(ang) + v.y * math.cos_f32(ang),
	}
}

// One sweeping blow along the locked heading: damage anything standing in the
// arc she is pointing at. `spread` widens it beyond a single fan-width.
frostbite_sweep :: proc(e: ^enemy, spread, damage: f32) {
	ec := e.position + e.size * 0.5
	face := e.boss_aux
	if raylib.Vector2Length(face) < 0.01 {
		return
	}
	perp := raylib.Vector2{-face.y, face.x}
	for i in 0 ..< FROST_FLURRY_TICKS {
		t := (f32(i) / f32(FROST_FLURRY_TICKS - 1) - 0.5) * spread
		dir := raylib.Vector2 {
			face.x + perp.x * t,
			face.y + perp.y * t,
		}
		dir = raylib.Vector2Normalize(dir)
		boss_blast(ec + dir * FROST_SLASH_RADIUS * 0.82, FROST_SLASH_RADIUS, damage, raylib.Color{200, 235, 255, 255})
	}
}

// Step along the locked heading for `time` seconds, leaving a silhouette
// behind. Used by the cross step and the pivot, so both read as motion.
frostbite_step :: proc(e: ^enemy, speed, time: f32, dT: f32) {
	e.position += e.boss_aux * speed * dT
	e.position.x = clamp(e.position.x, f32(WALL_THICK), f32(ARENA_W - WALL_THICK) - e.size.x)
	e.position.y = clamp(e.position.y, f32(WALL_THICK), f32(ARENA_H - WALL_THICK) - e.size.y)
	spawn_boss_ghost(e.position, e.size)
	// Brushing her mid-step hurts, but only glancingly.
	if inv_timer > 0 || tutorial_mode {
		return
	}
	rect := raylib.Rectangle{e.position.x, e.position.y, e.size.x, e.size.y}
	if raylib.CheckCollisionRecs(rect, {position.x, position.y, size.x, size.y}) {
		apply_player_damage(e.damage * FROST_CONTACT_MULT, e.position + e.size * 0.5)
		inv_timer = 0.5
		play(sounds.player_hurt)
	}
}

// Throw one fan. It curves back, so it threatens you twice.
frostbite_throw_fan :: proc(from, dir: raylib.Vector2, damage: f32) {
	append(
		&enemy_bullets,
		bullet {
			position = from - {9, 9},
			size = {18, 18},
			velocity = raylib.Vector2Normalize(dir) * FROST_THROW_SPEED,
			damage = damage,
			pierce = 0,
			boomerang = true,
			max_range = FROST_THROW_RANGE,
			effects = {.Freeze},
		},
	)
}

// Opening phrase, chosen by where the player is standing. The cross step is
// deliberately rare: she is a dancer first, so most of her turns are steps and
// wrist flicks rather than lunges.
frostbite_choose :: proc(dist: f32) -> i32 {
	r := rand.float32()
	if dist < FROST_CLOSE_RANGE {
		// In your face: slash, spin, or a rare committed lunge.
		if r < 0.3 {
			return 0 // fan slash
		} else if r < 0.55 {
			return 1 // waltz spin
		} else if r < 0.7 {
			return 4 // pivot and reset
		}
		return 3 // cross step
	} else if dist < FROST_FAR_RANGE {
		// Mid: throw a fan, sidestep, or flick a volley.
		if r < 0.3 {
			return 2 // fan throw
		} else if r < 0.55 {
			return 4 // pivot
		} else if r < 0.8 {
			return 5 // volley
		}
		return 3 // cross step
	}
	// Far: don't chase. Poke and turn away.
	if r < 0.45 {
		return 2 // fan throw
	} else if r < 0.8 {
		return 5 // volley
	}
	return 4 // pivot
}

update_boss_frostbite :: proc(e: ^enemy, dir: raylib.Vector2, dist: f32, spd: f32, dT: f32) {
	b := ARENA_BOSSES[arena]
	ec := e.position + e.size * 0.5
	pc := position + size * 0.5
	phase2 := e.boss_phase >= 2

	// She holds her distance only while she isn't mid-phrase.
	phrasing := e.state == .BOSS_ATTACK
	if !phrasing {
		boss_hold_range(e, dir, dist, spd, b.preferred_range, dT, 0.85)
	}

	e.state_timer -= dT
	#partial switch e.state {
	case .CHASE, .RECOVER:
		if e.state_timer <= 0 {
			e.boss_seq = 0
			// The pivot reads this to decide when to bend its arc.
			e.boss_timer2 = 0
			e.boss_next = frostbite_choose(dist)
			e.state_timer = FROST_WINDUP
			e.state = .WINDUP
			e.flash = 0.15
		}
	case .WINDUP:
		// Every phrase locks its heading the instant the tell appears, so the
		// drawn shape stays put while she drifts off it.
		e.boss_aux = dir
		if e.state_timer <= 0 {
			e.state = .BOSS_ATTACK
			switch e.boss_next {
			case 0:
				e.state_timer = 0.26 // the flurry
			case 1:
				e.state_timer = 0.7 // the spin
			case 2:
				e.state_timer = 0.35
			case 3:
				e.state_timer = FROST_CROSS_TIME + 0.2 // lunge, then the slash
			case 4:
				e.state_timer = FROST_PIVOT_TIME
			case 5:
				e.state_timer = 0.22
			}
		}
	case .BOSS_ATTACK:
		// Spin angle is shared by the waltz and the fan art, so keep it live.
		if e.boss_next == 1 {
			e.boss_spin += FROST_WALTZ_TURN * dT
		}
		switch e.boss_next {
		case 0: // fan slash: a flurry of sweeps, alternating shoulders
			if e.state_timer <= 0.16 && e.boss_seq < FROST_FLURRY_TICKS {
				side: f32 = 1.0
				if e.boss_seq % 2 == 1 {
					side = -1.0
				}
				frostbite_sweep(e, side * FROST_SLASH_ARC, e.damage * FROST_SLASH_DMG_MULT)
				e.boss_seq += 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.22 : 0.4
			}
		case 1: // waltz: she turns on the spot and the fans scythe around her
			tick := 0.6 / f32(FROST_WALTZ_TICKS)
			if tick > 0 && e.boss_seq < FROST_WALTZ_TICKS &&
			   (0.7 - e.state_timer) >= f32(e.boss_seq) * tick {
				boss_blast(
					ec,
					FROST_WALTZ_RADIUS,
					e.damage * FROST_WALTZ_DMG_MULT,
					raylib.Color{190, 230, 255, 255},
				)
				e.boss_seq += 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.22 : 0.4
			}
		case 2: // fan throw: both fans leave her hands and curve back
			if e.boss_seq == 0 {
				perp := raylib.Vector2{-e.boss_aux.y, e.boss_aux.x}
				frostbite_throw_fan(
					ec,
					raylib.Vector2Normalize(e.boss_aux + perp * FROST_THROW_SPREAD),
					e.damage * FROST_THROW_DMG_MULT,
				)
				frostbite_throw_fan(
					ec,
					raylib.Vector2Normalize(e.boss_aux - perp * FROST_THROW_SPREAD),
					e.damage * FROST_THROW_DMG_MULT,
				)
				e.muzzle = ENEMY_MUZZLE_FLASH_TIME
				e.muzzle_dir = e.boss_aux
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.25 : 0.45
			}
		case 3: // cross step: one short lunge that ends in a slash
			if e.state_timer > 0.2 {
				frostbite_step(e, FROST_CROSS_SPEED, FROST_CROSS_TIME, dT)
			} else if e.boss_seq == 0 {
				// The landing is the hit.
				frostbite_sweep(e, FROST_SLASH_ARC * 1.3, e.damage * FROST_CROSS_DMG_MULT)
				add_shake(5)
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.28 : 0.5
			}
		case 4: // pivot: no damage. She turns away and re-sets her angle.
			if e.boss_timer2 <= 0 {
				// Curve the step so it arcs around you instead of into you.
				e.boss_aux = rotate_vec2(e.boss_aux, 1.15)
				e.boss_timer2 = 0.16
			}
			e.boss_timer2 -= dT
			frostbite_step(e, FROST_PIVOT_SPEED, FROST_PIVOT_TIME, dT)
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.25 : 0.45
			}
		case 5: // fan volley: a tight three-flick, nothing more
			if e.boss_seq == 0 {
				boss_fan(
					ec,
					pc - ec,
					FROST_VOLLEY_COUNT,
					FROST_VOLLEY_SPREAD,
					FROST_VOLLEY_SPEED,
					e.damage * FROST_VOLLEY_DMG_MULT,
					8,
					{.Freeze},
				)
				e.muzzle = ENEMY_MUZZLE_FLASH_TIME
				e.muzzle_dir = e.boss_aux
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.25 : 0.45
			}
		}
	}
}

// ---------------------------------------------------------------------------
// MECHANIKTRON (FOUNDRY)
// An impervious war machine. It lobs exploding rockets and crashes both fists
// down on locked ground, and it keeps its armoured back turned so the weakpoint
// is never in reach. Only breaking the crystals it seeds around the arena stuns
// it -- and each full clear leaves it stunned longer than the last.
// ---------------------------------------------------------------------------
update_boss_mechaniktron :: proc(e: ^enemy, dir: raylib.Vector2, dist: f32, spd: f32, dT: f32) {
	b := ARENA_BOSSES[arena]
	ec := e.position + e.size * 0.5
	pc := position + size * 0.5

	// Exposed window: the machine locks up and its back weakpoint goes live. If
	// the window closes without a kill, it reseeds its crystals for another try.
	if e.boss_stun > 0 {
		e.boss_stun -= dT
		e.flash = max(e.flash, 0.04)
		if e.boss_stun <= 0 {
			e.boss_stun = 0
			mech_spawn_crystals()
			e.state = .RECOVER
			e.state_timer = 0.8
		}
		return
	}

	// Every crystal in the set downed exposes the weakpoint (longer each round).
	if len(crystals) == 0 {
		e.boss_clears += 1
		e.boss_stun = MECH_STUN_BASE + MECH_STUN_STEP * f32(e.boss_clears - 1)
		e.boss_aux = dir // freeze the facing; the weakpoint sits dead opposite
		e.state = .RECOVER
		e.state_timer = e.boss_stun
		e.flash = 0.5
		show_banner(cstring("WEAKPOINT EXPOSED"), raylib.Color{150, 220, 255, 255}, 1.6)
		play(sounds.shatter, 0.8)
		return
	}

	boss_hold_range(e, dir, dist, spd, b.preferred_range, dT, 0.5)
	e.state_timer -= dT
	#partial switch e.state {
	case .CHASE, .RECOVER:
		if e.state_timer <= 0 {
			e.boss_seq = 0
			if rand.float32() < 0.55 {
				e.boss_next = 0 // rocket salvo
			} else {
				e.boss_next = 1 // hand slam
				e.boss_aux = pc // lock the landing spot so it can be dodged
			}
			e.state = .WINDUP
			e.state_timer = 0.5
			e.flash = 0.15
		}
	case .WINDUP:
		if e.state_timer <= 0 {
			e.state = .BOSS_ATTACK
			e.state_timer = e.boss_next == 0 ? 1.1 : 0.7
		}
	case .BOSS_ATTACK:
		switch e.boss_next {
		case 0: // three rockets, lobbed on a cadence
			elapsed := 1.1 - e.state_timer
			want := int(elapsed / 0.3) + 1
			for e.boss_seq < i32(want) && e.boss_seq < 3 {
				mech_fire_rocket(ec, pc, e.damage)
				e.boss_seq += 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = 0.55
			}
		case 1: // both fists crash down on the locked spot
			if e.boss_seq == 0 {
				e.boss_seq = 1
				boss_blast(e.boss_aux, MECH_SLAM_RADIUS, e.damage, raylib.Color{190, 205, 220, 255})
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = 0.65
			}
		}
	}
}

// ---------------------------------------------------------------------------
// THORNWALD (FOREST)
// A tree horror: thorns spiral outward in rotating arms, a line of roots rips
// toward you, and it seeds the fight with splitters and orbiters.
// ---------------------------------------------------------------------------
update_boss_thornwald :: proc(e: ^enemy, dir: raylib.Vector2, dist: f32, spd: f32, dT: f32) {
	b := ARENA_BOSSES[arena]
	ec := e.position + e.size * 0.5
	phase2 := e.boss_phase >= 2

	boss_hold_range(e, dir, dist, spd, b.preferred_range, dT, 0.35)
	e.state_timer -= dT
	#partial switch e.state {
	case .CHASE, .RECOVER:
		if e.state_timer <= 0 {
			r := rand.float32()
			e.boss_seq = 0
			if r < 0.5 {
				e.boss_next = 0 // thorn spiral
				e.state_timer = 0.5
			} else if r < 0.8 {
				e.boss_next = 1 // root lash
				e.state_timer = 0.55
			} else {
				e.boss_next = 2 // saplings
				e.state_timer = 0.45
			}
			e.state = .WINDUP
			e.flash = 0.15
		}
	case .WINDUP:
		e.boss_aux = dir
		if e.state_timer <= 0 {
			e.state = .BOSS_ATTACK
			switch e.boss_next {
			case 0:
				e.state_timer = 1.2
			case 1:
				e.state_timer = 1.3
			case 2:
				e.state_timer = 0.5
			}
		}
	case .BOSS_ATTACK:
		switch e.boss_next {
		case 0: // rotating arms of thorns, a ring every 0.2s
			e.boss_spin += dT * (phase2 ? 2.2 : 1.5)
			elapsed := 1.2 - e.state_timer
			if e.boss_seq < 6 && elapsed >= f32(e.boss_seq) * 0.2 {
				boss_radial(
					ec,
					phase2 ? 10 : 8,
					235,
					e.damage * 0.5,
					11,
					e.boss_spin + f32(e.boss_seq) * 0.3,
				)
				e.boss_seq += 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.35 : 0.6
			}
		case 1: // root lash: roots rip out toward the player in a line
			total: i32 = phase2 ? 8 : 6
			step: f32 = 0.13
			elapsed := 1.3 - e.state_timer
			target := i32(elapsed / step)
			line := e.boss_aux
			if raylib.Vector2Length(line) > 0.01 {
				line = raylib.Vector2Normalize(line)
			}
			for e.boss_seq < total && e.boss_seq <= target {
				pa := ec + line * (60 + f32(e.boss_seq) * 88)
				boss_pillar(pa, e.damage * 0.7, raylib.Color{70, 120, 60, 255})
				e.boss_seq += 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.35 : 0.6
			}
		case 2:
			if e.boss_seq == 0 {
				boss_summon(.SPLITTER, phase2 ? 3 : 2)
				boss_summon(.ORBITER, 1)
				e.flash = 0.3
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = 0.6
			}
		}
	}
}

// ---------------------------------------------------------------------------
// BOGWRAITH (SWAMP)
// A bog spirit: rings of poison orbs, a phase step through you that leaves a
// poison pool behind, and summons of orbiting wisps.
// ---------------------------------------------------------------------------
update_boss_bogwraith :: proc(e: ^enemy, dir: raylib.Vector2, dist: f32, spd: f32, dT: f32) {
	b := ARENA_BOSSES[arena]
	ec := e.position + e.size * 0.5
	pc := position + size * 0.5
	phase2 := e.boss_phase >= 2

	boss_hold_range(e, dir, dist, spd, b.preferred_range, dT, 0.6)
	e.state_timer -= dT
	#partial switch e.state {
	case .CHASE, .RECOVER:
		if e.state_timer <= 0 {
			r := rand.float32()
			e.boss_seq = 0
			if r < 0.5 {
				e.boss_next = 0 // poison nova
				e.state_timer = 0.45
			} else if r < 0.8 {
				e.boss_next = 1 // phase through
				e.state_timer = 0.4
			} else {
				e.boss_next = 2 // wisps
				e.state_timer = 0.45
			}
			e.state = .WINDUP
			e.flash = 0.15
		}
	case .WINDUP:
		e.boss_aux = dir
		if e.state_timer <= 0 {
			e.state = .BOSS_ATTACK
			switch e.boss_next {
			case 0:
				e.state_timer = 0.45
			case 1:
				e.state_timer = 0.4
			case 2:
				e.state_timer = 0.5
			}
		}
	case .BOSS_ATTACK:
		switch e.boss_next {
		case 0:
			if e.boss_seq == 0 {
				boss_radial(
					ec,
					phase2 ? 18 : 12,
					240,
					e.damage * 0.5,
					12,
					rand.float32() * 6.28,
					{.Poison},
				)
				add_shake(4)
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.25 : 0.5
			}
		case 1: // phase across the player, leaving a poison pool where it stood
			if e.boss_seq == 0 {
				boss_blast(ec, 90, e.damage * 0.5, raylib.Color{150, 90, 200, 255})
				ang: f32 = 0
				to := pc - ec
				if raylib.Vector2Length(to) > 0.01 {
					ang = math.atan2_f32(to.y, to.x)
				}
				target := pc + raylib.Vector2{math.cos_f32(ang), math.sin_f32(ang)} * 150
				target.x = clamp(target.x, f32(WALL_THICK), f32(ARENA_W - WALL_THICK))
				target.y = clamp(target.y, f32(WALL_THICK), f32(ARENA_H - WALL_THICK))
				e.position = target - e.size * 0.5
				e.flash = 0.4
				add_shake(4)
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.3 : 0.55
			}
		case 2:
			if e.boss_seq == 0 {
				boss_summon(.ORBITER, phase2 ? 4 : 2)
				e.flash = 0.3
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = 0.6
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Telegraphs (drawn on the ground under the boss during its wind-up)
// ---------------------------------------------------------------------------

boss_tele_circle :: proc(pos: raylib.Vector2, r, k: f32, col: raylib.Color) {
	raylib.DrawCircleV(pos, r, raylib.Color{col.r, col.g, col.b, u8(28 + 46 * k)})
	raylib.DrawCircleLines(i32(pos.x), i32(pos.y), r, raylib.Color{col.r, col.g, col.b, u8(120 + 120 * k)})
}

boss_tele_line :: proc(from, to: raylib.Vector2, width, k: f32, col: raylib.Color) {
	raylib.DrawLineEx(from, to, width, raylib.Color{col.r, col.g, col.b, u8(80 + 140 * k)})
}

// A wedge of floor from `start` to `end` radians: how a fan sweep reads on the
// ground, rather than the straight lane a thrown shot would use.
boss_tele_arc :: proc(center: raylib.Vector2, r, start, end, k: f32, col: raylib.Color) {
	raylib.DrawCircleSector(
		center,
		r,
		start * 180 / math.PI,
		end * 180 / math.PI,
		24,
		raylib.Color{col.r, col.g, col.b, u8(28 + 46 * k)},
	)
	raylib.DrawCircleSectorLines(
		center,
		r,
		start * 180 / math.PI,
		end * 180 / math.PI,
		24,
		raylib.Color{col.r, col.g, col.b, u8(120 + 120 * k)},
	)
}

// The tell each boss paints while it winds up its chosen attack.
draw_boss_telegraph :: proc(e: enemy) {
	ec := e.position + e.size * 0.5
	pc := position + size * 0.5
	to := pc - ec
	k: f32 = 1 - clamp(e.state_timer / 0.9, 0, 1)
	if e.state == .WINDUP {
		switch e.boss_kind {
		case .PACKLEADER:
			if e.boss_next == 0 {
				boss_tele_line(ec, ec + raylib.Vector2Normalize(to) * 420, 3, k, raylib.Color{140, 240, 120, 255})
				boss_tele_circle(pc, 26, k, raylib.Color{190, 120, 220, 255})
			} else if e.boss_next == 2 {
				boss_tele_line(ec, ec + e.boss_aux * 260, 10, k, raylib.Color{255, 220, 120, 255})
			} else {
				boss_tele_circle(ec, 90 + 90 * (1 - k), k, raylib.Color{140, 220, 120, 255})
			}
		case .DUSTMAW:
			if e.boss_next == 2 {
				line := raylib.Vector2Normalize(to)
				boss_tele_line(ec, ec + line * 720, 12, k, raylib.Color{210, 170, 100, 255})
			} else if e.boss_next == 1 {
				boss_tele_circle(ec, 150, k, raylib.Color{200, 160, 90, 255})
			} else {
				boss_tele_circle(ec + raylib.Vector2Normalize(to) * 70, 60, k, raylib.Color{200, 160, 90, 255})
			}
		case .COLOSSUS:
			if e.boss_next == 0 {
				// Ground slam: the flat ring it is about to crack open.
				boss_tele_circle(ec, COLOSSUS_SLAM_RADIUS, k, raylib.Color{230, 200, 150, 255})
			} else if e.boss_next == 1 {
				// Heavy swing: the three blows, drawn where they will land.
				for i in 0 ..< 3 {
					ang := -COLOSSUS_SWING_ARC +
					(f32(2 - i) / 2.0) * (2.0 * COLOSSUS_SWING_ARC)
					face := e.boss_aux
					world := raylib.Vector2 {
						face.x * math.cos_f32(ang) - face.y * math.sin_f32(ang),
						face.x * math.sin_f32(ang) + face.y * math.cos_f32(ang),
					}
					boss_tele_circle(
						ec + world * COLOSSUS_SWING_REACH,
						COLOSSUS_SWING_RADIUS,
						k,
						raylib.Color{215, 195, 160, 255},
					)
				}
			} else if e.boss_next == 2 {
				// Boulder throw: the lane the rocks will come down in.
				face := e.boss_aux
				if raylib.Vector2Length(face) > 0.01 {
					boss_tele_line(
						ec,
						ec + face * 560,
						COLOSSUS_BOULDER_BLAST * 2,
						k,
						raylib.Color{200, 180, 145, 255},
					)
				}
			} else {
				// Wall charge: the whole lane it can drive down.
				face := e.boss_aux
				if raylib.Vector2Length(face) > 0.01 {
					boss_tele_line(
						ec,
						ec + face * 1200,
						e.size.x + 10,
						k,
						raylib.Color{220, 200, 160, 255},
					)
				}
			}
		case .FROSTBITE:
			// Each phrase draws the shape it will actually make. The pivot draws
			// nothing -- there is nothing to dodge, and she telegraphs it by
			// simply not committing.
			switch e.boss_next {
			case 0: // fan slash: the arc she is about to sweep
				if raylib.Vector2Length(e.boss_aux) > 0.01 {
					facing := math.atan2_f32(e.boss_aux.y, e.boss_aux.x)
					boss_tele_arc(ec, FROST_SLASH_RADIUS * 0.82, facing - FROST_SLASH_ARC * 0.5, facing + FROST_SLASH_ARC * 0.5, k, raylib.Color{190, 235, 255, 255})
				}
			case 1: // waltz: a ring, because the spin hits every side
				boss_tele_circle(ec, FROST_WALTZ_RADIUS, k, raylib.Color{190, 235, 255, 255})
			case 2: // fan throw: two lanes, angled apart, that come back
				if raylib.Vector2Length(e.boss_aux) > 0.01 {
					perp := raylib.Vector2{-e.boss_aux.y, e.boss_aux.x}
					sides := [2]f32{-1.0, 1.0}
					for s in sides {
						d := raylib.Vector2Normalize(e.boss_aux + perp * (FROST_THROW_SPREAD * s))
						boss_tele_line(ec, ec + d * FROST_THROW_RANGE * 1.6, 16, k, raylib.Color{150, 220, 255, 255})
					}
				}
			case 3: // cross step: the lunge lane, then the slash at the end
				if raylib.Vector2Length(e.boss_aux) > 0.01 {
					boss_tele_line(ec, ec + e.boss_aux * 300, 40, k, raylib.Color{190, 235, 255, 255})
				}
			case 5: // volley: a tight cone
				boss_tele_line(ec, ec + raylib.Vector2Normalize(to) * 420, 22, k, raylib.Color{150, 220, 255, 255})
			case 4:
				// pivot: no danger, no tell
			}
		case .MECHANIKTRON:
			if e.boss_next == 0 {
				// Rocket lock: a lane down the machine's aim.
				boss_tele_line(
					ec,
					ec + raylib.Vector2Normalize(to) * 460,
					10,
					k,
					raylib.Color{150, 220, 255, 255},
				)
			} else {
				// Hand slam: a ring on the locked landing spot.
				boss_tele_circle(e.boss_aux, MECH_SLAM_RADIUS, k, raylib.Color{190, 205, 220, 255})
			}
		case .THORNWALD:
			if e.boss_next == 0 {
				boss_tele_circle(ec, 70 + 140 * (1 - k), k, raylib.Color{110, 210, 90, 255})
			} else if e.boss_next == 1 {
				boss_tele_line(ec, ec + raylib.Vector2Normalize(to) * 420, 22, k, raylib.Color{90, 170, 70, 255})
			}
		case .BOGWRAITH:
			if e.boss_next == 0 {
				boss_tele_circle(ec, 70 + 130 * (1 - k), k, raylib.Color{180, 110, 230, 255})
			} else if e.boss_next == 1 {
				boss_tele_line(ec, ec + raylib.Vector2Normalize(to) * 340, 18, k, raylib.Color{180, 110, 230, 255})
			}
		}
	}
}

// ---------------------------------------------------------------------------
// Silhouettes
// ---------------------------------------------------------------------------

// Distinct body art per boss, drawn over (or instead of) its base rectangle.
draw_boss_body :: proc(e: enemy) {
	ec := e.position + e.size * 0.5
	er := max(e.size.x, e.size.y) * 0.5
	pc := position + size * 0.5
	facing := raylib.Vector2{1, 0}
	if raylib.Vector2Length(pc - ec) > 0.01 {
		facing = raylib.Vector2Normalize(pc - ec)
	}
	// Boss visuals are data-driven: ARENA_BOSSES[e.boss_kind].visuals.shapes
	// lists the shapes that make up the boss. Each shape's offset is relative
	// to the boss center and is rotated by `facing` so the boss always faces
	// the player.
	v := ARENA_BOSSES[boss_kind_to_arena_kind(e.boss_kind)].visuals
	for s in v.shapes {
		// Rotate the shape's offset by the boss's facing direction so it
		// stays anchored to the body as the boss turns.
		off := raylib.Vector2Rotate(s.offset, math.atan2_f32(facing.y, facing.x) + s.rotation)
		draw_boss_shape(ec, er, s, off)
	}
	// Dynamic per-boss decoration that can't be expressed in static shapes:
	// windup tells, state-specific changes, weakpoint pulses, etc.
	draw_boss_body_dynamic(e, ec, er, facing)
}

// Draw a single boss shape at `center + offset`.
draw_boss_shape :: proc(center, er: raylib.Vector2, s: Boss_Shape, off: raylib.Vector2) {
	p := center + off
	switch s.kind {
	case .CIRCLE:
		raylib.DrawCircleV(p, s.size.x, s.color)
	case .RECTANGLE:
		raylib.DrawRectangleRec(
			raylib.Rectangle{p.x - s.size.x, p.y - s.size.y, s.size.x * 2, s.size.y * 2},
			s.color,
		)
	case .TRIANGLE:
		// Triangle points along the rotated offset direction.
		dir := raylib.Vector2Normalize(off)
		if raylib.Vector2Length(dir) < 0.01 {
			dir = raylib.Vector2{1, 0}
		}
		perp := raylib.Vector2{-dir.y, dir.x}
		raylib.DrawTriangle(
			p + dir * s.size.x,
			p - dir * s.size.x * 0.5 + perp * s.size.y,
			p - dir * s.size.x * 0.5 - perp * s.size.y,
			s.color,
		)
	case .LINE:
		dir := raylib.Vector2Normalize(off)
		if raylib.Vector2Length(dir) < 0.01 {
			dir = raylib.Vector2{1, 0}
		}
		raylib.DrawLineEx(p, p + dir * s.size.x, s.size.y, s.color)
	case .SECTOR:
		dir := raylib.Vector2Normalize(off)
		if raylib.Vector2Length(dir) < 0.01 {
			dir = raylib.Vector2{1, 0}
		}
		base := math.atan2_f32(dir.y, dir.x)
		raylib.DrawCircleSector(p, s.size.x, base - s.size.y * 0.5, base + s.size.y * 0.5, 16, s.color)
	case .POLY:
		raylib.DrawPoly(p, i32(s.size.y), s.size.x, s.rotation, s.color)
	}
}

// Dynamic per-boss decoration that can't be expressed in static shapes:
// windup tells, state-specific changes, weakpoint pulses, etc.
draw_boss_body_dynamic :: proc(e: enemy, ec: raylib.Vector2, er: f32, facing: raylib.Vector2) {
	switch e.boss_kind {
	case .PACKLEADER:
		draw_boss_body_packleader(e, ec, er, facing)
	case .DUSTMAW:
		draw_boss_body_dustmaw(e, ec, er, facing)
	case .COLOSSUS:
		draw_boss_body_colossus(e, ec, er)
	case .FROSTBITE:
		draw_boss_body_frostbite(e, ec, er, facing)
	case .MECHANIKTRON:
		draw_boss_body_mechaniktron(e, ec, er, facing)
	case .THORNWALD:
		draw_boss_body_thornwald(e, ec, er)
	case .BOGWRAITH:
		draw_boss_body_bogwraith(e, ec, er, facing)
	}
}

draw_boss_body_packleader :: proc(e: enemy, ec: raylib.Vector2, er: f32, facing: raylib.Vector2) {
	// Eyes follow the player.
	eye := ec + facing * er * 0.35
	perp := raylib.Vector2{-facing.y, facing.x}
	raylib.DrawCircleV(eye + perp * er * 0.3, 3.5, raylib.YELLOW)
	raylib.DrawCircleV(eye - perp * er * 0.3, 3.5, raylib.YELLOW)
	// Snout.
	snout := ec + facing * er * 0.9
	raylib.DrawCircleV(snout, 4, raylib.Color{30, 50, 30, 255})
	if e.state == .WINDUP {
		raylib.DrawCircleLines(i32(ec.x), i32(ec.y), er * (0.9 + 0.25), raylib.YELLOW)
	}
}

draw_boss_body_dustmaw :: proc(e: enemy, ec: raylib.Vector2, er: f32, facing: raylib.Vector2) {
	if e.boss_hidden {
		// Just a disturbed mound of dirt with ripples, sliding over the ground.
		raylib.DrawCircleV(ec, er * 1.05, raylib.Color{96, 74, 46, 255})
		raylib.DrawCircleV(ec + {0, -er * 0.28}, er * 0.62, raylib.Color{132, 104, 66, 255})
		raylib.DrawCircleLines(i32(ec.x), i32(ec.y), er * 0.8, raylib.Color{80, 60, 38, 255})
		raylib.DrawCircleLines(i32(ec.x), i32(ec.y), er * 1.15, raylib.Color{70, 54, 34, 200})
		return
	}
	// Surfaced: segmented body with a maw facing the player.
	maw := ec + facing * er * 0.55
	raylib.DrawCircleV(maw, er * 0.5, raylib.Color{40, 24, 16, 255})
	perp := raylib.Vector2{-facing.y, facing.x}
	raylib.DrawTriangle(maw + perp * 6, maw + facing * 6, maw + perp * 4 - facing * 8, raylib.RAYWHITE)
	raylib.DrawTriangle(maw - perp * 6, maw + facing * 6, maw - perp * 4 - facing * 8, raylib.RAYWHITE)
}

draw_boss_body_colossus :: proc(e: enemy, ec: raylib.Vector2, er: f32) {
	// Cracks of glowing light.
	core := raylib.Color{255, 170, 70, 255}
	raylib.DrawLineEx(ec + {-er * 0.6, -er * 0.3}, ec + {er * 0.1, er * 0.5}, 2, core)
	raylib.DrawLineEx(ec + {er * 0.1, er * 0.5}, ec + {er * 0.6, -er * 0.1}, 2, core)
	raylib.DrawCircleV(ec, er * 0.22 + (e.state == .WINDUP ? 3 : 0), raylib.Color{255, 200, 110, 255})
}

draw_boss_body_frostbite :: proc(e: enemy, ec: raylib.Vector2, er: f32, facing: raylib.Vector2) {
	base := math.atan2_f32(facing.y, facing.x)

	// Two fans. They open wider while she's swinging or spinning.
	open: f32 = 0.9
	if e.state == .BOSS_ATTACK &&
	   (e.boss_next == 0 || e.boss_next == 1 || e.boss_next == 3) {
		open = 1.7
	}
	if e.boss_next == 1 {
		// Waltz: both fans ride the spin.
		open = 1.4
	}
	for i in 0 ..< 2 {
		side: f32 = 0.55
		if i == 1 {
			side = -0.55
		}
		spin := f32(0)
		if e.state == .BOSS_ATTACK && e.boss_next == 1 {
			spin = f32(e.boss_spin)
		}
		ang := base + side + spin
		dir := raylib.Vector2{math.cos_f32(ang), math.sin_f32(ang)}
		pivot := ec + dir * er * 0.85
		raylib.DrawCircleSector(
			pivot,
			er * 0.95,
			ang - open * 0.5,
			ang + open * 0.5,
			16,
			raylib.Color{235, 250, 255, 210},
		)
		raylib.DrawCircleSectorLines(
			pivot,
			er * 0.95,
			ang - open * 0.5,
			ang + open * 0.5,
			16,
			raylib.Color{120, 200, 240, 255},
		)
		// Ribs so a fan reads as a fan and not a blob.
		for k in -1 ..= 1 {
			ra := ang + f32(k) * open * 0.33
			raylib.DrawLineEx(
				pivot,
				pivot + raylib.Vector2{math.cos_f32(ra), math.sin_f32(ra)} * er * 0.9,
				2,
				raylib.Color{150, 215, 245, 190},
			)
		}
	}
}

draw_boss_body_mechaniktron :: proc(e: enemy, ec: raylib.Vector2, er: f32, facing_in: raylib.Vector2) {
	// While exposed the machine can't turn, so draw its frozen facing and let the
	// weakpoint stay where the stun left it.
	facing := facing_in
	if e.boss_stun > 0 && raylib.Vector2Length(e.boss_aux) > 0.01 {
		facing = raylib.Vector2Normalize(e.boss_aux)
	}
	perp := raylib.Vector2{-facing.y, facing.x}
	steel := raylib.Color{104, 118, 134, 255}
	dark := raylib.Color{52, 60, 70, 255}
	// Arms reaching at the player, ending in fists.
	for s in ([2]f32{-1, 1}) {
		shoulder := ec + facing * er * 0.1 + perp * (er * 0.66 * s)
		fist := ec + facing * er * 0.82 + perp * (er * 0.58 * s)
		raylib.DrawLineEx(shoulder, fist, er * 0.26, steel)
		if e.state == .WINDUP && e.boss_next == 1 {
			raylib.DrawCircleV(fist, er * 0.44, raylib.Color{200, 215, 230, 110})
		}
		raylib.DrawCircleV(fist, er * 0.28, dark)
	}
	// Head with a red optic toward the player.
	head := ec + facing * er * 0.42
	raylib.DrawCircleV(head, er * 0.4, dark)
	raylib.DrawCircleV(head + facing * er * 0.16, er * 0.13, raylib.Color{255, 90, 70, 255})
	// Weakpoint core on the back: dull while armoured, blazing while exposed.
	wp := ec - facing * er * 0.98
	if e.boss_stun > 0 {
		pulse := 0.5 + 0.5 * f32(math.sin(raylib.GetTime() * 12.0))
		raylib.DrawCircleV(wp, er * 0.52 * (1 + 0.15 * pulse), raylib.Color{150, 220, 255, 90})
		raylib.DrawCircleV(wp, er * 0.3, raylib.Color{190, 240, 255, 255})
	} else {
		raylib.DrawCircleV(wp, er * 0.28, raylib.Color{90, 110, 130, 255})
	}
	raylib.DrawCircleLines(i32(wp.x), i32(wp.y), er * 0.36, raylib.Color{150, 220, 255, 255})
}

draw_boss_body_thornwald :: proc(e: enemy, ec: raylib.Vector2, er: f32) {
	// Eyes in the trunk.
	raylib.DrawCircleV(ec + {-er * 0.14, er * 0.05}, 3, raylib.Color{200, 240, 120, 255})
	raylib.DrawCircleV(ec + {er * 0.14, er * 0.05}, 3, raylib.Color{200, 240, 120, 255})
}

draw_boss_body_bogwraith :: proc(e: enemy, ec: raylib.Vector2, er: f32, facing: raylib.Vector2) {
	// Hood shadow + glowing eyes.
	perp := raylib.Vector2{-facing.y, facing.x}
	eye := ec + facing * er * 0.2
	raylib.DrawCircleV(eye + perp * er * 0.22, 3, raylib.Color{210, 150, 255, 255})
	raylib.DrawCircleV(eye - perp * er * 0.22, 3, raylib.Color{210, 150, 255, 255})
	if e.state == .WINDUP {
		raylib.DrawCircleLines(i32(ec.x), i32(ec.y), er * 1.2, raylib.Color{200, 140, 255, 200})
	}
}

