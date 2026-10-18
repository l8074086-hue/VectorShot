package main
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "vendor:raylib"

// ---------------------------------------------------------------------------
// Settings
//
// Player-tunable options, persisted to settings.cfg next to the game. Options
// mostly gate optional feedback (damage numbers, screen shake, blood) so a
// player can dial the game's noise up or down. The chosen difficulty and the
// comfort-assist (GF mode) toggle also live here: they're run state in
// game.odin, but they persist so preferences survive between sessions.
// ---------------------------------------------------------------------------

Control_Scheme :: enum {
	MOUSE, // LMB fires, RMB kicks; the keyboard still works too
	KEYBOARD, // mouse buttons are inert; use SPACE to fire and E to kick
}

SETTINGS_PATH :: "settings.cfg"

Settings :: struct {
	master_volume:  f32, // 0..1
	muted:          bool,
	fullscreen:     bool,
	show_fps:       bool,
	damage_numbers: bool,
	hurt_vignette: bool, // red edge wash when the player is hit (0 disables it)
	screen_shake:   f32, // 0..1 intensity (0 disables shake entirely)
	blood:          bool,
	control_scheme: Control_Scheme,
	// Bitmask of cleared missions (bit i = MISSIONS[i] done). Mission progress is
	// persisted alongside preferences since it must survive restarts.
	missions_done:  u32,
	// Map progression. `maps_done` has bit i set once arena i's boss has been
	// beaten; `maps_unlocked` has bit i set when arena i is playable (the first
	// map starts unlocked, and each clear opens the next one up). Persisted so
	// unlocked maps survive restarts; the Ctrl+Shift+U dev cheat fills
	// `maps_unlocked` without marking anything cleared.
	maps_done:      u32,
	maps_unlocked:  u32,
	// Relic collection (bit i = RELICS[i] found at some point) and the subset you
	// take into a run (at most RELIC_MAX_EQUIPPED bits). Both persist: chests add
	// to the collection, and the Equipment screen picks the loadout that carries
	// into the next run.
	relics_owned:     u32,
	relics_equipped:  u32,
}

settings := Settings {
	master_volume  = 0.5,
	muted          = false,
	fullscreen     = true,
	show_fps       = false,
	damage_numbers = true,
	hurt_vignette = true,
	screen_shake   = 0.4,
	blood          = true,
	control_scheme = .MOUSE,
	missions_done  = 0,
	maps_done      = 0,
	maps_unlocked  = 1, // the first map is always open
	relics_owned   = 0,
	relics_equipped = 0,
}

// Volume the mixer should use right now (mute folds in here, as does the
// temporary auto-pause mute while the window is unfocused).
effective_volume :: proc() -> f32 {
	if settings.muted || audio_muted_here {
		return 0
	}
	return clamp(settings.master_volume, 0, 1)
}

// Match the real window state to the stored preference.
apply_fullscreen :: proc() {
	if settings.fullscreen != raylib.IsWindowFullscreen() {
		raylib.ToggleFullscreen()
	}
}

// --- persistence -----------------------------------------------------------

parse_bool :: proc(s: string, fallback: bool) -> bool {
	switch s {
	case "true", "1", "yes", "on":
		return true
	case "false", "0", "no", "off":
		return false
	}
	return fallback
}

parse_f32 :: proc(s: string, fallback: f32) -> f32 {
	if v, ok := strconv.parse_f32(s); ok {
		return v
	}
	return fallback
}

