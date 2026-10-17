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
boss_summon :: proc(kind: Enemy_Kind, count: i32) {
	for _ in 0 ..< count {
		spawn_enemy_at(kind, false, ARENAS[arena].waves, random_spawn_pos(ENEMIES[kind].size))
	}
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
update_boss_colossus :: proc(e: ^enemy, dir: raylib.Vector2, dist: f32, spd: f32, dT: f32) {
	b := ARENA_BOSSES[arena]
	ec := e.position + e.size * 0.5
	phase2 := e.boss_phase >= 2

	if e.state == .BOSS_ATTACK && e.boss_next == 2 && raylib.Vector2Length(e.boss_aux) > 0.01 {
		e.position += e.boss_aux * spd * (phase2 ? 2.6 : 1.9) * dT
	} else {
		boss_hold_range(e, dir, dist, spd, b.preferred_range, dT, 0.2)
	}

	e.state_timer -= dT
	#partial switch e.state {
	case .CHASE, .RECOVER:
		if e.state_timer <= 0 {
			r := rand.float32()
			e.boss_seq = 0
			if r < 0.45 {
				e.boss_next = 0 // stomp
				e.state_timer = 0.6
			} else if r < 0.78 {
				e.boss_next = 1 // rubble
				e.state_timer = 0.6
			} else {
				e.boss_next = 2 // charge
				e.state_timer = 0.6
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
				e.state_timer = 0.12
			case 1:
				e.state_timer = 1.0
			case 2:
				e.state_timer = 0.7
			}
		}
	case .BOSS_ATTACK:
		switch e.boss_next {
		case 0: // stomp: point-blank blast plus a ring of shockwave shards
			if e.boss_seq == 0 {
				boss_blast(ec, 150, e.damage, raylib.Color{200, 180, 140, 255})
				boss_radial(ec, phase2 ? 16 : 12, 190, e.damage * 0.5, 14)
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.5 : 0.85
			}
		case 1: // rubble: rocks pound the ground around the player, one by one
			total: i32 = phase2 ? 4 : 3
			step: f32 = 0.25
			elapsed := 1.0 - e.state_timer
			target := i32(elapsed / step)
			pc := position + size * 0.5
			for e.boss_seq < total && e.boss_seq <= target {
				off := raylib.Vector2{rand.float32_range(-60, 60), rand.float32_range(-60, 60)}
				boss_blast(pc + off, 78, e.damage * 0.7, raylib.Color{180, 150, 110, 255})
				e.boss_seq += 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.5 : 0.8
			}
		case 2: // charge ends in a heavy slam
			if e.state_timer <= 0 {
				boss_blast(ec, 160, e.damage, raylib.Color{200, 180, 140, 255})
				boss_radial(ec, phase2 ? 16 : 12, 190, e.damage * 0.5, 14)
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.6 : 0.9
			}
		}
	}
}

