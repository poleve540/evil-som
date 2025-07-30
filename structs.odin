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

Image :: struct
{
	surface: ^sdl3.Surface,
	tex: ^sdl3.Texture,
	pos: [2]f32
}

GameState :: struct
{
	cam: Camera
}
