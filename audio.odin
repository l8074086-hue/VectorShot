package main

import "core:math"
import "core:math/rand"
import "vendor:raylib"

// All audio is synthesized at runtime: each effect is rendered to raw PCM and
// wrapped in a tiny in-memory WAV header, then handed to raylib. That keeps the
// repo free of binary assets and makes the whole palette tweakable in code.

SAMPLE_RATE :: 44100

Synth_Wave :: enum {
	SINE,
	SQUARE,
	SAW,
	TRIANGLE,
	NOISE,
}

Synth_Params :: struct {
	wave:      Synth_Wave,
	f0:        f32, // start frequency in Hz
	f1:        f32, // end frequency in Hz (0 == hold at f0)
	duration:  f32, // seconds
	volume:    f32, // 0..1
	attack:    f32, // seconds to ramp up from silence
	decay:     f32, // exponential decay rate (0 == no decay)
	noise_mix: f32, // 0..1 blend of white noise on top of the oscillator
}

// --- WAV assembly -----------------------------------------------------------

put_u32 :: proc(buf: []u8, off: int, v: u32) {
	buf[off + 0] = u8(v & 0xff)
	buf[off + 1] = u8((v >> 8) & 0xff)
	buf[off + 2] = u8((v >> 16) & 0xff)
	buf[off + 3] = u8((v >> 24) & 0xff)
}

put_u16 :: proc(buf: []u8, off: int, v: u16) {
	buf[off + 0] = u8(v & 0xff)
	buf[off + 1] = u8((v >> 8) & 0xff)
}

// Render one sound to a 16-bit mono WAV byte buffer (44-byte header + samples).
synth_build :: proc(p: Synth_Params) -> []u8 {
	n := max(1, int(p.duration * f32(SAMPLE_RATE)))
	data_size := n * 2
	buf := make([]u8, 44 + data_size)

	put_u32(buf, 0, 0x46464952) // "RIFF"
	put_u32(buf, 4, u32(36 + data_size))
	put_u32(buf, 8, 0x45564157) // "WAVE"
	put_u32(buf, 12, 0x20746d66) // "fmt "
	put_u32(buf, 16, 16) // PCM header size
	put_u16(buf, 20, 1) // format: PCM
	put_u16(buf, 22, 1) // channels: mono
	put_u32(buf, 24, SAMPLE_RATE)
	put_u32(buf, 28, SAMPLE_RATE * 2) // byte rate
	put_u16(buf, 32, 2) // block align
	put_u16(buf, 34, 16) // bits per sample
	put_u32(buf, 36, 0x61746164) // "data"
	put_u32(buf, 40, u32(data_size))

	f0 := p.f0
	f1 := p.f1 == 0 ? p.f0 : p.f1
	release := f32(0.004) // snap the tail to zero so it doesn't click
	phase: f32 = 0

	for i in 0 ..< n {
		frac := f32(i) / f32(n)
		freq := f0 + (f1 - f0) * frac
		phase += freq / f32(SAMPLE_RATE)
		for phase >= 1 {
			phase -= 1
		}

		osc: f32
		switch p.wave {
		case .SINE:
			osc = math.sin(phase * 2 * math.PI)
		case .SQUARE:
			osc = phase < 0.5 ? 1 : -1
		case .SAW:
			osc = phase * 2 - 1
		case .TRIANGLE:
			osc = phase < 0.5 ? (phase * 4 - 1) : (3 - phase * 4)
		case .NOISE:
			osc = rand.float32() * 2 - 1
		}
		if p.noise_mix > 0 {
			osc = osc * (1 - p.noise_mix) + (rand.float32() * 2 - 1) * p.noise_mix
		}

		t := f32(i) / f32(SAMPLE_RATE)
		env: f32 = 1
		if p.attack > 0 && t < p.attack {
			env = t / p.attack
		}
		if p.decay > 0 {
			env *= math.exp(-p.decay * max(0, t - p.attack))
		}
		if remaining := p.duration - t; remaining < release {
			env *= remaining / release
		}

		s := clamp(osc * env * p.volume, -1, 1)
		v := u16(i16(s * 32767))
		off := 44 + i * 2
		buf[off + 0] = u8(v & 0xff)
		buf[off + 1] = u8((v >> 8) & 0xff)
	}
	return buf
}

// Render params into a playable raylib sound.
synth :: proc(p: Synth_Params) -> raylib.Sound {
	buf := synth_build(p)
	defer delete(buf)
	wave := raylib.LoadWaveFromMemory(".wav", raw_data(buf), i32(len(buf)))
	sound := raylib.LoadSoundFromWave(wave)
	raylib.UnloadWave(wave)
	return sound
}

// ---------------------------------------------------------------------------
// Sound bank
// ---------------------------------------------------------------------------

Game_Sounds :: struct {
	primary:     [Gun]raylib.Sound,
	secondary:   [Secondary]raylib.Sound,
	kick:        raylib.Sound,
	dash:        raylib.Sound,
	reload:      raylib.Sound,
	hit:         raylib.Sound,
	enemy_die:   raylib.Sound,
	player_hurt: raylib.Sound,
	coin:        raylib.Sound,
	ammo:        raylib.Sound,
	health:      raylib.Sound,
	explosion:   raylib.Sound,
	card:        raylib.Sound,
	shop_buy:    raylib.Sound,
	wave_start:  raylib.Sound,
	game_over:   raylib.Sound,
	ui_move:     raylib.Sound,
	ui_select:   raylib.Sound,
}

