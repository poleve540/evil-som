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
import pq "core:container/priority_queue"

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
	if !init_game(&game) do return

	// Rendering data
	map_tex := sdl3.CreateTextureFromSurface(renderer, game.country_surface)
	sdl3.SetTextureScaleMode(map_tex, .NEAREST)

	pcolors := make(map[u32][3]u8, len(game.province_centers))
	for k in game.province_centers
	{
		pcolors[k] = {u8(rand.int_max(255)), u8(rand.int_max(255)), u8(rand.int_max(255))}
	}

	last_ticks := sdl3.GetTicks()

	event: sdl3.Event
	for global_run
	{
		current_ticks := sdl3.GetTicks()
		delta_time := f32(current_ticks - last_ticks) / 1000
		last_ticks = current_ticks

		game.mouse_delta = {0, 0}
		game.mouse_scroll = 0
		game.mouse_left_just_pressed = false

		for sdl3.PollEvent(&event)
		{
			#partial switch event.type
			{
			case .QUIT:
				global_run = false

			case .MOUSE_MOTION:
				game.mouse_delta += {event.motion.xrel, event.motion.yrel}
				game.mouse_pos = {event.motion.x, event.motion.y}

			case .MOUSE_BUTTON_DOWN:
				// Special cases that only execute on MOUSE_BUTTON_UP
				if event.button.button == sdl3.BUTTON_LEFT
				{
					game.mouse_left_just_pressed = true
					break
				}
				fallthrough

			case .MOUSE_BUTTON_UP:
				if event.button.button == sdl3.BUTTON_MIDDLE
				{
					game.mouse_middle_pressed = event.button.down
				}

			case .MOUSE_WHEEL:
				game.mouse_scroll = event.wheel.y
			}
		}

		update_game_camera(&game)
		for &d in game.divisions do update_division(&d, &game, delta_time)

		render_game(renderer, &game, map_tex)

		sdl3.RenderPresent(renderer)
	}
}

init_division :: proc(division: ^Division, game: ^GameState, start_province: u32)
{
	division.province = start_province
	init_timer(&division.timer, 0.5)
}

get_hovered_province :: proc(using game: ^GameState) -> (region: u32, ok: bool)
{
	world_mouse_pos := vec2_screen_to_world(mouse_pos, &cam)
	surface_size := [2]f32{f32(province_surface.w), f32(province_surface.h)}
	pixel_pos := (world_mouse_pos - game.map_rect.pos) / game.map_rect.size * surface_size
	pixel_pos.x = math.wrap(pixel_pos.x, surface_size.x)
	pixel_pos.y = math.wrap(pixel_pos.y, surface_size.y)

	region = get_surface_packed_rgb(province_surface, {i32(pixel_pos.x), i32(pixel_pos.y)}) or_return

	if region == 0 do return

	ok = true
	return
}

set_division_target :: proc(graph: Graph, goal: u32, division: ^Division) -> bool
{
	path := get_shortest_path(graph, division.province, goal) or_return
	division.path = path
	return true
}

init_game :: proc(game: ^GameState) -> bool
{
	country_surface := image.Load("map.png")
	province_surface := image.Load("provinces.png")

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

	province_centers := province_centers_load_from_file("province_centers.json") or_return
	province_graph := province_graph_load_from_file("province_neighbors.json") or_return

	game.province_centers = province_centers
	game.province_graph = province_graph

	provinces, err := slice.map_keys(game.province_graph)
	if err != .None
	{
		fmt.eprintln(err)
		return false
	}
	for i in 0..<10
	{
		division: Division
		start_province := rand.choice(provinces)
		init_division(&division, game, start_province)
		append(&game.divisions, division)
	}

	return true
}

update_division :: proc(division: ^Division, game: ^GameState, delta_time: f32)
{
	exit: if game.mouse_left_just_pressed
	{
		selected_province := get_hovered_province(game) or_break exit
		set_division_target(game.province_graph, selected_province, division) or_break exit
		division.timer.run = true
	}

	i := update_timer(&division.timer, delta_time)
	for _ in 0..<i
	{
		assert(len(division.path) != 0)
		division.province = pop_front(&division.path)
		if len(division.path) == 0 do division.timer.run = false
	}
}

update_game_camera :: proc(using game: ^GameState)
{
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
}

