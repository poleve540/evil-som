package main

import "vendor:sdl3"
import "vendor:sdl3/image"

import "core:fmt"
import "core:slice"
import "core:os"
import "core:encoding/json"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:strconv"

SW :: 1280
SH :: 720

global_run := true

main :: proc()
{
	window: ^sdl3.Window
	renderer: ^sdl3.Renderer

	// Implicitely calls Init({.VIDEO})
	sdl3.CreateWindowAndRenderer("hoi4 ripoff ripoff clone", SW, SH, {}, &window, &renderer)

	if window == nil
	{
		fmt.eprintfln("Could not create window: %s", sdl3.GetError())
		return
	}

	if renderer == nil
	{
		fmt.eprintfln("Could not create renderer: %s", sdl3.GetError())
		return
	}

	sdl3.SetRenderVSync(renderer, 1)

	// Game data
	game: GameState
	if !game_init(&game) do return

	// Rendering data
	map_tex := sdl3.CreateTextureFromSurface(renderer, game.country_surface)
	sdl3.SetTextureScaleMode(map_tex, .NEAREST)

	last_ticks := sdl3.GetTicks()

	event: sdl3.Event
	for global_run
	{
		game.keys_prev = game.keys
		game.mouse_buttons_prev = game.mouse_buttons

		current_ticks := sdl3.GetTicks()
		delta_time := f32(current_ticks - last_ticks) / 1000
		last_ticks = current_ticks
		
		game.mouse_delta = {0, 0}
		game.mouse_scroll = 0

		for sdl3.PollEvent(&event)
		{
			#partial switch event.type
			{
			case .QUIT:
				global_run = false

			case .KEY_DOWN, .KEY_UP:
				key: Key
				#partial switch event.key.scancode
				{
				case .W: key = .UP
				case .A: key = .LEFT
				case .S: key = .DOWN
				case .D: key = .RIGHT
				}

				game.keys[key] = event.key.down

			case .MOUSE_MOTION:
				game.mouse_delta += {event.motion.xrel, event.motion.yrel}
				game.mouse_pos = {event.motion.x, event.motion.y}

			case .MOUSE_BUTTON_UP, .MOUSE_BUTTON_DOWN:
				mouse_button: MouseButton
				if event.button.button == sdl3.BUTTON_LEFT do mouse_button = .LEFT
				else if event.button.button == sdl3.BUTTON_MIDDLE do mouse_button = .MIDDLE
				else if event.button.button == sdl3.BUTTON_RIGHT do mouse_button = .RIGHT
				game.mouse_buttons[mouse_button] = event.button.down

			case .MOUSE_WHEEL:
				game.mouse_scroll = event.wheel.y
			}
		}

		camera_update(&game, delta_time)

		for &d in game.divisions
		{
			division_update(&d, &game, delta_time)
		}

		game_render(renderer, &game, map_tex)

		sdl3.RenderPresent(renderer)
	}
}

