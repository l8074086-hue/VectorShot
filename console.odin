package main
import "core:strconv"
import "core:strings"
import "vendor:raylib"

// ---------------------------------------------------------------------------
// Debug command panel
//
// A Quake-style console overlay, toggled with ` (GRAVE) during a run. While it
// is open the world is frozen (dT is zeroed in main) and gameplay keys are
// ignored (world_key_* below), so you can type without getting attacked.
// ---------------------------------------------------------------------------

CONSOLE_MAX_LINES :: 12
CONSOLE_LINE_LEN :: 100
CONSOLE_MAX_INPUT :: 96
CONSOLE_PANEL_H :: 300 // px, docked to the bottom of the 800x600 canvas

console_open: bool = false
console_len: int = 0
console_input: [CONSOLE_MAX_INPUT]u8

console_line :: struct {
	text:  [CONSOLE_LINE_LEN]u8,
	error: bool,
}
console_lines: [CONSOLE_MAX_LINES]console_line
console_line_count: int

// Gameplay input that yields to the console. Everything in the PLAYING loop
// reads keys through these so typing can't move, shoot, dash, etc.
world_key_pressed :: proc(k: raylib.KeyboardKey) -> bool {
	return !console_open && raylib.IsKeyPressed(k)
}

world_key_down :: proc(k: raylib.KeyboardKey) -> bool {
	return !console_open && raylib.IsKeyDown(k)
}

console_toggle :: proc() {
	if console_open {
		console_close()
	} else {
		console_open = true
		console_len = 0
		// ESC should close the console, not quit the game, while it is open.
		raylib.SetExitKey(raylib.KeyboardKey.KEY_NULL)
	}
}

console_close :: proc() {
	if !console_open {
		return
	}
	console_open = false
	raylib.SetExitKey(raylib.KeyboardKey.ESCAPE)
}

// Append a line of output, scrolling older lines off the top. `error` only
// changes the draw color.
console_print :: proc(msg: string, error := false) {
	if console_line_count == CONSOLE_MAX_LINES {
		for i in 1 ..< CONSOLE_MAX_LINES {
			console_lines[i - 1] = console_lines[i]
		}
		console_line_count -= 1
	}
	line := &console_lines[console_line_count]
	n := min(len(msg), CONSOLE_LINE_LEN - 1)
	for i in 0 ..< n {
		line.text[i] = msg[i]
	}
	line.text[n] = 0
	line.error = error
	console_line_count += 1
}