get_shortest_path :: proc(graph: Graph, start: u32, goal: u32, include_start := false) -> (path: [dynamic]u32, found: bool)
{
	// TODO(pol): This is very slow. I should use a priority queue.
	min_dist :: proc(nodes: []u32, dist: map[u32]int) -> int
	{
		assert(len(nodes) != 0)

		min := 0

		for n, i in nodes
		{
			assert(n in dist)
			if dist[n] < dist[nodes[min]]
			{
				min = i
			}
		}

		return min
	}

	Node :: struct
	{
		value: u32,
		cost: int
	}

	q: pq.Priority_Queue(Node)
	pq.init(&q,
		proc(a, b: Node) -> bool {return a.cost < b.cost},
		pq.default_swap_proc(Node)
	)
	defer pq.destroy(&q)

	prev := make(map[u32]u32)
	defer delete(prev)
	cost := make(map[u32]int)
	defer delete(cost)

	cost[start] = 0
	pq.push(&q, Node{start, 0})

	for k in graph
	{
		if k == start do continue
		cost[k] = 1e7
		pq.push(&q, Node{k, 1e7})
	}

	outer: for pq.len(q) != 0
	{
		u := pq.pop(&q).value

		if cost[u] == 1e7 do break

		for v in graph[u]
		{
			current_cost_v := cost[u] + 1
			if current_cost_v < cost[v]
			{
				prev[v] = u
				if v == goal do break outer

				cost[v] = current_cost_v
				for n, i in q.queue
				{
					if n.value == v
					{
						q.queue[i].cost = current_cost_v
						pq.fix(&q, i)
						break
					}
				}
			}

		}
	}

	// Goal not found
	if goal not_in prev do return

	path = make([dynamic]u32)
	u := goal
	for u != start
	{
		append(&path, u)
		u = prev[u]
	}
	if include_start do append(&path, start)

	slice.reverse(path[:])
	found = true

	return
}

render_graph :: proc(renderer: ^sdl3.Renderer, cam: ^Camera, centers: json.Object, neighbors: json.Object, pcolors: map[string][3]u8)
{
	// For each province
	for k, v in neighbors
	{
		c := pcolors[k]

		sdl3.SetRenderDrawColor(renderer, c.r, c.g, c.b, 0)

		// Draw the center point
		rect := Rect{
			pos = json_array_to_vec2(centers[k].(json.Array)),
			size = {1, 1}
		}

		rect = rect_world_to_screen(rect, cam)

		sdl3.RenderFillRect(renderer, (^sdl3.FRect)(&rect))

		// Draw lines to other provinces
		for neighbor in v.(json.Array)
		{
			npos := json_array_to_vec2(centers[neighbor.(json.String)].(json.Array))
			npos = vec2_world_to_screen(npos, cam)

			sdl3.RenderLine(renderer, rect.pos.x, rect.pos.y, npos.x, npos.y)
		}
	}
}

render_game :: proc(renderer: ^sdl3.Renderer, game: ^GameState, map_tex: ^sdl3.Texture)
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
	sdl3.SetRenderDrawColor(renderer, 0, 0, 255, sdl3.ALPHA_OPAQUE)
	for d in game.divisions
	{
		division_rect := Rect{game.province_centers[d.province], DIVISION_SIZE}
		division_screen_rect := rect_world_to_screen(division_rect, &game.cam)
		sdl3.RenderFillRect(renderer, (^sdl3.FRect)(&division_screen_rect))
	}
}

rect_floor :: proc(rect: Rect) -> Rect
{
	rect := rect
	rect.pos = linalg.floor(rect.pos)
	rect.size = linalg.floor(rect.size)

	return rect
}

province_centers_load_from_file :: proc(file: string) -> (centers: map[u32][2]f32, ok: bool)
{
	centers_json := json_load_from_file(file) or_return

	centers = make(map[u32][2]f32, len(centers_json.(json.Object)))
	for key, value in centers_json.(json.Object)
	{
		centers[u32(strconv.atoi(key))] = json_array_to_vec2(value.(json.Array))
	}

	ok = true
	return
}

province_graph_load_from_file :: proc(file: string) -> (graph: Graph, ok: bool)
{
	neighbors_json := json_load_from_file(file) or_return

	graph = make(Graph, len(neighbors_json.(json.Object)))
	for key, value in neighbors_json.(json.Object)
	{
		neighbors := make([]u32, len(value.(json.Array)))
		for neighbor, i in value.(json.Array)
		{
			neighbors[i] = u32(neighbor.(json.Float))
		}
		graph[u32(strconv.atoi(key))] = neighbors
	}

	ok = true
	return
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

// TODO(pol): Speed could be improved by converting all surfaces to a common format
get_surface_packed_rgb :: proc(surface: ^sdl3.Surface, pixel_pos: [2]i32) -> (result: u32, ok: bool)
{
	pixels := slice.bytes_from_ptr(surface.pixels, int(surface.h*surface.pitch))

	// NOTE(pol): SDL internally uses a hash table for finding the pixel format
	format := sdl3.GetPixelFormatDetails(surface.format)
	size := format.bytes_per_pixel

	if pixel_pos.x >= 0 && pixel_pos.x < surface.w && pixel_pos.y >= 0 && pixel_pos.y < surface.h
	{
		i := pixel_pos.y*surface.pitch + pixel_pos.x * i32(size)
		packed_rgb := (^u32)(&pixels[i])

		rgb_result: [4]byte
		sdl3.GetRGB(packed_rgb^, format, nil, &rgb_result.r, &rgb_result.g, &rgb_result.b)

		result = (^u32)(&rgb_result[0])^
		ok = true
	}

	return
}

json_load_from_file :: proc(file: string) -> (root: json.Value, ok: bool)
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