button_just_pressed :: proc(using game: ^GameState, button: union #no_nil {Key, MouseButton}) -> bool
{
	switch b in button
	{
	case Key:
		return !keys_prev[b] && keys[b]
	case MouseButton:
		return !mouse_buttons_prev[b] && mouse_buttons[b]
	}

	return false
}

button_pressed :: proc(game: ^GameState, button: union {Key, MouseButton}) -> bool
{
	switch b in button
	{
		case Key:
			return game.keys[b]
		case MouseButton:
			return game.mouse_buttons[b]
	}

	return false
}

division_init :: proc(using division: ^Division, game: ^GameState, #any_int start_province: int)
{
	province = start_province
	speed = 100
	color = {u8(rand.int_max(255)), u8(rand.int_max(255)), u8(rand.int_max(255))}
}

get_hovered_province :: proc(using game: ^GameState) -> (region: int, ok: bool)
{
	world_mouse_pos := vec2_screen_to_world(mouse_pos, &cam)
	surface_size := [2]f32{f32(province_surface.w), f32(province_surface.h)}
	pixel_pos := (world_mouse_pos - game.map_rect.pos) / game.map_rect.size * surface_size
	pixel_pos.x = math.wrap(pixel_pos.x, surface_size.x)
	pixel_pos.y = math.wrap(pixel_pos.y, surface_size.y)

	region_rgb := get_rgba32_surface_packed_rgb(province_surface, {i32(pixel_pos.x), i32(pixel_pos.y)}) or_return

	if region_rgb == 0 do return

	region = rgb_to_node[region_rgb]

	ok = true
	return
}

division_set_target :: proc(division: ^Division, game: ^GameState, goal: int) -> bool
{
	if game.pathfinding.update_flowfield[goal]
	{
		game.pathfinding.flowfields[goal] = get_all_shortest_paths_dijkstra(&game.pathfinding, game.province_graph, goal)
		game.pathfinding.update_flowfield[goal] = false
	}

	// Goal not found
	if game.pathfinding.flowfields[goal][division.province] == -1 do return false

	// Build path to goal from division.province
	clear(&division.path)

	v := game.pathfinding.flowfields[goal][division.province]
	for v != goal
	{
		append(&division.path, v)
		v = game.pathfinding.flowfields[goal][v]
	}
	append(&division.path, goal)

	return true
}

game_init :: proc(game: ^GameState) -> bool
{
	load_rgba32_image :: proc(file: cstring) -> ^sdl3.Surface
	{
		surface := image.Load(file)
		rgba_surface := sdl3.ConvertSurface(surface, .RGBA32)
		sdl3.DestroySurface(surface)
		return rgba_surface
	}

	country_surface := load_rgba32_image("map.png")
	province_surface := load_rgba32_image("provinces.png")

	if country_surface == nil
	{
		fmt.eprintln("Failed to load country surface")
		return false
	}

	if province_surface == nil
	{
		fmt.eprintln("Failed to load province surface")
		return false
	}

	if country_surface.w != province_surface.w || country_surface.h != province_surface.h
	{
		fmt.eprintln("Country and province surfaces should be the same dimensions")
		return false
	}

	game.country_surface = country_surface
	game.province_surface = province_surface

	game.map_rect = {size = {f32(country_surface.w), f32(country_surface.h)}}
	game.cam = {
		pos = game.map_rect.size/2,
		offset = {SW/2, SH/2},
		zoom = 1
	}

	matching_keys :: proc(a, b: $M/map[$K]$V) -> bool
	{
		if len(a) != len(b) do return false
		for k in a do if k not_in b do return false
		for k in b do if k not_in a do return false

		return true
	}

	province_centers_json := json_load_from_file("province_centers.json") or_return
	defer json.destroy_value(province_centers_json)
	province_neighbors_json := json_load_from_file("province_neighbors.json") or_return
	defer json.destroy_value(province_neighbors_json)

	if !matching_keys(province_centers_json.(json.Object), province_neighbors_json.(json.Object))
	{
		fmt.eprintln("Keys of province_centers.json and province_neighbors.json do not match")
		return false
	}

	vertices, err := slice.map_keys(province_neighbors_json.(json.Object))
	defer delete(vertices)
	if err != .None
	{
		fmt.eprintln("Failed to load province_neighbors.json keys:", err)
		return false
	}

	slice.sort(vertices)

	game.province_graph = make(Graph, len(vertices))
	for v, i in vertices
	{
		neighbors_json := province_neighbors_json.(json.Object)[v].(json.Array)
		neighbors := make([]int, len(neighbors_json))
		for w, j in neighbors_json
		{
			w_string := fmt.aprint(w)
			defer delete(w_string)
			neighbors[j] = slice.binary_search(vertices, w_string) or_return
		}
		center_pos := json_array_to_vec2(province_centers_json.(json.Object)[v].(json.Array))
		game.rgb_to_node[u32(strconv.atoi(v))] = i

		game.province_graph[i] = Node{
			neighbors = neighbors,
			center_pos = center_pos
		}
	}

	game.divisions = make([dynamic]Division, 10)
	for &division in game.divisions
	{
		start_province := rand.int63_max(i64(len(game.province_graph)))
		division_init(&division, game, start_province)
	}

	pathfinding_init(&game.pathfinding, game.province_graph)

	return true
}

division_update :: proc(division: ^Division, game: ^GameState, delta_time: f32)
{
	province_distance :: proc(graph: Graph, a, b: int) -> f32
	{
		return linalg.distance(graph[a].center_pos, graph[b].center_pos)
	}

	if !slice.is_empty(division.path[:])
	{
		division.distance_traveled += delta_time * division.speed

		for division.distance_traveled >= division.total_distance
		{
			division.province = pop_front(&division.path)

			if slice.is_empty(division.path[:]) do break

			next := slice.first(division.path[:])
			division.total_distance = province_distance(game.province_graph, division.province, next)

			division.distance_traveled -= division.total_distance
		}
	}

	exit: if button_just_pressed(game, MouseButton.LEFT)
	{
		// TODO(pol): Compute selected_province early, before division_update()
		selected_province := get_hovered_province(game) or_break exit

		// Already on the selected province
		if selected_province == division.province do break exit

		// Already on it's way the selected province
		if !slice.is_empty(division.path[:]) &&
		selected_province == slice.last(division.path[:])
		{
			break exit
		}

		division_set_target(division, game, selected_province) or_break exit

		division.distance_traveled = 0
		next := slice.first(division.path[:])
		division.total_distance = province_distance(game.province_graph, division.province, next)
	}
}

camera_update :: proc(using game: ^GameState, delta_time: f32)
{
	zoom :: proc(cam: ^Camera, scroll: f32, mouse_pos: [2]f32)
	{
		world_mouse_pos := vec2_screen_to_world(mouse_pos, cam)

		cam.pos = world_mouse_pos
		cam.offset = mouse_pos

		cam.zoom += scroll
		cam.zoom = clamp(cam.zoom, 1, 10)
	}

	if button_pressed(game, MouseButton.MIDDLE) do cam.pos -= mouse_delta / cam.zoom

	if mouse_scroll != 0 do zoom(&cam, mouse_scroll, mouse_pos)

	CAM_SPEED :: 350
	if button_pressed(game, Key.UP)    do cam.pos.y -= CAM_SPEED * delta_time / cam.zoom
	if button_pressed(game, Key.DOWN)  do cam.pos.y += CAM_SPEED * delta_time / cam.zoom
	if button_pressed(game, Key.LEFT)  do cam.pos.x -= CAM_SPEED * delta_time / cam.zoom
	if button_pressed(game, Key.RIGHT) do cam.pos.x += CAM_SPEED * delta_time / cam.zoom
}

json_array_to_vec2 :: proc(array: json.Array) -> [2]f32
{
	assert(len(array) == 2)
	x, ok1 := array[0].(json.Float)
	y, ok2 := array[1].(json.Float)
	assert(ok1 && ok2)
	// pixel center
	return {f32(x)+0.5, f32(y)+0.5}
}

game_render :: proc(renderer: ^sdl3.Renderer, game: ^GameState, map_tex: ^sdl3.Texture)
{
	sdl3.SetRenderDrawColor(renderer, 255, 255, 255, sdl3.ALPHA_OPAQUE)
	sdl3.RenderClear(renderer)

	// Render map
	map_screen_rect := rect_world_to_screen(game.map_rect, &game.cam)
	map_screen_rect = rect_floor(map_screen_rect)
	// TODO(pol): Should be tiled using sdl3.RenderTextureTiled
	sdl3.RenderTexture(renderer, map_tex, nil, (^sdl3.FRect)(&map_screen_rect))

	// render_graph(renderer, cam, centers, graph, pcolors)

	// Render division
	DIVISION_SIZE :: [2]f32{5, 5}
	for d in game.divisions
	{
		sdl3.SetRenderDrawColor(renderer, d.color.r, d.color.g, d.color.g, sdl3.ALPHA_OPAQUE)
		division_rect := Rect{game.province_graph[d.province].center_pos, DIVISION_SIZE}
		division_screen_rect := rect_world_to_screen(division_rect, &game.cam)
		sdl3.RenderFillRect(renderer, (^sdl3.FRect)(&division_screen_rect))

		if !slice.is_empty(d.path[:])
		{
			start := vec2_world_to_screen(game.province_graph[d.province].center_pos, &game.cam)
			end := vec2_world_to_screen(game.province_graph[slice.first(d.path[:])].center_pos, &game.cam)
			sdl3.RenderLine(renderer, start.x, start.y, end.x, end.y)
		}
	}
}

rect_floor :: proc(rect: Rect) -> Rect
{
	rect := rect
	rect.pos = linalg.floor(rect.pos)
	rect.size = linalg.floor(rect.size)

	return rect
}

vec2_screen_to_world :: proc(vec2: [2]f32, cam: ^Camera) -> [2]f32
{
	vec2 := vec2
	vec2 -= cam.offset
	vec2 /= cam.zoom
	vec2 += cam.pos
	return vec2
}

vec2_world_to_screen :: proc(vec2: [2]f32, cam: ^Camera) -> [2]f32
{
	vec2 := vec2
	vec2 -= cam.pos
	vec2 *= cam.zoom
	vec2 += cam.offset
	return vec2
}

rect_world_to_screen :: proc(rect: Rect, cam: ^Camera) -> Rect
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

get_rgba32_surface_packed_rgb :: proc(surface: ^sdl3.Surface, pixel_pos: [2]i32) -> (result: u32, ok: bool)
{
	pixels := slice.bytes_from_ptr(surface.pixels, int(surface.h*surface.pitch))

	if pixel_pos.x >= 0 && pixel_pos.x < surface.w && pixel_pos.y >= 0 && pixel_pos.y < surface.h
	{
		i := pixel_pos.y*surface.pitch + pixel_pos.x * 4
		return (^u32)(&pixels[i])^ & 0x00FFFFFF, true
	}

	return
}

json_load_from_file :: proc(file: string) -> (root: json.Value, ok: bool)
{
	data, err2 := os.read_entire_file_or_err(file)
	if err2 != nil
	{
		fmt.eprintfln("JSON: Failed to load %s: %v", file, err2)
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

