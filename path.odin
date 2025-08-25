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
			new_cost := cost[v] + node_distance(graph, u, v)
			if graph[u].walkable && (!visited[u] || new_cost < cost[u])
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