settings_load :: proc() {
	data, err := os.read_entire_file_from_path(SETTINGS_PATH, context.allocator)
	if err != nil {
		return // no file yet: keep defaults
	}
	defer delete(data)

	for line in strings.split_lines(string(data), context.temp_allocator) {
		l := strings.trim_space(line)
		if len(l) == 0 || l[0] == '#' {
			continue
		}
		parts := strings.split_n(l, "=", 2, context.temp_allocator)
		if len(parts) != 2 {
			continue
		}
		key := strings.trim_space(parts[0])
		val := strings.trim_space(parts[1])
		switch key {
		case "volume":
			settings.master_volume = clamp(parse_f32(val, settings.master_volume), 0, 1)
		case "muted":
			settings.muted = parse_bool(val, settings.muted)
		case "maps_done":
			settings.maps_done = u32(parse_run_i32(val, i32(settings.maps_done)))
		case "maps_unlocked":
			settings.maps_unlocked = u32(parse_run_i32(val, i32(settings.maps_unlocked)))
		case "relics_owned":
			settings.relics_owned = u32(parse_run_i32(val, i32(settings.relics_owned)))
		case "relics_equipped":
			settings.relics_equipped = u32(parse_run_i32(val, i32(settings.relics_equipped)))
		case "fullscreen":
			settings.fullscreen = parse_bool(val, settings.fullscreen)
		case "show_fps":
			settings.show_fps = parse_bool(val, settings.show_fps)
		case "damage_numbers":
			settings.damage_numbers = parse_bool(val, settings.damage_numbers)
		case "hurt_vignette":
			settings.hurt_vignette = parse_bool(val, settings.hurt_vignette)
		case "screen_shake":
			settings.screen_shake = clamp(parse_f32(val, settings.screen_shake), 0, 1)
		case "blood":
			settings.blood = parse_bool(val, settings.blood)
		case "control_scheme":
			switch val {
			case "mouse":
				settings.control_scheme = .MOUSE
			case "keyboard":
				settings.control_scheme = .KEYBOARD
			}
		case "missions_done":
			settings.missions_done = u32(parse_f32(val, f32(settings.missions_done)))
		case "difficulty":
			switch val {
			case "easy":
				difficulty = .EASY
			case "normal":
				difficulty = .NORMAL
			case "hard":
				difficulty = .HARD
			}
		case "assists":
			gf_mode = parse_bool(val, gf_mode)
		}
	}
}

settings_save :: proc() {
	sb: strings.Builder
	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)
	fmt.sbprintf(&sb, "# Roguelike settings (rewritten on change)\n")
	fmt.sbprintf(&sb, "volume=%.3f\n", settings.master_volume)
	fmt.sbprintf(&sb, "muted=%v\n", settings.muted)
	fmt.sbprintf(&sb, "fullscreen=%v\n", settings.fullscreen)
	fmt.sbprintf(&sb, "show_fps=%v\n", settings.show_fps)
	fmt.sbprintf(&sb, "damage_numbers=%v\n", settings.damage_numbers)
	fmt.sbprintf(&sb, "hurt_vignette=%v\n", settings.hurt_vignette)
	fmt.sbprintf(&sb, "screen_shake=%.3f\n", settings.screen_shake)
	fmt.sbprintf(&sb, "blood=%v\n", settings.blood)
	fmt.sbprintf(
		&sb,
		"control_scheme=%s\n",
		settings.control_scheme == .MOUSE ? "mouse" : "keyboard",
	)
	fmt.sbprintf(
		&sb,
		"difficulty=%s\n",
		difficulty == .EASY ? "easy" : (difficulty == .HARD ? "hard" : "normal"),
	)
	fmt.sbprintf(&sb, "assists=%v\n", gf_mode)
	fmt.sbprintf(&sb, "missions_done=%i\n", i32(settings.missions_done))
	fmt.sbprintf(&sb, "maps_done=%i\n", i32(settings.maps_done))
	fmt.sbprintf(&sb, "maps_unlocked=%i\n", i32(settings.maps_unlocked))
	fmt.sbprintf(&sb, "relics_owned=%i\n", i32(settings.relics_owned))
	fmt.sbprintf(&sb, "relics_equipped=%i\n", i32(settings.relics_equipped))

	_ = os.write_entire_file(SETTINGS_PATH, strings.to_string(sb))
}
