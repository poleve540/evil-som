package main

import "vendor:sdl3"

Camera :: struct
{
	pos: [2]f32,
	offset: [2]f32,
	zoom: f32
}

Rect :: struct
{
	pos: [2]f32,
	size: [2]f32
}

Division :: struct
{
	pos: [2]f32,
	province: u32,
	path: [dynamic]u32,
	timer: som_Timer
}

Graph :: map[u32][]u32

GameState :: struct
{
	cam: Camera,
	country_surface: ^sdl3.Surface, // Countries hitboxes
	province_surface: ^sdl3.Surface, // Provinces hitboxes
	province_graph: Graph,
	province_centers: map[u32][2]f32,
	map_rect: Rect,
	divisions: [dynamic]Division,

	mouse_delta: [2]f32,
	mouse_pos: [2]f32,
	mouse_scroll: f32,
	mouse_middle_pressed: bool,
	mouse_left_just_pressed: bool
}
