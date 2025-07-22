package som

import "vendor:sdl3"
import "vendor:sdl3/image"

import "core:fmt"
import "core:slice"
import "core:os"
import "core:encoding/json"

global_run := true

main :: proc()
{
	window: ^sdl3.Window
	renderer: ^sdl3.Renderer

 	// Implicitely calls Init({.VIDEO})
	sdl3.CreateWindowAndRenderer("hoi4 ripoff ripoff clone", 1280, 720, {}, &window, &renderer)

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

	img := image.Load("map.png")
	tex := sdl3.CreateTextureFromSurface(renderer, img)
	sdl3.SetTextureScaleMode(tex, .NEAREST)

	provinces := image.Load("provinces.png")

	data, ok := os.read_entire_file_from_filename("province_centers.json")
	if !ok
	{
		fmt.eprintln("Failed to load the file!")
		return
	}

	json_data, err := json.parse(data)
	if err != .None
	{
		fmt.eprintln("Failed to parse json file. Error:", err)
		return
	}

	root := json_data.(json.Object)

	mouse_pos: [2]f32
	mouse_delta: [2]f32
	mouse_scroll: f32

	mouse_middle_pressed: bool
	mouse_left_just_pressed: bool

	cam_pos: [2]f32
	zoom: f32 = 1

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

		MOUSE_SENSITIVITY :: 0.5
		if mouse_middle_pressed
		{
			cam_pos -= mouse_delta * MOUSE_SENSITIVITY
		}

		if mouse_scroll != 0
		{
			a := (mouse_pos.x + cam_pos.x) / zoom
			b := (mouse_pos.y + cam_pos.y) / zoom

			zoom += mouse_scroll
			zoom = clamp(zoom, 1, 10)

			new_posx := a * zoom - mouse_pos.x
			new_posy := b * zoom - mouse_pos.y
			cam_pos.x = new_posx
			cam_pos.y = new_posy
		}

		// TODO(pol): Have the map's FRect, texture and surfaces together
		map_rect := sdl3.FRect{
			x = -cam_pos.x,
			y = -cam_pos.y,
			w = f32(img.w) * zoom,
			h = f32(img.h) * zoom
		}

		// NOTE(pol): normalized_pos beyond [0, 1] will be useful when tiling the map
		normalized_pos := (mouse_pos - {map_rect.x, map_rect.y}) / {map_rect.w, map_rect.h}
		pixel_pos := normalized_to_pixel_pos(provinces, normalized_pos)

		exit: if mouse_left_just_pressed
		{
			pixel, ok1 := get_surface_rgb(provinces, pixel_pos)

			if !ok1 || pixel == 0 do break exit

			rgb_string := fmt.aprintf("(%i, %i, %i)", pixel[0], pixel[1], pixel[2])
			center, ok2 := root[rgb_string]
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

		sdl3.SetRenderDrawColor(renderer, 0, 0, 0, sdl3.ALPHA_OPAQUE)
		sdl3.RenderClear(renderer)

		sdl3.RenderTexture(renderer, tex, nil, &map_rect)

		// Province world to screen
		division_rect := sdl3.FRect{
			x = map_rect.x + (division_pos.x / f32(provinces.w)) * map_rect.w,
			y = map_rect.y + (division_pos.y / f32(provinces.h)) * map_rect.h,
			w = 10 / f32(provinces.w) * map_rect.w,
			h = 10 / f32(provinces.h) * map_rect.h
		}

		sdl3.RenderFillRect(renderer, &division_rect)

		sdl3.RenderPresent(renderer)
	}
}

normalized_to_pixel_pos :: proc(surface: ^sdl3.Surface, normalized_pos: [2]f32) -> [2]i32
{
	pixel_pos := normalized_pos * {f32(surface.w), f32(surface.h)}
	return {i32(pixel_pos.x), i32(pixel_pos.y)}
}

// TODO(pol): pixel_pos beyond w and h should wrap for tiling
// NOTE(pol): Speed could be improved by converting all surfaces to a common format
get_surface_rgb :: proc(surface: ^sdl3.Surface, pixel_pos: [2]i32) -> (result: [3]byte, ok: bool)
{
	pixels := slice.bytes_from_ptr(surface.pixels, int(surface.h*surface.pitch))

	// NOTE(pol): SDL internally uses a hash table for finding the pixel format
	format := sdl3.GetPixelFormatDetails(surface.format)
	size := format.bytes_per_pixel

	if pixel_pos.x >= 0 && pixel_pos.x < surface.w && pixel_pos.y >= 0 && pixel_pos.y < surface.h
	{
		i := pixel_pos.y*surface.pitch + pixel_pos.x * i32(size)
		pixel := (^u32)(&pixels[i])
		sdl3.GetRGB(pixel^, format, nil, &result.r, &result.g, &result.b)
		ok = true
	}

	return
}
