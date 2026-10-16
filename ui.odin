package main
import "vendor:raylib"

// ---------------------------------------------------------------------------
// UI helpers
//
// Every menu in the game is keyboard-driven; these helpers bolt mouse support
// on top without changing that. The mouse is tracked in canvas space (set once
// per frame in main) so widgets can be hit-tested anywhere.
// ---------------------------------------------------------------------------

mouse_pos: raylib.Vector2
mouse: raylib.Rectangle

// A centered, clickable line of text. Hover brightens it to yellow and the
// left mouse button reports a click. `y` is the text's top edge, matching
// draw_centered so a row can be switched between the two freely. Also returns
// whether the row is hovered, so callers can move their keyboard selection.
ui_row :: proc(label: cstring, y, size: i32, color: raylib.Color) -> (clicked: bool, hovered: bool) {
	w := raylib.MeasureText(label, size)
	x := 400 - w / 2
	rect := raylib.Rectangle{f32(x) - 16, f32(y) - 6, f32(w) + 32, f32(size) + 12}
	hovered = raylib.CheckCollisionRecs(mouse, rect)
	c := hovered ? raylib.YELLOW : color
	raylib.DrawText(label, x, y, size, c)
	clicked = hovered && raylib.IsMouseButtonPressed(.LEFT)
	return
}

// A left-aligned clickable line (list rows inside a screen).
ui_row_at :: proc(label: cstring, x, y, size: i32, color: raylib.Color) -> bool {
	w := raylib.MeasureText(label, size)
	rect := raylib.Rectangle{f32(x) - 8, f32(y) - 5, f32(w) + 16, f32(size) + 10}
	hover := raylib.CheckCollisionRecs(mouse, rect)
	c := hover ? raylib.YELLOW : color
	raylib.DrawText(label, x, y, size, c)
	return hover && raylib.IsMouseButtonPressed(.LEFT)
}

// Drag-track for a 0..1 slider. `id` must be unique per slider so a drag keeps
// controlling the same one. Returns the (possibly updated) value.
ui_drag_slider: i32 = -1

ui_slider :: proc(id: i32, label: cstring, label_x, y, track_x, track_w: i32, value: f32) -> f32 {
	raylib.DrawText(label, label_x, y, 18, raylib.RAYWHITE)
	track := raylib.Rectangle{f32(track_x), f32(y) + 5, f32(track_w), 12}
	if raylib.CheckCollisionRecs(mouse, track) && raylib.IsMouseButtonPressed(.LEFT) {
		ui_drag_slider = id
	}
	if ui_drag_slider == id && raylib.IsMouseButtonReleased(.LEFT) {
		ui_drag_slider = -1
	}
	v := clamp(value, 0, 1)
	if ui_drag_slider == id {
		v = clamp((mouse_pos.x - track.x) / track.width, 0, 1)
	}
	raylib.DrawRectangleRec(track, raylib.DARKGRAY)
	raylib.DrawRectangleRec(
		raylib.Rectangle{track.x, track.y, track.width * v, track.height},
		raylib.SKYBLUE,
	)
	knob := track.x + track.width * v
	raylib.DrawRectangle(i32(knob) - 4, y, 8, 22, raylib.RAYWHITE)
	raylib.DrawText(raylib.TextFormat("%i%%", i32(v * 100)), track_x + track_w + 12, y, 18, raylib.GRAY)
	return v
}

// A labelled settings row: label on the left, value on the right, with a
// highlight band when selected or hovered. Returns click/hover like ui_row.
ui_setting_row :: proc(label, value: cstring, y: i32, selected: bool) -> (clicked: bool, hovered: bool) {
	rect := raylib.Rectangle{100, f32(y) - 6, 600, 34}
	hovered = raylib.CheckCollisionRecs(mouse, rect)
	if selected || hovered {
		raylib.DrawRectangleRec(
			rect,
			selected ? raylib.Color{40, 40, 72, 255} : raylib.Color{28, 28, 40, 255},
		)
	}
	raylib.DrawText(label, 116, y, 22, hovered ? raylib.YELLOW : raylib.RAYWHITE)
	vw := raylib.MeasureText(value, 22)
	raylib.DrawText(value, 684 - vw, y, 22, selected ? raylib.SKYBLUE : raylib.GRAY)
	clicked = hovered && raylib.IsMouseButtonPressed(.LEFT)
	return
}
