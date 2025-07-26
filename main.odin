package som

import "vendor:sdl3"
import "vendor:sdl3/image"

import "core:fmt"
import "core:slice"
import "core:os"
import "core:encoding/json"
import "core:math"
import "core:math/linalg"

global_run := true
SW :: 1280
SH :: 720

som_Camera :: struct
{
	pos: [2]f32,
	offset: [2]f32,
	zoom: f32
}

som_Rect :: struct
{
	pos: [2]f32,
	size: [2]f32
}

main :: proc()
{
	window: ^sdl3.Window
	renderer: ^sdl3.Renderer

	// Implicitely calls Init({.VIDEO})
	sdl3.CreateWindowAndRenderer("hoi4 ripoff ripoff clone", SW, SH, {}, &window, &renderer)

	if window == nil
	{
		sdl3.LogError(i32(sdl3.LogCategory.ERROR), "Could not create window: %s\n", sdl3.GetError())
		return
	}

	if renderer == nil
	{
		sdl3.LogError(i32(sdl3.LogCategory.ERROR), "Could not create renderer: %s\n", sdl3.GetError())
		return
	}

	sdl3.SetRenderVSync(renderer, 1)

	map_surface := image.Load("map.png")
	tex := sdl3.CreateTextureFromSurface(renderer, map_surface)
	sdl3.SetTextureScaleMode(tex, .NEAREST)

	provinces := image.Load("provinces.png")

	centers_json, ok1 := load_json_from_file("province_centers.json")
	if !ok1 do return

	neighbors_json, ok2 := load_json_from_file("province_neighbors.json")
	if !ok2 do return

	mouse_pos: [2]f32
	mouse_delta: [2]f32
	mouse_scroll: f32

	mouse_middle_pressed: bool
	mouse_left_just_pressed: bool

	map_rect := som_Rect{size = {f32(map_surface.w), f32(map_surface.h)}}

	cam := som_Camera{
		pos = map_rect.size/2,
		offset = {SW/2, SH/2},
		zoom = 1
	}

	DIVISION_SIZE :: [2]f32{10, 10}
	division_pos: [2]f32

	event: sdl3.Event
	for global_run
	{
		mouse_delta = {0, 0}
		mouse_scroll = 0
		mouse_left_just_pressed = false

		for sdl3.PollEvent(&event)
		{
			#partial switch event.type
			{
			case .QUIT:
				global_run = false

			case .MOUSE_MOTION:
				mouse_delta += {event.motion.xrel, event.motion.yrel}
				mouse_pos = {event.motion.x, event.motion.y}

			case .MOUSE_BUTTON_DOWN:
				// Special cases that only execute on
				// MOUSE_BUTTON_UP
				if event.button.button == sdl3.BUTTON_LEFT
				{
					mouse_left_just_pressed = true
					break
				}
				fallthrough

			case .MOUSE_BUTTON_UP:
				if event.button.button == sdl3.BUTTON_MIDDLE
				{
					mouse_middle_pressed = event.button.down
				}

			case .MOUSE_WHEEL:
				mouse_scroll = event.wheel.y
			}
		}

		if mouse_middle_pressed
		{
			cam.pos -= mouse_delta / cam.zoom
		}

		// Move cam.pos on zoom
		if mouse_scroll != 0
		{
			world_mouse_pos := vec2_screen_to_world(mouse_pos, &cam)

			cam.pos = world_mouse_pos
			cam.offset = mouse_pos

			cam.zoom += mouse_scroll
			cam.zoom = clamp(cam.zoom, 1, 10)
		}

		// NOTE(pol): normalized_pos beyond [0, 1] will be useful when tiling the map
		exit: if mouse_left_just_pressed
		{
			world_mouse_pos := vec2_screen_to_world(mouse_pos, &cam)
			surface_size := [2]f32{f32(map_surface.w), f32(map_surface.h)}
			pixel_pos := (world_mouse_pos - map_rect.pos) / map_rect.size * surface_size
			pixel_pos.x = math.wrap(pixel_pos.x, f32(map_surface.w))
			pixel_pos.y = math.wrap(pixel_pos.y, f32(map_surface.h))

			pixel, ok1 := get_surface_packed_rgb(provinces, {i32(pixel_pos.x), i32(pixel_pos.y)})
			if !ok1 || pixel == 0 do break exit

			rgb_string := fmt.aprint(pixel)
			center, ok2 := centers_json.(json.Object)[rgb_string]
			if !ok2
			{
				fmt.eprintln("Province center not found!:", rgb_string)
				break exit
			}

			division_pos = json_array_to_vec2(center.(json.Array))

			json_array_to_vec2 :: proc(array: json.Array) -> [2]f32
			{
				assert(len(array) == 2)
				x, ok1 := array[0].(json.Float)
				y, ok2 := array[1].(json.Float)
				assert(ok1 && ok2)
				// pixel center
				return {f32(x)+0.5, f32(y)+0.5}
			}
		}

		sdl3.SetRenderDrawColor(renderer, 255, 255, 255, sdl3.ALPHA_OPAQUE)
		sdl3.RenderClear(renderer)

		// TODO(pol): Have the map's FRect, texture and surfaces together
		map_screen_rect := rect_world_to_screen(map_rect, &cam)

		rect_floor :: proc(rect: som_Rect) -> som_Rect
		{
			rect := rect
			rect.pos = linalg.floor(rect.pos)
			rect.size = linalg.floor(rect.size)

			return rect
		}

		map_screen_rect = rect_floor(map_screen_rect)
		sdl3.RenderTexture(renderer, tex, nil, (^sdl3.FRect)(&map_screen_rect))

		// World position to screen
		division_screen_rect := rect_world_to_screen({division_pos, DIVISION_SIZE}, &cam)
		sdl3.RenderFillRect(renderer, (^sdl3.FRect)(&division_screen_rect))

		sdl3.RenderPresent(renderer)
	}
}