// Drain the character queue and handle editing keys. Called once per frame while
// the console is open.
console_update :: proc() {
	for {
		ch := raylib.GetCharPressed()
		if ch == 0 {
			break
		}
		// Skip the toggle key itself and anything non-printable.
		if ch >= 32 && ch < 127 && ch != '`' && console_len < CONSOLE_MAX_INPUT - 1 {
			console_input[console_len] = u8(ch)
			console_len += 1
		}
	}
	if (raylib.IsKeyPressed(raylib.KeyboardKey.BACKSPACE) ||
	   raylib.IsKeyPressedRepeat(raylib.KeyboardKey.BACKSPACE)) && console_len > 0 {
		console_len -= 1
	}
	if raylib.IsKeyPressed(raylib.KeyboardKey.ENTER) ||
	   raylib.IsKeyPressed(raylib.KeyboardKey.KP_ENTER) {
		console_input[console_len] = 0
		cmd := string(console_input[:console_len])
		if len(cmd) > 0 {
			console_print(string(raylib.TextFormat("> %s", cmd)), false)
			console_execute(cmd)
		}
		console_len = 0
	}
	if raylib.IsKeyPressed(raylib.KeyboardKey.ESCAPE) {
		console_close()
		return
	}
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

enemy_kind_from_token :: proc(s: string) -> (Enemy_Kind, bool) {
	switch s {
	case "1", "grunt", "gr":
		return .GRUNT, true
	case "2", "runner", "run":
		return .RUNNER, true
	case "3", "tank":
		return .TANK, true
	case "4", "ranged", "shooter", "shoot":
		return .RANGED, true
	case "5", "charger", "charge":
		return .CHARGER, true
	}
	return .GRUNT, false
}

is_elite_token :: proc(s: string) -> bool {
	return s == "elite" || s == "e" || s == "1"
}

console_help :: proc() {
	console_print("commands:")
	console_print("spawn <grunt|runner|tank|shooter|charger|1-5> [elite]")
	console_print("item <health|ammo|coin> [amount]")
	console_print("set <wave|coins|health|maxhp|ammo|speed|damage|projectiles|pierce|spread|invuln> <v>")
	console_print("gun <damage|cooldown|spread|mag|ammo|pierce|speed|projectiles|bullet> <v>  (primary)")
	console_print("give <dash|attack|speed|health|projectile|precision|pierce>")
	console_print("nextwave   spawn the next wave now")
	console_print("clear      remove all enemies    ` or ESC closes")
}

console_execute :: proc(cmd: string) {
	fields := strings.fields(cmd)
	defer delete(fields)
	if len(fields) == 0 {
		return
	}

	switch fields[0] {
	case "help", "?":
		console_help()

	case "spawn":
		console_cmd_spawn(fields)

	case "item", "drop":
		console_cmd_item(fields)

	case "set":
		console_cmd_set(fields)

	case "gun":
		console_cmd_gun(fields)

	case "give":
		if len(fields) < 2 {
			console_print("usage: give <upgrade>", true)
			return
		}
		if console_give(fields[1]) {
			console_print(string(raylib.TextFormat("granted %s", fields[1])))
		} else {
			console_print(string(raylib.TextFormat("unknown upgrade: %s", fields[1])), true)
		}

	case "clear", "kill":
		clear(&enemies)
		clear(&enemy_bullets)
		console_print("cleared enemies")

	case "nextwave", "wave+":
		new_wave(&enemies, wave)
		wave += 1
		console_print(string(raylib.TextFormat("wave %i spawned", wave - 1)))

	case:
		console_print(string(raylib.TextFormat("unknown command: %s", fields[0])), true)
	}
}

console_cmd_spawn :: proc(fields: []string) {
	if len(fields) < 2 {
		console_print("usage: spawn <enemy> [elite]", true)
		return
	}
	kind, ok := enemy_kind_from_token(fields[1])
	if !ok {
		console_print(string(raylib.TextFormat("unknown enemy: %s", fields[1])), true)
		return
	}
	elite := len(fields) >= 3 && is_elite_token(fields[2])
	spawn_enemy_near_player(kind, elite, wave)
	console_print(
		string(
			raylib.TextFormat(
				"spawned %s%s",
				ENEMIES[kind].name,
				elite ? cstring(" (elite)") : cstring(""),
			),
		),
	)
}

console_cmd_item :: proc(fields: []string) {
	if len(fields) < 2 {
		console_print("usage: item <health|ammo|coin> [amount]", true)
		return
	}
	kind: Drop_Kind
	default := f32(0)
	switch fields[1] {
	case "health", "hp", "h":
		kind = .HEALTH
		default = 20
	case "ammo", "a":
		kind = .AMMO
		default = 8
	case "coin", "coins", "c", "gold", "money":
		kind = .CURRENCY
		default = 5
	case:
		console_print(string(raylib.TextFormat("unknown item: %s", fields[1])), true)
		return
	}
	amount := default
	if len(fields) >= 3 {
		if v, ok := strconv.parse_f32(fields[2]); ok {
			amount = v
		}
	}
	spawn_drop_near_player(kind, amount)
	console_print(
		string(raylib.TextFormat("dropped %s x%g", fields[1], amount)),
	)
}

console_cmd_set :: proc(fields: []string) {
	if len(fields) < 3 {
		console_print("usage: set <key> <value>", true)
		return
	}
	val, ok := strconv.parse_f32(fields[2])
	if !ok {
		console_print(string(raylib.TextFormat("bad value: %s", fields[2])), true)
		return
	}
	iv := i32(val)

	switch fields[1] {
	case "wave":
		wave = max(iv, 1)
	case "coins", "gold", "currency":
		currency = iv
	case "health", "hp":
		health = min(val, max_health)
	case "maxhp", "max_health":
		max_health = val
		health = min(health, max_health)
	case "ammo":
		primary.ammo = iv
		primary.ammo_cap = max(primary.ammo_cap, iv)
		secondary.ammo = iv
		secondary.ammo_cap = max(secondary.ammo_cap, iv)
	case "speed":
		SPEED = val
	case "damage", "dmg":
		bonus_damage = val
	case "projectiles", "proj":
		bonus_projectiles = iv
	case "pierce":
		bonus_pierce = iv
	case "spread":
		spread_cut = val
	case "invuln", "inv":
		inv_timer = val
	case:
		console_print(string(raylib.TextFormat("unknown key: %s", fields[1])), true)
		return
	}
	console_print(string(raylib.TextFormat("%s = %g", fields[1], val)))
}

console_cmd_gun :: proc(fields: []string) {
	if len(fields) < 3 {
		console_print("usage: gun <stat> <value>", true)
		return
	}
	val, ok := strconv.parse_f32(fields[2])
	if !ok {
		console_print(string(raylib.TextFormat("bad value: %s", fields[2])), true)
		return
	}
	iv := i32(val)

	switch fields[1] {
	case "damage", "dmg":
		GUNS[gun].damage = val
	case "cooldown", "rate":
		GUNS[gun].cooldown = val
	case "spread":
		GUNS[gun].spread = val
	case "mag", "magazine":
		GUNS[gun].magazine_capacity = iv
		primary.mag_cap = iv
		primary.mag = iv
	case "ammo":
		GUNS[gun].ammo_capacity = iv
		primary.ammo_cap = iv
		primary.ammo = iv
	case "pierce":
		GUNS[gun].pierce = iv
	case "speed":
		GUNS[gun].bullet_speed = val
	case "projectiles", "proj":
		GUNS[gun].projectiles = iv
	case "bullet", "size":
		GUNS[gun].bullet_size = {val, val}
	case:
		console_print(string(raylib.TextFormat("unknown gun stat: %s", fields[1])), true)
		return
	}
	console_print(string(raylib.TextFormat("%s %s = %g", GUNS[gun].name, fields[1], val)))
}

// Returns false if the token isn't a known card.
console_give :: proc(name: string) -> bool {
	switch name {
	case "dash":
		apply_upgrade("DASH")
	case "attack", "dmg":
		apply_upgrade("ATTACK")
	case "speed":
		apply_upgrade("SPEED")
	case "health", "hp":
		apply_upgrade("HEALTH")
	case "projectile", "proj":
		apply_upgrade("PROJECTILE")
	case "precision", "spread":
		apply_upgrade("PRECISION")
	case "pierce":
		apply_upgrade("PIERCE")
	case:
		return false
	}
	return true
}

// ---------------------------------------------------------------------------
// Drawing (screen space; called at the end of the PLAYING frame)
// ---------------------------------------------------------------------------

console_draw :: proc() {
	if !console_open {
		return
	}
	y0 := i32(600 - CONSOLE_PANEL_H)
	raylib.DrawRectangle(0, y0, 800, CONSOLE_PANEL_H, raylib.Color{0, 0, 0, 225})
	raylib.DrawRectangleLines(0, y0, 800, CONSOLE_PANEL_H, raylib.Color{90, 90, 100, 255})

	ly := y0 + 10
	for i in 0 ..< console_line_count {
		line := &console_lines[i]
		color := line.error ? raylib.RED : raylib.LIGHTGRAY
		raylib.DrawText(cstring(&line.text[0]), 12, ly, 18, color)
		ly += 20
	}

	// Input row, pinned to the bottom of the panel.
	iy := i32(600 - 26)
	raylib.DrawRectangle(0, iy - 5, 800, 31, raylib.Color{18, 18, 22, 255})
	raylib.DrawText(cstring(">"), 12, iy, 20, raylib.GREEN)
	console_input[console_len] = 0
	text := cstring(&console_input[0])
	raylib.DrawText(text, 30, iy, 20, raylib.WHITE)
	// Blinking cursor.
	if int(raylib.GetTime() * 2) % 2 == 0 {
		cx := 30 + raylib.MeasureText(text, 20)
		raylib.DrawRectangle(cx, iy, 10, 20, raylib.WHITE)
	}
}