// ---------------------------------------------------------------------------
// FROSTBITE (GLACIER)
// A fast ice wraith that keeps its distance: wide freezing icicle fans, frost
// novas that ring it, and short blinks that reposition it with a frost burst.
// ---------------------------------------------------------------------------
update_boss_frostbite :: proc(e: ^enemy, dir: raylib.Vector2, dist: f32, spd: f32, dT: f32) {
	b := ARENA_BOSSES[arena]
	ec := e.position + e.size * 0.5
	pc := position + size * 0.5
	phase2 := e.boss_phase >= 2

	boss_hold_range(e, dir, dist, spd, b.preferred_range, dT, 0.85)
	e.state_timer -= dT
	#partial switch e.state {
	case .CHASE, .RECOVER:
		if e.state_timer <= 0 {
			r := rand.float32()
			e.boss_seq = 0
			if r < 0.5 {
				e.boss_next = 0 // icicle fan
				e.state_timer = 0.4
			} else if r < 0.8 {
				e.boss_next = 1 // frost nova
				e.state_timer = 0.45
			} else {
				e.boss_next = 2 // blink
				e.state_timer = 0.3
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
				e.state_timer = 0.25
			case 1:
				e.state_timer = 0.3
			case 2:
				e.state_timer = 0.2
			}
		}
	case .BOSS_ATTACK:
		switch e.boss_next {
		case 0:
			if e.boss_seq == 0 {
				boss_fan(ec, pc - ec, phase2 ? 9 : 7, 0.14, 380, e.damage, 10, {.Freeze})
				e.muzzle = ENEMY_MUZZLE_FLASH_TIME
				e.muzzle_dir = dir
				add_shake(3)
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.25 : 0.45
			}
		case 1:
			if e.boss_seq == 0 {
				boss_radial(
					ec,
					phase2 ? 20 : 14,
					250,
					e.damage * 0.5,
					11,
					rand.float32() * 6.28,
					{.Freeze},
				)
				add_shake(4)
				e.boss_seq = 1
			}
			if e.state_timer <= 0 {
				e.state = .RECOVER
				e.state_timer = phase2 ? 0.25 : 0.45
			}
		case 2: // blink to a fresh spot at range, bursting frost where it lands
			if e.boss_seq == 0 {
				ang := rand.float32() * 2 * math.PI
				from := raylib.Vector2{math.cos_f32(ang), math.sin_f32(ang)}
				target := pc + from * 200
				target.x = clamp(target.x, f32(WALL_THICK), f32(ARENA_W - WALL_THICK))
				target.y = clamp(target.y, f32(WALL_THICK), f32(ARENA_H - WALL_THICK))
				e.position = target - e.size * 0.5
				e.flash = 0.5
				boss_radial(e.position + e.size * 0.5, 8, 230, e.damage * 0.4, 10, 0, {.Freeze})
				add_shake(5)
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
				boss_tele_circle(ec, 150, k, raylib.Color{230, 200, 150, 255})
			} else if e.boss_next == 1 {
				boss_tele_circle(pc, 74, k, raylib.Color{200, 160, 110, 255})
			} else {
				boss_tele_line(ec, ec + raylib.Vector2Normalize(to) * 320, 34, k, raylib.Color{220, 200, 160, 255})
			}
		case .FROSTBITE:
			if e.boss_next == 0 {
				boss_tele_line(ec, ec + e.boss_aux * 460, 16, k, raylib.Color{150, 220, 255, 255})
			} else if e.boss_next == 1 {
				boss_tele_circle(ec, 70 + 120 * (1 - k), k, raylib.Color{150, 220, 255, 255})
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
	switch e.boss_kind {
	case .PACKLEADER:
		pack_leader_body(e, ec, er, facing)
	case .DUSTMAW:
		dustmaw_body(e, ec, er, facing)
	case .COLOSSUS:
		colossus_body(e, ec, er)
	case .FROSTBITE:
		frostbite_body(e, ec, er)
	case .MECHANIKTRON:
		mechaniktron_body(e, ec, er, facing)
	case .THORNWALD:
		thornwald_body(e, ec, er)
	case .BOGWRAITH:
		bogwraith_body(e, ec, er, facing)
	}
}

pack_leader_body :: proc(e: enemy, ec: raylib.Vector2, er: f32, facing: raylib.Vector2) {
	// Two ears, a darker mane ring, a pair of eyes and a snout toward the player.
	raylib.DrawTriangle(
		ec + {-er * 0.55, -er},
		ec + {-er * 0.15, -er * 1.5},
		ec + {-er * 0.1, -er},
		raylib.Color{60, 92, 52, 255},
	)
	raylib.DrawTriangle(
		ec + {er * 0.55, -er},
		ec + {er * 0.15, -er * 1.5},
		ec + {er * 0.1, -er},
		raylib.Color{60, 92, 52, 255},
	)
	raylib.DrawCircleLines(i32(ec.x), i32(ec.y), er * 0.85, raylib.Color{40, 70, 40, 255})
	eye := ec + facing * er * 0.35
	perp := raylib.Vector2{-facing.y, facing.x}
	raylib.DrawCircleV(eye + perp * er * 0.3, 3.5, raylib.YELLOW)
	raylib.DrawCircleV(eye - perp * er * 0.3, 3.5, raylib.YELLOW)
	snout := ec + facing * er * 0.9
	raylib.DrawCircleV(snout, 4, raylib.Color{30, 50, 30, 255})
	if e.state == .WINDUP {
		raylib.DrawCircleLines(i32(ec.x), i32(ec.y), er * (0.9 + 0.25), raylib.YELLOW)
	}
}

dustmaw_body :: proc(e: enemy, ec: raylib.Vector2, er: f32, facing: raylib.Vector2) {
	if e.boss_hidden {
		// Just a disturbed mound of dirt with ripples, sliding over the ground.
		raylib.DrawCircleV(ec, er * 1.05, raylib.Color{96, 74, 46, 255})
		raylib.DrawCircleV(ec + {0, -er * 0.28}, er * 0.62, raylib.Color{132, 104, 66, 255})
		raylib.DrawCircleLines(i32(ec.x), i32(ec.y), er * 0.8, raylib.Color{80, 60, 38, 255})
		raylib.DrawCircleLines(i32(ec.x), i32(ec.y), er * 1.15, raylib.Color{70, 54, 34, 200})
		return
	}
	// Surfaced: a segmented body with a maw facing the player.
	raylib.DrawCircleV(ec - facing * er * 0.5, er * 0.75, raylib.Color{150, 120, 74, 255})
	raylib.DrawCircleV(ec, er * 0.95, raylib.Color{178, 146, 92, 255})
	raylib.DrawCircleV(ec + facing * er * 0.35, er * 0.7, raylib.Color{206, 172, 108, 255})
	maw := ec + facing * er * 0.55
	raylib.DrawCircleV(maw, er * 0.5, raylib.Color{40, 24, 16, 255})
	perp := raylib.Vector2{-facing.y, facing.x}
	raylib.DrawTriangle(maw + perp * 6, maw + facing * 6, maw + perp * 4 - facing * 8, raylib.RAYWHITE)
	raylib.DrawTriangle(maw - perp * 6, maw + facing * 6, maw - perp * 4 - facing * 8, raylib.RAYWHITE)
}

colossus_body :: proc(e: enemy, ec: raylib.Vector2, er: f32) {
	raylib.DrawRectangleRec(
		raylib.Rectangle{ec.x - er * 0.9, ec.y - er * 0.9, er * 1.8, er * 1.8},
		raylib.Color{108, 108, 118, 255},
	)
	raylib.DrawRectangleLinesEx(
		raylib.Rectangle{ec.x - er * 0.9, ec.y - er * 0.9, er * 1.8, er * 1.8},
		3,
		raylib.Color{70, 70, 80, 255},
	)
	// Cracks of glowing light.
	core := raylib.Color{255, 170, 70, 255}
	raylib.DrawLineEx(ec + {-er * 0.6, -er * 0.3}, ec + {er * 0.1, er * 0.5}, 2, core)
	raylib.DrawLineEx(ec + {er * 0.1, er * 0.5}, ec + {er * 0.6, -er * 0.1}, 2, core)
	raylib.DrawCircleV(ec, er * 0.22 + (e.state == .WINDUP ? 3 : 0), raylib.Color{255, 200, 110, 255})
}

frostbite_body :: proc(e: enemy, ec: raylib.Vector2, er: f32) {
	raylib.DrawPoly(ec, 4, er * 1.15, 0, raylib.Color{150, 225, 255, 255})
	raylib.DrawPoly(ec, 4, er * 0.7, 0, raylib.Color{215, 245, 255, 255})
	// Ring of shards.
	for i in 0 ..< 6 {
		ang := f32(i) * (math.PI / 3) + f32(e.boss_spin)
		dir := raylib.Vector2{math.cos_f32(ang), math.sin_f32(ang)}
		raylib.DrawTriangle(
			ec + dir * er * 0.9,
			ec + dir * er * 1.5,
			ec + dir * er * 0.9 + raylib.Vector2{-dir.y, dir.x} * 5,
			raylib.Color{180, 235, 255, 220},
		)
	}
}

mechaniktron_body :: proc(e: enemy, ec: raylib.Vector2, er: f32, facing_in: raylib.Vector2) {
	// While exposed the machine can't turn, so draw its frozen facing and let the
	// weakpoint stay where the stun left it.
	facing := facing_in
	if e.boss_stun > 0 && raylib.Vector2Length(e.boss_aux) > 0.01 {
		facing = raylib.Vector2Normalize(e.boss_aux)
	}
	perp := raylib.Vector2{-facing.y, facing.x}
	steel := raylib.Color{104, 118, 134, 255}
	dark := raylib.Color{52, 60, 70, 255}
	// Treads.
	raylib.DrawRectangleRec(
		raylib.Rectangle{ec.x - er * 0.98, ec.y - er * 0.34, er * 1.96, er * 0.68},
		dark,
	)
	// Back plate: the armour that hides the weakpoint.
	back := ec - facing * er * 0.55
	raylib.DrawRectangleRec(
		raylib.Rectangle{back.x - er * 0.55, back.y - er * 0.55, er * 1.1, er * 1.1},
		raylib.Color{70, 80, 92, 255},
	)
	// Torso.
	raylib.DrawRectangleRec(
		raylib.Rectangle{ec.x - er * 0.68, ec.y - er * 0.68, er * 1.36, er * 1.36},
		steel,
	)
	raylib.DrawRectangleLinesEx(
		raylib.Rectangle{ec.x - er * 0.68, ec.y - er * 0.68, er * 1.36, er * 1.36},
		2,
		dark,
	)
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

thornwald_body :: proc(e: enemy, ec: raylib.Vector2, er: f32) {
	// Trunk.
	raylib.DrawRectangleRec(
		raylib.Rectangle{ec.x - er * 0.35, ec.y - er * 0.4, er * 0.7, er * 1.3},
		raylib.Color{78, 58, 36, 255},
	)
	// Canopy.
	raylib.DrawCircleV(ec + {0, -er * 0.75}, er * 0.65, raylib.Color{56, 112, 56, 255})
	raylib.DrawCircleV(ec + {-er * 0.5, -er * 0.45}, er * 0.45, raylib.Color{68, 132, 62, 255})
	raylib.DrawCircleV(ec + {er * 0.5, -er * 0.45}, er * 0.45, raylib.Color{68, 132, 62, 255})
	// Roots.
	raylib.DrawTriangle(
		ec + {-er * 0.35, er * 0.85},
		ec + {-er * 0.7, er * 1.15},
		ec + {-er * 0.05, er * 0.95},
		raylib.Color{60, 46, 30, 255},
	)
	raylib.DrawTriangle(
		ec + {er * 0.35, er * 0.85},
		ec + {er * 0.7, er * 1.15},
		ec + {er * 0.05, er * 0.95},
		raylib.Color{60, 46, 30, 255},
	)
	// Eyes in the trunk.
	raylib.DrawCircleV(ec + {-er * 0.14, er * 0.05}, 3, raylib.Color{200, 240, 120, 255})
	raylib.DrawCircleV(ec + {er * 0.14, er * 0.05}, 3, raylib.Color{200, 240, 120, 255})
}

bogwraith_body :: proc(e: enemy, ec: raylib.Vector2, er: f32, facing: raylib.Vector2) {
	col := e.color
	// Tattered robe: a hood circle over a downward triangle skirt.
	raylib.DrawCircleV(ec + {0, -er * 0.2}, er * 0.95, raylib.Color{col.r, col.g, col.b, 220})
	raylib.DrawTriangle(
		ec + {-er * 0.85, er * 0.2},
		ec + {er * 0.85, er * 0.2},
		ec + {0, er * 1.25},
		raylib.Color{col.r, col.g, col.b, 200},
	)
	// Hood shadow + glowing eyes.
	raylib.DrawCircleV(ec + {0, -er * 0.2}, er * 0.55, raylib.Color{28, 16, 38, 235})
	perp := raylib.Vector2{-facing.y, facing.x}
	eye := ec + facing * er * 0.2
	raylib.DrawCircleV(eye + perp * er * 0.22, 3, raylib.Color{210, 150, 255, 255})
	raylib.DrawCircleV(eye - perp * er * 0.22, 3, raylib.Color{210, 150, 255, 255})
	if e.state == .WINDUP {
		raylib.DrawCircleLines(i32(ec.x), i32(ec.y), er * 1.2, raylib.Color{200, 140, 255, 200})
	}
}
