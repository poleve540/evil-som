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
	province: int,
	path: [dynamic]int,
	color: [3]u8,
	speed: f32,
	distance_traveled: f32,
	total_distance: f32
}

Key :: enum
{
	NONE,
	UP,
	DOWN,
	LEFT,
	RIGHT
}

MouseButton :: enum
{
	NONE,
	LEFT,
	MIDDLE,
	RIGHT
}

Node :: struct
{
	neighbors: []int,
	center_pos: [2]f32
}

Graph :: #soa[]Node

GameState :: struct
{
	cam: Camera,

	country_surface: ^sdl3.Surface, // Country hitboxes
	province_surface: ^sdl3.Surface, // Province hitboxes

	// TODO(pol): Put the Graph in PathfindingContext
	province_graph: Graph,
	pathfinding: PathfindingContext,
	rgb_to_node: map[u32]int,

	map_rect: Rect,

	divisions: [dynamic]Division,

	selected_province: int,

	// TODO(pol): Put all this in some kind of MouseState struct
	mouse_delta: [2]f32,
	mouse_pos: [2]f32,
	mouse_scroll: f32,

	keys: [Key]bool,
	keys_prev: [Key]bool,

	mouse_buttons: [MouseButton]bool,
	mouse_buttons_prev: [MouseButton]bool
}
