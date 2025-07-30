package main

import "vendor:sdl3"
import "vendor:sdl3/image"
import mu "vendor:microui"

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

SOM_DEBUG :: true

global_run := true
global_mu_context: mu.Context

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
	map_tex := sdl3.CreateTextureFromSurface(renderer, map_surface)
	sdl3.SetTextureScaleMode(map_tex, .NEAREST)

	provinces := image.Load("provinces.png")

	province_centers, ok1 := load_province_centers_from_file("province_centers.json")
	if !ok1 do return

	province_graph, ok2 := load_province_graph_from_file("province_neighbors.json")
	if !ok2 do return

	pcolors := make(map[u32][3]u8)
	for k in province_centers
	{
		pcolors[k] = {u8(rand.int_max(255)), u8(rand.int_max(255)), u8(rand.int_max(255))}
	}

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
	division_province: u32 = 256
	division_timer := som_Timer{start_time = 0.5}
	division_timer.time_left = division_timer.start_time
	division_path: [dynamic]u32 // List of nodes the division must traverse

	last_ticks := sdl3.GetTicks()
	delta_time: f32
	current_ticks: u64

	event: sdl3.Event
	for global_run
	{
		current_ticks = sdl3.GetTicks()
		delta_time = f32(current_ticks - last_ticks) / 1000

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

		if division_timer.run do division_timer.time_left -= delta_time

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

		exit: if mouse_left_just_pressed
		{
			// TODO(pol): Wrap it in a function
			world_mouse_pos := vec2_screen_to_world(mouse_pos, &cam)
			surface_size := [2]f32{f32(map_surface.w), f32(map_surface.h)}
			pixel_pos := (world_mouse_pos - map_rect.pos) / map_rect.size * surface_size
			pixel_pos.x = math.wrap(pixel_pos.x, f32(map_surface.w))
			pixel_pos.y = math.wrap(pixel_pos.y, f32(map_surface.h))

			pixel := get_surface_packed_rgb(provinces, {i32(pixel_pos.x), i32(pixel_pos.y)}) or_break exit
			if pixel == 0 do break exit

			path, found := dijkstra(province_graph, division_province, pixel)

			if !found
			{
				delete(path)
				break exit
			}

			division_path = path
			division_timer.run = true
		}

		if division_timer.time_left < 0
		{
			division_province = pop_front(&division_path)
			// Reset timer
			division_timer.time_left = division_timer.start_time
			if len(division_path) == 0
			{
				division_timer.run = false
				delete(division_path)
			}
		}

		render_game(
			renderer, &cam,
			map_rect, map_tex,
			{province_centers[division_province], DIVISION_SIZE},
			province_centers, province_graph, pcolors
		)

		sdl3.RenderPresent(renderer)

		last_ticks = current_ticks
	}
}

dijkstra :: proc(graph: map[u32][]u32, start: u32, goal: u32, include_start := false) -> (path: [dynamic]u32, found: bool)
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

render_graph :: proc(renderer: ^sdl3.Renderer, cam: ^som_Camera, centers: json.Object, neighbors: json.Object, pcolors: map[string][3]u8)
{
	// For each province
	for k, v in neighbors
	{
		c := pcolors[k]

		sdl3.SetRenderDrawColor(renderer, c.r, c.g, c.b, 0)

		// Draw the center point
		rect := som_Rect{
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

render_game :: proc(renderer: ^sdl3.Renderer, cam: ^som_Camera, map_rect: som_Rect,
		    map_tex: ^sdl3.Texture, division_rect: som_Rect, centers: map[u32][2]f32,
		    graph: map[u32][]u32, pcolors: map[u32][3]u8)
{
	sdl3.SetRenderDrawColor(renderer, 255, 255, 255, sdl3.ALPHA_OPAQUE)
	sdl3.RenderClear(renderer)

	// TODO(pol): Have the map's FRect, texture and surfaces together
	map_screen_rect := rect_world_to_screen(map_rect, cam)
	map_screen_rect = rect_floor(map_screen_rect)

	rect_floor :: proc(rect: som_Rect) -> som_Rect
	{
		rect := rect
		rect.pos = linalg.floor(rect.pos)
		rect.size = linalg.floor(rect.size)

		return rect
	}

	// TODO(pol): Should be tiled using sdl3.RenderTextureTiled
	sdl3.RenderTexture(renderer, map_tex, nil, (^sdl3.FRect)(&map_screen_rect))

	// when SOM_DEBUG
	// {
	// 	render_graph(renderer, cam, centers, graph, pcolors)
	// }

	// World position to screen
	division_screen_rect := rect_world_to_screen(division_rect, cam)
	sdl3.RenderFillRect(renderer, (^sdl3.FRect)(&division_screen_rect))
}

load_province_centers_from_file :: proc(file: string) -> (centers: map[u32][2]f32, ok: bool)
{
	centers_json := load_json_from_file(file) or_return

	centers = make(map[u32][2]f32)
	for key, value in centers_json.(json.Object)
	{
		centers[u32(strconv.atoi(key))] = json_array_to_vec2(value.(json.Array))
	}

	ok = true
	return
}

load_province_graph_from_file :: proc(file: string) -> (graph: map[u32][]u32, ok: bool)
{
	neighbors_json := load_json_from_file(file) or_return

	graph = make(map[u32][]u32)
	for key, value in neighbors_json.(json.Object)
	{
		neighbors := make([]u32, len(value.(json.Array)))
		for neighbor, i in value.(json.Array)
		{
			neighbors[i] = u32(strconv.atoi(neighbor.(json.String)))
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