sounds: Game_Sounds
audio_ready: bool

// Play a sound with optional pitch scaling. No-ops when there is no audio
// device (e.g. a headless machine), so the game still runs everywhere.
play :: proc(s: raylib.Sound, pitch := f32(1)) {
	if !audio_ready {
		return
	}
	raylib.SetSoundPitch(s, pitch)
	raylib.PlaySound(s)
}

audio_init :: proc() {
	raylib.InitAudioDevice()
	audio_ready = raylib.IsAudioDeviceReady()
	if !audio_ready {
		return
	}

	// Weapon reports: punchy, tuned per gun family.
	sounds.primary[.SNIPER] = synth({.SAW, 240, 60, 0.30, 0.75, 0.001, 9, 0.35})
	sounds.primary[.SHOTGUN] = synth({.NOISE, 400, 120, 0.22, 0.8, 0.001, 12, 0.8})
	sounds.primary[.SMG] = synth({.SQUARE, 520, 300, 0.07, 0.4, 0.001, 30, 0.2})
	sounds.primary[.RIFLE] = synth({.SQUARE, 400, 180, 0.12, 0.5, 0.001, 18, 0.35})
	sounds.primary[.MINIGUN] = synth({.SQUARE, 460, 220, 0.05, 0.32, 0.001, 40, 0.4})
	sounds.primary[.CANNON] = synth({.SAW, 160, 40, 0.34, 0.85, 0.001, 8, 0.5})

	sounds.secondary[.PISTOL] = synth({.SQUARE, 440, 200, 0.10, 0.45, 0.001, 20, 0.3})
	sounds.secondary[.REVOLVER] = synth({.SAW, 300, 90, 0.22, 0.65, 0.001, 12, 0.4})
	sounds.secondary[.DUAL] = synth({.SQUARE, 500, 260, 0.07, 0.38, 0.001, 26, 0.25})
	sounds.secondary[.SAWED] = synth({.NOISE, 380, 120, 0.2, 0.75, 0.001, 13, 0.85})

	// Actions and feedback.
	sounds.kick = synth({.NOISE, 140, 50, 0.18, 0.7, 0.002, 14, 0.5})
	sounds.dash = synth({.NOISE, 200, 900, 0.16, 0.4, 0.01, 10, 1.0})
	sounds.reload = synth({.SQUARE, 300, 220, 0.08, 0.35, 0.002, 25, 0.5})
	sounds.hit = synth({.SQUARE, 700, 500, 0.05, 0.3, 0.001, 40, 0.3})
	sounds.enemy_die = synth({.SAW, 500, 120, 0.22, 0.5, 0.002, 12, 0.3})
	sounds.player_hurt = synth({.SAW, 180, 80, 0.25, 0.6, 0.002, 10, 0.4})
	sounds.explosion = synth({.NOISE, 120, 35, 0.60, 0.9, 0.001, 5, 1.0})

	// Pickups + UI.
	sounds.coin = synth({.SINE, 900, 1400, 0.10, 0.45, 0.001, 16, 0})
	sounds.ammo = synth({.SQUARE, 600, 400, 0.09, 0.4, 0.002, 22, 0.4})
	sounds.health = synth({.SINE, 500, 800, 0.18, 0.45, 0.005, 10, 0})
	sounds.card = synth({.SINE, 700, 1000, 0.09, 0.4, 0.001, 18, 0})
	sounds.shop_buy = synth({.SINE, 1000, 1500, 0.14, 0.45, 0.001, 10, 0})
	sounds.wave_start = synth({.SQUARE, 300, 500, 0.30, 0.5, 0.01, 6, 0.1})
	sounds.game_over = synth({.SAW, 400, 80, 0.90, 0.6, 0.02, 3, 0.15})
	sounds.ui_move = synth({.SQUARE, 500, 500, 0.04, 0.25, 0.001, 40, 0})
	sounds.ui_select = synth({.SINE, 800, 1200, 0.08, 0.4, 0.001, 20, 0})
}

audio_shutdown :: proc() {
	if !audio_ready {
		return
	}
	for s in sounds.primary {
		raylib.UnloadSound(s)
	}
	for s in sounds.secondary {
		raylib.UnloadSound(s)
	}
	raylib.UnloadSound(sounds.kick)
	raylib.UnloadSound(sounds.dash)
	raylib.UnloadSound(sounds.reload)
	raylib.UnloadSound(sounds.hit)
	raylib.UnloadSound(sounds.enemy_die)
	raylib.UnloadSound(sounds.player_hurt)
	raylib.UnloadSound(sounds.coin)
	raylib.UnloadSound(sounds.ammo)
	raylib.UnloadSound(sounds.health)
	raylib.UnloadSound(sounds.explosion)
	raylib.UnloadSound(sounds.card)
	raylib.UnloadSound(sounds.shop_buy)
	raylib.UnloadSound(sounds.wave_start)
	raylib.UnloadSound(sounds.game_over)
	raylib.UnloadSound(sounds.ui_move)
	raylib.UnloadSound(sounds.ui_select)
	raylib.CloseAudioDevice()
}
