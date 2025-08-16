package main

import queue "core:container/priority_queue"
import "core:slice"
import "core:math"
import "core:math/linalg"

QueueItem :: struct {node: int, cost: f32}

PathfindingContext :: struct
{
	q: queue.Priority_Queue(QueueItem),
	visited: []bool,
	prev: []int,
	cost: []f32,

	flowfields: [][]int,
	update_flowfield: []bool
}

pathfinding_init :: proc(using path: ^PathfindingContext, graph: Graph)
{
	num_vertices := len(graph)

	queue.init(
		&q,
		proc(a, b: QueueItem) -> bool {return a.cost < b.cost},
		queue.default_swap_proc(QueueItem),
		num_vertices
	)
	visited = make([]bool, num_vertices)
	prev = make([]int, num_vertices)
	cost = make([]f32, num_vertices)

	flowfields = make([][]int, num_vertices)
	update_flowfield = make([]bool, num_vertices)
	slice.fill(update_flowfield, true)
}

get_all_shortest_paths_dijkstra :: proc(using path: ^PathfindingContext, graph: Graph, source: int) -> []int
{
	slice.fill(visited, false)
	queue.clear(&q)

	visited[source] = true
	queue.push(&q, QueueItem{source, 0})

	flowfield := make([]int, len(graph))
	slice.fill(flowfield, -1)

	for queue.len(q) != 0
	{
		v := queue.pop(&q).node

		for u in graph[v].neighbors
		{
			new_cost := cost[v] + (linalg.distance(graph[v].center_pos, graph[u].center_pos))
			if !visited[u] || new_cost < cost[u]
			{
				cost[u] = new_cost
				queue.push(&q, QueueItem{u, new_cost})
				visited[u] = true
				flowfield[u] = v
			}
		}
	}

	return flowfield
}

// find_path :: proc(graph: Graph, start, goal: int, append_start := false) -> (path: [dynamic]int, found: bool)
// {
// 	slice.fill(visited, false)
// 	queue.clear(&q)
//
// 	visited[start] = true
// 	queue.enqueue(&q, start)
//
// 	for queue.len(q) != 0
// 	{
// 		v := queue.dequeue(&q)
//
// 		if v == goal do break
//
// 		for u in graph[v].neighbors
// 		{
// 			if !visited[u]
// 			{
// 				queue.enqueue(&q, u)
// 				visited[u] = true
// 				prev[u] = v
// 			}
// 		}
// 	}
//
// 	// Goal not found
// 	if !visited[goal] do return
//
// 	v := goal
// 	for v != start
// 	{
// 		append(&path, v)
// 		v = prev[v]
// 	}
// 	if append_start do append(&path, start)
// 	slice.reverse(path[:])
//
// 	return path, true
// }