vec2_screen_to_world :: proc(vec2: [2]f32, cam: ^som_Camera) -> [2]f32
{
	vec2 := vec2
	vec2 -= cam.offset
	vec2 /= cam.zoom
	vec2 += cam.pos
	return vec2
}

vec2_world_to_screen :: proc(vec2: [2]f32, cam: ^som_Camera) -> [2]f32
{
	vec2 := vec2
	vec2 -= cam.pos
	vec2 *= cam.zoom
	vec2 += cam.offset
	return vec2
}

rect_world_to_screen :: proc(rect: som_Rect, cam: ^som_Camera) -> som_Rect
{
	rect := rect
	rect.pos = vec2_world_to_screen(rect.pos, cam)
	rect.size *= cam.zoom

	return rect
}


vec2_floor :: proc(v: [2]f32) -> [2]f32
{
	v := v
	v.x = math.floor(v.x)
	v.y = math.floor(v.y)
	return v
}

// TODO(pol): Speed could be improved by converting all surfaces to a common format
get_surface_packed_rgb :: proc(surface: ^sdl3.Surface, pixel_pos: [2]i32) -> (result: i32, ok: bool)
{
	pixels := slice.bytes_from_ptr(surface.pixels, int(surface.h*surface.pitch))

	// NOTE(pol): SDL internally uses a hash table for finding the pixel format
	format := sdl3.GetPixelFormatDetails(surface.format)
	size := format.bytes_per_pixel

	if pixel_pos.x >= 0 && pixel_pos.x < surface.w && pixel_pos.y >= 0 && pixel_pos.y < surface.h
	{
		i := pixel_pos.y*surface.pitch + pixel_pos.x * i32(size)
		packed_rgb := (^u32)(&pixels[i])

		rgb_result := [4]byte{}
		sdl3.GetRGB(packed_rgb^, format, nil, &rgb_result.r, &rgb_result.g, &rgb_result.b)

		result = (^i32)(&rgb_result[0])^
		ok = true
	}

	return
}

	load_json_from_file :: proc(file: string) -> (root: json.Value, ok: bool)
	{
		data, ok1 := os.read_entire_file_from_filename(file)
		if !ok1
		{
			fmt.eprintln("JSON: Failed to load", file)
			ok = false
			return
		}
		defer delete(data)

		json_data, err := json.parse(data)
		if err != .None
		{
			fmt.eprintfln("JSON: Failed to parse %v. Error: %v", file, err)
			ok = false
			return
		}

		return json_data, true
	}
